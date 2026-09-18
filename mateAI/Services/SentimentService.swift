import Foundation
import NaturalLanguage

/// Which engine produced a given sentiment score, so the UI can be transparent about it
/// (e.g. a badge next to a journal entry's detected mood).
enum SentimentSource: String, Sendable {
    case onDevice = "On-device (NaturalLanguage)"
    case bert = "BERT (Ollama)"
    case ollama = "Ollama (Gemma)"
}

/// Scores free text on-device using Apple's NaturalLanguage sentiment model.
/// Returns a value in [-1.0, +1.0], where negative = negative sentiment.
///
/// For multi-sentence journal entries, scores each sentence and averages for stability.
final class SentimentService {
    static let shared = SentimentService()

    private let tagger = NLTagger(tagSchemes: [.sentimentScore])
    private let sentenceTokenizer = NLTokenizer(unit: .sentence)

    func score(for text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        let sentences = splitIntoSentences(trimmed)
        if sentences.count <= 1 {
            return scoreParagraph(trimmed)
        }

        let scores = sentences.map { scoreParagraph($0) }
        return emphasize(scores)
    }

    /// Combines per-sentence sentiment so one meaningful sentence isn't diluted to neutral
    /// by several flat ones. Each sentence is weighted by how strongly it deviates from
    /// zero, so a single very negative sentence in an otherwise plain paragraph still reads
    /// as negative (robust for real journal entries, which are usually 2–5 sentences).
    private func emphasize(_ scores: [Double]) -> Double {
        let totalWeight = scores.reduce(0) { $0 + 1 + abs($1) * 3 }
        guard totalWeight > 0 else { return 0 }
        let weightedSum = scores.reduce(0) { $0 + $1 * (1 + abs($1) * 3) }
        return min(1.0, max(-1.0, weightedSum / totalWeight))
    }

    /// Human-readable band for a score.
    func band(for text: String) -> String {
        Constants.band(for: score(for: text))
    }

    /// Blends manual mood slider value with journal sentiment (same formula as DailyWellness).
    func combinedScore(manualMood: Double, journalText: String) -> Double {
        let journalScore = score(for: journalText)
        if journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return manualMood
        }
        return (manualMood + journalScore) / 2.0
    }

    /// Reads the *meaning* of a journal description, not just a slider value. Engine
    /// priority when Ollama is enabled and reachable:
    ///   1. BERT — a real fine-tuned BERT sentiment classifier (when the tag is pulled)
    ///   2. the general-purpose LLM judge, which reads the entry's emotional tone
    /// and when neither is available it falls back to the on-device NaturalLanguage score
    /// above. Either way, the description text — not the mood slider — is what's analyzed.
    func deepScore(for text: String) async -> (score: Double, source: SentimentSource) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (0.0, .onDevice) }

        if let bertScore = await BertSentimentProvider.shared.classify(for: trimmed) {
            return (bertScore.score, .bert)
        }

        if let aiScore = await OllamaProvider.sentimentScore(for: trimmed) {
            return (aiScore, .ollama)
        }

        return (score(for: trimmed), .onDevice)
    }

    private func scoreParagraph(_ text: String) -> Double {
        tagger.string = text
        let (sentiment, _) = tagger.tag(
            at: text.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        let raw = Double(sentiment?.rawValue ?? "0") ?? 0.0
        return min(1.0, max(-1.0, raw))
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        sentenceTokenizer.string = text
        var sentences: [String] = []
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        return sentences
    }
}
