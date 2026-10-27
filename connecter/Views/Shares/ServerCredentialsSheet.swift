import SwiftUI

/// User and password shared by the shares of one server that inherit them.
struct ServerCredentialsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mountManager: MountManager
    let host: String

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Server Credentials")
                .font(.title2.bold())

            GlassSection(label: LocalizedStringKey(host)) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Username").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("Optional", text: $username)
                    }
                    GridRow {
                        Text("Password").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        SecureField("Optional", text: $password)
                    }
                }
                Text("Used by the shares on this server that have “Use the server’s credentials” turned on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    mountManager.setServerCredentials(
                        host: host,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password
                    )
                    dismiss()
                }
                .modifier(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            username = mountManager.settings(forHost: host).username
            password = KeychainManager.load(
                for: .serverCredentials(host: host, username: username)
            ).password ?? ""
        }
    }
}
