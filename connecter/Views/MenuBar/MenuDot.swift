import AppKit

/// Flat status dot drawn inline in the text of each menu bar row, in the style
/// of Finder's sidebar tags: crisp fill, a hairline darker rim, no shadow.
///
/// Rows of a `MenuBarExtra` menu are bridged to `NSMenuItem`s whose separate
/// icon images aren't shown, but their attributed title is drawn as-is — so the
/// dot travels inside the text as an inline image.
enum MenuDot {
    /// Circle diameter, like Finder's tag dots next to 13 pt text.
    static let diameter: CGFloat = 9
    /// Space between the dot and the text (part of the image so the gap is stable).
    static let trailingGap: CGFloat = 6

    /// The image's bottom sits on the text baseline; with a 9 pt circle that
    /// centres it on the cap height of the menu font, as Finder does.
    static let baselineOffset: CGFloat = 0

    static let mounted = make(.systemGreen)
    static let busy = make(.systemOrange)
    static let error = make(.systemRed)
    static let idle = make(.systemGray)

    static func image(for status: ShareConfig.ConnectionStatus) -> NSImage {
        switch status {
        case .connected:                  mounted
        case .connecting, .disconnecting: busy
        case .error:                      error
        case .disconnected, .offline:     idle
        }
    }

    private static func make(_ color: NSColor) -> NSImage {
        let size = NSSize(width: diameter + trailingGap, height: diameter)
        let image = NSImage(size: size, flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter))
            color.setFill()
            circle.fill()
            // Hairline rim, slightly darker than the fill, keeps the edge crisp on light backgrounds.
            let rim = NSBezierPath(ovalIn: NSRect(x: 0.25, y: 0.25, width: diameter - 0.5, height: diameter - 0.5))
            rim.lineWidth = 0.5
            color.blended(withFraction: 0.25, of: .black)?.setStroke()
            rim.stroke()
            return true
        }
        image.isTemplate = false   // keep the colour; template images get tinted
        return image
    }
}
