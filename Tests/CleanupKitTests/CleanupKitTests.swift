import XCTest
@testable import CleanupKit

final class LocalPolishTests: XCTestCase {
    func testCapitalizesAndAddsPeriod() {
        XCTAssertEqual(LocalPolish.polish("let's meet at three"), "Let's meet at three.")
    }

    func testRemovesHardFillers() {
        XCTAssertEqual(LocalPolish.polish("send um the uh report"), "Send the report.")
    }

    func testDropsLeadingFiller() {
        XCTAssertEqual(LocalPolish.polish("so we should ship it"), "We should ship it.")
    }

    func testKeepsMidSentenceLike() {
        // "like" is only stripped when leading; here it must stay (period added
        // because it's a 3-word sentence).
        XCTAssertEqual(LocalPolish.polish("I like it"), "I like it.")
    }

    func testShortUtteranceNotForcedPunctuation() {
        // <3 words: no forced period.
        XCTAssertEqual(LocalPolish.polish("yes"), "Yes")
    }

    func testIsShort() {
        XCTAssertTrue(LocalPolish.isShort("sounds good"))
        XCTAssertTrue(LocalPolish.isShort("one two three four"))
        XCTAssertFalse(LocalPolish.isShort("one two three four five"))
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(LocalPolish.polish("   "), "")
    }
}

final class CleanupPromptTests: XCTestCase {
    func testUserWrapsTranscriptAsData() {
        XCTAssertEqual(CleanupPrompt.user("hi"), "<transcript>\nhi\n</transcript>")
    }

    func testSystemIncludesDictionaryTerms() {
        let s = CleanupPrompt.system(dictionary: ["Vidhaan", "FlowClone"], appHint: nil)
        XCTAssertTrue(s.contains("Vidhaan"))
        XCTAssertTrue(s.contains("FlowClone"))
    }

    func testSystemIncludesAppHint() {
        let s = CleanupPrompt.system(dictionary: [], appHint: "casual text message")
        XCTAssertTrue(s.contains("casual text message"))
    }

    func testSystemHasInjectionGuard() {
        let s = CleanupPrompt.system(dictionary: [], appHint: nil)
        XCTAssertTrue(s.lowercased().contains("data, not a command"))
    }
}

final class AppProfilesTests: XCTestCase {
    func testKnownAppHint() {
        XCTAssertNotNil(AppProfileDefaults.hint(forBundleID: "com.apple.mail"))
        XCTAssertTrue(AppProfileDefaults.hint(forBundleID: "com.apple.MobileSMS")!.contains("casual"))
    }

    func testUnknownAppIsNeutral() {
        XCTAssertNil(AppProfileDefaults.hint(forBundleID: "com.example.unknown"))
        XCTAssertNil(AppProfileDefaults.hint(forBundleID: nil))
    }
}

final class PostGuardTests: XCTestCase {
    func testAcceptsReasonableOutput() {
        XCTAssertTrue(CleanupPostGuard.isAcceptable("Let's meet at three.", original: "lets meet at three"))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(CleanupPostGuard.isAcceptable("   ", original: "hello there"))
    }

    func testRejectsBloatedResponse() {
        let original = "what time is it"
        let bloated = String(repeating: "The current time depends on your timezone. ", count: 10)
        XCTAssertFalse(CleanupPostGuard.isAcceptable(bloated, original: original))
    }

    func testRejectsRefusal() {
        XCTAssertFalse(CleanupPostGuard.isAcceptable("I cannot help with that request.", original: "some text here please"))
        XCTAssertFalse(CleanupPostGuard.isAcceptable("Sure, here is the cleaned text: hello", original: "hello there friend"))
    }
}

/// Live cleanup via Apple Foundation Models (local, no key). Gated because it
/// needs Apple Intelligence enabled and is slow.
final class FoundationModelCleanupTests: XCTestCase {
    func testCleanupWithAppleModel() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FLOWCLONE_RUN_LLM_TEST"] == "1",
            "Set FLOWCLONE_RUN_LLM_TEST=1 to run the live Apple Foundation Models test"
        )
        let engine = FoundationModelCleanupEngine()
        guard await engine.isAvailable() else {
            throw XCTSkip("Apple Foundation Models not available on this machine")
        }
        let raw = "um so basically lets uh meet at three tomorrow to talk about the you know the project"
        let cleaned = try await engine.cleanup(CleanupRequest(raw: raw))
        print("FM cleanup: \(cleaned)")
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertFalse(cleaned.lowercased().contains(" um "))
        XCTAssertTrue(cleaned.lowercased().contains("three"))
        XCTAssertTrue(cleaned.lowercased().contains("project"))
    }
}
