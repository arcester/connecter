import SwiftUI

extension ShareConfig.ConnectionStatus {
    var iconName: String {
        switch self {
        case .disconnected:  "externaldrive"
        case .connecting:    "arrow.trianglehead.2.clockwise"
        case .connected:     "externaldrive.fill.badge.checkmark"
        case .disconnecting: "arrow.trianglehead.2.clockwise"
        case .error:         "externaldrive.badge.xmark"
        }
    }

    var color: Color {
        switch self {
        case .disconnected:  .secondary
        case .connecting:    .orange
        case .connected:     .green
        case .disconnecting: .orange
        case .error:         .red
        }
    }

    var label: String {
        switch self {
        case .disconnected:  String(localized: "Disconnected")
        case .connecting:    String(localized: "Connecting…")
        case .connected:     String(localized: "Mounted")
        case .disconnecting: String(localized: "Disconnecting…")
        case .error:         String(localized: "Error")
        }
    }
}
