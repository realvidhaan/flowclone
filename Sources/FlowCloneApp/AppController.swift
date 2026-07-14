import Foundation
import SwiftUI
import os
import FlowCore
import HotkeyService
import AudioService
import IndicatorUI
import TranscriptionKit
import InjectionKit
import CleanupKit
import PersistenceKit

/// Top-level runtime coordinator. Owns the hotkey, audio, and indicator, and
/// drives the shared `DictationStateMachine`. In M1 the pipeline ends after
/// recording (transcription/cleanup/injection arrive in later milestones), but
/// the wiring is already shaped so those slot in.
@MainActor
final class AppController: ObservableObject {
    private let log = Logger(subsystem: "com.flowclone.app", category: "AppController")

    private let hotkeys = HotkeyService(hotkey: .fn)
    private let audio = AudioCaptureService()
    let indicator = IndicatorController()

    private let sttEngine: any TranscriptionEngine = SpeechAnalyzerEngine()
    private var session: (any TranscriptionSession)?
    private let injector: any TextInjector = PasteInjector()

    /// Bundle ID of the app focused when recording started — used for the
    /// per-app formatting hint and (later) history.
    private var targetBundleID: String?

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var hotkeyActive = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var lastLevel: Float = 0
    /// The most recent transcript, surfaced in the menu (visible proof STT works
    /// before injection lands in M3).
    @Published private(set) var lastTranscript: String = ""

    /// Minimum hold before we actually commit to a recording session, so a
    /// quick accidental tap of the hotkey doesn't flash the pill.
    private let holdDebounce: Duration = .milliseconds(150)
    private var armTask: Task<Void, Never>?

    init() {
        audio.onLevel = { [weak self] level in
            self?.lastLevel = level
            self?.indicator.update(level: level)
        }
        hotkeys.onEvent = { [weak self] event in
            self?.handle(hotkey: event)
        }
    }

    // MARK: Startup

    /// Requests permissions and starts the hotkey tap. Safe to call repeatedly
    /// (e.g. after the user grants a permission in System Settings).
    func startServices() {
        Task { _ = await AudioCaptureService.requestMicrophone() }
        // Pre-install the speech model so the first dictation isn't slow.
        Task { try? await sttEngine.prepare() }

        if HotkeyService.inputMonitoringStatus != .granted {
            HotkeyService.requestInputMonitoring()
        }
        hotkeyActive = hotkeys.start()
        if !hotkeyActive {
            log.notice("Hotkey inactive — Input Monitoring not granted yet")
        }
        accessibilityGranted = Accessibility.isTrusted
    }

    func retryHotkey() {
        guard !hotkeyActive else { return }
        hotkeyActive = hotkeys.start()
        accessibilityGranted = Accessibility.isTrusted
    }

    func requestAccessibility() {
        Accessibility.requestIfNeeded()
        accessibilityGranted = Accessibility.isTrusted
    }

    // MARK: Hotkey handling

    private func handle(hotkey event: HotkeyEvent) {
        switch event {
        case .down:
            beginArming()
        case .up:
            endRecording()
        case .cancel:
            cancel()
        }
    }

