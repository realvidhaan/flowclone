import Foundation

/// A per-app formatting rule: the focused app's bundle ID selects a hint that's
/// injected into the cleanup prompt so dictation into Mail reads differently
/// from dictation into Messages or a code editor.
public struct AppProfile: Codable, Equatable, Sendable {
    public var bundleID: String
    public var displayName: String
    public var formattingHint: String

    public init(bundleID: String, displayName: String, formattingHint: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.formattingHint = formattingHint
    }
}

/// Built-in defaults, seeded on first launch. Users can edit/add in Settings (M5).
public enum AppProfileDefaults {
    public static let all: [AppProfile] = [
        AppProfile(bundleID: "com.apple.mail", displayName: "Mail",
                   formattingHint: "email prose with full punctuation; do not add a greeting or sign-off."),
        AppProfile(bundleID: "com.apple.MobileSMS", displayName: "Messages",
                   formattingHint: "a casual text message; minimal punctuation, lowercase is fine, no formal capitalization."),
        AppProfile(bundleID: "com.tinyspeck.slackmacgap", displayName: "Slack",
                   formattingHint: "a casual chat message."),
        AppProfile(bundleID: "com.hnc.Discord", displayName: "Discord",
                   formattingHint: "a casual chat message."),
        AppProfile(bundleID: "com.microsoft.VSCode", displayName: "VS Code",
                   formattingHint: "verbatim technical dictation; keep code-like tokens intact and remove filler less aggressively."),
        AppProfile(bundleID: "com.apple.Terminal", displayName: "Terminal",
                   formattingHint: "a verbatim shell command or technical text; do not add punctuation."),
        AppProfile(bundleID: "com.googlecode.iterm2", displayName: "iTerm",
                   formattingHint: "a verbatim shell command or technical text; do not add punctuation."),
        AppProfile(bundleID: "com.apple.Notes", displayName: "Notes",
                   formattingHint: "clear prose with standard punctuation."),
        AppProfile(bundleID: "notion.id", displayName: "Notion",
                   formattingHint: "clear prose with standard punctuation."),
    ]

    /// The formatting hint for a bundle ID, or nil (neutral) if unknown.
    public static func hint(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        return all.first { $0.bundleID == bundleID }?.formattingHint
    }
}
