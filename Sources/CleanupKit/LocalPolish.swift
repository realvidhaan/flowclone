import Foundation

/// Deterministic, offline text polish. Two roles:
///   1. The **fast path** for very short utterances (skips the LLM so "yes" /
///      "sounds good" feel instant).
///   2. The **terminal fallback** when every LLM engine fails — nicer than
///      injecting the raw transcript.
///
/// Intentionally conservative: it only strips unambiguous standalone fillers,
/// capitalizes the first letter, and adds terminal punctuation. It never
/// reorders or rewrites words.
public enum LocalPolish {
    /// Standalone filler words removed anywhere in the text.
    static let fillers: Set<String> = ["um", "uh", "erm", "ah", "hmm"]
    /// Fillers removed only when they lead the utterance (too risky mid-sentence,
    /// e.g. "I like it").
    static let leadingFillers: [String] = ["like", "so", "you know", "i mean", "well"]

    public static func wordCount(_ text: String) -> Int {
        text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    /// Whether an utterance is short enough to skip the LLM.
    public static func isShort(_ text: String) -> Bool {
        wordCount(text) <= 4
    }

    public static func polish(_ text: String) -> String {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return "" }

        // Drop a leading filler word/phrase (case-insensitive), once.
        for phrase in leadingFillers {
            if let range = leadingRange(of: phrase, in: working) {
                working.removeSubrange(range)
                working = working.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Remove standalone hard fillers anywhere.
        var words = working.split(separator: " ").map(String.init)
        words.removeAll { fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        working = words.joined(separator: " ")
        guard !working.isEmpty else { return "" }

        // Capitalize the first letter.
        working = capitalizingFirstLetter(working)

        // Add terminal punctuation for sentence-length utterances.
        if wordCount(working) >= 3, let last = working.last, !".!?".contains(last) {
            working.append(".")
        }
        return working
    }

    private static func leadingRange(of phrase: String, in text: String) -> Range<String.Index>? {
        let lowered = text.lowercased()
        let target = phrase.lowercased() + " "
        guard lowered.hasPrefix(target) else { return nil }
        return text.startIndex..<text.index(text.startIndex, offsetBy: phrase.count)
    }

    private static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
