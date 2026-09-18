import Foundation

/// A classification made by a real BERT sentiment model (e.g. `bert-base-uncased`
/// fine-tuned on the SST-2 benchmark). `label` holds the model's verdict and
/// `confidence` its certainty in 0...1.
struct BertClassification: Sendable {
    enum Label: String {
        case positive = "POSITIVE"
        case negative = "NEGATIVE"
        case neutral = "NEUTRAL"
    }

    let label: Label
    let confidence: Double

    /// MindMate's [-1, 1] mood scale, derived from label + confidence:
    /// POSITIVE → +confidence, NEGATIVE → -confidence, NEUTRAL → 0.
    var score: Double {
        switch label {
        case .positive: return confidence
        case .negative: return -confidence
        case .neutral: return 0
        }
    }
}

/// Runs a *dedicated* fine-tuned BERT sentiment classifier through a locally-hosted
/// Ollama server and maps its verdict onto MindMate's [-1, 1] mood scale.
///
/// Unlike the general-purpose Gemini/Gemma chat model used elsewhere, BERT here is a
/// single-purpose text classifier, so journal text is scored the way ML models are
/// traditionally trained to do it. The tag is configurable (`OllamaSettings.bertModel`)
/// — any Ollama-hosted BERT/RoBERTa/DistilBERT SST-2-style tag works. Pull it once with:
///
///     ollama pull dugong/bert-base-uncased-finetuned-sst2
///
/// Sentiment priority (see `SentimentService.deepScore`):
///   1. BERT (classifier, Ollama) — when enabled and the tag is pulled
///   2. Ollama LLM judge (Gemma)  — reads the journal's meaning
///   3. Apple NaturalLanguage     — on-device fallback, always available
final class BertSentimentProvider {
    static let shared = BertSentimentProvider()

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let options: Options

        struct Options: Encodable {
            let temperature: Double
        }
    }

    private struct GenerateResponse: Decodable {
        let response: String?
        let error: String?
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    private struct ClassifyPayload: Decodable {
        let label: String?
        let score: Double?
        let confidence: Double?
    }

    // Caching the server's model list lets us avoid a `/api/tags` round-trip on every
    // keystroke while typing a journal entry. Refreshed once per minute.
    private var cachedTagPresent: Bool?
    private var lastTagCheck: Date = .distantPast
    private let tagCacheTTL: TimeInterval = 60

    /// True when the user enabled BERT sentiment AND the Ollama server has the configured
    /// BERT tag pulled. Cheap after the first check in a session.
    func isAvailable(settings: OllamaSettings = .shared) async -> Bool {
        guard settings.isEnabled, settings.bertEnabled else { return false }
        if let cachedTagPresent, Date().timeIntervalSince(lastTagCheck) < tagCacheTTL {
            return cachedTagPresent
        }
        guard let url = settings.baseURL?.appendingPathComponent("api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let tags = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
                cache(false)
                return false
            }
            let wanted = settings.bertModel
            let family = wanted.split(separator: ":").first.map(String.init) ?? wanted
            let present = tags.models.contains {
                $0.name == wanted || $0.name.hasPrefix(family)
            }
            cache(present)
            return present
        } catch {
            cache(false)
            return false
        }
    }

    /// Classifies a piece of text with the BERT model and returns its verdict, or nil when
    /// BERT is disabled, unreachable, misconfigured, or the output can't be understood.
    func classify(for text: String, settings: OllamaSettings = .shared) async -> BertClassification? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard await isAvailable(settings: settings),
              let url = settings.baseURL?.appendingPathComponent("api/generate") else {
            return nil
        }

        let body = GenerateRequest(
            model: settings.bertModel,
            prompt: trimmed,
            stream: false,
            options: .init(temperature: 0)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = settings.requestTimeout
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            guard let raw = decoded.response, !raw.isEmpty else { return nil }
            return parse(raw)
        } catch {
            return nil
        }
    }

    // MARK: - Output parsing

    /// Understands the common shapes BERT classifier output arrives in:
    ///   • `{"label": "POSITIVE", "score": 0.99}`       (JSON)
    ///   • `POSITIVE` / `NEGATIVE` / `LABEL_0` / `LABEL_1` (bare token)
    ///   • `POSITIVE 0.96` / `['POSITIVE', 0.94]`       (token + probability)
    ///   • `0.93` / `93%`                               (bare probability)
    private func parse(_ raw: String) -> BertClassification? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) JSON with label/score.
        if let jsonRange = text.range(of: "\\{[^{}]*\\}", options: .regularExpression),
           let data = String(text[jsonRange]).data(using: .utf8),
           let payload = try? JSONDecoder().decode(ClassifyPayload.self, from: data) {
            if let label = normalizeLabel(payload.label ?? ""),
               let confidence = payload.score ?? payload.confidence {
                return .init(label: label, confidence: clamp01(confidence))
            }
            if let label = normalizeLabel(payload.label ?? "") {
                return .init(label: label, confidence: 0.8)
            }
        }

        // 2) A bare label token, possibly followed by a probability.
        if let label = normalizeLabel(text) {
            return .init(label: label, confidence: extractProbability(from: text, label: label) ?? 0.9)
        }

        // 3) A raw number (0.9, .92, 92%, 0.96) with no label: above 0.5 reads positive.
        if let probability = probability(in: text) {
            return BertClassification(
                label: probability >= 0.5 ? .positive : .negative,
                confidence: abs(probability - 0.5) * 2
            )
        }

        return nil
    }

    private func normalizeLabel(_ token: String) -> BertClassification.Label? {
        let upper = token
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")

        switch upper {
        case "POSITIVE", "POSITIVE.":
            return .positive
        case "NEGATIVE", "NEGATIVE.":
            return .negative
        case "NEUTRAL", "NEUTRAL.":
            return .neutral
        case "LABEL_1", "LABEL:1", "1":
            return .positive
        case "LABEL_0", "LABEL:0", "0":
            return .negative
        default:
            return nil
        }
    }

    /// Finds a 0...1 (or 0...100%) confidence value in the model's reply, ignoring the
    /// label token itself so `LABEL_0` → "0" isn't mistaken for a 0.0 probability.
    private func extractProbability(from text: String, label: BertClassification.Label) -> Double? {
        var remaining = text
        for noise in ["POSITIVE", "NEGATIVE", "NEUTRAL", "LABEL_0", "LABEL_1", "[", "]", "{", "}", "'", "\"", ",", ":"] {
            remaining = remaining.replacingOccurrences(of: noise, with: "", options: .caseInsensitive)
        }
        let cleaned = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if let match = cleaned.range(of: "(?<![0-9])([0-9]*\\.)?[0-9]+", options: .regularExpression),
           let value = Double(cleaned[match]) {
            return clamp01(value >= 0 && value <= 1 ? value : (value <= 100 ? value / 100 : 1))
        }
        return nil
    }

    /// Finds a standalone 0...1 (or 0...100%) confidence value anywhere in the reply,
    /// used when there's no label token at all.
    private func probability(in text: String) -> Double? {
        if let match = text.range(of: "(?<![0-9])([0-9]*\\.)?[0-9]+", options: .regularExpression),
           let value = Double(text[match]) {
            return clamp01(value >= 0 && value <= 1 ? value : (value <= 100 ? value / 100 : 1))
        }
        return nil
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private func cache(_ present: Bool) {
        cachedTagPresent = present
        lastTagCheck = .now
    }
}