import SwiftUI

struct ShareFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: ShareConfig?
    let onSave: (ShareConfig) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var name: String
    @State private var host: String
    @State private var path: String
    @State private var username: String
    @State private var password: String
    @State private var showDeleteConfirmation = false
    @State private var allConfigs: [ShareConfig] = []
    @State private var discoveredShares: [MountedSMBVolume] = []
    @State private var isTestingConnection = false
    @State private var connectionTestPassed: Bool? = nil

    init(existing: ShareConfig?, onSave: @escaping (ShareConfig) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _name     = State(initialValue: existing?.name ?? "")
        _host     = State(initialValue: existing?.host ?? "")
        _path     = State(initialValue: existing?.path ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _password = State(initialValue: existing?.password ?? "")
    }

    private var isEditing: Bool { existing != nil }

    // MARK: - Normalised input

    private var cleanHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private var cleanPath: String { MountManager.normalizedSharePath(path) }

    /// Another configured share already points at the same host and path.
    private var isDuplicate: Bool {
        allConfigs.contains {
            $0.id != existing?.id
                && $0.host.caseInsensitiveCompare(cleanHost) == .orderedSame
                && MountManager.normalizedSharePath($0.path).caseInsensitiveCompare(cleanPath) == .orderedSame
        }
    }

    private var isValid: Bool { !cleanHost.isEmpty && !cleanPath.isEmpty && !isDuplicate }

    private func applyDiscovered(_ volume: MountedSMBVolume) {
        name = volume.volumeName
        host = volume.host
        path = volume.sharePath
        if let user = volume.user { username = user }
    }

    /// Accepts a pasted `smb://host/share` and splits it into host and path.
    private func parseHostInput(_ raw: String) {
        var value = raw
        for prefix in ["smb://", "smb:", "//"] {
            if value.lowercased().hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        if let slashIndex = value.firstIndex(of: "/") {
            let extractedPath = String(value[value.index(after: slashIndex)...])
            host = String(value[..<slashIndex])
            if !extractedPath.isEmpty { path = extractedPath }
        } else {
            host = value
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isEditing ? "Edit SMB share" : "New SMB share")
                .font(.title2.bold())

            if !isEditing && !discoveredShares.isEmpty {
                GlassSection(label: "Mounted in Finder") {
                    VStack(spacing: 0) {
                        ForEach(discoveredShares) { volume in
                            DiscoveredShareButton(volume: volume, onSelect: { applyDiscovered(volume) })
                        }
                    }
                }
            }

            GlassSection(label: "Identification") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("Optional", text: $name)
                    }
                    GridRow {
                        Text("Host / IP").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("192.168.1.1 or server.local", text: $host)
                            .onChange(of: host) { _, new in
                                let lower = new.lowercased()
                                if lower.hasPrefix("smb:") || lower.hasPrefix("//") {
                                    parseHostInput(new)
                                }
                            }
                    }
                    GridRow {
                        Text("Path").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("share-name", text: $path)
                    }
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        HStack(spacing: 8) {
                            Button {
                                Task { await testConnection() }
                            } label: {
                                if isTestingConnection {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Test connection", systemImage: "network")
                                }
                            }
                            .disabled(cleanHost.isEmpty || isTestingConnection)

                            if let passed = connectionTestPassed {
                                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(passed ? .green : .red)
                                    .accessibilityHidden(true)
                                Text(passed ? "Port 445 reachable" : "Port 445 unreachable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if isDuplicate {
                    Label("This share is already configured.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .onChange(of: host) { connectionTestPassed = nil }

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
                Text("Leave the password empty to use the one Finder saved for this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if isEditing, onDelete != nil {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .help("Delete share")
                    .accessibilityLabel(Text("Delete share"))
                    .confirmationDialog(
                        "Delete \"\(name.isEmpty ? host : name)\"?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            onDelete?()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }

                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    let config = ShareConfig(
                        id: existing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        host: cleanHost,
                        path: cleanPath,
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        isEnabled: existing?.isEnabled ?? true,
                        connectionStatus: existing?.connectionStatus ?? .disconnected
                    )
                    onSave(config)
                    dismiss()
                }
                .modifier(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            allConfigs = ShareConfig.loadAll()
            if !isEditing {
                discoveredShares = MountManager.mountedSMBVolumes().filter { volume in
                    !allConfigs.contains {
                        $0.host.caseInsensitiveCompare(volume.host) == .orderedSame
                            && MountManager.normalizedSharePath($0.path)
                                .caseInsensitiveCompare(volume.sharePath) == .orderedSame
                    }
                }
            }
        }
    }
}

// MARK: - Connection test

extension ShareFormSheet {
    /// Tests TCP connectivity to port 445 (SMB) on the current host with a 3-second timeout.
    func testConnection() async {
        let target = cleanHost
        guard !target.isEmpty else { return }
        isTestingConnection = true
        connectionTestPassed = nil
        let success = await PortProbe.isOpen(host: target)
        isTestingConnection = false
        connectionTestPassed = success
    }
}

// MARK: - Discovered share row

extension MountedSMBVolume: Identifiable {
    var id: String { mountPoint }
}

/// Button row for an SMB volume that Finder already has mounted.
struct DiscoveredShareButton: View {
    let volume: MountedSMBVolume
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.volumeName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: "smb://\(volume.host)/\(volume.sharePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(AppSettings.shared.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Use this share")
    }
}
