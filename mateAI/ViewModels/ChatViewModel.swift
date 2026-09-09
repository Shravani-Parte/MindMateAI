import Foundation
import SwiftData
import Observation

@Observable
final class ChatViewModel {
    var draft: String = ""
    var showCrisisBanner: Bool = false

    private var context: ModelContext
    private var session: ChatSession

    init(context: ModelContext) {
        self.context = context
        let newSession = ChatSession()
        context.insert(newSession)
        self.session = newSession
    }

    var messages: [ChatMessage] {
        session.messages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Full chat pipeline: risk screen -> (crisis path) or (sentiment + counselor reply).
    func send(profile: UserProfile?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""

        let sentiment = SentimentService.shared.score(for: text)
        let risk = RiskDetector.shared.assess(text)

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
            showCrisisBanner = true

            let event = CrisisEvent(
                triggerCategory: risk.matchedCategory ?? "unspecified",
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
        } else {
            let replyText = CounselorService.shared.reply(
                to: text,
                sentimentScore: sentiment,
                profile: profile
            )
            let reply = ChatMessage(isUser: false, text: replyText, sentimentScore: 0, isCrisisFlag: false)
            reply.session = session
            session.messages.append(reply)
            context.insert(reply)
        }

        session.recomputeSessionSentiment()
        try? context.save()
    }
}
