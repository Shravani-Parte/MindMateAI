import Foundation

struct RiskAssessment {
    let riskScore: Double
    let isCrisis: Bool
    let matchedCategory: String?
}

/// Lightweight, fully on-device keyword risk screen.
/// This runs BEFORE the counselor generates a reply. If risk is high,
/// the app skips the normal reply and shows crisis resources instead.
///
/// This is intentionally simple for a mini-project. A production app should
/// pair this with a small trained classifier (Core ML) for better recall,
/// and never rely on keyword matching alone.
final class RiskDetector {
    static let shared = RiskDetector()

    private let crisisKeywords: [String: Double] = [
        "kill myself": 1.0,
        "suicide": 1.0,
        "end my life": 1.0,
        "want to die": 0.95,
        "hurt myself": 0.85,
        "self harm": 0.85,
        "self-harm": 0.85,
        "no reason to live": 0.9,
        "can't go on": 0.7,
        "cant go on": 0.7,
        "overdose": 0.9,
        "give up on life": 0.8,
        "not worth living": 0.85
    ]

    func assess(_ text: String) -> RiskAssessment {
        let lowered = text.lowercased()
        var bestScore = 0.0
        var bestCategory: String?

        for (phrase, weight) in crisisKeywords where lowered.contains(phrase) {
            if weight > bestScore {
                bestScore = weight
                bestCategory = phrase
            }
        }

        return RiskAssessment(
            riskScore: bestScore,
            isCrisis: bestScore >= Constants.crisisRiskThreshold,
            matchedCategory: bestCategory
        )
    }
}
