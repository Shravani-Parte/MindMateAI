import Foundation

/// Generates empathetic, non-diagnostic supportive replies.
///
/// NOTE: To keep this mini-project runnable on any device with zero setup,
/// this is a lightweight local template engine driven by sentiment band +
/// profile context — NOT a generative model.
///
/// To upgrade to a real on-device LLM, replace the body of `reply(to:...)`
/// with a call to one of:
///   - Apple Foundation Models: `LanguageModelSession` (iOS 18+, A17 Pro/M-series+)
///   - MLX-Swift or llama.cpp with a quantized small model (e.g. Llama-3-8B-4bit)
/// Keep the same function signature so ChatViewModel doesn't need to change.
final class CounselorService {
    static let shared = CounselorService()

    private let repliesByBand: [String: [String]] = [
        "Very Low": [
            "That sounds really heavy. I'm here with you — would it help to talk through what's weighing on you?",
            "I can hear that today has been hard. You don't have to carry this alone."
        ],
        "Low": [
            "It sounds like today has been tough. What's one small thing that might make the next hour a bit easier?",
            "Thanks for sharing that. Rough days happen — want to try a short grounding exercise together?"
        ],
        "Neutral": [
            "Thanks for checking in. How has your energy been today compared to usual?",
            "I'm listening. Is there anything specific on your mind right now?"
        ],
        "High": [
            "Glad to hear some positive energy today. What's been going well?",
            "That's great to hear. What helped make today feel this way?"
        ],
        "Very High": [
            "Love hearing that! What's one thing you'd like to carry forward from today?",
            "That's wonderful. Want to jot down what's working so you can look back on it later?"
        ]
    ]

    func reply(to message: String, sentimentScore: Double, profile: UserProfile?) -> String {
        let band = Constants.band(for: sentimentScore)
        let options = repliesByBand[band] ?? repliesByBand["Neutral"]!
        var response = options.randomElement() ?? options[0]

        if let profile, !profile.stressors.trimmingCharacters(in: .whitespaces).isEmpty,
           band == "Low" || band == "Very Low" {
            response += " I remember you mentioned \(profile.stressors.lowercased()) has been a stressor lately — is that part of it?"
        }
        return response
    }
}
