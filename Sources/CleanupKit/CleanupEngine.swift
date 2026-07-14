import Foundation

/// Input to a cleanup pass.
public struct CleanupRequest: Sendable, Equatable {
    /// The raw transcript from STT.
    public var raw: String
    /// Personal-dictionary terms whose spelling should be enforced.
    public var dictionary: [String]
    /// Formatting hint for the focused app (email vs casual text vs code…).
    public var appHint: String?

    public init(raw: String, dictionary: [String] = [], appHint: String? = nil) {
        self.raw = raw
        self.dictionary = dictionary
        self.appHint = appHint
    }
}

public enum CleanupError: Error, Equatable {
    case unavailable
    case badResponse
    case timedOut
}

/// Cleans up a raw transcript: removes filler words, fixes punctuation and
/// capitalization, applies dictionary spellings and the app formatting hint,
/// without rewriting content. Swappable between cloud (Groq) and local
/// (Apple Foundation Models, Ollama).
public protocol CleanupEngine: Sendable {
    var displayName: String { get }
    /// Whether the engine can run right now (key present, model available…).
    func isAvailable() async -> Bool
    func cleanup(_ request: CleanupRequest) async throws -> String
}
