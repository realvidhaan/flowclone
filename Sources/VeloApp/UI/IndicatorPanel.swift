import SwiftUI
import AppKit
import QuartzCore
import IndicatorUI

/// Owns a borderless, non-activating floating `NSPanel` that hosts the SwiftUI
/// recording indicator.
///
/// The contract is that the pill is visible in *every* app the user dictates
/// into — ordinary windows, other apps' native-fullscreen Spaces, and over
/// higher-level overlay UI such as screen-share and call chrome. Two properties
/// buy that, and both must be re-asserted rather than set once:
///
/// - **Level.** The panel sits at `.screenSaver`, above `.popUpMenu` and above
///   the chrome other apps raise over their own windows. (The one thing no
///   AppKit window can cover is a fullscreen-exclusive game that owns the
///   display outright — an OS limit, not something to work around here.)
/// - **Space membership.** `.canJoinAllSpaces` is applied by the WindowServer
///   when the window is *ordered in*. Entering a fullscreen app creates a brand
///   new Space afterwards, which an already-ordered panel does not join on its
///   own — so we re-order on every active-space change.
///
/// Every visible state goes through `present(_:)`, which is the single path that
/// configures, positions, orders front, and renders. Nothing else orders the
/// panel in, so no state transition can be quietly left behind.
@MainActor
final class IndicatorController {
    let model = IndicatorModel()
    private var panel: NSPanel?

    /// Bumped on every `present`. Lets a delayed hide (e.g. the 1.5s transient
    /// error dismissal) no-op once a newer state has taken over the pill.
    private var presentToken: Int = 0
    private var isPresented = false

    // `nonisolated(unsafe)` so the nonisolated `deinit` can unregister them; they
    // are only ever assigned once, from `init`. Matches `AppController.wakeObserver`.
    nonisolated(unsafe) private var spaceObserver: NSObjectProtocol?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    init() {
        // Re-assert front-most-ness when the user moves to another Space. This is
        // what carries the pill into an app's native-fullscreen Space, which did
        // not exist when the panel was first ordered in.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.reassertIfPresented() }
        }
        // Displays added/removed/rearranged: the cached frame is now stale.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionIfPresented() }
        }
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: Presentation

    /// Shows `state` on the pill and guarantees it is on screen, on the current
    /// Space, above other windows, and painted before returning.
    ///
    /// Returns a token to hand to `hide(token:)` if the caller intends to dismiss
    /// *this particular* state after a delay.
    @discardableResult
    func present(_ state: IndicatorState) -> Int {
        model.state = state
        presentToken &+= 1
        isPresented = true

        let panel = ensurePanel()
        // Level and collection behavior are re-applied rather than trusted to
        // stick: AppKit re-manages a floating panel's level across activation
        // changes, and re-stating the behavior before ordering in is what makes
        // the WindowServer bind the panel to the Space we're about to show it on.
        configure(panel)
        reposition(panel)
        panel.orderFrontRegardless()
        render(panel)
        return presentToken
    }

    /// Feeds the live mic level. Deliberately model-only: this runs once per audio
    /// buffer, so it must not re-order the window or force a synchronous flush.
    func update(level: Float) {
        model.level = level
    }

    /// Hides the pill unconditionally. Used by the deterministic teardown paths,
    /// which always mean "this session is over, take it down".
    func hide() {
        isPresented = false
        model.state = .hidden
        model.level = 0
        panel?.orderOut(nil)
    }

    /// Hides only if `token` is still the state currently on screen. A delayed
    /// dismissal must not tear down a pill that a newer session has since put up.
    func hide(token: Int) {
        guard token == presentToken else { return }
        hide()
    }

    // MARK: Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        configure(panel)
        self.panel = panel
        return panel
    }

    /// The properties that decide *where in the window hierarchy* the pill lives.
    /// Split out because they must be re-applied on every present and on every
    /// space change, not just at construction.
    private func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        // Above `.popUpMenu` (101) and above the chrome apps raise over their own
        // fullscreen windows. Not `CGShieldingWindowLevel()` — that would also
        // draw over the screensaver and login window, which we have no business
        // covering.
        panel.level = .screenSaver
        // `.canJoinAllSpaces` + `.stationary`: show on whatever Space is active and
        // don't slide during Space transitions. `.fullScreenAuxiliary`: allowed
        // alongside another app's fullscreen window. `.ignoresCycle`: keep the pill
        // out of Cmd-` window cycling.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // We never activate (Velo is `LSUIElement`), so the panel must survive the
        // app "losing" focus it never had.
        panel.hidesOnDeactivate = false
    }

    private func reassertIfPresented() {
        guard isPresented, let panel else { return }
        configure(panel)
        reposition(panel)
        panel.orderFrontRegardless()
        render(panel)
    }

    private func repositionIfPresented() {
        guard isPresented, let panel else { return }
        reposition(panel)
    }

    /// Bottom-centers the pill on the screen the user is actually working on.
    ///
    /// `NSScreen.main` is documented as the screen holding the *key window* —
    /// Velo is a menu-bar agent and never has one, so it is not a reliable anchor.
    /// The pointer is the best available proxy for the user's attention.
    private func reposition(_ panel: NSPanel) {
        guard let screen = activeScreen() else { return }
        // Size to content *before* centering. The panel is born at a placeholder
        // 160x44, and the hosting view only adopts the pill's real width once laid
        // out — centering against the placeholder leaves the first show off-center.
        if let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            if fitting.width > 0, fitting.height > 0, fitting != panel.frame.size {
                panel.setContentSize(fitting)
            }
        }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Synchronously lays out, draws, and *composites* the panel's hosting view so
    /// its pixels reach the screen before control returns, instead of on a later
    /// (possibly delayed) run-loop pass. `NSHostingView` is layer-backed, so
    /// `display()` alone only updates its Core Animation layer in-process — the
    /// WindowServer shows it only once the current `CATransaction` commits, which
    /// normally waits for the run loop. If the caller then blocks the main thread
    /// (e.g. the synchronous keychain read in session setup, which `present` is
    /// called immediately before) that commit never fires and the "visible" panel
    /// stays blank. `CATransaction.flush()` pushes the layer state to the render
    /// server immediately, so the pill appears now.
    private func render(_ panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        CATransaction.flush()
    }
}
