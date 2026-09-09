import Foundation
import SwiftData

@Model
final class ChatSession {
    var id: UUID
    var startDate: Date
    var sessionSentiment: Double

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage] = []

    init(id: UUID = UUID(), startDate: Date = .now, sessionSentiment: Double = 0.0) {
        self.id = id
        self.startDate = startDate
        self.sessionSentiment = sessionSentiment
    }

    func recomputeSessionSentiment() {
        let userScores = messages.filter { $0.isUser }.map { $0.sentimentScore }
        guard !userScores.isEmpty else {
            sessionSentiment = 0
            return
        }
        sessionSentiment = userScores.reduce(0, +) / Double(userScores.count)
    }
}
