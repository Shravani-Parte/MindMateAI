import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ChatViewModel {
    var draft: String = ""
    var showCrisisBanner: Bool = false
    var isGenerating: Bool = false
    /// Bumped whenever the message list grows or a streamed reply advances, so the view
    /// knows to scroll to the latest message.
    var scrollTick: Int = 0
    /// Reflects whichever backend actually served the most recent reply (Ollama, Apple's
    /// on-device model, MLX, or the template fallback) rather than just what's configured.
    private(set) var activeBackend: LLMBackend = CounselorService.shared.lastUsedBackend

    private var context: ModelContext
    private var session: ChatSession
    private var replyTask: Task<Void, Never>?
    private var lastUserSentiment: Double = 0

    /// Loads the most recent chat session so conversation persists across launches;
    /// creates a fresh one only when none exists yet.
    init(context: ModelContext) {
        self.context = context
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            self.session = existing
        } else {
            let newSession = ChatSession()
            context.insert(newSession)
            self.session = newSession
            try? context.save()
        }
    }

    var messages: [ChatMessage] {
        session.messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Clears the ongoing conversation and starts a fresh session.
    func startNewChat() {
        replyTask?.cancel()
        replyTask = nil

        let newSession = ChatSession()
        context.insert(newSession)
        try? context.save()

        session = newSession
        showCrisisBanner = false
        isGenerating = false
        draft = ""
        activeBackend = CounselorService.shared.lastUsedBackend
        scrollTick += 1
    }

    func send(profile: UserProfile) {
        send(text: draft, profile: profile)
    }

    func send(text input: String, profile: UserProfile) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        draft = ""

        let sentiment = SentimentService.shared.score(for: text)
        let risk = RiskDetector.shared.assess(text)
        lastUserSentiment = sentiment

        let userMessage = ChatMessage(
            isUser: true,
            text: text,
            sentimentScore: sentiment,
            isCrisisFlag: risk.isCrisis
        )
        userMessage.session = session
        session.messages.append(userMessage)
        context.insert(userMessage)

        if risk.isCrisis {
            handleCrisis(message: text, category: risk.matchedCategory)
        } else {
            beginReply(profile: profile)
        }
    }

    /// Full chat pipeline: risk screen → (crisis path) or (sentiment + streaming LLM reply).
    private func beginReply(profile: UserProfile) {
        // Recent conversation for the model, user first. Excludes the (soon-to-be) empty
        // assistant placeholder.
        let history: [OllamaProvider.ChatMessagePayload] = messages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(24)
            .map { .init(role: $0.isUser ? "user" : "assistant", content: $0.text) }

        let assistantMessage = ChatMessage(
            isUser: false,
            text: "",
            sentimentScore: 0,
            isCrisisFlag: false
        )
        assistantMessage.session = session
        session.messages.append(assistantMessage)
        context.insert(assistantMessage)
        try? context.save()
        scrollTick += 1

        isGenerating = true
        let sentiment = lastUserSentiment

        replyTask?.cancel()
        replyTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var buffer = ""
            var lastFlush = Date()

            do {
                let stream = CounselorService.shared.streamChatReply(
                    history: history,
                    sentimentScore: sentiment,
                    profile: profile
                )
                for try await fragment in stream {
                    if Task.isCancelled { return }
                    buffer += fragment
                    // Throttle SwiftData writes so we don't save on every token.
                    if Date().timeIntervalSince(lastFlush) > 0.04 {
                        assistantMessage.text = buffer
                        lastFlush = Date()
                        scrollTick += 1
                    }
                }
                assistantMessage.text = buffer
            } catch {
                if Task.isCancelled { return }
                if buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assistantMessage.text = "I'm sorry — I hit a hiccup on my end. Could you tell me a little more?"
                }
            }

            guard !Task.isCancelled else { return }

            if assistantMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                assistantMessage.text = TemplateLLMProvider.shared.reply(
                    to: history.last?.content ?? "",
                    sentimentScore: sentiment,
                    profile: profile
                )
            }

            activeBackend = CounselorService.shared.lastUsedBackend
            isGenerating = false
            session.recomputeSessionSentiment()
            scrollTick += 1
            try? context.save()
        }
    }

    private func handleCrisis(message text: String, category: String?) {
        showCrisisBanner = true

        let event = CrisisEvent(
            triggerCategory: category ?? "unspecified",
            messageText: text
        )
        context.insert(event)

        let safetyReply = ChatMessage(
            isUser: false,
            text: "I'm really glad you told me. What you're feeling matters, and you don't have to face it alone. Please consider reaching out to a crisis line right now — tap the banner above for immediate resources.",
            sentimentScore: 0,
            isCrisisFlag: true
        )
        safetyReply.session = session
        session.messages.append(safetyReply)
        context.insert(safetyReply)

        session.recomputeSessionSentiment()
        scrollTick += 1
        try? context.save()
    }
}