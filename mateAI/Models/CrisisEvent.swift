import Foundation
import SwiftData

@Model
final class CrisisEvent {
    var id: UUID
    var timestamp: Date
    var triggerCategory: String
    var messageText: String

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        triggerCategory: String,
        messageText: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.triggerCategory = triggerCategory
        self.messageText = messageText
    }
}
