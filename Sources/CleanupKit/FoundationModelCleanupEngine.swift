import Foundation
import FoundationModels

/// Fully-local cleanup using Apple's on-device model (macOS 26). No API key, no
/// network — the private default and the automatic fallback when Groq is
/// unavailable or offline.
public struct FoundationModelCleanupEngine: CleanupEngine {
    public let displayName = "Apple Foundation Models (on-device)"

    public init() {}

    public func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    public func cleanup(_ request: CleanupRequest) async throws -> String {
        guard await isAvailable() else { throw CleanupError.unavailable }
        let session = LanguageModelSession(
            instructions: CleanupPrompt.system(dictionary: request.dictionary, appHint: request.appHint)
        )
        let response = try await session.respond(
            to: CleanupPrompt.user(request.raw),
            options: GenerationOptions(temperature: 0)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
