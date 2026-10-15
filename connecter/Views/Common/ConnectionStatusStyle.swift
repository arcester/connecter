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
        case .unreachable:   .secondary
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
        case .unreachable:   String(localized: "Server unreachable")
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
        case .unreachable:    "wifi.exclamationmark"
        }
    }
}
