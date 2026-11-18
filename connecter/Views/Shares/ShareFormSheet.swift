import SwiftUI

struct ShareFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: ShareConfig?
    let onSave: (ShareConfig) -> Void
    /// Set when adding: lets the user add several shares of a server at once.
    var onAddShares: (([ShareConfig]) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var name: String
    @State private var host: String
    @State private var path: String
    @State private var username: String
    @State private var password: String
    @State private var usesServerCredentials: Bool
    /// Shown instead of "Use the server's credentials" while the server has none:
    /// the share's user and password become the server's.
    @State private var savesServerCredentials: Bool
    @State private var showDeleteConfirmation = false
    @State private var allConfigs: [ShareConfig] = []
    @State private var discoveredShares: [MountedSMBVolume] = []
    @State private var isTestingConnection = false
    @State private var connectionTestPassed: Bool? = nil
    // Adding a whole server
    @State private var addsServer = false
    @State private var isChoosingShares = false
    @State private var pickerError: String?
    @State private var pickerFinished = false
    @State private var serverVolumes: [MountedSMBVolume] = []
    @State private var selectedVolumes: Set<String> = []   // mount points

    /// `initialHost` pre-fills a new share (added from a server's menu).
    init(existing: ShareConfig?, initialHost: String = "", onSave: @escaping (ShareConfig) -> Void,
         onAddShares: (([ShareConfig]) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave
        self.onAddShares = onAddShares
        self.onDelete = onDelete
        _name     = State(initialValue: existing?.name ?? "")
        _host     = State(initialValue: existing?.host ?? initialHost)
        _path     = State(initialValue: existing?.path ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _password = State(initialValue: existing?.password ?? "")
        _usesServerCredentials = State(initialValue: existing?.usesServerCredentials
            ?? !MountManager.shared.settings(forHost: initialHost).username.isEmpty)
        _savesServerCredentials = State(initialValue: existing == nil)
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

    /// User of the server's shared credentials; empty when it has none.
    private var serverUsername: String { MountManager.shared.settings(forHost: cleanHost).username }

    private var isValid: Bool { !cleanHost.isEmpty && !cleanPath.isEmpty && !isDuplicate }

    /// The server has credentials to inherit (or this share already inherits them).
    private var offersServerCredentials: Bool {
        !cleanHost.isEmpty && (!serverUsername.isEmpty || usesServerCredentials)
    }

    /// Already in the list, through the server's host or any of its other addresses.
    private func isConfigured(_ volume: MountedSMBVolume) -> Bool {
        allConfigs.contains { config in
            MountManager.shared.hosts(for: config).contains { $0.caseInsensitiveCompare(volume.host) == .orderedSame }
                && config.normalizedPath.caseInsensitiveCompare(volume.sharePath) == .orderedSame
        }
    }

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

            if !isEditing && onAddShares != nil {
                Picker("Add", selection: $addsServer) {
                    Text("One share").tag(false)
                    Text("Shares of a server").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            if addsServer {
                serverSections
            } else {
                shareSections
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
                if !addsServer {
                    testConnectionButton
                }

                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    if addsServer {
                        addServerShares()
                        return
                    }
                    let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    let savesForServer = savesServerCredentials && !offersServerCredentials && !cleanHost.isEmpty
                    if savesForServer {
                        MountManager.shared.setServerCredentials(host: cleanHost, username: user, password: password)
                    }
                    let config = ShareConfig(
                        id: existing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        host: cleanHost,
                        path: cleanPath,
                        username: savesForServer ? "" : user,
                        password: savesForServer ? "" : password,
                        isEnabled: existing?.isEnabled ?? true,
                        usesServerCredentials: savesForServer || (usesServerCredentials && offersServerCredentials),
                        connectionStatus: existing?.connectionStatus ?? .disconnected
                    )
                    onSave(config)
                    dismiss()
                }
                .modifier(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(addsServer ? selectedVolumes.isEmpty : !isValid)
            }
        }
        .padding(24)
        .modifier(SheetWidth())
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            allConfigs = MountManager.shared.configs
            // Shares mounted in Finder but not in the app: start with picking one
            // of them; otherwise with the server's shares.
            // Added from the menu of a server that has credentials: go straight to
            // its shares, mounted ones first, then macOS's list of all of them.
            let opensServer = !isEditing && onAddShares != nil && !cleanHost.isEmpty && !serverUsername.isEmpty
            if !isEditing && onAddShares != nil {
                addsServer = opensServer || !MountManager.shared.mountedVolumes.contains { !isConfigured($0) }
            }
            if !isEditing {
                Task {
                    // Scan off the main actor: a slow SMB mount must not freeze the sheet.
                    let volumes = await MountManager.shared.refreshMountedVolumes()
                    discoveredShares = volumes.filter { !isConfigured($0) }
                    guard opensServer else { return }
                    let addresses = MountManager.shared.hosts(for: ShareConfig(host: cleanHost))
                    addServerVolumes(discoveredShares.filter { volume in
                        addresses.contains { $0.caseInsensitiveCompare(volume.host) == .orderedSame }
                    })
                    guard addsServer else { return }   // the user switched to "One share"
                    loadServerCredentials()
                    await chooseServerShares()
                }
            }
        }
    }
}

// MARK: - Sections

extension ShareFormSheet {
    @ViewBuilder
    private var shareSections: some View {
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
            }
            if isDuplicate {
                Label("This share is already configured.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: host) {
            connectionTestPassed = nil
            // A new share inherits by default on a server that has credentials.
            if !isEditing { usesServerCredentials = !serverUsername.isEmpty }
        }

        GlassSection(label: "Credentials") {
            if offersServerCredentials {
                Toggle("Use the server’s credentials", isOn: $usesServerCredentials)
            }
            if usesServerCredentials && offersServerCredentials {
                if serverUsername.isEmpty {
                    Label("This server has no credentials yet. Set them with “Server Settings…” in the server’s menu.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Mounts as \(serverUsername), the user set for \(cleanHost).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
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
                if existing?.passwordUnavailable == true {
                    Label("The saved password could not be read from the Keychain. Enter it again to replace it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Leave the password empty to use the one Finder saved for this server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !offersServerCredentials && !cleanHost.isEmpty {
                    Toggle("Save as this server’s credentials", isOn: $savesServerCredentials)
                        .help("Other shares of this server can then use them")
                }
            }
        }
    }

    /// Bottom-left, next to the result; needs the host and the share.
    private var testConnectionButton: some View {
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
            .disabled(!isValid || isTestingConnection)

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

// MARK: - Adding a whole server

extension ShareFormSheet {
    @ViewBuilder
    private var serverSections: some View {
        GlassSection(label: "Server") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Host / IP").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("192.168.1.1 or server.local", text: $host)
                }
                GridRow {
                    Text("Username").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("Optional", text: $username)
                }
                GridRow {
                    Text("Password").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    SecureField("Optional", text: $password)
                }
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    HStack(spacing: 8) {
                        Button {
                            Task { await chooseServerShares() }
                        } label: {
                            Label("Choose Shares…", systemImage: "externaldrive.connected.to.line.below")
                        }
                        .disabled(cleanHost.isEmpty || isChoosingShares)
                        if isChoosingShares {
                            ProgressView().controlSize(.small)
                            Text("Pick the shares in the macOS window")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let pickerError {
                Label(pickerError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("macOS lists the server’s shares and mounts the ones you pick. They are added with these credentials as the server’s.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: host) {
            serverVolumes = []
            selectedVolumes = []
            pickerFinished = false
            pickerError = nil
            loadServerCredentials()
        }
        .onAppear { loadServerCredentials() }

        if !serverVolumes.isEmpty {
            GlassSection(label: "Shares to Add") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(serverVolumes) { volume in
                        Toggle(isOn: Binding(
                            get: { selectedVolumes.contains(volume.mountPoint) },
                            set: { isOn in
                                if isOn {
                                    selectedVolumes.insert(volume.mountPoint)
                                } else {
                                    selectedVolumes.remove(volume.mountPoint)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: volume.volumeName)
                                Text(verbatim: "smb://\(volume.host)/\(volume.sharePath)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if pickerFinished {
            Label("The shares you picked are already in Connecter.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Fills in the server's saved user and password, when it has them.
    private func loadServerCredentials() {
        let user = serverUsername
        guard !user.isEmpty else { return }
        username = user
        password = KeychainManager.load(for: .serverCredentials(host: cleanHost, username: user)).password ?? ""
    }

    private func chooseServerShares() async {
        isChoosingShares = true
        pickerError = nil
        defer { isChoosingShares = false }
        do {
            let volumes = try await MountManager.shared.mountSharesFromSystemPicker(
                host: cleanHost,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            addServerVolumes(volumes.filter { !isConfigured($0) })
            pickerFinished = true
        } catch is CancellationError {
            // The user closed the macOS window: nothing to show.
        } catch MountError.serverUnreachable {
            pickerError = String(localized: "Port 445 unreachable")
        } catch MountError.mountTimedOut {
            pickerError = String(localized: "The macOS window for choosing shares did not finish in time.")
        } catch {
            pickerError = String(localized: "macOS could not mount the shares. The activity log has the details.")
        }
    }

    /// Lists (and ticks) volumes not listed yet; keeps the ones already there.
    private func addServerVolumes(_ volumes: [MountedSMBVolume]) {
        let new = volumes.filter { volume in !serverVolumes.contains { $0.mountPoint == volume.mountPoint } }
        serverVolumes += new
        selectedVolumes.formUnion(new.map(\.mountPoint))
    }

    /// Adds the picked shares on the server's credentials. With no user typed,
    /// the one macOS mounted them as is kept, so they find the password the
    /// system Keychain saved for it.
    private func addServerShares() {
        let chosen = serverVolumes.filter { selectedVolumes.contains($0.mountPoint) }
        let typedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        MountManager.shared.setServerCredentials(
            host: cleanHost,
            username: typedUser.isEmpty ? (chosen.compactMap(\.user).first ?? "") : typedUser,
            password: password
        )
        onAddShares?(chosen.map {
            ShareConfig(name: $0.volumeName, host: cleanHost, path: $0.sharePath, usesServerCredentials: true)
        })
        dismiss()
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
