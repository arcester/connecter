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

    /// Coloured dot for the menu bar list. Rows of a `MenuBarExtra` menu are
    /// bridged to plain `NSMenuItem`s that don't draw SwiftUI label icons at
    /// all (neither SF Symbols nor custom `NSImage`s — only the status item's
    /// own label supports images, see StatusBarIcon.swift). Emoji are text, so
    /// they always render and keep their colour.
    var menuDot: String {
        switch self {
        case .connected:                  "🟢"
        case .connecting, .disconnecting: "🟠"
        case .error:                      "🔴"
        case .disconnected, .offline:     "⚪️"
        }
    }
}
