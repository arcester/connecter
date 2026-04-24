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

    enum ConnectionStatus: String, Codable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case error
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
                KeychainManager.save(configs[i].password, forID: configs[i].id)
                configs[i].password = ""
                needsMigration = true
            }
            configs[i].password = KeychainManager.load(forID: configs[i].id) ?? ""
        }

        if needsMigration { _persist(configs) }
        return configs
    }

    static func saveAll(_ configs: [ShareConfig]) {
        for config in configs {
            KeychainManager.save(config.password, forID: config.id)
        }
        _persist(configs)
    }

    // TODO: iCloud — descomentar cuando haya cuenta de desarrollador con iCloud habilitado
    // static func migrateStorage(toCloud: Bool) {
    //     if toCloud {
    //         if let data = UserDefaults.standard.data(forKey: storeKey) {
    //             NSUbiquitousKeyValueStore.default.set(data, forKey: storeKey)
    //             NSUbiquitousKeyValueStore.default.synchronize()
    //         }
    //     } else {
    //         if let data = NSUbiquitousKeyValueStore.default.data(forKey: storeKey) {
    //             UserDefaults.standard.set(data, forKey: storeKey)
    //         }
    //     }
    // }

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
