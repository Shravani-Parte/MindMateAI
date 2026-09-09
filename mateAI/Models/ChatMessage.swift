import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var timestamp: Date
    var isUser: Bool
    var text: String
    var sentimentScore: Double
    var isCrisisFlag: Bool
    var session: ChatSession?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        isUser: Bool,
        text: String,
        sentimentScore: Double = 0.0,
        isCrisisFlag: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isUser = isUser
        self.text = text
        self.sentimentScore = sentimentScore
        self.isCrisisFlag = isCrisisFlag
    }
}
