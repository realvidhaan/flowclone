import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

public enum InjectionError: Error, Equatable {
    /// A secure input field (password manager, Terminal secure entry) is active;
    /// synthetic events won't reach it. Text is left on the clipboard instead.
    case secureInputActive
    /// Accessibility permission not granted, so events can't be posted.
    case accessibilityNotGranted
    case empty
}

/// Inserts text at the cursor in whatever app is focused. Used from the main
/// actor only (not `Sendable`).
public protocol TextInjector {
    func inject(_ text: String) throws
}

/// Detects whether a secure keyboard-entry field currently has focus.
public enum SecureInputDetector {
    public static var isEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}

/// Accessibility (AX) trust — required to post synthetic keyboard events.
public enum Accessibility {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility if not trusted (shows the system dialog).
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        // The literal value of kAXTrustedCheckOptionPrompt; used directly to
        // avoid referencing the non-concurrency-safe global CFString.
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

/// Identifies the focused (frontmost) application — used for history and per-app
/// injection/formatting overrides.
public enum FocusedAppInspector {
    public static var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public static var frontmostName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
