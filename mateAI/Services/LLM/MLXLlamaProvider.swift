import Foundation

/// Optional Llama backend via mlx-swift-lm (https://github.com/ml-explore/mlx-swift-lm).
///
/// To enable Llama on-device:
/// 1. Xcode → File → Add Package Dependencies → mlx-swift-lm
/// 2. Add products: MLXLLM, MLXLMCommon
/// 3. Bundle a quantized model (e.g. Llama-3.2-1B-Instruct-4bit) in the app target
/// 4. Implement generation below using the mlx-swift-lm quick-start API
/// 5. Enable "Increased Memory Limit" capability for the target
enum MLXLlamaProvider {
    static var isAvailable: Bool { false }

    static func loadIfNeeded() async throws {}

    static func generate(
        userMessage: String,
        sentimentScore: Double,
        profile: UserProfile?
    ) async -> String? {
        nil
    }
}
