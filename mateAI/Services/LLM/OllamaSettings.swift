import Foundation

/// Persists the user-configurable connection details for a locally-running Ollama server
/// (https://ollama.com), used both for chat replies and for LLM-based journal sentiment
/// analysis. Everything here stays on-device/on-LAN — MindMate never talks to a public
/// cloud endpoint.
///
/// Marked `nonisolated` (with `shared` as `nonisolated(unsafe)`) so it can be referenced
/// from default-parameter-value expressions in `OllamaProvider`, which Swift always
/// evaluates in a nonisolated context regardless of this module's default MainActor
/// isolation. This is safe: the only mutable state here is `UserDefaults`, which is
/// itself thread-safe.
nonisolated final class OllamaSettings {
    nonisolated(unsafe) static let shared = OllamaSettings()

    private let defaults: UserDefaults
    private let requestTimeoutValue: TimeInterval = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Keys {
        static let isEnabled = "ollama.isEnabled"
        static let host = "ollama.host"
        static let model = "ollama.model"
        static let bertEnabled = "ollama.bertEnabled"
        static let bertModel = "ollama.bertModel"
    }

    /// Whether Ollama should be tried before Apple's on-device model / templates.
    /// On by default so chat + sentiment use the local Gemma model out of the box;
    /// any failure silently falls back to the on-device engine or templates.
    var isEnabled: Bool {
        get { defaults.object(forKey: Keys.isEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    /// e.g. "http://127.0.0.1:11434" (Simulator, same Mac as `ollama serve`) or
    /// "http://192.168.1.23:11434" (physical device on the same Wi-Fi network).
    var host: String {
        get { defaults.string(forKey: Keys.host) ?? Constants.defaultOllamaHost }
        set { defaults.set(newValue, forKey: Keys.host) }
    }

    /// Ollama model tag, e.g. "gemma3n:e2b". Must already be pulled on the host machine.
    var model: String {
        get { defaults.string(forKey: Keys.model) ?? Constants.defaultOllamaModel }
        set { defaults.set(newValue, forKey: Keys.model) }
    }

    /// Whether journal sentiment tries the dedicated BERT classifier first (true) or skips
    /// straight to the general-purpose Ollama chat model. On by default so sentiment uses
    /// a proper classifier when the BERT tag is available; anything it can't handle falls
    /// back to the regular LLM judge or on-device NaturalLanguage scoring.
    var bertEnabled: Bool {
        get { defaults.object(forKey: Keys.bertEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.bertEnabled) }
    }

    /// Ollama tag for the BERT sentiment classifier, e.g.
    /// "dugong/bert-base-uncased-finetuned-sst2". Must already be pulled on the host.
    var bertModel: String {
        get { defaults.string(forKey: Keys.bertModel) ?? Constants.bertSentimentModel }
        set { defaults.set(newValue, forKey: Keys.bertModel) }
    }

    var requestTimeout: TimeInterval { requestTimeoutValue }

    /// Normalizes `host` into a usable base URL, defaulting/repairing a missing scheme.
    var baseURL: URL? {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { trimmed = Constants.defaultOllamaHost }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        // Drop a trailing slash so appendingPathComponent doesn't produce "//api/...".
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        return URL(string: trimmed)
    }
}
