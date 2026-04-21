import Foundation
import Security

/// Stores and retrieves SMB share passwords from the macOS Keychain.
///
/// Passwords are stored as generic passwords keyed by the share's UUID so
/// they never touch UserDefaults. On first run, any plaintext passwords still
/// present in UserDefaults are automatically migrated here.
///
/// As a fallback when the app has no stored password, `findSystemPassword`
/// looks up internet-password entries saved by Finder / the OS when the user
/// previously connected to the same server manually.
enum KeychainManager {

    private static let service = Bundle.main.bundleIdentifier ?? "es.guzman.connecter"

    // MARK: - App Keychain (keyed by share UUID)

    /// Saves `password` for the given share ID. Passing an empty string removes
    /// any existing entry. Items are marked synchronizable so iCloud Keychain
    /// replicates them across the user's other Macs automatically.
    static func save(_ password: String, forID id: UUID) {
        let account = id.uuidString

        // Delete both synchronizable and non-synchronizable variants so we
        // don't leave stale legacy entries behind.
        for sync in [kCFBooleanTrue, kCFBooleanFalse] as [CFBoolean] {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: sync
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        guard !password.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
            kSecAttrLabel as String: "Connectar",
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// Returns the stored password for the given share ID, or `nil` if none.
    /// Checks synchronizable items first; falls back to legacy non-synchronizable
    /// items and migrates them on the fly.
    static func load(forID id: UUID) -> String? {
        // Primary: synchronizable (iCloud Keychain)
        let syncQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        if SecItemCopyMatching(syncQuery as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let password = String(data: data, encoding: .utf8) {
            return password
        }

        // Fallback: legacy non-synchronizable item — migrate to synchronizable
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        result = nil
        guard SecItemCopyMatching(legacyQuery as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }

        // Migrar: re-guardar como sincronizable (save() borra la entrada antigua)
        save(password, forID: id)
        return password
    }

    /// Removes the stored password for the given share ID (both variants).
    static func delete(forID id: UUID) {
        for sync in [kCFBooleanTrue, kCFBooleanFalse] as [CFBoolean] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id.uuidString,
                kSecAttrSynchronizable as String: sync
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - System Keychain fallback

    /// Searches the macOS system Keychain for an internet password that Finder
    /// or the OS saved when the user previously connected to `server` manually.
    /// Returns `nil` if no matching entry is found or access is denied.
    static func findSystemPassword(server: String, username: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !username.isEmpty {
            query[kSecAttrAccount as String] = username
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
