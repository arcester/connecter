import Foundation
import Security

/// Stores and retrieves SMB share passwords in the macOS Keychain.
///
/// Every share is an *internet password* item (secret empty when the share
/// has no password of its own) whose attributes
/// carry the host, share path, user name and display name, under a private
/// security domain so it never collides with the entries Finder saves for the
/// same server. Because the attributes describe the share, the share list can
/// be rebuilt from the Keychain alone (`storedShares()`), and when the item is
/// synchronizable it follows the user to other Macs through iCloud Keychain.
///
/// Safety rules:
/// - `save` never deletes anything. An item is removed only through
///   `delete(for:)` / `removeSuperseded`, i.e. an explicit user action.
/// - `load` distinguishes "no item" from "item exists but could not be read"
///   (locked keychain, denied access prompt for an item written by a build
///   with another signature), so callers never mistake a refused read for an
///   empty password.
///
/// Older builds stored generic-password items keyed by the share's UUID; they
/// are migrated to the new format the first time they are read.
///
/// As a fallback when the app has no stored password, `findSystemPassword`
/// looks up the entries Finder / the OS saved when the user connected manually.
enum KeychainManager {

    /// A share described by one of Connecter's Keychain items (attributes only).
    struct StoredShare: Identifiable {
        let host: String
        let sharePath: String
        let username: String
        let name: String
        /// Whether the item carries a password (recorded in its "kind" attribute).
        let hasPassword: Bool

        var id: String { "\(host.lowercased())|\(sharePath.lowercased())|\(username)" }
        var displayName: String { name.isEmpty ? host : name }
        var smbURLString: String { "smb://\(host)/\(sharePath)" }

        /// Same share as `config` (host and path, case-insensitive)?
        func matches(_ config: ShareConfig) -> Bool {
            config.host.caseInsensitiveCompare(host) == .orderedSame
                && config.normalizedPath.caseInsensitiveCompare(sharePath) == .orderedSame
        }
    }

    /// Outcome of looking up a share's password.
    enum LoadResult {
        case found(String)
        case notFound
        /// The item exists (or the keychain is unavailable) but the secret could not be read.
        case unavailable(OSStatus)

        var password: String? {
            if case .found(let value) = self { return value }
            return nil
        }
    }

    /// Part of an internet-password item's primary key: keeps Connecter's
    /// items apart from the ones Finder and other apps create.
    private static let securityDomain = "es.guzman.connecter"

    /// "Kind" attribute (shown in Keychain Access); also records whether the
    /// item carries a password, so listings don't need to read the secret.
    private static let kindWithPassword = "Connecter SMB share"
    private static let kindWithoutPassword = "Connecter SMB share (no password)"

    /// Service name of the legacy generic-password items (keyed by share UUID).
    private static let legacyService = Bundle.main.bundleIdentifier ?? "es.guzman.connecter"

    /// Synchronizable (iCloud Keychain) items need an application identifier
    /// entitlement (Keychain Sharing capability). Without it `SecItemAdd`
    /// returns `errSecMissingEntitlement`; the item is then stored locally and
    /// we stop trying for the rest of the session.
    private static var synchronizableUnavailable = false

    /// Keys whose read failure was already logged this session (avoids spam:
    /// `loadAll()` runs on every settings change).
    private static var reportedUnavailable: Set<String> = []

    // MARK: - App items (one per share)

