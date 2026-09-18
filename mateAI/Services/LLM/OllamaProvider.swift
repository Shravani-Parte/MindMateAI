import Foundation

/// Talks to a locally-hosted Ollama server (https://ollama.com) to run a small open model —
/// by default Google's Gemma "e2b" checkpoint (`gemma4:e2b`) — for two purposes:
///   1. Generating warm, supportive counselor replies in chat (`streamChat`).
///   2. Scoring the *meaning* of a free-text journal description, not just a mood slider
///      (`sentimentScore`).
///
/// Setup (one-time, on the machine that will run the model):
///   1. Install Ollama: https://ollama.com/download
///   2. `ollama pull gemma4:e2b`
///   3. `ollama serve` (defaults to http://127.0.0.1:11434)
///   4. In MindMate → Settings → AI Engine, confirm the server URL and model.
///      The iOS Simulator can reach the Mac's own 127.0.0.1 directly; a physical device
///      needs the Mac's LAN IP instead.
///
/// Chat uses Ollama's streaming `/api/chat` endpoint so replies appear token-by-token;
/// sentiment scoring stays non-streaming so the bare `{"score": …}` JSON is easy to parse.
enum OllamaProvider {

    // MARK: - Wire types

    struct ChatMessagePayload: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessagePayload]
        let stream: Bool
        let options: Options
        /// Disables chain-of-thought for thinking-capable models (e.g. Gemma) so replies
        /// start streaming immediately; omitted entirely for models that don't support it.
        let think: Bool?

        struct Options: Codable {
            let temperature: Double
        }
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let role: String; let content: String }
        let message: Message?
    }

    private struct ChatStreamResponse: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
        let done: Bool?
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    // MARK: - Availability

    /// Pings `GET /api/tags` to confirm the server is reachable at all. Fast, cheap, and
    /// safe to call frequently (e.g. from a "Test Connection" button).
    static func isReachable(settings: OllamaSettings = .shared) async -> Bool {
        guard let url = settings.baseURL?.appendingPathComponent("api/tags") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Reachability + confirms the configured model has actually been pulled on the host.
    static func checkAvailability(settings: OllamaSettings = .shared) async -> AvailabilityResult {
        guard let url = settings.baseURL?.appendingPathComponent("api/tags") else {
            return .init(isReachable: false, hasModel: false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .init(isReachable: false, hasModel: false)
            }
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            let wanted = settings.model
            let wantedFamily = wanted.split(separator: ":").first.map(String.init) ?? wanted
            let hasModel = tags.models.contains {
                $0.name == wanted || $0.name.hasPrefix(wantedFamily)
            }
            return .init(isReachable: true, hasModel: hasModel)
        } catch {
            return .init(isReachable: false, hasModel: false)
        }
    }

    struct AvailabilityResult {
        let isReachable: Bool
        let hasModel: Bool
        var isFullyAvailable: Bool { isReachable && hasModel }
    }

    // MARK: - Streaming chat reply generation

    /// Streams a counselor reply through the local Ollama `/api/chat` endpoint, yielding
    /// content fragments as they arrive. The stream finishes without yielding anything
    /// when Ollama is disabled, unreachable, or errors out, so callers can fall through
    /// to the next backend in the pipeline.
    ///
    /// `history` should be the recent conversation as `(role, content)` pairs (roles:
    /// `user` / `assistant`). The system instructions plus any profile context are
    /// prepended automatically, so callers only need to pass the exchange itself.
    static func streamChat(
        history: [ChatMessagePayload],
        sentimentScore: Double,
        profile: UserProfile?,
        settings: OllamaSettings = .shared
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard settings.isEnabled,
                      let url = settings.baseURL?.appendingPathComponent("api/chat") else {
                    continuation.finish()
                    return
                }

                // Build the message array: system instructions + profile context first,
                // then the actual conversation.
                var systemContext = CounselorInstructions.text
                if let profile {
                    var extra = ""
                    if !profile.stressors.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        extra += " Known stressor: \(profile.stressors)."
                    }
                    if !profile.goals.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        extra += " Wellness goal: \(profile.goals)."
                    }
                    if !extra.isEmpty {
                        systemContext += "\n\nContext about you:" + extra
                    }
                }
                systemContext += "\n\nThe user's current mood band is \(Constants.band(for: sentimentScore))."

                var messages: [ChatMessagePayload] = [.init(role: "system", content: systemContext)]
                messages.append(contentsOf: history)
                if messages.last?.role != "user" {
                    messages.append(.init(role: "user", content: "[Continue gently.]"))
                }

                do {
                    let body = ChatRequest(
                        model: settings.model,
                        messages: messages,
                        stream: true,
                        options: .init(temperature: 0.7),
                        think: false
                    )
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = settings.requestTimeout
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.finish()
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatStreamResponse.self, from: data) else {
                            continue
                        }
                        if chunk.done == true {
                            break
                        }
                        if let content = chunk.message?.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Journal sentiment analysis

    /// Uses the same local model to read the *meaning* of a piece of free text (e.g. a
    /// journal entry's description) and return a sentiment score in [-1, 1], where -1 is
    /// very negative and +1 is very positive. Returns nil when Ollama is disabled,
    /// unreachable, or the model's output can't be parsed — callers should fall back to
    /// the on-device `SentimentService` NaturalLanguage score in that case.
    static func sentimentScore(
        for text: String,
        settings: OllamaSettings = .shared
    ) async -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, settings.isEnabled,
              let url = settings.baseURL?.appendingPathComponent("api/chat") else {
            return nil
        }

        let instructions = """
        You are a sentiment scoring engine for a mental wellness journal. Read the entry \
        and judge its overall emotional tone. Respond with ONLY a single JSON object of the \
        exact form {"score": <number>} where <number> is between -1.0 (very negative) and \
        1.0 (very positive), with 0.0 being neutral. Do not diagnose, do not add advice, and \
        do not include any text, explanation, or Markdown besides that JSON object.
        """

        let body = ChatRequest(
            model: settings.model,
            messages: [
                ChatMessagePayload(role: "system", content: instructions),
                ChatMessagePayload(role: "user", content: trimmed)
            ],
            stream: false,
            options: .init(temperature: 0.0),
            think: false
        )

        guard let responseText = await send(body, to: url, settings: settings) else { return nil }
        return extractScore(from: responseText)
    }

    // MARK: - Shared request plumbing

    private static func send(_ body: ChatRequest, to url: URL, settings: OllamaSettings) async -> String? {
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
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            let content = decoded.message?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let content, !content.isEmpty else { return nil }
            return content
        } catch {
            return nil
        }
    }

    /// Parses a `{"score": -0.4}`-shaped reply, tolerating extra prose or code fences the
    /// model might add despite instructions, and clamps the result to [-1, 1].
    private static func extractScore(from text: String) -> Double? {
        struct ScorePayload: Decodable { let score: Double }

        if let jsonRange = text.range(of: "\\{[^{}]*\\}", options: .regularExpression),
           let data = String(text[jsonRange]).data(using: .utf8),
           let payload = try? JSONDecoder().decode(ScorePayload.self, from: data) {
            return min(1.0, max(-1.0, payload.score))
        }

        if let match = text.range(of: "-?[0-1](\\.[0-9]+)?", options: .regularExpression),
           let value = Double(text[match]) {
            return min(1.0, max(-1.0, value))
        }

        return nil
    }
}