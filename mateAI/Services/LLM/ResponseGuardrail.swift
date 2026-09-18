import Foundation

/// Post-generation safety filter for LLM counselor output.
enum ResponseGuardrail {
    private static let blockedPhrases = [
        "you have depression",
        "you have anxiety",
        "you are bipolar",
        "diagnosed with",
        "prescribe",
        "take this medication",
        "you should take",
        "dosage of"
    ]

    static func filter(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            return fallback
        }

        let lower = result.lowercased()
        for phrase in blockedPhrases where lower.contains(phrase) {
            return "I'm here to support you emotionally, but I can't provide medical or diagnostic advice. Would you like to talk more about how you're feeling?"
        }

        if result.count > 500 {
            result = String(result.prefix(497)) + "..."
        }
        return result
    }

    private static let fallback =
        "Thank you for sharing that with me. I'm here to listen — what's been weighing on you most today?"
}