    private func beginArming() {
        guard case .idle = state else { return }
        // Capture the target app now (FlowClone is a menu-bar agent and never
        // becomes frontmost, so this stays the user's app through the session).
        targetBundleID = FocusedAppInspector.frontmostBundleID
        // Start capturing immediately (cheap), but only reveal the pill and
        // commit to the session after the debounce, so taps don't flicker.
        startAudio()
        armTask?.cancel()
        armTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.holdDebounce)
            guard !Task.isCancelled else { return }
            self.transition(.hotkeyDown(.dictation))
            self.indicator.show(.recording)
            await self.startSession()
        }
    }

    private func startSession() async {
        do {
            let session = try await sttEngine.makeSession(contextualStrings: [])
            // Only attach if we're still recording (user may have released).
            guard case .recording = state else {
                await session.cancel()
                return
            }
            self.session = session
            audio.onBuffer = { [weak session] buffer in
                session?.feed(buffer)
            }
        } catch {
            log.error("Failed to start STT session: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Speech model unavailable"))
            transition(.failed("Speech model unavailable"))
            scheduleErrorReset()
        }
    }

    private func endRecording() {
        armTask?.cancel()
        armTask = nil
        audio.onBuffer = nil
        stopAudio()

        switch state {
        case .recording:
            transition(.hotkeyUp)          // -> transcribing
            indicator.setState(.processing)
            Task { [weak self] in await self?.finishTranscription() }
        default:
            // Debounce hadn't fired, or an error is showing: nothing to finalize.
            if state.isBusy { transition(.cancel) }
            discardSession()
            indicator.hide()
        }
    }

    private func finishTranscription() async {
        guard let session else {
            state = .idle
            indicator.hide()
            return
        }
        self.session = nil
        do {
            let transcript = try await session.finish()
            log.info("Transcript: \(transcript, privacy: .public)")
            transition(.transcriptFinalized(transcript))
            guard !transcript.isEmpty else {
                // Machine already returned to idle on empty transcript.
                indicator.hide()
                return
            }
            // cleaning: run the LLM cleanup pass (or fast/deterministic path).
            let hint = AppProfileDefaults.hint(forBundleID: targetBundleID)
            let request = CleanupRequest(raw: transcript, dictionary: [], appHint: hint)
            let cleaned = await makeCleanupPipeline().cleanup(request)
            lastTranscript = cleaned
            transition(.cleaned(cleaned))       // cleaning -> injecting
            inject(cleaned)
        } catch {
            log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Transcription failed"))
            transition(.failed("Transcription failed"))
            scheduleErrorReset()
        }
    }

    /// Builds the cleanup chain from current settings. With a Groq key: Groq
    /// (fast, smart) with Apple Foundation Models as the offline fallback. With
    /// no key: an empty engine list, so the pipeline uses the fast deterministic
    /// LocalPolish — keeping the out-of-box experience quick.
    private func makeCleanupPipeline() -> CleanupPipeline {
        var engines: [any CleanupEngine] = []
        if let key = KeychainStore.get(.groqAPIKey), !key.isEmpty {
            engines.append(GroqCleanupEngine(apiKey: key))
            engines.append(FoundationModelCleanupEngine())
        }
        return CleanupPipeline(engines: engines)
    }

    private func inject(_ text: String) {
        do {
            try injector.inject(text)
            transition(.injected)          // -> idle
            indicator.hide()
        } catch InjectionError.secureInputActive {
            log.notice("Secure input active; text left on clipboard")
            indicator.setState(.error("Secure field — copied instead"))
            transition(.failed("Secure field — copied instead"))
            scheduleErrorReset()
        } catch InjectionError.accessibilityNotGranted {
            log.notice("Accessibility not granted; cannot inject")
            indicator.setState(.error("Grant Accessibility to insert text"))
            transition(.failed("Grant Accessibility"))
            scheduleErrorReset()
        } catch {
            log.error("Injection failed: \(error.localizedDescription, privacy: .public)")
            indicator.setState(.error("Couldn't insert text"))
            transition(.failed("Injection failed"))
            scheduleErrorReset()
        }
    }

    private func cancel() {
        armTask?.cancel()
        armTask = nil
        audio.onBuffer = nil
        stopAudio()
        if state.isBusy { transition(.cancel) }
        discardSession()
        indicator.hide()
    }

    private func discardSession() {
        guard let session else { return }
        self.session = nil
        Task { await session.cancel() }
    }

    private func scheduleErrorReset() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            if case .error = self.state {
                self.transition(.reset)
                self.indicator.hide()
            }
        }
    }

    // MARK: Audio

    private func startAudio() {
        do { try audio.start() } catch {
            log.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopAudio() {
        audio.stop()
    }

    // MARK: State machine

    private func transition(_ event: DictationEvent) {
        state = DictationStateMachine.reduce(state, event)
    }
}
