import SwiftUI

/// Edits one share, or adds shares to a server: pick the server (or type a
/// new one), its credentials and the shares — the ones already mounted in
/// Finder, the ones picked in macOS's window, or one typed by name.
struct ShareFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existing: ShareConfig?
    /// Server picked when the sheet opens (added from a server's menu).
    let initialHost: String
    let onSave: (ShareConfig) -> Void
    /// Set when adding.
    var onAddShares: (([ShareConfig]) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var name: String
    @State private var host: String
    @State private var path: String
    @State private var username: String
    @State private var password: String
    @State private var usesServerCredentials: Bool
    /// Editing, on a server with no credentials: the share's user and
    /// password become the server's.
    @State private var savesServerCredentials = false
    @State private var showDeleteConfirmation = false
    @State private var allConfigs: [ShareConfig] = []
    /// SMB volumes mounted on this Mac that no share in the list matches.
    @State private var discoveredShares: [MountedSMBVolume] = []
    @State private var isTestingConnection = false
    @State private var connectionTestPassed: Bool? = nil
    // Adding
    /// Main host of the server the shares are added to; empty: a new one, typed in `host`.
    @State private var selectedServer = ""
    @State private var serverWasChosen = false
    @State private var isChoosingShares = false
    @State private var pickerError: String?
    @State private var pickerFinished = false
    @State private var serverVolumes: [MountedSMBVolume] = []
    @State private var selectedVolumes: Set<String> = []   // mount points

    init(existing: ShareConfig?, initialHost: String = "", onSave: @escaping (ShareConfig) -> Void = { _ in },
         onAddShares: (([ShareConfig]) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.initialHost = initialHost
        self.onSave = onSave
        self.onAddShares = onAddShares
        self.onDelete = onDelete
        _name     = State(initialValue: existing?.name ?? "")
        _host     = State(initialValue: existing?.host ?? "")
        _path     = State(initialValue: existing?.path ?? "")
        _username = State(initialValue: existing?.username ?? "")
        _password = State(initialValue: existing?.password ?? "")
        _usesServerCredentials = State(initialValue: existing?.usesServerCredentials ?? true)
    }

    private var isEditing: Bool { existing != nil }

    // MARK: - Normalised input

    private var cleanHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    private var cleanPath: String { MountManager.normalizedSharePath(path) }

    /// The server the share belongs to: the one picked, or the one typed —
    /// as its server's main host when it is one of its other addresses.
    private var targetHost: String {
        if !isEditing && !selectedServer.isEmpty { return selectedServer }
        return MountManager.shared.serverHost(forAddress: cleanHost) ?? cleanHost
    }

    /// The server already has a share at `path` (other than the one edited).
    private func isInList(path: String) -> Bool {
        let key = targetHost.lowercased()
        return allConfigs.contains {
            $0.id != existing?.id && $0.serverKey == key
                && $0.normalizedPath.caseInsensitiveCompare(path) == .orderedSame
        }
    }

    private var isDuplicate: Bool { !cleanPath.isEmpty && isInList(path: cleanPath) }

    /// User of the server's shared credentials; empty when it has none.
    private var serverUsername: String { MountManager.shared.settings(forHost: targetHost).username }

    private var isValid: Bool { !cleanHost.isEmpty && !cleanPath.isEmpty && !isDuplicate }

    /// Adding: a server, and some shares ticked or one typed.
    private var canAdd: Bool {
        !targetHost.isEmpty && !isChoosingShares && !isDuplicate
            && (!selectedVolumes.isEmpty || !cleanPath.isEmpty)
    }

    /// The server has credentials to inherit (or this share already inherits them).
    private var offersServerCredentials: Bool {
        !targetHost.isEmpty && (!serverUsername.isEmpty || usesServerCredentials)
    }

    /// Already in the list, through the server's host or any of its other addresses.
    private func isConfigured(_ volume: MountedSMBVolume) -> Bool {
        allConfigs.contains { config in
            MountManager.shared.hosts(for: config).contains { $0.caseInsensitiveCompare(volume.host) == .orderedSame }
                && config.normalizedPath.caseInsensitiveCompare(volume.sharePath) == .orderedSame
        }
    }

    /// The server a mounted volume belongs to: the one in the list that has
    /// its address, or the address itself.
    private func server(of volume: MountedSMBVolume) -> String {
        MountManager.shared.serverHost(forAddress: volume.host) ?? volume.host
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

            if isEditing {
                shareSections
            } else {
                addSections
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
                if isEditing {
                    testConnectionButton
                }

                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    if !isEditing {
                        addShares()
                        return
                    }
                    let server = targetHost
                    let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    let savesForServer = savesServerCredentials && !offersServerCredentials && !server.isEmpty
                    if savesForServer {
                        MountManager.shared.setServerCredentials(host: server, username: user, password: password)
                    }
                    let config = ShareConfig(
                        id: existing?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        host: server,
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
                .disabled(isEditing ? !isValid : !canAdd)
            }
        }
        .padding(24)
        .modifier(SheetWidth())
        .fixedSize(horizontal: false, vertical: true)
        // .task, not onAppear: closing the sheet cancels the scan and the picker below.
        .task {
            allConfigs = MountManager.shared.configs
            guard !isEditing else { return }
            discoveredShares = MountManager.shared.mountedVolumes.filter { !isConfigured($0) }
            selectedServer = defaultServer
            selectServer()
            // Added from the menu of a server that has credentials: open macOS's
            // list of its shares straight away.
            let opensPicker = !initialHost.isEmpty && !serverUsername.isEmpty
            // Scan off the main actor: a slow SMB mount must not freeze the sheet.
            let volumes = await MountManager.shared.refreshMountedVolumes()
            guard !Task.isCancelled else { return }
            discoveredShares = volumes.filter { !isConfigured($0) }
            // The scan found other servers: pick the default again, unless
            // the user already picked one or is typing a new one.
            if !serverWasChosen && host.isEmpty && selectedServer != defaultServer {
                selectedServer = defaultServer
                selectServer()
            } else {
                addServerVolumes(discoveredShares.filter { server(of: $0).caseInsensitiveCompare(targetHost) == .orderedSame })
            }
            if opensPicker && !serverWasChosen { await chooseServerShares() }
        }
    }
}

// MARK: - Editing a share

extension ShareFormSheet {
    @ViewBuilder
    private var shareSections: some View {
        GlassSection(label: "Identification") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("Optional", text: $name)
                }
                GridRow {
                    Text("Host / IP").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    hostField
                }
                GridRow {
                    Text("Path").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                    TextField("share-name", text: $path)
                }
            }
            if isDuplicate {
                duplicateWarning
            }
        }
        .onChange(of: host) {
            connectionTestPassed = nil
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
                    mountsAsCaption
                }
            } else {
                credentialFields
                if existing?.passwordUnavailable == true {
                    Label("The saved password could not be read from the Keychain. Enter it again to replace it.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                finderPasswordCaption
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

    // MARK: Shared pieces

    /// Splits a pasted `smb://host/share` into host and path.
    private var hostField: some View {
        TextField("192.168.1.1 or server.local", text: $host)
            .onChange(of: host) { _, new in
                let lower = new.lowercased()
                if lower.hasPrefix("smb:") || lower.hasPrefix("//") {
                    parseHostInput(new)
                }
            }
    }

    private var credentialFields: some View {
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

    private var mountsAsCaption: some View {
        Text("Mounts as \(serverUsername), the user set for \(targetHost).")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var finderPasswordCaption: some View {
        Text("Leave the password empty to use the one Finder saved for this server.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var duplicateWarning: some View {
        Label("This share is already configured.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

// MARK: - Adding shares

extension ShareFormSheet {
    @ViewBuilder
    private var addSections: some View {
        GlassSection(label: "Server") {
            Picker("Server", selection: Binding(
                get: { selectedServer },
                set: { new in
                    selectedServer = new
                    serverWasChosen = true
                    selectServer()
                }
            )) {
                ForEach(serverChoices, id: \.self) { host in
                    Text(verbatim: host).tag(host)
                }
                if !serverChoices.isEmpty { Divider() }
                Text("New Server…").tag("")
            }
            .labelsHidden()
            .disabled(isChoosingShares)   // macOS's window holds the mount slot meanwhile

            if selectedServer.isEmpty {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Host / IP").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        hostField
                    }
                }
                .onChange(of: targetHost) { serverChanged(clearingCredentials: false) }
            }
        }

        GlassSection(label: "Credentials") {
            if !serverUsername.isEmpty {
                Toggle("Use the server’s credentials", isOn: $usesServerCredentials)
            }
            if !serverUsername.isEmpty && usesServerCredentials {
                mountsAsCaption
            } else {
                credentialFields
                if serverUsername.isEmpty {
                    Text("Saved as the server’s credentials, for its other shares too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                finderPasswordCaption
            }
        }

        GlassSection(label: "Shares to Add") {
            VStack(alignment: .leading, spacing: 8) {
                if !serverVolumes.isEmpty {
                    // A server with many shares must not push «Add» off the screen.
                    ScrollView {
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
                    .frame(maxHeight: 200)
                    .scrollBounceBehavior(.basedOnSize)
                }
                if serverVolumes.isEmpty && pickerFinished {
                    Label("The shares you picked are already in Connecter.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Path").gridColumnAlignment(.trailing).foregroundStyle(.secondary)
                        TextField("share-name", text: $path)
                    }
                }
                if isDuplicate {
                    duplicateWarning
                }
                HStack(spacing: 8) {
                    Button {
                        Task { await chooseServerShares() }
                    } label: {
                        Label("Choose Shares…", systemImage: "externaldrive.connected.to.line.below")
                    }
                    .disabled(targetHost.isEmpty || isChoosingShares)
                    if isChoosingShares {
                        ProgressView().controlSize(.small)
                        Text("Pick the shares in the macOS window")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let pickerError {
                    Label(pickerError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("macOS lists the server’s shares and mounts the ones you pick.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Servers in the list, then the ones only Finder has shares of.
    private var serverChoices: [String] {
        var hosts = MountManager.shared.serverGroups.map(\.host)
        for volume in discoveredShares {
            let host = server(of: volume)
            if !hosts.contains(where: { $0.caseInsensitiveCompare(host) == .orderedSame }) { hosts.append(host) }
        }
        return hosts
    }

    /// The server asked for, else the first with shares mounted in Finder and
    /// not in the list yet, else the first in the list, else a new one.
    private var defaultServer: String {
        if !initialHost.isEmpty {
            return serverChoices.first { $0.caseInsensitiveCompare(initialHost) == .orderedSame } ?? initialHost
        }
        return discoveredShares.first.map(server(of:)) ?? serverChoices.first ?? ""
    }

    /// A server was picked: start over with its credentials and its shares
    /// mounted in Finder.
    private func selectServer() {
        host = ""
        serverChanged(clearingCredentials: true)
    }

    /// Lists the server's shares mounted in Finder (ticked) and fills in the
    /// credentials it would mount with. A server with credentials inherits
    /// them; one without takes those of another of its shares, or the user
    /// Finder mounted it as.
    private func serverChanged(clearingCredentials: Bool) {
        serverVolumes = []
        selectedVolumes = []
        pickerFinished = false
        pickerError = nil
        usesServerCredentials = true
        if clearingCredentials {
            username = ""
            password = ""
        }
        let target = targetHost
        let mounted = discoveredShares.filter { server(of: $0).caseInsensitiveCompare(target) == .orderedSame }
        addServerVolumes(mounted)
        guard serverUsername.isEmpty else { return }
        let key = target.lowercased()
        if let sibling = allConfigs.first(where: { $0.serverKey == key && !$0.usesServerCredentials && !$0.username.isEmpty }) {
            username = sibling.username
            password = sibling.passwordUnavailable ? "" : sibling.password
        } else if let user = mounted.compactMap(\.user).first {
            username = user
            password = ""   // the one Finder saved
        }
    }

    /// The user and password the new shares mount with.
    private var chosenCredentials: (username: String, password: String) {
        if !serverUsername.isEmpty && usesServerCredentials {
            let password = KeychainManager.load(for: .serverCredentials(host: targetHost, username: serverUsername)).password
            return (serverUsername, password ?? "")
        }
        return (username.trimmingCharacters(in: .whitespacesAndNewlines), password)
    }

    private func chooseServerShares() async {
        isChoosingShares = true
        pickerError = nil
        defer { isChoosingShares = false }
        let credentials = chosenCredentials
        do {
            let volumes = try await MountManager.shared.mountSharesFromSystemPicker(
                hosts: MountManager.shared.hosts(for: ShareConfig(host: targetHost)),
                username: credentials.username,
                password: credentials.password
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

    /// Adds the ticked shares and the typed one. On a server with credentials
    /// they inherit them, or keep their own if the user turned that off; the
    /// server's are never replaced. On a server without, the user and
    /// password become the server's — with no user typed, the one macOS
    /// mounted them as, so they find the password Finder saved for it.
    private func addShares() {
        let server = targetHost
        let chosen = serverVolumes.filter { selectedVolumes.contains($0.mountPoint) }
        var shares = chosen.map { (name: $0.volumeName, path: $0.sharePath) }
        if !cleanPath.isEmpty && !shares.contains(where: { $0.path.caseInsensitiveCompare(cleanPath) == .orderedSame }) {
            shares.append((MountManager.volumeName(forSharePath: cleanPath), cleanPath))
        }
        let typedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var inherits = !serverUsername.isEmpty && usesServerCredentials
        if serverUsername.isEmpty {
            let user = typedUser.isEmpty ? (chosen.compactMap(\.user).first ?? "") : typedUser
            if !user.isEmpty {
                MountManager.shared.setServerCredentials(host: server, username: user, password: password)
                inherits = true
            }
        }
        onAddShares?(shares.map {
            ShareConfig(name: $0.name, host: server, path: $0.path,
                        username: inherits ? "" : typedUser, password: inherits ? "" : password,
                        usesServerCredentials: inherits)
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

extension MountedSMBVolume: Identifiable {
    var id: String { mountPoint }
}
