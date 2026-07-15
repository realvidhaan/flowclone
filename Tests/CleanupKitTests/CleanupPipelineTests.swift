import XCTest
@testable import CleanupKit

final class CleanupPipelineTests: XCTestCase {
    /// The old fast-path skipped the LLM for ≤2-word utterances; now every
    /// non-empty utterance gets an LLM pass.
    func testShortUtteranceStillRunsLLM() async {
        let engine = SpyCleanupEngine(output: "Hi.")
        let pipeline = CleanupPipeline(engines: [engine])
        let out = await pipeline.cleanup(CleanupRequest(raw: "hi"))
        XCTAssertEqual(out, "Hi.")
        let called = await engine.wasCalled()
        XCTAssertTrue(called, "the LLM engine must run even for a 1-word phrase")
    }

    func testEmptyInputSkipsEngine() async {
        let engine = SpyCleanupEngine(output: "x")
        let out = await CleanupPipeline(engines: [engine]).cleanup(CleanupRequest(raw: "   "))
        XCTAssertEqual(out, "")
        let called = await engine.wasCalled()
        XCTAssertFalse(called)
    }

    func testFallsBackToLocalPolishWhenNoEngine() async {
        // No engines (offline / local-only): deterministic polish still cleans it.
        let out = await CleanupPipeline(engines: []).cleanup(CleanupRequest(raw: "um hello there"))
        XCTAssertFalse(out.lowercased().contains("um "))
        XCTAssertFalse(out.isEmpty)
    }

    func testFallsBackWhenEngineOutputRejected() async {
        // A ballooning (refusal-shaped) output is rejected → local polish.
        let engine = SpyCleanupEngine(output: "Sure, here is the cleaned version you asked for and more and more")
        let out = await CleanupPipeline(engines: [engine]).cleanup(CleanupRequest(raw: "hello there"))
        XCTAssertFalse(out.isEmpty)
        XCTAssertFalse(out.lowercased().hasPrefix("sure"))
    }
}

private actor SpyCleanupEngine: CleanupEngine {
    nonisolated let displayName = "Spy"
    private let output: String
    private var called = false

    init(output: String) { self.output = output }

    nonisolated func isAvailable() async -> Bool { true }

    func cleanup(_ request: CleanupRequest) async throws -> String {
        called = true
        return output
    }

    func wasCalled() -> Bool { called }
}