    /// Backs the share up in the Keychain: name, server, path, user and the
    /// password if there is one (the secret is empty otherwise, so the share
    /// list itself can always be rebuilt). Returns `true` if an item was added
    /// or changed.
    ///
    /// An existing item is updated in place, and only when something changed,
    /// so iCloud Keychain is not churned on every save. If the existing item
    /// cannot be read (access denied) it is left alone, unless the caller
    /// provides a password — the value the user just typed is authoritative —
    /// in which case it is replaced. Nothing here ever removes an item; see
    /// `delete(for:)` and `removeSuperseded`.
    @discardableResult
    static func save(_ config: ShareConfig) -> Bool {
        let data = Data(config.password.utf8)
        let label = "Connecter: \(config.displayName)"
        let kind = config.password.isEmpty ? kindWithoutPassword : kindWithPassword

        switch fetchItem(for: config) {
        case .found(let item):
            let unchanged = (item[kSecValueData as String] as? Data ?? Data()) == data
                && (item[kSecAttrLabel as String] as? String) == label
                && (item[kSecAttrComment as String] as? String ?? "") == config.name
                && (item[kSecAttrDescription as String] as? String) == kind
            if unchanged { return false }
            let status = update(config, data: data, label: label, kind: kind)
            if status != errSecSuccess {
                LogManager.shared.error("[Keychain] Could not update the item for \(config.displayName): \(message(status))")
                return false
            }
            return true

        case .notFound:
            return add(config, data: data, label: label, kind: kind)

        case .unavailable(let readStatus):
            // Never overwrite a secret we cannot read with nothing.
            guard !config.password.isEmpty else { return false }
            if update(config, data: data, label: label, kind: kind) == errSecSuccess { return true }
            LogManager.shared.warning("[Keychain] Replacing the unreadable item for \(config.displayName) (\(message(readStatus)))")
            SecItemDelete(keyQuery(for: config, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
            return add(config, data: data, label: label, kind: kind)
        }
    }

    /// Returns the stored password for the share, or why it is not available.
    /// Legacy UUID-keyed items are migrated to the new format on the fly.
    static func load(for config: ShareConfig) -> LoadResult {
        switch fetchItem(for: config) {
        case .found(let item):
            guard let data = item[kSecValueData as String] as? Data,
                  let password = String(data: data, encoding: .utf8)
            else { return .unavailable(errSecDecode) }
            return .found(password)

        case .unavailable(let status):
            let key = config.credentialKey
            if !reportedUnavailable.contains(key) {
                reportedUnavailable.insert(key)
                LogManager.shared.warning("[Keychain] Could not read the password for \(config.displayName): \(message(status))")
            }
            return .unavailable(status)

        case .notFound:
            guard let legacy = loadLegacy(forID: config.id) else { return .notFound }
            var migrated = config
            migrated.password = legacy
            save(migrated)
            // Only drop the old item once the new one is confirmed readable
            // (direct fetch, not load(): the latter would recurse if the add failed).
            if case .found(let item) = fetchItem(for: config),
               (item[kSecValueData as String] as? Data) == Data(legacy.utf8) {
                deleteLegacy(forID: config.id)
            }
            return .found(legacy)
        }
    }

    /// Removes the share's password (new and legacy formats). Explicit user
    /// action only: deleting the share or clearing its password.
    static func delete(for config: ShareConfig) {
        SecItemDelete(keyQuery(for: config, synchronizable: kSecAttrSynchronizableAny) as CFDictionary)
        deleteLegacy(forID: config.id)
    }

    /// After a share's host, path or user changed and the new item was written,
    /// removes the item stored under the old key. If the new item is not
    /// readable, the old one is kept as a safety net.
    static func removeSuperseded(_ old: ShareConfig, replacedBy new: ShareConfig) {
        guard old.credentialKey != new.credentialKey else { return }
        if old.passwordUnavailable && new.password.isEmpty {
            // The old item still holds a secret this build could not read; the
            // new one has none, so keep the old copy rather than lose it.
            LogManager.shared.warning("[Keychain] Kept the previous item for \(old.displayName): its password could not be read, so it was not cleared")
            return
        }
        if load(for: new).password == new.password {
            delete(for: old)
        } else {
            LogManager.shared.warning("[Keychain] Kept the previous item for \(old.displayName): the new one could not be verified")
        }
    }

    /// Every share Connecter has a password for, described by the item
    /// attributes only — no secret is read. Used to rebuild the share list.
    static func storedShares() -> [StoredShare] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: securityDomain,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return [] }

        var seen: Set<String> = []
        return items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String, !host.isEmpty,
                  let path = item[kSecAttrPath as String] as? String, !path.isEmpty
            else { return nil }
            let username = item[kSecAttrAccount as String] as? String ?? ""
            // A local and a synchronizable copy of the same share count once.
            guard seen.insert("\(host)|\(path)|\(username)").inserted else { return nil }
            return StoredShare(
                host: host,
                sharePath: path,
                username: username,
                name: item[kSecAttrComment as String] as? String ?? "",
                hasPassword: (item[kSecAttrDescription as String] as? String) != kindWithoutPassword
            )
        }
    }

    // MARK: - System Keychain fallback

    /// Searches the macOS Keychain for an internet password that Finder or
    /// the OS saved when the user previously connected to `server` manually.
    /// Connecter's own items (same server/user/protocol) are skipped, and only
    /// the chosen candidate's secret is read, so no access prompt is triggered
    /// for items that are not going to be used. Returns `nil` if nothing
    /// matches or access is denied.
    static func findSystemPassword(server: String, username: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecReturnAttributes as String: true,
            kSecReturnPersistentRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if !username.isEmpty {
            query[kSecAttrAccount as String] = username
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return nil }

        for item in items {
            if (item[kSecAttrSecurityDomain as String] as? String) == securityDomain { continue }
            guard let ref = item[kSecValuePersistentRef as String] as? Data else { continue }
            let read: [String: Any] = [
                kSecValuePersistentRef as String: ref,
                kSecReturnData as String: true,
            ]
            var data: AnyObject?
            if SecItemCopyMatching(read as CFDictionary, &data) == errSecSuccess,
               let bytes = data as? Data,
               let password = String(data: bytes, encoding: .utf8) {
                return password
            }
        }
        return nil
    }

    // MARK: - Private: item access

    private enum Fetch {
        case found([String: Any])
        case notFound
        case unavailable(OSStatus)
    }

    /// Reads the share's item with its attributes and secret.
    private static func fetchItem(for config: ShareConfig) -> Fetch {
        var query = keyQuery(for: config, synchronizable: kSecAttrSynchronizableAny)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let item = result as? [String: Any] else { return .unavailable(errSecDecode) }
            return .found(item)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable(status)
        }
    }

    /// Adds a new item, preferring a synchronizable one. A duplicate (item
    /// present but not returned by the read) is updated instead.
    private static func add(_ config: ShareConfig, data: Data, label: String, kind: String) -> Bool {
        let variants: [Bool] = synchronizableUnavailable ? [false] : [true, false]
        for synchronizable in variants {
            var attributes = keyQuery(for: config, synchronizable: synchronizable)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = label
            attributes[kSecAttrComment as String] = config.name
            attributes[kSecAttrDescription as String] = kind
            let status = SecItemAdd(attributes as CFDictionary, nil)
            switch status {
            case errSecSuccess:
                return true
            case errSecDuplicateItem:
                let updated = update(config, data: data, label: label, kind: kind)
                if updated != errSecSuccess {
                    LogManager.shared.error("[Keychain] Could not replace the item for \(config.displayName): \(message(updated))")
                    return false
                }
                return true
            case errSecMissingEntitlement where synchronizable:
                // Expected without the Keychain Sharing capability: fall back to a local item.
                synchronizableUnavailable = true
                LogManager.shared.info("[Keychain] iCloud Keychain sync is not available for this build — items are stored on this Mac only")
            default:
                LogManager.shared.error("[Keychain] Could not save the item for \(config.displayName): \(message(status))")
                return false
            }
        }
        return false
    }

    private static func update(_ config: ShareConfig, data: Data, label: String, kind: String) -> OSStatus {
        let changes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrComment as String: config.name,
            kSecAttrDescription as String: kind,
        ]
        return SecItemUpdate(
            keyQuery(for: config, synchronizable: kSecAttrSynchronizableAny) as CFDictionary,
            changes as CFDictionary
        )
    }

    /// Primary-key attributes of the share's item. `synchronizable` is a Bool
    /// for adds, or `kSecAttrSynchronizableAny` for queries/updates/deletes.
    private static func keyQuery(for config: ShareConfig, synchronizable: Any) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: securityDomain,
            kSecAttrServer as String: config.host.lowercased(),
            kSecAttrPath as String: config.normalizedPath,
            kSecAttrAccount as String: config.username,
            kSecAttrProtocol as String: kSecAttrProtocolSMB,
            kSecAttrSynchronizable as String: synchronizable,
        ]
    }

    // MARK: - Private: legacy items (generic password keyed by share UUID)

    private static func legacyQuery(forID id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    private static func loadLegacy(forID id: UUID) -> String? {
        var query = legacyQuery(forID: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteLegacy(forID id: UUID) {
        SecItemDelete(legacyQuery(forID: id) as CFDictionary)
    }

    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
    }
}
