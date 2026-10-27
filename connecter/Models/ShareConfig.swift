import Foundation

/// Configuration for a single SMB share.
struct ShareConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var host: String
    var path: String
    var username: String
    var password: String
    var isEnabled: Bool
    /// Mount with the server's user and password (`ServerSettings` + its
    /// Keychain item) instead of this share's own.
    var usesServerCredentials: Bool
    /// Runtime connection state — not persisted to disk.
    /// Always resets to `.disconnected` when the app loads.
    var connectionStatus: ConnectionStatus = .disconnected
    /// Runtime only: the Keychain holds a password for this share but it could
    /// not be read (locked keychain or denied access). `password` is empty then.
    var passwordUnavailable = false

    enum ConnectionStatus: String, Codable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case error
        /// Enabled, not mounted, and the Mac has no network connection.
        case offline
        /// Enabled, not mounted, and the server does not answer on the SMB
        /// port; the app keeps checking and mounts as soon as it is back.
        case unreachable
    }

    /// True while a transition is in progress and the UI should block interaction.
    var isBusy: Bool {
        connectionStatus == .connecting || connectionStatus == .disconnecting
    }

    /// Excludes `connectionStatus` from serialization — it is runtime-only.
    private enum CodingKeys: String, CodingKey {
        case id, name, host, path, username, password, isEnabled, usesServerCredentials
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        path = try c.decode(String.self, forKey: .path)
        username = try c.decode(String.self, forKey: .username)
        password = try c.decode(String.self, forKey: .password)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        // Lists saved before servers existed: every share keeps its own credentials.
        usesServerCredentials = try c.decodeIfPresent(Bool.self, forKey: .usesServerCredentials) ?? false
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        path: String = "",
        username: String = "",
        password: String = "",
        isEnabled: Bool = true,
        usesServerCredentials: Bool = false,
        connectionStatus: ConnectionStatus = .disconnected
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.path = path
        self.username = username
        self.password = password
        self.isEnabled = isEnabled
        self.usesServerCredentials = usesServerCredentials
        self.connectionStatus = connectionStatus
    }
}

// MARK: - Derived values

extension ShareConfig {
    /// Share path without surrounding slashes or whitespace ("/video/" → "video").
    var normalizedPath: String { MountManager.normalizedSharePath(path) }

    /// Identifies the share's Keychain item; changes when host, path or user change.
    var credentialKey: String { "\(host.lowercased())|\(normalizedPath)|\(username)" }

    /// Groups shares by server: the host, case-insensitive.
    var serverKey: String { host.lowercased() }

    /// The Keychain item that holds a server's shared password: an entry with
    /// no share path, so `KeychainManager.storedShares()` never lists it.
    static func serverCredentials(host: String, username: String, password: String = "") -> ShareConfig {
        ShareConfig(host: host.lowercased(), path: "", username: username, password: password)
    }
}

// MARK: - Server settings

/// Settings shared by every share on one server (shares are grouped by host).
struct ServerSettings: Codable {
    /// User for the shares that inherit the server's credentials; the password
    /// lives in the Keychain (`ShareConfig.serverCredentials`).
    var username = ""
    /// A paused server's shares are unmounted and not checked until it is resumed.
    var isPaused = false

    private static let storeKey = "serverSettings"

    /// Settings by `ShareConfig.serverKey`.
    static func loadAll() -> [String: ServerSettings] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let servers = try? JSONDecoder().decode([String: ServerSettings].self, from: data)
        else { return [:] }
        return servers
    }

    static func saveAll(_ servers: [String: ServerSettings]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}

// MARK: - Persistence

extension ShareConfig {
    private static let storeKey = "shareConfigs"

    static func loadAll() -> [ShareConfig] {
        // TODO: iCloud — cuando se active el sync, leer de NSUbiquitousKeyValueStore
        // let useCloud = AppSettings.shared.iCloudSync
        // let rawData: Data?
        // if useCloud {
        //     rawData = NSUbiquitousKeyValueStore.default.data(forKey: storeKey)
        //            ?? UserDefaults.standard.data(forKey: storeKey)
        // } else {
        //     rawData = UserDefaults.standard.data(forKey: storeKey)
        // }
        let rawData = UserDefaults.standard.data(forKey: storeKey)

        guard let data = rawData,
              var configs = try? JSONDecoder().decode([ShareConfig].self, from: data)
        else { return [] }

        var needsMigration = false
        for i in configs.indices {
            if !configs[i].password.isEmpty {
                // Plaintext password left by a very old build: move it to the Keychain.
                KeychainManager.save(configs[i])
                configs[i].password = ""
                needsMigration = true
            }
            switch KeychainManager.load(for: configs[i]) {
            case .found(let password):
                configs[i].password = password
            case .notFound:
                configs[i].password = ""
            case .unavailable:
                configs[i].password = ""
                configs[i].passwordUnavailable = true
            }
        }

        if needsMigration { _persist(configs) }
        return configs
    }

    /// Persists the share list (passwords stripped). Keychain items are
    /// written only where a password actually changed — `KeychainManager.save`
    /// for that share — so a stale in-memory value never overwrites an item
    /// edited in Keychain Access or on another Mac. Removal is explicit too:
    /// `KeychainManager.delete(for:)` when the user deletes a share or clears
    /// its password, `removeSuperseded` when host/path/user changed.
    static func saveList(_ configs: [ShareConfig]) {
        _persist(configs)
    }

    private static func _persist(_ configs: [ShareConfig]) {
        var stripped = configs
        for i in stripped.indices { stripped[i].password = "" }
        guard let data = try? JSONEncoder().encode(stripped) else { return }
        // TODO: iCloud — cuando se active el sync, escribir a NSUbiquitousKeyValueStore
        // if AppSettings.shared.iCloudSync {
        //     NSUbiquitousKeyValueStore.default.set(data, forKey: storeKey)
        //     NSUbiquitousKeyValueStore.default.synchronize()
        // } else {
        //     UserDefaults.standard.set(data, forKey: storeKey)
        // }
        UserDefaults.standard.set(data, forKey: storeKey)
    }
}
