import Foundation
import NaturalLanguage

/// Scores free text on-device using Apple's NaturalLanguage framework.
/// Returns a value in [-1.0, +1.0], where negative = negative sentiment.
final class SentimentService {
    static let shared = SentimentService()

    private let tagger = NLTagger(tagSchemes: [.sentimentScore])

    func score(for text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0.0 }

        tagger.string = trimmed
        let (sentiment, _) = tagger.tag(
            at: trimmed.startIndex,
            unit: .paragraph,
            scheme: .sentimentScore
        )
        return Double(sentiment?.rawValue ?? "0") ?? 0.0
    }
}
