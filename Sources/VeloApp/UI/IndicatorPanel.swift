import SwiftUI
import AppKit
import QuartzCore
import IndicatorUI

/// Owns a borderless, non-activating floating `NSPanel` that hosts the SwiftUI
/// recording indicator. The panel floats above all apps and spaces and never
/// steals focus, so dictation into the focused app is unaffected.
@MainActor
final class IndicatorController {
    let model = IndicatorModel()
    private var panel: NSPanel?

    func show(_ state: IndicatorState) {
        model.state = state
        ensurePanel()
        reposition()
        panel?.orderFrontRegardless()
        // Ordering a window front only *marks* it for display on the next run-loop
        // pass. The recording pill is shown immediately before the caller dives
        // into synchronous session setup (a main-thread keychain read in
        // `sttEngine()`, dictionary/DB queries) that can hold the main thread long
        // enough to swallow that pass — leaving the panel `isVisible == true` but
        // never painted. Force the content to render now so the pill is on screen
        // the instant recording starts, regardless of what the caller does next.
        forceImmediateRender()
    }

    /// Synchronously lays out, draws, and *composites* the panel's hosting view so
    /// its pixels reach the screen before control returns, instead of on a later
    /// (possibly delayed) run-loop pass. `NSHostingView` is layer-backed, so
    /// `display()` alone only updates its Core Animation layer in-process — the
    /// WindowServer shows it only once the current `CATransaction` commits, which
    /// normally waits for the run loop. If the caller then blocks the main thread
    /// (e.g. a synchronous keychain read in session setup) that commit never fires
    /// and the "visible" panel stays blank. `CATransaction.flush()` pushes the
    /// layer state to the render server immediately, so the pill appears now.
    private func forceImmediateRender() {
        guard let panel else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
    }

    func update(level: Float) {
        model.level = level
    }

    func setState(_ state: IndicatorState) {
        model.state = state
    }

    func hide() {
        model.state = .hidden
        model.level = 0
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
