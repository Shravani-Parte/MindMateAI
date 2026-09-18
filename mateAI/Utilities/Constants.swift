import Foundation

nonisolated enum Constants {
    /// Bundled MLX Llama model folder name (add via Copy Bundle Resources when using MLX).
    static let llamaModelDirectoryName = "Llama-3.2-1B-Instruct-4bit"

    /// Default local Ollama server address. Works out of the box for the iOS Simulator
    /// (which shares the Mac's network stack). On a physical device, point this at your
    /// Mac's LAN IP instead, e.g. "http://192.168.1.23:11434", from Settings → AI Engine.
    static let defaultOllamaHost = "http://127.0.0.1:11434"

    /// Default Ollama model tag. Small enough to run comfortably on a laptop while
    /// chatting. Pull it once with `ollama pull gemma4:e2b` on the machine running
    /// `ollama serve`. Change it from Settings → AI Engine if you pull a different tag.
    static let defaultOllamaModel = "gemma4:e2b"

    /// Ollama tag for a *real* fine-tuned BERT sentiment classifier (`bert-base-uncased`
    /// fine-tuned on the SST-2 benchmark). BERT is a dedicated single-purpose model, so it
    /// scores journal sentiment more like a classifier than a chat model. Pull it once with
    /// `ollama pull dugong/bert-base-uncased-finetuned-sst2` on the machine running
    /// `ollama serve`. Change it from Settings → AI Engine if you pulled a different tag.
    static let bertSentimentModel = "dugong/bert-base-uncased-finetuned-sst2"

    /// Risk score (0...1) at/above which the chat pipeline shows the crisis banner
    /// instead of a normal counselor reply.
    static let crisisRiskThreshold: Double = 0.7

    /// Combined mood score at/below which Trends surfaces a "consider professional help" nudge.
    static let lowMoodThreshold: Double = -0.2

    /// Consecutive low-mood days before a nudge is considered "persistent".
    static let lowMoodStreakDaysForNudge: Int = 3

    /// All five mood bands, coldest → warmest. Kept in one place so charts, chips, and
    /// distribution views color and label consistently.
    static let bands: [String] = ["Very Low", "Low", "Neutral", "High", "Very High"]

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
