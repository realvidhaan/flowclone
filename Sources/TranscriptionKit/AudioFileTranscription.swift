import Foundation
import AVFoundation

/// Transcribes an audio file by streaming its buffers through a transcription
/// session. Used for offline/file-based transcription and for tests (which feed
/// synthesized speech). Works with any `TranscriptionEngine`.
public func transcribeAudioFile(
    _ url: URL,
    using engine: any TranscriptionEngine,
    contextualStrings: [String] = []
) async throws -> String {
    let session = try await engine.makeSession(contextualStrings: contextualStrings)
    do {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk = AVAudioFrameCount(4096)

        while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            do {
                try file.read(into: buffer)
            } catch {
                break
            }
            if buffer.frameLength == 0 { break }
            session.feed(buffer)
        }
        return try await session.finish()
    } catch {
        // makeSession already started a background results task; tear it down if
        // opening/reading the file (or finishing) throws, so it can't leak.
        await session.cancel()
        throw error
    }
}
