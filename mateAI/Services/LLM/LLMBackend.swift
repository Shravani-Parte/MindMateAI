import Foundation

/// Describes which on-device engine is generating counselor replies.
enum LLMBackend: String, Sendable {
    case ollama = "Ollama (Gemma)"
    case appleFoundationModel = "Apple On-Device LLM"
    case mlxLlama = "Llama (MLX)"
    case template = "Supportive Templates"

    var detail: String {
        switch self {
        case .ollama:
            "Powered by a local Gemma model served through Ollama on your Mac/network."
        case .appleFoundationModel:
            "Powered by Apple Intelligence on-device model (iOS 26+, A17 Pro or later)."
        case .mlxLlama:
            "Powered by a bundled Llama model via MLX Swift."
        case .template:
            "Using local templates while the on-device model loads or is unavailable."
        }
    }
}
