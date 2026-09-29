import AppKit

/// Small flat-colour status dot with a soft shadow, drawn inline in the text
/// of each menu bar row.
///
/// Rows of a `MenuBarExtra` menu are bridged to `NSMenuItem`s whose separate
/// icon images aren't shown, but their attributed title is drawn as-is — so the
/// dot travels inside the text as an inline image. Emoji would also render
/// there, but they can't be flat-coloured or shadowed, nor sized precisely.
enum MenuDot {
    /// Circle diameter — about half the height of the menu text.
    static let diameter: CGFloat = 7
    /// Room around the circle for the shadow.
    static let padding: CGFloat = 1.5

    /// Vertical offset applied to the dot in the row text. Shifting down by the
    /// padding puts the circle's bottom exactly on the baseline, but a round
    /// shape there reads as sitting too low, so it's lifted one Retina pixel.
    static let baselineOffset: CGFloat = -padding + 0.5

    static let mounted = make(.systemGreen)
    static let busy = make(.systemOrange)
    static let error = make(.systemRed)
    static let idle = make(NSColor(srgbRed: 0.80, green: 0.80, blue: 0.82, alpha: 1))

    static func image(for status: ShareConfig.ConnectionStatus) -> NSImage {
        switch status {
        case .connected:                  mounted
        case .connecting, .disconnecting: busy
        case .error:                      error
        case .disconnected, .offline:     idle
        }
    }

    private static func make(_ color: NSColor) -> NSImage {
        let side = diameter + padding * 2
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.shadowBlurRadius = 1
            shadow.set()
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: padding, y: padding, width: diameter, height: diameter)).fill()
            return true
        }
        image.isTemplate = false   // keep the colour; template images get tinted
        return image
    }
}
