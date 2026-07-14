import XCTest
import AppKit
@testable import InjectionKit

final class PasteboardSnapshotTests: XCTestCase {
    /// Uses a uniquely-named private pasteboard so the user's real clipboard is
    /// never touched.
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("com.flowclone.test.\(UUID().uuidString)"))
    }

    func testCaptureAndRestoreStringContent() {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("original clipboard", forType: .string)

        let snapshot = PasteboardSnapshot.capture(pb)

        // Simulate our injector overwriting the clipboard.
        pb.clearContents()
        pb.setString("injected text", forType: .string)
        XCTAssertEqual(pb.string(forType: .string), "injected text")

        // Restore.
        snapshot.restore(to: pb)
        XCTAssertEqual(pb.string(forType: .string), "original clipboard")
    }

    func testRestoreEmptyClipboard() {
        let pb = makePasteboard()
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(pb)

        pb.setString("something", forType: .string)
        snapshot.restore(to: pb)
        XCTAssertNil(pb.string(forType: .string))
    }

    func testChangeCountCaptured() {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("a", forType: .string)
        let snapshot = PasteboardSnapshot.capture(pb)
        XCTAssertEqual(snapshot.changeCount, pb.changeCount)
    }
}

final class KeystrokeChunkingTests: XCTestCase {
    func testShortStringSingleChunk() {
        XCTAssertEqual(KeystrokeInjector.chunks(of: "hello"), ["hello"])
    }

    func testChunkBoundary() {
        let text = String(repeating: "a", count: 45) // 45 ASCII = 45 UTF-16 units
        let chunks = KeystrokeInjector.chunks(of: text)
        XCTAssertEqual(chunks.count, 3) // 20 + 20 + 5
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= KeystrokeInjector.maxUnitsPerEvent })
    }

    func testEmojiNotSplit() {
        // Each 👨‍👩‍👧 is many UTF-16 units; must never be split mid-grapheme.
        let text = String(repeating: "👨‍👩‍👧", count: 5)
        let chunks = KeystrokeInjector.chunks(of: text)
        XCTAssertEqual(chunks.joined(), text)
        // Reassembled character count preserved.
        XCTAssertEqual(chunks.joined().count, text.count)
    }

    func testEmptyString() {
        XCTAssertEqual(KeystrokeInjector.chunks(of: ""), [])
    }
}

final class SecureInputTests: XCTestCase {
    func testSecureInputQueryDoesNotCrash() {
        // Value depends on environment; just assert it returns.
        _ = SecureInputDetector.isEnabled
    }
}
