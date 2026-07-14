import Foundation
import SwiftData

/// A past dictation, kept locally for the history view.
@Model
public final class TranscriptionRecord {
    public var date: Date
    public var rawText: String
    public var cleanedText: String
    public var sttEngine: String
    public var llmEngine: String
    public var latencyMS: Int
    public var targetBundleID: String?

    public init(
        date: Date = Date(),
        rawText: String,
        cleanedText: String,
        sttEngine: String,
        llmEngine: String,
        latencyMS: Int,
        targetBundleID: String? = nil
    ) {
        self.date = date
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.sttEngine = sttEngine
        self.llmEngine = llmEngine
        self.latencyMS = latencyMS
        self.targetBundleID = targetBundleID
    }
}

/// A personal-dictionary entry. `spoken` is optional: when set, it's a
/// substitution (spoken → written); when nil, `written` is just a term whose
/// spelling should be biased/enforced.
@Model
public final class DictionaryEntry {
    public var written: String
    public var spoken: String?
    public var enabled: Bool
    public var createdAt: Date

    public init(written: String, spoken: String? = nil, enabled: Bool = true, createdAt: Date = Date()) {
        self.written = written
        self.spoken = spoken
        self.enabled = enabled
        self.createdAt = createdAt
    }
}

/// A per-app formatting profile (persisted; seeded from `AppProfileDefaults`).
@Model
public final class AppProfileRecord {
    @Attribute(.unique) public var bundleID: String
    public var displayName: String
    public var formattingHint: String
    public var enabled: Bool

    public init(bundleID: String, displayName: String, formattingHint: String, enabled: Bool = true) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.formattingHint = formattingHint
        self.enabled = enabled
    }
}
