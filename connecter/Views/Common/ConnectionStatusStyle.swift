import AppKit
import SwiftUI

extension ShareConfig.ConnectionStatus {
    var color: Color {
        switch self {
        case .disconnected:  .secondary
        case .connecting:    .orange
        case .connected:     .green
        case .disconnecting: .orange
        case .error:         .red
        case .offline:       .secondary
        }
    }

    var label: String {
        switch self {
        case .disconnected:  String(localized: "Disconnected")
        case .connecting:    String(localized: "Connecting…")
        case .connected:     String(localized: "Mounted")
        case .disconnecting: String(localized: "Disconnecting…")
        case .error:         String(localized: "Error")
        case .offline:       String(localized: "No network")
        }
    }

    /// SF Symbol used in the menu bar list.
    var menuIconName: String {
        switch self {
        case .disconnected:   "circle"
        case .connecting:     "arrow.trianglehead.2.clockwise"
        case .connected:      "checkmark.circle.fill"
        case .disconnecting:  "arrow.trianglehead.2.clockwise"
        case .error:          "xmark.circle.fill"
        case .offline:        "wifi.slash"
        }
    }

    /// Coloured, non-template version of `menuIconName` for use as a menu item
    /// image. A `MenuBarExtra` menu bridges each row to a plain `NSMenuItem`,
    /// which only supports a single-line title plus one image — a SwiftUI
    /// `Label` with `.foregroundStyle(color)` on its icon gets rasterised as a
    /// monochrome template image and loses its colour (same limitation worked
    /// around for the top-level icon in StatusBarIcon.swift). Baking the colour
    /// into the image itself and marking it non-template preserves it.
    var menuStatusImage: NSImage {
        let symbol = NSImage(
            systemSymbolName: menuIconName,
            accessibilityDescription: label
        )!.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))!

        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor(color).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = label
        return image
    }
}
