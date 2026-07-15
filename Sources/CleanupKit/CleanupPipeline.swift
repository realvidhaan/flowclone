import Foundation
import os

/// Validates cleanup output before we trust it. Discards empty, bloated, or
/// refusal-shaped responses so a misbehaving model falls through the chain.
public enum CleanupPostGuard {
    private static let refusalPrefixes = [
        "i cannot", "i can't", "i'm sorry", "i am sorry", "sorry,", "as an ai",
        "sure, here", "here is", "here's the", "certainly",
    ]

    public static func isAcceptable(_ output: String, original: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Reject responses that ballooned (likely the model answered/expanded).
        if trimmed.count > Int(Double(original.count) * 2.5) + 40 { return false }
        let lowered = trimmed.lowercased()
        if refusalPrefixes.contains(where: { lowered.hasPrefix($0) }) { return false }
        return true
    }
}

/// The cleanup chain: always run an LLM pass (so even short phrases are cleaned),
/// trying engines in order (each with a timeout and post-guard), and falling back
/// to a deterministic local polish so text always comes out — even offline or
/// when every engine fails.
public struct CleanupPipeline: Sendable {
    private let engines: [any CleanupEngine]
    private let perEngineTimeout: Duration
    private let log = Logger(subsystem: "com.flowclone.app", category: "Cleanup")

    /// - Parameter engines: ordered by preference, e.g. [Groq, AppleFM].
    public init(engines: [any CleanupEngine], perEngineTimeout: Duration = .milliseconds(2500)) {
        self.engines = engines
        self.perEngineTimeout = perEngineTimeout
    }

    public func cleanup(_ request: CleanupRequest) async -> String {
        let raw = request.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        // An LLM pass runs on every non-empty utterance — the fast model is cheap,
        // and even short phrases benefit from real cleanup. `LocalPolish` is only
        // the terminal fallback below (offline / no engine / all engines failed).
        for engine in engines {
            guard await engine.isAvailable() else { continue }
            do {
                let output = try await withTimeout(perEngineTimeout) {
                    try await engine.cleanup(request)
                }
                if CleanupPostGuard.isAcceptable(output, original: raw) {
                    return output
                }
                log.notice("Cleanup output rejected by post-guard (\(engine.displayName, privacy: .public))")
            } catch {
                log.notice("Cleanup engine failed (\(engine.displayName, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Everything failed or was rejected: deterministic fallback.
        return LocalPolish.polish(raw)
    }
}

/// Runs `operation` but throws `CleanupError.timedOut` if it exceeds `duration`.
func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @Sendable @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw CleanupError.timedOut
        }
        guard let result = try await group.next() else { throw CleanupError.timedOut }
        group.cancelAll()
        return result
    }
}
