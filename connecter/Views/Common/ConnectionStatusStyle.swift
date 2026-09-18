import SwiftUI

extension ShareConfig.ConnectionStatus {
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
