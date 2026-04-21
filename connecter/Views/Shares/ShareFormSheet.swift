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
    @State private var discoveredShares: [DiscoveredShare] = []
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
    private var isValid: Bool { !host.isEmpty && !path.isEmpty }

    private func applyDiscovered(_ d: DiscoveredShare) {
        name = d.volumeName
        host = d.serverHost
        path = d.sharePath
        if let u = d.loginUser { username = u }
    }

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
                        ForEach(discoveredShares) { d in
                            DiscoveredShareButton(d: d, onSelect: { applyDiscovered(d) })
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
                            .disabled(host.isEmpty || isTestingConnection)

                            if let passed = connectionTestPassed {
                                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(passed ? .green : .red)
                                Text(passed ? "Port 445 reachable" : "Port 445 unreachable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
            }

            HStack {
                if isEditing, onDelete != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete share", systemImage: "trash")
                    }
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
                        name: name,
                        host: host,
                        path: path,
                        username: username,
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
            if !isEditing {
                discoveredShares = discoverMountedSMBShares(excluding: ShareConfig.loadAll())
            }
        }
    }
}

// MARK: - Connection test

extension ShareFormSheet {
    /// Tests TCP connectivity to port 445 (SMB) on the current host.
    /// Uses `nc -z` for a non-blocking probe with a 3-second timeout.
    func testConnection() async {
        guard !host.isEmpty else { return }
        isTestingConnection = true
        connectionTestPassed = nil
        let h = host

        let success = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-z", "-w", "3", h, "445"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value

        isTestingConnection = false
        connectionTestPassed = success
    }
}

// MARK: - Discovered share model

struct DiscoveredShare: Identifiable {
    let id = UUID()
    let volumeName: String
    let serverHost: String
    let sharePath: String
    let loginUser: String?
}

/// Button row for a single discovered share.
struct DiscoveredShareButton: View {
    let d: DiscoveredShare
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.volumeName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("smb://\(d.serverHost)/\(d.sharePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SMB share discovery

func discoverMountedSMBShares(excluding existing: [ShareConfig]) -> [DiscoveredShare] {
    let keys: Set<URLResourceKey> = [.volumeURLForRemountingKey, .volumeLocalizedNameKey]
    guard let volumes = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: []
    ) else { return [] }

    return volumes.compactMap { url in
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let remountURL = values.volumeURLForRemounting,
            remountURL.scheme == "smb",
            let host = remountURL.host, !host.isEmpty
        else { return nil }

        let volName = values.volumeLocalizedName ?? url.lastPathComponent
        let rawPath = remountURL.path
        let sharePath = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath

        if existing.contains(where: { $0.host == host && $0.path == sharePath }) { return nil }

        return DiscoveredShare(
            volumeName: volName, serverHost: host, sharePath: sharePath, loginUser: remountURL.user
        )
    }
}
