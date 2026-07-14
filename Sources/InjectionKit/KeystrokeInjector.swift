import CoreGraphics
import Foundation

/// Fallback injector: types text as synthetic Unicode key events. No clipboard
/// involvement, but slower and occasionally dropped by apps that throttle
/// synthetic input. Used for apps configured to prefer typing over paste.
public final class KeystrokeInjector: TextInjector {
    /// Max UTF-16 units per event. `CGEventKeyboardSetUnicodeString` is reliable
    /// only for short strings, so text is chunked.
    static let maxUnitsPerEvent = 20

    public init() {}

    public func inject(_ text: String) throws {
        guard !text.isEmpty else { throw InjectionError.empty }
        guard Accessibility.isTrusted else { throw InjectionError.accessibilityNotGranted }

        let source = CGEventSource(stateID: .combinedSessionState)
        for chunk in Self.chunks(of: text) {
            let units = Array(chunk.utf16)
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down?.post(tap: .cghidEventTap)

            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Splits text into chunks of at most `maxUnitsPerEvent` UTF-16 units,
    /// without splitting a Swift `Character` (grapheme) across chunks.
    static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentUnits = 0
        for character in text {
            let charUnits = character.utf16.count
            if currentUnits + charUnits > maxUnitsPerEvent, !current.isEmpty {
                result.append(current)
                current = ""
                currentUnits = 0
            }
            current.append(character)
            currentUnits += charUnits
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
