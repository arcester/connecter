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
        case id, name, host, path, username, password, isEnabled
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        path: String = "",
        username: String = "",
        password: String = "",
        isEnabled: Bool = true,
        connectionStatus: ConnectionStatus = .disconnected
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.path = path
        self.username = username
        self.password = password
        self.isEnabled = isEnabled
        self.connectionStatus = connectionStatus
    }
}

// MARK: - Derived values

extension ShareConfig {
    /// Share path without surrounding slashes or whitespace ("/video/" → "video").
    var normalizedPath: String { MountManager.normalizedSharePath(path) }

    /// Identifies the share's Keychain item; changes when host, path or user change.
    var credentialKey: String { "\(host.lowercased())|\(normalizedPath)|\(username)" }
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
