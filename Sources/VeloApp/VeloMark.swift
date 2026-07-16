import AppKit

/// The Velo brand mark — four rising bars (a voice gathering) terminating in a
/// text I-beam cursor — rendered as a menu-bar template glyph.
///
/// Per the Velo Logo System (Section 05, "Small Sizes"): at menu-bar size the
/// mark is a monochrome **template** glyph with no squircle and no fill tile, so
/// macOS tints it automatically for light/dark menu bars. Drawn from the brand
/// geometry (a 196×170 viewBox of seven rounded rects) so it stays crisp at any
/// scale — same source of truth as `Scripts/generate-icon.swift`.
enum VeloMark {
    // (x, y, w, h, cornerRadius) in the 196×170 viewBox, SVG (top-down) coords.
    private static let rects: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat)] = [
        (8, 57, 16, 56, 8),      // rising bar 1
        (40, 41, 16, 88, 8),     // rising bar 2
        (72, 24, 16, 122, 8),    // rising bar 3
        (104, 10, 16, 150, 8),   // rising bar 4 (tallest)
        (158, 10, 16, 150, 8),   // cursor shaft
        (144, 10, 44, 14, 7),    // cursor top cap
        (144, 146, 44, 14, 7),   // cursor bottom cap
    ]
    private static let viewBox = CGSize(width: 196, height: 170)

    /// Menu-bar glyph. `isTemplate` lets macOS tint it for the active menu bar;
    /// 18 pt tall matches the status-bar cap height.
    static var menuBarImage: NSImage {
        let height: CGFloat = 18
        let scale = height / viewBox.height
        let size = NSSize(width: viewBox.width * scale, height: height)
        // `flipped: true` → top-down coordinates, so the viewBox rects map directly.
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for m in rects {
                NSBezierPath(
                    roundedRect: CGRect(x: m.x * scale, y: m.y * scale,
                                        width: m.w * scale, height: m.h * scale),
                    xRadius: m.r * scale, yRadius: m.r * scale
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
