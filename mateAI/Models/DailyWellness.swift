import Foundation
import SwiftData

@Model
final class DailyWellness {
    var id: UUID
    var date: Date
    var manualMoodScore: Double?      // -1.0 ... 1.0, from the slider
    var journalText: String
    var journalSentimentScore: Double // -1.0 ... 1.0, from NLTagger
    var combinedScore: Double         // blended daily score used for charts/trends

    init(
        id: UUID = UUID(),
        date: Date = .now,
        manualMoodScore: Double? = nil,
        journalText: String = "",
        journalSentimentScore: Double = 0.0
    ) {
        self.id = id
        self.date = date
        self.manualMoodScore = manualMoodScore
        self.journalText = journalText
        self.journalSentimentScore = journalSentimentScore
        if let manualMoodScore {
            self.combinedScore = (manualMoodScore + journalSentimentScore) / 2.0
        } else {
            self.combinedScore = journalSentimentScore
        }
    }
}
