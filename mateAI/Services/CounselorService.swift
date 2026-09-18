import Foundation

/// Generates empathetic, non-diagnostic supportive replies using on-device LLM when available.
///
/// Pipeline: Ollama (local Gemma, if enabled & reachable) → Foundation Models (Apple
/// Intelligence) → optional MLX Llama → template fallback.
/// `RiskDetector` runs before this service is called; `ResponseGuardrail` filters LLM output.
@MainActor
final class CounselorService {
    static let shared = CounselorService()

    /// Which backend actually produced the most recent reply — kept for the chat status
    /// bar and Settings screen, since Ollama's availability can change reply to reply.
    private(set) var lastUsedBackend: LLMBackend = .template

    /// Streams a reply fragment-by-fragment. Tries Ollama first (when enabled), then
    /// Apple's on-device model, then MLX Llama, then the template fallback. Always yields
    /// at least one fragment unless the consuming task is cancelled, so the chat never
    /// hangs on an empty reply.
    func streamChatReply(
        history: [OllamaProvider.ChatMessagePayload],
        sentimentScore: Double,
        profile: UserProfile?
    ) -> AsyncThrowingStream<String, Error> {
        let latestUserText = history.last?.content ?? ""

        return AsyncThrowingStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // 1) Local Ollama (Gemma) — streaming.
                if OllamaSettings.shared.isEnabled {
                    var receivedContent = false
                    do {
                        let stream = OllamaProvider.streamChat(
                            history: history,
                            sentimentScore: sentimentScore,
                            profile: profile
                        )
                        for try await fragment in stream {
                            receivedContent = true
                            continuation.yield(fragment)
                        }
                    } catch {
                        // Partial content is already delivered; fall through only if empty.
                    }
                    if receivedContent {
                        self.lastUsedBackend = .ollama
                        continuation.finish()
                        return
                    }
                }

                // 2) Apple on-device LLM.
                if let appleReply = await LLMService.shared.generateReply(
                    userMessage: latestUserText,
                    sentimentScore: sentimentScore,
                    profile: profile
                ) {
                    self.lastUsedBackend = LLMService.shared.activeBackend
                    continuation.yield(ResponseGuardrail.filter(appleReply))
                    continuation.finish()
                    return
                }

                // 3) Optional bundled Llama (MLX).
                if MLXLlamaProvider.isAvailable,
                   let llamaReply = await MLXLlamaProvider.generate(
                       userMessage: latestUserText,
                       sentimentScore: sentimentScore,
                       profile: profile
                   ) {
                    self.lastUsedBackend = .mlxLlama
                    continuation.yield(ResponseGuardrail.filter(llamaReply))
                    continuation.finish()
                    return
                }

                // 4) Supportive templates.
                self.lastUsedBackend = .template
                continuation.yield(
                    TemplateLLMProvider.shared.reply(
                        to: latestUserText,
                        sentimentScore: sentimentScore,
                        profile: profile
                    )
                )
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Synchronous template-only path (used by previews and tests).
    func reply(to message: String, sentimentScore: Double, profile: UserProfile?) -> String {
        TemplateLLMProvider.shared.reply(
            to: message,
            sentimentScore: sentimentScore,
            profile: profile
        )
    }
}