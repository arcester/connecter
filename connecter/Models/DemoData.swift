import Foundation

/// Made-up servers and shares for screenshots (`CONNECTER_DEMO=1`, Debug
/// builds only): nothing real is shown, checked, mounted or saved. Names are
/// Spanish when the app runs in Spanish and English otherwise.
enum DemoData {
    private static let spanish = Bundle.main.preferredLocalizations.first == "es"

    private static let nas = "nas.local"
    private static let office = spanish ? "oficina.local" : "office.local"
    private static let server = spanish ? "servidor.local" : "server.local"

    static let shares: [ShareConfig] = [
        share("archivo", "archive", on: nas, .connected),
        share("fotos", "photos", on: nas, .connected),
        share("música", "music", on: nas, enabled: false),
        share("time-machine", "time-machine", on: nas, enabled: false),
        share("vídeo", "video", on: nas, .connected),
        share("documentos", "documents", on: office, .unreachable),
        share("proyectos", "projects", on: office, .unreachable),
        share("copias", "backups", on: server),
    ]

    /// A share named in the app's language; its path is the name without accents.
    private static func share(_ es: String, _ en: String, on host: String,
                              _ status: ShareConfig.ConnectionStatus = .disconnected, enabled: Bool = true) -> ShareConfig {
        let name = spanish ? es : en
        return ShareConfig(name: name, host: host, path: name.folding(options: .diacriticInsensitive, locale: nil),
                           isEnabled: enabled, connectionStatus: status)
    }

    static let servers: [String: ServerSettings] = [
        nas: ServerSettings(username: "admin"),
        server: ServerSettings(username: "admin", isPaused: true),
    ]

    /// What Settings › Keychain lists: every demo share, saved with a password.
    static var storedShares: [KeychainManager.StoredShare] {
        shares.map {
            KeychainManager.StoredShare(host: $0.host, sharePath: $0.path, username: "admin", name: $0.name,
                                        hasPassword: true, usesServerCredentials: false)
        }
    }
}
