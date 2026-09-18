import Foundation
import SwiftData

@Model
final class DailyWellness {
    var id: UUID
    var date: Date
    var manualMoodScore: Double?      // -1.0 ... 1.0, from the slider
    var journalText: String
    var journalSentimentScore: Double // -1.0 ... 1.0, from analyzing the description text
    var journalSentimentSource: String = SentimentSource.onDevice.rawValue // which engine produced journalSentimentScore
    var combinedScore: Double         // blended daily score used for charts/trends

    init(
        id: UUID = UUID(),
        date: Date = .now,
        manualMoodScore: Double? = nil,
        journalText: String = "",
        journalSentimentScore: Double = 0.0,
        journalSentimentSource: String = SentimentSource.onDevice.rawValue
    ) {
        self.id = id
        self.date = date
        self.manualMoodScore = manualMoodScore
        self.journalText = journalText
        self.journalSentimentScore = journalSentimentScore
        self.journalSentimentSource = journalSentimentSource
        self.combinedScore = Self.computeCombined(
            manualMoodScore: manualMoodScore,
            journalSentimentScore: journalSentimentScore,
            journalText: journalText
        )
    }

    func updateScores(
        manualMood: Double,
        journalText: String,
        journalSentiment: Double,
        journalSentimentSource: String = SentimentSource.onDevice.rawValue
    ) {
        manualMoodScore = manualMood
        self.journalText = journalText
        journalSentimentScore = journalSentiment
        self.journalSentimentSource = journalSentimentSource
        combinedScore = Self.computeCombined(
            manualMoodScore: manualMood,
            journalSentimentScore: journalSentiment,
            journalText: journalText
        )
    }

    static func computeCombined(
        manualMoodScore: Double?,
        journalSentimentScore: Double,
        journalText: String
    ) -> Double {
        let hasJournal = !journalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let manualMoodScore, hasJournal {
            // The journal sentiment reflects the *meaning* of what the user wrote, so it
            // leads the blend. A neutral (or unset) slider must not drag a strongly
            // negative/positive description back toward zero — text detection should be
            // able to reach the extremes on its own.
            return manualMoodScore * 0.3 + journalSentimentScore * 0.7
        }
        if let manualMoodScore {
            return manualMoodScore
        }
        return journalSentimentScore
    }
}
