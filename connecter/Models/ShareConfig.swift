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
    private static let userDefaultsKey = "shareConfigs"

    /// Carga todos los shares, migrando contraseñas en texto plano al Keychain si las hubiera.
    static func loadAll() -> [ShareConfig] {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            var configs = try? JSONDecoder().decode([ShareConfig].self, from: data)
        else { return [] }

        var needsMigration = false
        for i in configs.indices {
            if !configs[i].password.isEmpty {
                // Contraseña en texto plano → Keychain
                KeychainManager.save(configs[i].password, forID: configs[i].id)
                configs[i].password = ""
                needsMigration = true
            }
            configs[i].password = KeychainManager.load(forID: configs[i].id) ?? ""
        }

        if needsMigration { _persist(configs) }

        return configs
    }

    /// Guarda todos los shares. Las contraseñas van al Keychain; el resto a UserDefaults.
    static func saveAll(_ configs: [ShareConfig]) {
        for config in configs {
            KeychainManager.save(config.password, forID: config.id)
        }
        _persist(configs)
    }

    /// Escribe las configs en UserDefaults con las contraseñas vacías.
    private static func _persist(_ configs: [ShareConfig]) {
        var stripped = configs
        for i in stripped.indices { stripped[i].password = "" }
        guard let data = try? JSONEncoder().encode(stripped) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
