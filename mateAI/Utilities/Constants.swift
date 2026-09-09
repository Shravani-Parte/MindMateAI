import Foundation

enum Constants {
    /// Risk score (0...1) at/above which the chat pipeline shows the crisis banner
    /// instead of a normal counselor reply.
    static let crisisRiskThreshold: Double = 0.7

    /// Combined mood score at/below which Trends surfaces a "consider professional help" nudge.
    static let lowMoodThreshold: Double = -0.2

    /// Consecutive low-mood days before a nudge is considered "persistent".
    static let lowMoodStreakDaysForNudge: Int = 3

    /// Maps a sentiment score in [-1, 1] to a human-readable band.
    static func band(for score: Double) -> String {
        switch score {
        case ..<(-0.6): return "Very Low"
        case -0.6..<(-0.2): return "Low"
        case -0.2..<0.2: return "Neutral"
        case 0.2..<0.6: return "High"
        default: return "Very High"
        }
    }
}
