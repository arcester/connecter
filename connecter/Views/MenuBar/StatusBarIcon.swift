import AppKit
import SwiftUI

/// Builds the menu bar image: the folder symbol plus a small colour dot only
/// when something needs attention (orange = partial or connecting, red = error
/// or stuck NetAuth). All mounted, or nothing enabled, shows the plain folder. Drawn with AppKit because `MenuBarExtra`
/// rasterises composite SwiftUI labels as monochrome template images.
///
/// The image uses a drawing handler, so AppKit re-renders it with the menu
/// bar's own appearance: the folder follows the label colour (light or dark
/// menu bar) while the dot keeps its colour.
enum StatusBarIcon {

    /// Point size of the symbol, matching other menu bar extras.
    private static let symbolSize: CGFloat = 16

    static func image(for status: MountManager.OverallStatus) -> NSImage {
        guard let dot = dotColor(for: status) else {
            // Nothing to report: a plain template symbol, exactly like the system's.
            let plain = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .regular))!
            plain.isTemplate = true
            return plain
        }

        let symbol = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: symbolSize, weight: .regular))!
        let size = NSSize(width: symbol.size.width + 3, height: symbol.size.height + 1)
        let dotDiameter: CGFloat = 7

        let image = NSImage(size: size, flipped: false) { rect in
            // Folder in the current label colour (resolved for the menu bar's appearance).
            let symbolRect = NSRect(x: 0, y: 1, width: symbol.size.width, height: symbol.size.height)
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.labelColor.set()
            symbolRect.fill(using: .sourceAtop)

            // Dot at the bottom-right, with a gap so it reads against the folder.
            let dotRect = NSRect(x: rect.maxX - dotDiameter, y: 0, width: dotDiameter, height: dotDiameter)
            let gap = dotRect.insetBy(dx: -1.5, dy: -1.5)
            if let context = NSGraphicsContext.current {
                context.saveGraphicsState()
                context.compositingOperation = .destinationOut   // punch a hole around the dot
                NSBezierPath(ovalIn: gap).fill()
                context.restoreGraphicsState()
            }
            dot.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = String(localized: "Connecter")
        return image
    }

    private static func dotColor(for status: MountManager.OverallStatus) -> NSColor? {
        switch status {
        case .idle:       nil
        case .allMounted: nil
        case .partial:    .systemOrange
        case .error:      .systemRed
        }
    }
}
