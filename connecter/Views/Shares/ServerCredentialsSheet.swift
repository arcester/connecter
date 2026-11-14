import SwiftUI

/// A server's addresses (main and others) and the user and password shared
/// by its shares that inherit them.
struct ServerCredentialsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var mountManager: MountManager
    let host: String

    @State private var mainHost = ""
    @State private var otherHosts = ""
    @State private var username = ""
    @State private var password = ""

    /// The main address as typed, without `smb://` or slashes.
    private var cleanMainHost: String {
        ServerSettings.parseHosts(mainHost, excluding: "").first ?? ""
    }

    /// The new main address is already another server in the list.
    private var isOtherServer: Bool {
        let key = cleanMainHost.lowercased()
        return key != host.lowercased() && mountManager.configs.contains { $0.serverKey == key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Server Settings")
                .font(.title2.bold())

            GlassSection(label: "Addresses") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Main").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("192.168.1.1 or server.local", text: $mainHost)
                    }
                    GridRow {
                        Text("Others").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("nas.vpn.lan, 10.8.0.5", text: $otherHosts)
                    }
                }
                if isOtherServer {
                    Label("Another server in the list already uses this address.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Use the others for the same server reached another way, such as its name or IP on a VPN; separate them with commas. Before each mount, Connecter checks every address at once and uses the first one that answers, in order: the main one, then the others. A share mounted through any of them counts as mounted. Shares mounted through an address you remove are mounted again through the rest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassSection(label: "Credentials") {
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
                Button("Save", action: save)
                    .modifier(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanMainHost.isEmpty || isOtherServer)
            }
        }
        .padding(24)
        .modifier(SheetWidth())
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            mainHost = host
            otherHosts = (mountManager.settings(forHost: host).otherHosts ?? []).joined(separator: ", ")
            username = mountManager.settings(forHost: host).username
            password = KeychainManager.load(
                for: .serverCredentials(host: host, username: username)
            ).password ?? ""
        }
    }

    private func save() {
        let newHost = cleanMainHost
        let others = ServerSettings.parseHosts(otherHosts, excluding: newHost)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressesChanged = newHost != host
            || others != (mountManager.settings(forHost: host).otherHosts ?? [])
        let manager = mountManager
        let password = password
        Task {
            // Addresses first: a new main address moves the credentials with it.
            if addressesChanged {
                await manager.setAddresses(host: host, main: newHost, others: others)
            }
            manager.setServerCredentials(host: newHost, username: user, password: password)
        }
        dismiss()
    }
}
