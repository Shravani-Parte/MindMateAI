import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Orchestrates on-device LLM generation with template fallback.
@MainActor
final class LLMService {
    static let shared = LLMService()

    private(set) var activeBackend: LLMBackend = .template

#if canImport(FoundationModels)
    private var foundationSession: LanguageModelSession?
#endif

    private init() {
        refreshAvailability()
    }

    /// Apple's on-device model never has its assets in the Simulator, and probing it there
    /// floods the console with `com.apple.modelcatalog` / `ModelManagerError` logs. We only
    /// consider it on real hardware; on Simulator we go straight to templates (or Ollama).
    var isAppleModelUsable: Bool {
#if canImport(FoundationModels)
#if targetEnvironment(simulator)
        return false
#else
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
#endif
#else
        return false
#endif
    }

    func refreshAvailability() {
        activeBackend = isAppleModelUsable ? .appleFoundationModel : .template
    }

    var isOnDeviceLLMAvailable: Bool {
        activeBackend != .template
    }

    /// Generates a counselor reply. Returns nil when the LLM path fails so callers can fall back.
    func generateReply(
        userMessage: String,
        sentimentScore: Double,
        profile: UserProfile?
    ) async -> String? {
#if canImport(FoundationModels)
        guard isAppleModelUsable else {
            activeBackend = .template
            return nil
        }

        activeBackend = .appleFoundationModel

        if foundationSession == nil {
            foundationSession = LanguageModelSession(instructions: CounselorInstructions.text)
        }

        guard let foundationSession, !foundationSession.isResponding else { return nil }

        let band = Constants.band(for: sentimentScore)
        var context = "The user's detected mood band is \(band) (score: \(String(format: "%.2f", sentimentScore)))."

        if let profile {
            if !profile.stressors.isEmpty {
                context += " Known stressor: \(profile.stressors)."
            }
            if !profile.goals.isEmpty {
                context += " Wellness goal: \(profile.goals)."
            }
        }

        let prompt = """
        \(context)

        User message: "\(userMessage)"

        Reply as MindMate in 2–4 warm, supportive sentences.
        """

        do {
            let options = GenerationOptions(temperature: 0.7)
            let response = try await foundationSession.respond(to: prompt, options: options)
            return ResponseGuardrail.filter(response.content)
        } catch {
            activeBackend = .template
            return nil
        }
#else
        return nil
#endif
    }

    func setBackend(_ backend: LLMBackend) {
        activeBackend = backend
    }

    /// Resets the multi-turn session (e.g. after deleting chat data).
    func resetSession() {
#if canImport(FoundationModels)
        foundationSession = nil
#endif
        refreshAvailability()
    }
}