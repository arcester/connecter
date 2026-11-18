import Foundation
import Combine
import NetFS
import AppKit

// MARK: - Errors

enum MountError: LocalizedError {
    case invalidURL
    /// NetFS refused the mount; `status` is its error code (0 if unknown).
    case mountFailed(String, status: Int32 = 0)
    /// A user is set but no password was found for it anywhere.
    case missingPassword(user: String)
    case mountTimedOut(TimeInterval)
    case unmountFailed(String)
    case alreadyMounted
    case notMounted
    case netAuthRestartCancelled
    case netAuthRestartFailed(String)
    case netAuthRestartUnavailable
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid SMB URL"
        case .mountFailed(let msg, _):  return "Mount failed: \(msg)"
        case .missingPassword(let user):
            return "No password saved for \(user) — on macOS 27 NetAuth does not answer without one"
        case .mountTimedOut(let secs):
            return "Mount did not complete within \(Int(secs)) s — check the share's username and password"
        case .unmountFailed(let msg):   return "Unmount failed: \(msg)"
        case .alreadyMounted:           return "Volume is already mounted"
        case .notMounted:               return "Volume is not mounted"
        case .netAuthRestartCancelled:  return "NetAuth restart was cancelled"
        case .netAuthRestartFailed(let msg): return "Could not restart NetAuth: \(msg)"
        case .serverUnreachable:        return "The server does not answer on the SMB port (445)"
        case .netAuthRestartUnavailable:
            return "The sandboxed build cannot restart NetAuth; run “\(MountManager.netAuthRestartCommand)” in Terminal"
        }
    }
}

// MARK: - Mounted volume snapshot

/// An SMB volume currently mounted on this Mac.
struct MountedSMBVolume: Sendable {
    let host: String
    /// Share path without leading/trailing slashes, e.g. "video" or "team/docs".
    let sharePath: String
    let mountPoint: String
    let volumeName: String
    let user: String?
}

// MARK: - Manager

/// Manages SMB shares with one independent monitoring task per share.
/// Each share's status is updated in isolation — no global check loop,
/// no shared mutable state between shares.
@MainActor
final class MountManager: ObservableObject {

    static let shared = MountManager()

    /// Terminal command that restarts the NetAuth agents; shown to the user
    /// when the app itself is not allowed to do it (App Sandbox).
    nonisolated static let netAuthRestartCommand = "killall NetAuthSysAgent NetAuthAgent"

    private let log = LogManager.shared

    @Published private(set) var configs: [ShareConfig] = ShareConfig.loadAll()

    /// Per-server settings (shared credentials, pause) by `ShareConfig.serverKey`.
    @Published private(set) var servers: [String: ServerSettings] = ServerSettings.loadAll()

    /// Last snapshot of the SMB volumes mounted on this Mac. Refreshed off the
    /// main actor by every share check and by mount/unmount notifications, so
    /// UI code can answer "is it mounted?" instantly. Stat-ing a stale SMB
    /// mount can block for seconds, which must never happen on the main thread.
    @Published private(set) var mountedVolumes: [MountedSMBVolume] = []
    private var volumeObservers: [NSObjectProtocol] = []

    /// Scan in progress, shared by concurrent `refreshMountedVolumes()` callers
    /// (several share checks at once) so the mount table is read only once.
    private var ongoingVolumeRefresh: Task<[MountedSMBVolume], Never>?

    /// One task per share ID. Each task checks and mounts its share independently.
    private var shareTasks: [UUID: Task<Void, Never>] = [:]

    /// Consecutive failure count per share. Reset to 0 on success or manual retry.
    private var failureCounts: [UUID: Int] = [:]

    /// Observer for system wake-from-sleep notification.
    private var wakeObserver: NSObjectProtocol?

    /// Pending re-check scheduled after the network came back.
    private var networkRecoveryTask: Task<Void, Never>?

    /// Shares with a check/mount currently in progress (share id → attempt token).
    /// Prevents overlapping mount attempts for the same share (e.g. refresh pressed
    /// while connecting). The token lets a stale attempt finish without clearing
    /// a newer one started after a NetAuth restart or system wake.
    private var inFlight: [UUID: UUID] = [:]

    /// Probable cause of each share's last failed mount, shown instead of
    /// "Error"; cleared as soon as the share leaves the error state.
    @Published private(set) var problems: [UUID: MountProblem] = AppEnvironment.isDemo ? DemoData.problems : [:]

    /// True when a mount timed out although the server's SMB port answers —
    /// the signature of a hung NetAuth agent (seen on macOS 27). Cleared as soon
    /// as any mount succeeds, NetAuth is restarted, or the user dismisses it.
    @Published private(set) var netAuthSuspected = false
    private var netAuthDiagnosisRunning = false

    /// When the app last restarted NetAuth on its own; automatic restarts are
    /// rate-limited so a persistent problem surfaces to the user instead of looping.
    private var lastAutoNetAuthRestart: Date?
    private static let autoNetAuthRestartCooldown: TimeInterval = 600

    /// Hard limit for a single NetFS mount attempt. On macOS 27, NetAuth can stop
    /// answering (a failed authentication with `UIOption = NoUI`, or a remount
    /// right after a share drops), so without this the share would stay
    /// "connecting" forever. Healthy mounts complete in 1–15 s.
    private static let mountTimeout: TimeInterval = 30

    /// NetFS requests are issued one at a time. Two simultaneous mounts against
    /// the same server (both shares at launch, after a wake, or after they drop
    /// together) is the pattern seen right before NetAuth stops answering: one
    /// completes and the other never does. Serialising them, with a short gap,
    /// keeps the agent to the one-request-at-a-time flow Finder uses.
    private var mountInProgress = false
    private var mountWaiters: [CheckedContinuation<Void, Never>] = []
    private var lastMountFinished: Date?
    private static let gapBetweenMounts: TimeInterval = 2

    /// QA-only: simulate a hung NetAuth (see `mount()`); cleared by `restartNetAuth()`.
    private static var simulateNetAuthHang =
        ProcessInfo.processInfo.environment["CONNECTER_SIMULATE_NETAUTH_HANG"] != nil

    init() {
        log.debug("MountManager started\(AppEnvironment.isSandboxed ? " (App Sandbox)" : "")")
        startWakeObserver()
        startNetworkObserver()
        startVolumeObserver()
        Task { await refreshMountedVolumes() }
    }

    // MARK: - Overall status (menu bar dot)

    enum OverallStatus {
        case idle, allMounted, partial, error

        /// Short user-facing description, used by the menu header and accessibility.
        var summary: String {
            switch self {
            case .idle:       String(localized: "No active shares")
            case .allMounted: String(localized: "All connected")
            case .partial:    String(localized: "Partial connection")
            case .error:      String(localized: "Not connected")
            }
        }
    }

    /// One-glance summary of every active share.
    var overallStatus: OverallStatus {
        let enabled = configs.filter(isActive)
        guard !enabled.isEmpty else { return .idle }
        if netAuthSuspected || enabled.contains(where: { $0.connectionStatus == .error }) { return .error }
        if enabled.allSatisfy({ $0.connectionStatus == .connected }) { return .allMounted }
        return .partial
    }

    // MARK: - Monitoring lifecycle

    /// Starts independent monitoring tasks for all enabled shares.
    func startMonitoring() {
        guard !AppEnvironment.isDemo else { return }   // demo states stay as set
        adoptServerCredentials()
        backUpSharesToKeychain()
        syncTasks()
        log.debug("Monitor started (\(shareTasks.count) task(s), interval: \(Int(AppSettings.shared.monitorInterval))s)")
    }

    func stopMonitoring() {
        for task in shareTasks.values { task.cancel() }
        shareTasks.removeAll()
        log.debug("Monitor stopped")
    }

    // MARK: - Mounted volume snapshot

    private func startVolumeObserver() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification,
                     NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            volumeObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    // Fresh scan: one already running may predate this (un)mount.
                    await self?.refreshMountedVolumes(reuseInFlight: false)
                    if name == NSWorkspace.didUnmountNotification { self?.recheckDroppedShares() }
                }
            })
        }
    }

    /// A volume went away outside the app (ejected in Finder, server dropped):
    /// re-check the shares still shown as mounted now instead of at their next
    /// interval. The app's own unmounts mark the share `.disconnecting` first.
    private func recheckDroppedShares() {
        let dropped = configs.filter {
            $0.connectionStatus == .connected && isActive($0) && mountPoint(for: $0) == nil
        }
        for config in dropped {
            Task { await checkShare(id: config.id) }
        }
    }

    /// Rescans the mounted volumes off the main actor and updates `mountedVolumes`.
    /// Joins a scan already in progress unless `reuseInFlight` is false.
    @discardableResult
    func refreshMountedVolumes(reuseInFlight: Bool = true) async -> [MountedSMBVolume] {
        if reuseInFlight, let ongoing = ongoingVolumeRefresh { return await ongoing.value }
        let task = Task.detached(priority: .utility) { Self.mountedSMBVolumes() }
        if reuseInFlight { ongoingVolumeRefresh = task }
        let volumes = await task.value
        if reuseInFlight { ongoingVolumeRefresh = nil }
        mountedVolumes = volumes
        return volumes
    }

    // MARK: - Sleep / wake handling

    private func startWakeObserver() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleSystemWake()
            }
        }
    }

    /// Called automatically when the Mac wakes from sleep.
    /// Cancels stale tasks (which may be blocked on dead network I/O),
    /// resets failure counts, and restarts monitoring after a short delay
    /// so the network stack has time to come back up.
    private func handleSystemWake() async {
        log.debug("System wake detected — restarting monitors in 5 s")

        restartAllTasks()
        try? await Task.sleep(for: .seconds(5))
        syncTasks()
        log.debug("Monitors restarted after wake (\(shareTasks.count) task(s))")
    }

    /// Cancels every share task, forgets failures and in-flight attempts, and
    /// marks enabled shares as connecting. Call `syncTasks()` afterwards.
    private func restartAllTasks() {
        for task in shareTasks.values { task.cancel() }
        shareTasks.removeAll()
        failureCounts.removeAll()
        inFlight.removeAll()
        for i in configs.indices where isActive(configs[i]) {
            configs[i].connectionStatus = .connecting
        }
    }

    // MARK: - Network availability

    private func startNetworkObserver() {
        NetworkMonitor.shared.onAvailabilityChange = { [weak self] available in
            self?.handleNetworkChange(available: available)
        }
    }

    /// Pauses checks while offline and re-checks every enabled share shortly
    /// after connectivity returns, instead of waiting for the next
    /// (possibly backed-off) interval.
    private func handleNetworkChange(available: Bool) {
        networkRecoveryTask?.cancel()
        guard available else {
            log.warning("Network unavailable — mount checks paused")
            for i in configs.indices
            where isActive(configs[i]) && configs[i].connectionStatus != .connected {
                configs[i].connectionStatus = .offline
            }
            return
        }

        log.debug("Network available — re-checking shares in 3 s")
        networkRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.failureCounts.removeAll()
            let ids = self.configs.filter(self.isActive).map(\.id)
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask { await self.checkShare(id: id) }
                }
            }
        }
    }

    // MARK: - NetAuth health (macOS 27 hang)

    /// After a mount timeout, checks whether the server's SMB port still answers.
    /// If it does, the request never completed because NetAuth is not responding.
    /// The NetAuth agents run in the user session, so a non-sandboxed build
    /// restarts them itself (rate-limited); the sandboxed App Store build is
    /// not allowed to signal other processes and shows instructions instead.
    private func diagnoseNetAuth(host: String) async {
        guard !netAuthSuspected, !netAuthDiagnosisRunning else { return }
        netAuthDiagnosisRunning = true
        defer { netAuthDiagnosisRunning = false }
        guard await PortProbe.isOpen(host: host) else { return }
        log.warning("NetAuth is not responding: \(host):445 answers but the mount request never completed")

        if !AppEnvironment.isSandboxed {
            let cooledDown = lastAutoNetAuthRestart.map {
                Date().timeIntervalSince($0) > Self.autoNetAuthRestartCooldown
            } ?? true
            if cooledDown && !Self.simulateNetAuthHang {
                lastAutoNetAuthRestart = Date()
                if await killNetAuthAgentsUnprivileged() {
                    log.info("NetAuth agents restarted automatically — retrying shares")
                    restartAllTasks()
                    syncTasks()
                    return
                }
            }
        }

        netAuthSuspected = true
        if AppEnvironment.isSandboxed {
            log.warning("This build cannot restart NetAuth itself — run “\(Self.netAuthRestartCommand)” in Terminal, then retry")
        } else {
            log.warning("Use “Restart NetAuth” in the main window to recover")
        }
        NotificationManager.shared.sendNetAuthNotResponding()
    }

    /// Kills the NetAuth agents as the current user. They are per-session
    /// LaunchAgents, so no privileges are needed; launchd respawns them on demand.
    /// Returns `false` if the processes belong to another user or the app is
    /// sandboxed (signals to other processes are denied there).
    private func killNetAuthAgentsUnprivileged() async -> Bool {
        guard !AppEnvironment.isSandboxed else { return false }
        guard let (output, _) = try? await runProcess(
            "/usr/bin/killall", arguments: ["NetAuthSysAgent", "NetAuthAgent"]
        ) else { return false }
        // killall exits non-zero when one of the names has no process — that is
        // fine (nothing to restart); only a permission error means we cannot do it.
        if output.localizedCaseInsensitiveContains("not permitted") {
            log.warning("Cannot restart NetAuth without privileges: \(output)")
            return false
        }
        return true
    }

    /// Restarts the NetAuth agents and retries every enabled share. Tries the
    /// unprivileged path first; falls back to macOS's administrator-password
    /// dialog only if the agents belong to another user.
    func restartNetAuth() async throws {
        guard !AppEnvironment.isSandboxed else { throw MountError.netAuthRestartUnavailable }
        log.info("Restarting NetAuth agents…")
        if await killNetAuthAgentsUnprivileged() == false {
            let shell = "/usr/bin/killall NetAuthSysAgent NetAuthAgent 2>/dev/null; exit 0"
            let script = "do shell script \"\(shell)\" with administrator privileges"
            let (output, code) = try await runProcess("/usr/bin/osascript", arguments: ["-e", script])
            guard code == 0 else {
                if output.contains("-128") {
                    log.info("NetAuth restart cancelled by the user")
                    throw MountError.netAuthRestartCancelled
                }
                log.error("NetAuth restart failed: \(output)")
                throw MountError.netAuthRestartFailed(output)
            }
        }
        log.info("NetAuth agents restarted — retrying shares")
        Self.simulateNetAuthHang = false
        lastAutoNetAuthRestart = Date()
        netAuthSuspected = false
        restartAllTasks()
        syncTasks()
    }

    /// Forgets failures and retries every enabled share right away — used after
    /// the user has restarted NetAuth by hand (sandboxed build).
    func retryAfterManualRecovery() {
        log.info("Retrying all shares after manual recovery")
        Self.simulateNetAuthHang = false
        netAuthSuspected = false
        restartAllTasks()
        syncTasks()
    }

    /// Hides the NetAuth warning until the next mount timeout.
    func dismissNetAuthWarning() {
        netAuthSuspected = false
    }

    // MARK: - Config management

    /// Call after adding, editing, or deleting shares (caller handles persistence).
    /// Syncs the task list and preserves current connection statuses.
    func reloadConfigs() {
        let stored = ShareConfig.loadAll()

        // Cancel tasks and remove Keychain passwords for deleted shares
        let storedIDs = Set(stored.map(\.id))
        for removed in configs where !storedIDs.contains(removed.id) {
            shareTasks[removed.id]?.cancel()
            shareTasks.removeValue(forKey: removed.id)
            failureCounts.removeValue(forKey: removed.id)
            KeychainManager.delete(for: removed)
        }

        // Rebuild configs array preserving live connection statuses
        var updated = stored
        for i in updated.indices {
            if let live = configs.first(where: { $0.id == updated[i].id }) {
                updated[i].connectionStatus = live.connectionStatus
            }
        }
        configs = updated

        syncTasks()
    }

    /// Outcome of `recoverSharesFromKeychain()`.
    struct KeychainRecovery {
        var added = 0
        var alreadyConfigured = 0
        var unreadable = 0

        /// User-facing summary for an alert.
        var message: String {
            var lines: [String] = []
            if added > 0 {
                lines.append(String(localized: "\(added) shares recovered"))
            } else if alreadyConfigured > 0 {
                lines.append(String(localized: "All saved shares are already in the list."))
            } else if unreadable == 0 {
                lines.append(String(localized: "No saved shares found in the Keychain."))
            }
            if unreadable > 0 {
                lines.append(String(localized: "\(unreadable) shares could not be read from the Keychain."))
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Makes sure every share in the list has its Keychain item (name, server,
    /// path, user and password if any). Runs at launch and on demand from
    /// Settings; returns how many items were added or updated.
    @discardableResult
    func backUpSharesToKeychain() -> Int {
        var written = 0
        for config in configs where !config.passwordUnavailable {
            if KeychainManager.save(config) { written += 1 }
        }
        if written > 0 { log.info("Backed up \(written) share(s) to the Keychain") }
        return written
    }

    /// Adds shares that exist in the Keychain but are missing from the list
    /// (e.g. after moving to the sandboxed build, or shares added on another
    /// Mac with iCloud Keychain). Pass `only` to restore specific items. Items
    /// whose secret cannot be read are left untouched and reported.
    @discardableResult
    func recoverSharesFromKeychain(only selected: Set<String>? = nil) -> KeychainRecovery {
        var current = configs
        var result = KeychainRecovery()
        for stored in KeychainManager.storedShares() {
            if let selected, !selected.contains(stored.id) { continue }
            let alreadyConfigured = current.contains { stored.matches($0) }
            if alreadyConfigured {
                result.alreadyConfigured += 1
                continue
            }
            var config = ShareConfig(
                name: stored.name, host: stored.host, path: stored.sharePath,
                username: stored.username, isEnabled: true,
                usesServerCredentials: stored.usesServerCredentials
            )
            guard let password = KeychainManager.load(for: config).password else {
                result.unreadable += 1
                continue
            }
            config.password = password
            current.append(config)
            result.added += 1
        }
        // Shares that inherit their server's credentials need the server's user,
        // which lives in the preferences: take it from the server's Keychain item.
        let serverUsers = KeychainManager.storedServerUsers()
        for key in Set(current.filter(\.usesServerCredentials).map(\.serverKey))
        where settings(forHost: key).username.isEmpty {
            guard let user = serverUsers[key], !user.isEmpty else { continue }
            servers[key, default: ServerSettings()].username = user
            ServerSettings.saveAll(servers)
            log.info("Recover from Keychain: user \(user) restored for server \(key)")
        }
        if result.added > 0 {
            ShareConfig.saveList(current)   // the Keychain items already exist
            reloadConfigs()
        }
        log.info("Recover from Keychain: \(result.added) added, \(result.alreadyConfigured) already configured, \(result.unreadable) unreadable")
        return result
    }

    /// Enables or disables a single share. Starts or stops its task accordingly.
    func setEnabled(_ enabled: Bool, forID id: UUID) {
        guard let i = configs.firstIndex(where: { $0.id == id }) else { return }
        let name = configs[i].displayName
        configs[i].isEnabled = enabled
        ShareConfig.saveList(configs)   // list only — no Keychain round trips
        log.info("Share \"\(name)\" \(enabled ? "enabled" : "disabled")")

        if enabled {
            if isActive(configs[i]) { startTask(for: configs[i]) }
        } else {
            configs[i].connectionStatus = .disconnected
            problems[id] = nil
            shareTasks[id]?.cancel()
            shareTasks.removeValue(forKey: id)
            failureCounts.removeValue(forKey: id)
        }
    }

    // MARK: - Servers

    /// The shares on one server (same host, case-insensitive).
    struct ServerGroup: Identifiable {
        /// `ShareConfig.serverKey`.
        let id: String
        /// As typed in the first share.
        let host: String
        let shares: [ShareConfig]
    }

    /// Shares grouped by server; servers sorted by host, shares by name.
    var serverGroups: [ServerGroup] {
        Dictionary(grouping: configs, by: \.serverKey)
            .map { key, shares in
                ServerGroup(id: key, host: shares[0].host, shares: shares.sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                })
            }
            .sorted { $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending }
    }

    /// Every address the share's server answers to: its host first, then the
    /// server's other addresses (a VPN…) in the user's order.
    func hosts(for config: ShareConfig) -> [String] {
        [config.host] + (settings(forHost: config.host).otherHosts ?? [])
    }

    /// The main host of the server in the list that answers to `address`
    /// (its host or one of its other addresses, case-insensitive), skipping
    /// the server `excluding`; `nil` when none does.
    func serverHost(forAddress address: String, excluding: String? = nil) -> String? {
        configs.first { config in
            config.serverKey != excluding?.lowercased()
                && hosts(for: config).contains { $0.caseInsensitiveCompare(address) == .orderedSame }
        }?.host
    }

    /// Sets the server's main address (`newHost`, may equal `host`) and its
    /// other addresses, then retries its shares that are not mounted.
    ///
    /// Shares mounted through an address that is no longer the server's are
    /// unmounted first: the app would not see them as mounted any more and
    /// would mount a second copy at /Volumes/<share>-1. A new main address
    /// moves every share to it, with their Keychain items and the server's
    /// settings and credentials.
    func setAddresses(host: String, main newHost: String, others: [String]) async {
        let oldKey = host.lowercased()
        let newKey = newHost.lowercased()
        let oldAddresses = Set(([oldKey] + (settings(forHost: oldKey).otherHosts ?? [])).map { $0.lowercased() })
        let removed = oldAddresses.subtracting(([newKey] + others).map { $0.lowercased() })

        if !removed.isEmpty {
            let volumes = await refreshMountedVolumes(reuseInFlight: false)
            for share in configs where share.serverKey == oldKey {
                let mountedThroughRemoved = volumes.contains {
                    removed.contains($0.host.lowercased())
                        && $0.sharePath.caseInsensitiveCompare(share.normalizedPath) == .orderedSame
                }
                guard mountedThroughRemoved else { continue }
                log.info("[\(share.displayName)] Unmounting: mounted through an address the server no longer has")
                markDisconnecting(id: share.id)
                try? await unmount(share)
                setStatus(.disconnected, forID: share.id)
            }
        }

        if newKey != oldKey {
            moveServer(from: oldKey, to: newHost)
        }
        servers[newKey, default: ServerSettings()].otherHosts = others.isEmpty ? nil : others
        ServerSettings.saveAll(servers)
        log.info("Addresses for server \(newHost): \(([newHost] + others).joined(separator: ", "))")

        let ids = configs
            .filter { $0.serverKey == newKey && isActive($0) && $0.connectionStatus != .connected }
            .map(\.id)
        for id in ids { await retryShare(id: id) }
    }

    /// Re-keys a server under a new main address: its shares (and their
    /// Keychain items), its settings and its credentials.
    private func moveServer(from oldKey: String, to newHost: String) {
        let newKey = newHost.lowercased()
        let username = settings(forHost: oldKey).username
        servers[newKey] = servers.removeValue(forKey: oldKey)
        ServerSettings.saveAll(servers)

        // The server's password: moved only when it could be read, so a locked
        // or denied item is never replaced by an empty one.
        let oldCredentials = ShareConfig.serverCredentials(host: oldKey, username: username)
        if case .found(let password) = KeychainManager.load(for: oldCredentials) {
            let newCredentials = ShareConfig.serverCredentials(host: newKey, username: username, password: password)
            KeychainManager.save(newCredentials)
            KeychainManager.removeSuperseded(oldCredentials, replacedBy: newCredentials)
        }

        var moved = configs
        for i in moved.indices where moved[i].serverKey == oldKey {
            let old = moved[i]
            moved[i].host = newHost
            KeychainManager.save(moved[i])
            KeychainManager.removeSuperseded(old, replacedBy: moved[i])
        }
        ShareConfig.saveList(moved)
        log.info("Server \(oldKey) renamed to \(newHost)")
        reloadConfigs()
    }

    /// The first of a server's addresses, in order, whose SMB port answers.
    /// All are probed at once: a dead VPN name can take the whole timeout.
    private func reachableHost(among hosts: [String]) async -> String? {
        let open = await withTaskGroup(of: (Int, Bool).self) { group in
            for (i, host) in hosts.enumerated() {
                group.addTask { (i, await PortProbe.isOpen(host: host)) }
            }
            var open = Set<Int>()
            for await (i, isOpen) in group where isOpen { open.insert(i) }
            return open
        }
        return hosts.indices.first(where: open.contains).map { hosts[$0] }
    }

    func settings(forHost host: String) -> ServerSettings {
        servers[host.lowercased()] ?? ServerSettings()
    }

    func isPaused(_ config: ShareConfig) -> Bool {
        servers[config.serverKey]?.isPaused == true
    }

    /// Monitored and kept mounted: enabled, on a server that is not paused.
    func isActive(_ config: ShareConfig) -> Bool {
        config.isEnabled && !isPaused(config)
    }

    /// Paused unmounts the server's shares and stops checking them; automatic
    /// checks them every interval and mounts them. Each share's own switch is
    /// left as it is.
    func setMode(_ mode: ServerSettings.Mode, host: String) async {
        let key = host.lowercased()
        servers[key, default: ServerSettings()].mode = mode
        ServerSettings.saveAll(servers)
        log.info("Server \(host) set to \(mode)")

        let shares = configs.filter { $0.serverKey == key && $0.isEnabled }
        for share in shares { failureCounts.removeValue(forKey: share.id) }
        syncTasks()   // stops or starts their watch tasks
        if mode == .paused {
            for share in shares {
                if isMounted(share) {
                    markDisconnecting(id: share.id)
                    try? await unmount(share)
                }
                setStatus(.disconnected, forID: share.id)
            }
        }
    }

    /// Removes the server with all its shares, their Keychain items, its
    /// settings and its credentials. Mounted shares stay mounted, as when a
    /// single share is deleted.
    func deleteServer(host: String) {
        let key = host.lowercased()
        let count = configs.filter { $0.serverKey == key }.count
        KeychainManager.delete(for: .serverCredentials(host: key, username: settings(forHost: key).username))
        servers.removeValue(forKey: key)
        ServerSettings.saveAll(servers)
        ShareConfig.saveList(configs.filter { $0.serverKey != key })
        log.info("Server \(host) deleted with \(count) share(s)")
        reloadConfigs()   // stops their tasks and deletes their Keychain items
    }

    /// Stores the user and password the server's inheriting shares mount with,
    /// then retries those that are not mounted. The Keychain item is keyed by
    /// user: after a user change the old item goes once the new one is readable.
    func setServerCredentials(host: String, username: String, password: String) {
        let key = host.lowercased()
        let old = ShareConfig.serverCredentials(host: key, username: settings(forHost: key).username)
        let new = ShareConfig.serverCredentials(host: key, username: username, password: password)
        KeychainManager.save(new)
        KeychainManager.removeSuperseded(old, replacedBy: new)
        servers[key, default: ServerSettings()].username = username
        ServerSettings.saveAll(servers)
        log.info("Credentials saved for server \(host) — user=\(username.isEmpty ? "(guest)" : username)")
        adoptServerCredentials()

        let ids = configs
            .filter { $0.serverKey == key && $0.usesServerCredentials && isActive($0) && $0.connectionStatus != .connected }
            .map(\.id)
        Task { for id in ids { await retryShare(id: id) } }
    }

    /// Shares that mount with the same user and password as their server
    /// switch to inheriting them, and their duplicate password leaves the
    /// Keychain. A share without a password of its own mounts with the one
    /// Finder saved, so that is the one compared.
    func adoptServerCredentials() {
        var serverPasswords: [String: String?] = [:]   // by server key, read once; nil = unreadable
        for config in configs where !config.usesServerCredentials {
            let user = settings(forHost: config.host).username
            guard !user.isEmpty, config.username.caseInsensitiveCompare(user) == .orderedSame else { continue }
            let key = config.serverKey
            if serverPasswords[key] == nil {
                switch KeychainManager.load(for: .serverCredentials(host: key, username: user)) {
                case .found(let password): serverPasswords[key] = password
                case .notFound:            serverPasswords[key] = ""
                case .unavailable:         serverPasswords[key] = .some(nil)
                }
            }
            guard let serverPassword = serverPasswords[key] ?? nil else { continue }
            // Both empty: both mount with Finder's password, no need to read it.
            var ownPassword = config.password
            if ownPassword.isEmpty && !serverPassword.isEmpty {
                ownPassword = KeychainManager.findSystemPassword(server: config.host, username: config.username) ?? ""
            }
            guard ownPassword == serverPassword else { continue }
            log.info("[\(config.displayName)] Same user and password as its server — now uses the server’s credentials")
            switchToServerCredentials(id: config.id)
        }
    }

    /// Worth a second try with the server's credentials: the share's own were
    /// rejected or missing, and its server has a user set.
    private func canRetryWithServerCredentials(_ config: ShareConfig, after error: Error) -> Bool {
        guard !config.usesServerCredentials, !settings(forHost: config.host).username.isEmpty else { return false }
        let problem = MountProblem(error)
        return problem == .wrongCredentials || problem == .missingPassword
    }

    /// Turns on "Use the server's credentials" for the share and removes its
    /// own password from the Keychain (the item stays, without a secret, as
    /// the share's backup).
    private func switchToServerCredentials(id: UUID) {
        guard let i = configs.firstIndex(where: { $0.id == id }) else { return }
        let old = configs[i]
        configs[i].usesServerCredentials = true
        configs[i].password = ""
        configs[i].passwordUnavailable = false
        KeychainManager.save(configs[i])
        KeychainManager.removeSuperseded(old, replacedBy: configs[i])
        ShareConfig.saveList(configs)
    }

    // MARK: - Public: immediate actions

    /// Triggers an immediate check for one share (used by the refresh button).
    func refreshShare(id: UUID) async {
        await checkShare(id: id)
    }

    /// Resets the failure count and immediately retries mounting.
    /// Use this for user-initiated retries so the count doesn't carry over from past failures.
    func retryShare(id: UUID) async {
        failureCounts[id] = 0
        setStatus(.disconnected, forID: id)
        await checkShare(id: id)
    }

    // MARK: - Public: mount / unmount

    /// Mounts through `host`, one of the server's addresses (default: its own host).
    func mount(_ config: ShareConfig, via host: String? = nil) async throws {
        let host = host ?? config.host
        await acquireMountSlot()
        defer { releaseMountSlot() }
        // The share may have been disabled, or mounted by Finder or the system's
        // own reconnection, while we waited for the slot.
        try Task.checkCancellation()
        guard await mountPointOffMain(for: config) == nil else { throw MountError.alreadyMounted }

        let sharePath = Self.normalizedSharePath(config.path)
        let urlString = "smb://\(host)/\(sharePath)"
        guard !host.isEmpty, !sharePath.isEmpty, let url = URL(string: urlString) else {
            log.error("Invalid SMB URL for \(config.displayName)")
            throw MountError.invalidURL
        }

        // The share's own credentials, or its server's; with no stored password,
        // fall back to the system Keychain (Finder-saved entries)
        var username = config.username
        var password = config.password
        var passwordSource = "app keychain"
        if config.usesServerCredentials {
            username = settings(forHost: config.host).username
            password = KeychainManager.load(
                for: .serverCredentials(host: config.host, username: username)
            ).password ?? ""
            passwordSource = "server credentials"
        } else if config.passwordUnavailable {
            log.warning("[\(config.displayName)] The stored password could not be read from the Keychain")
        }
        if password.isEmpty {
            password = KeychainManager.findSystemPassword(server: config.host, username: username)
                ?? (host == config.host ? nil : KeychainManager.findSystemPassword(server: host, username: username))
                ?? ""
            passwordSource = password.isEmpty ? "none" : "system keychain"
        }

        let userLabel = username.isEmpty ? "(guest)" : username
        log.info("Mounting via NetFS: \(urlString) — user=\(userLabel), password from \(passwordSource)")
        if !username.isEmpty && password.isEmpty {
            log.warning("[\(config.displayName)] No stored password — on macOS 27 NetAuth will not answer; re-enter the password in the share or server settings")
        }

        let user: CFString? = username.isEmpty ? nil : (username as CFString)
        let pass: CFString? = password.isEmpty ? nil : (password as CFString)

        // "UIOption" = "NoUI" suppresses the NetAuth credential dialog
        let openOpts = NSMutableDictionary(dictionary: ["UIOption": "NoUI"])
        // SoftMount: report errors immediately instead of hanging on unresponsive servers
        let mountOpts = NSMutableDictionary(dictionary: ["SoftMount": true])

        // QA hook: launch with `CONNECTER_SIMULATE_NETAUTH_HANG=1` to make every
        // mount behave as if NetAuth never answered, until "Restart NetAuth" is used.
        if Self.simulateNetAuthHang {
            log.warning("Simulating NetAuth hang (CONNECTER_SIMULATE_NETAUTH_HANG is set)")
            throw MountError.mountTimedOut(Self.mountTimeout)
        }

        // A mount attempt that never completed (hung NetAuth, lost network) leaves
        // an empty /Volumes/<share> behind, and macOS then mounts the next time at
        // /Volumes/<share>-1, which breaks saved paths (a Lightroom catalogue, a
        // Time Machine destination…). If that stale directory is there, ask NetFS
        // to mount exactly on it. Should that be refused, fall back to the default.
        let volumeName = Self.volumeName(forSharePath: sharePath)
        let staleMountPoint = await Task.detached(priority: .utility) {
            Self.staleMountPoint(forVolumeName: volumeName)
        }.value

        var result: (status: Int32, timedOut: Bool)
        if let staleMountPoint {
            log.info("[\(config.displayName)] Reusing the stale mount point \(staleMountPoint)")
            let pinnedOpts = NSMutableDictionary(dictionary: mountOpts)
            pinnedOpts["MountAtMountDir"] = true   // kNetFSMountAtMountDirKey
            result = await Self.netFSMount(
                url: url as CFURL, mountPath: URL(fileURLWithPath: staleMountPoint) as CFURL,
                user: user, pass: pass,
                openOptions: openOpts, mountOptions: pinnedOpts,
                timeout: Self.mountTimeout
            )
            if result.status != 0, !result.timedOut {
                log.warning("[\(config.displayName)] Could not mount on \(staleMountPoint) (\(netFSError(result.status))) — letting macOS pick the mount point")
                result = await Self.netFSMount(
                    url: url as CFURL, mountPath: nil, user: user, pass: pass,
                    openOptions: openOpts, mountOptions: mountOpts,
                    timeout: Self.mountTimeout
                )
            }
        } else {
            result = await Self.netFSMount(
                url: url as CFURL, mountPath: nil, user: user, pass: pass,
                openOptions: openOpts, mountOptions: mountOpts,
                timeout: Self.mountTimeout
            )
        }

        if result.timedOut {
            log.error("NetFS mount timed out after \(Int(Self.mountTimeout)) s (NetAuth did not answer): \(urlString)")
        } else if result.status != 0 {
            log.error("NetFS mount failed (\(result.status)): \(netFSError(result.status))")
        }
        // With a user but no password the cause is known, whatever NetFS answered.
        if (result.timedOut || result.status != 0) && !username.isEmpty && password.isEmpty {
            throw MountError.missingPassword(user: username)
        }
        if result.timedOut { throw MountError.mountTimedOut(Self.mountTimeout) }
        if result.status != 0 { throw MountError.mountFailed(netFSError(result.status), status: result.status) }

        // NetFS only completes after the volume is confirmed mounted: report where.
        // Fresh scan: one already running predates this mount.
        let volumes = await refreshMountedVolumes(reuseInFlight: false)
        if let mountPoint = Self.findMountPoint(hosts: hosts(for: config), path: config.path, in: volumes) {
            log.info("[\(config.displayName)] Mounted at \(mountPoint)")
            if mountPoint != "/Volumes/\(volumeName)" {
                let stale = await Task.detached(priority: .utility) {
                    Self.staleMountPointDirectories(forVolumeName: volumeName)
                }.value
                if !stale.isEmpty {
                    let quoted = stale.map { "\"\($0)\"" }.joined(separator: " ")
                    log.warning("[\(config.displayName)] /Volumes/\(volumeName) is taken by a stale directory. To get the original path back, remove the empty leftovers in Terminal: sudo rmdir \(quoted)")
                }
            }
        }
    }

    // MARK: - Adding a whole server

    /// Generous: the user is choosing shares in the system window meanwhile.
    /// shortcut: the picker holds the mount slot until it closes (other shares'
    /// mounts wait, closing the sheet does not cancel it); cancel the NetFS
    /// request from the sheet if users leave the window open.
    private static let pickerTimeout: TimeInterval = 300

    /// Asks macOS to show its own window for choosing shares on a server (the
    /// NetAuth picker Finder's "Connect to Server" uses), through the first of
    /// its `hosts` that answers, and mounts the ones the user picks. Returns
    /// every SMB volume of the server mounted afterwards, through any of them.
    /// Throws `CancellationError` when the user cancels the window.
    func mountSharesFromSystemPicker(hosts: [String], username: String, password: String) async throws -> [MountedSMBVolume] {
        guard !(hosts.first ?? "").isEmpty else { throw MountError.invalidURL }
        guard let host = await reachableHost(among: hosts) else { throw MountError.serverUnreachable }
        guard let url = URL(string: "smb://\(host)") else { throw MountError.invalidURL }

        await acquireMountSlot()
        defer { releaseMountSlot() }
        log.info("Opening the system share picker for smb://\(host) — user=\(username.isEmpty ? "(ask)" : username)")
        // No share path and no "NoUI": NetAuth asks which shares to mount (and
        // for a password if the one given is wrong).
        let result = await Self.netFSMount(
            url: url as CFURL, mountPath: nil,
            user: username.isEmpty ? nil : username as CFString,
            pass: password.isEmpty ? nil : password as CFString,
            openOptions: NSMutableDictionary(),
            mountOptions: NSMutableDictionary(dictionary: ["SoftMount": true]),
            timeout: Self.pickerTimeout
        )
        if result.timedOut {
            log.error("The system share picker for \(host) did not finish in \(Int(Self.pickerTimeout)) s")
            throw MountError.mountTimedOut(Self.pickerTimeout)
        }
        switch result.status {
        case 0, EEXIST:   // EEXIST: what was picked was already mounted
            break
        case -128:        // userCanceledErr
            log.info("System share picker for \(host) cancelled")
            throw CancellationError()
        default:
            let message = netFSError(result.status)
            log.error("System share picker for \(host) failed (\(result.status)): \(message)")
            throw MountError.mountFailed(message, status: result.status)
        }
        let keys = Set(hosts.map { $0.lowercased() })
        return await refreshMountedVolumes(reuseInFlight: false).filter { keys.contains($0.host.lowercased()) }
    }

    // MARK: - One NetFS request at a time

    private func acquireMountSlot() async {
        if mountInProgress {
            await withCheckedContinuation { continuation in
                mountWaiters.append(continuation)
            }
        } else {
            mountInProgress = true
        }
        if let finished = lastMountFinished {
            let wait = Self.gapBetweenMounts - Date().timeIntervalSince(finished)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        }
    }

    private func releaseMountSlot() {
        lastMountFinished = Date()
        if mountWaiters.isEmpty {
            mountInProgress = false
        } else {
            // Hand the slot straight to the next waiter (it stays "in progress").
            mountWaiters.removeFirst().resume()
        }
    }

    // MARK: - Mount point helpers

    /// Name macOS gives the volume: the last component of the share path.
    nonisolated static func volumeName(forSharePath sharePath: String) -> String {
        sharePath.split(separator: "/").last.map(String.init) ?? sharePath
    }

    /// `/Volumes/<name>` when it exists as a plain directory that nothing is
    /// mounted on (a leftover of an interrupted mount), otherwise `nil`.
    nonisolated static func staleMountPoint(forVolumeName name: String) -> String? {
        let path = "/Volumes/\(name)"
        return isStaleDirectory(path) ? path : nil
    }

    /// Every empty leftover for the volume: `/Volumes/<name>` and `/Volumes/<name>-N`.
    nonisolated static func staleMountPointDirectories(forVolumeName name: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        return entries
            .filter { $0 == name || ($0.hasPrefix(name + "-") && Int($0.dropFirst(name.count + 1)) != nil) }
            .map { "/Volumes/\($0)" }
            .filter(isStaleDirectory)
            .sorted()
    }

    /// A directory that is not itself a mount point (same device as /Volumes).
    private nonisolated static func isStaleDirectory(_ path: String) -> Bool {
        var info = stat(), parent = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              stat("/Volumes", &parent) == 0
        else { return false }
        return info.st_dev == parent.st_dev
    }

    /// Runs `NetFSMountURLAsync` and waits for its completion, but never longer
    /// than `timeout`. On timeout the request is cancelled and `timedOut` is set.
    ///
    /// The synchronous `NetFSMountURLSync` cannot be used: on macOS 27 it blocks
    /// forever when authentication fails with `UIOption = NoUI`, and a late
    /// completion (or none at all) must not crash the continuation, hence the
    /// resume-once guard.
    private nonisolated static func netFSMount(
        url: CFURL,
        mountPath: CFURL?,
        user: CFString?,
        pass: CFString?,
        openOptions: NSMutableDictionary,
        mountOptions: NSMutableDictionary,
        timeout: TimeInterval
    ) async -> (status: Int32, timedOut: Bool) {
        final class State: @unchecked Sendable {
            let lock = NSLock()
            var finished = false
            var requestID: AsyncRequestID?
        }
        let state = State()
        let queue = DispatchQueue.global(qos: .userInitiated)

        return await withCheckedContinuation { continuation in
            func finish(status: Int32, timedOut: Bool) {
                state.lock.lock()
                let alreadyFinished = state.finished
                state.finished = true
                state.lock.unlock()
                guard !alreadyFinished else { return }
                continuation.resume(returning: (status, timedOut))
            }

            var requestID: AsyncRequestID?
            let launchStatus = NetFSMountURLAsync(
                url,
                mountPath,  // nil → macOS picks /Volumes/<share> (or <share>-1 if that exists)
                user,
                pass,
                openOptions,
                mountOptions,
                &requestID,
                queue
            ) { status, _, _ in
                finish(status: status, timedOut: false)
            }

            if launchStatus != 0 {
                finish(status: launchStatus, timedOut: false)
                return
            }

            state.lock.lock()
            state.requestID = requestID
            state.lock.unlock()

            queue.asyncAfter(deadline: .now() + timeout) {
                state.lock.lock()
                let pending = !state.finished
                let id = state.requestID
                state.lock.unlock()
                guard pending else { return }
                if let id { NetFSMountURLCancel(id) }
                finish(status: ETIMEDOUT, timedOut: true)
            }
        }
    }

    /// Unmounts the share through Disk Arbitration (`FileManager.unmountVolume`),
    /// which is allowed inside the App Sandbox — unlike spawning `diskutil`.
    func unmount(_ config: ShareConfig) async throws {
        guard let mountPoint = await mountPointOffMain(for: config) else {
            throw MountError.notMounted
        }
        log.info("Unmounting \(mountPoint)…")

        do {
            try await Self.unmountVolume(at: URL(fileURLWithPath: mountPoint))
        } catch {
            log.error("Unmount failed: \(error.localizedDescription)")
            throw MountError.unmountFailed(error.localizedDescription)
        }
        log.info("Unmounted \(mountPoint)")
    }

    private nonisolated static func unmountVolume(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FileManager.default.unmountVolume(at: url, options: []) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Mount status

    /// Instant answer from the cached snapshot (UI code paths).
    func isMounted(_ config: ShareConfig) -> Bool {
        mountPoint(for: config) != nil
    }

    /// Local path where the share is currently mounted according to the
    /// cached snapshot, or `nil` if it isn't.
    func mountPoint(for config: ShareConfig) -> String? {
        Self.findMountPoint(hosts: hosts(for: config), path: config.path, in: mountedVolumes)
    }

    /// Fresh answer: rescans the volumes off the main actor first.
    private func mountPointOffMain(for config: ShareConfig) async -> String? {
        Self.findMountPoint(hosts: hosts(for: config), path: config.path, in: await refreshMountedVolumes())
    }

    /// Every browsable SMB volume currently mounted, as seen by the system.
    nonisolated static func mountedSMBVolumes() -> [MountedSMBVolume] {
        guard !AppEnvironment.isDemo else { return [] }   // no real volumes in screenshots
        let keys: Set<URLResourceKey> = [.volumeURLForRemountingKey, .volumeLocalizedNameKey]
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]
        ) else { return [] }

        return volumes.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: keys),
                let remount = values.volumeURLForRemounting,
                remount.scheme == "smb",
                let host = remount.host, !host.isEmpty
            else { return nil }
            return MountedSMBVolume(
                host: host,
                sharePath: normalizedSharePath(remount.path),
                mountPoint: url.path,
                volumeName: values.volumeLocalizedName ?? url.lastPathComponent,
                user: remount.user
            )
        }
    }

    private nonisolated static func findMountPoint(
        hosts: [String], path: String, in volumes: [MountedSMBVolume]
    ) -> String? {
        // Mounted through any of the server's addresses counts: otherwise a share
        // mounted over the VPN would be mounted again at /Volumes/<share>-1.
        let targetHosts = Set(hosts.map { $0.lowercased() })
        let targetPath = normalizedSharePath(path).lowercased()
        return volumes.first {
            targetHosts.contains($0.host.lowercased()) && $0.sharePath.lowercased() == targetPath
        }?.mountPoint
    }

    /// Share path without surrounding slashes or whitespace ("/video/" → "video").
    nonisolated static func normalizedSharePath(_ path: String) -> String {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Private: task management

    /// Ensures every active share has a running task and no other share has
    /// one (paused servers); does not restart existing ones.
    private func syncTasks() {
        for config in configs {
            if isActive(config) {
                if shareTasks[config.id] == nil { startTask(for: config) }
            } else if let task = shareTasks.removeValue(forKey: config.id) {
                task.cancel()
            }
        }
    }

    private func startTask(for config: ShareConfig) {
        shareTasks[config.id]?.cancel()
        let id = config.id
        shareTasks[id] = Task { [weak self] in
            await self?.checkShare(id: id)
            while !Task.isCancelled {
                let interval = self?.nextInterval(for: id) ?? 30.0
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.checkShare(id: id)
            }
        }
    }

    /// Returns the next check interval with exponential backoff based on consecutive failures.
    private func nextInterval(for id: UUID) -> TimeInterval {
        let failures = failureCounts[id] ?? 0
        let base = AppSettings.shared.monitorInterval
        switch failures {
        case 0:  return base
        case 1:  return max(base * 2, 60)
        case 2:  return max(base * 4, 120)
        default: return 300
        }
    }

    // MARK: - Private: per-share check (only touches this share's slot in configs)

    private func checkShare(id: UUID) async {
        // One check at a time per share — a refresh while a mount is in progress
        // must not start a second (possibly hanging) NetFS request.
        guard inFlight[id] == nil else { return }
        if AppEnvironment.isDemo {   // demo GIF: a share switched on "mounts" after a moment, nothing real
            guard configs.first(where: { $0.id == id })?.connectionStatus == .disconnected else { return }
            setStatus(.connecting, forID: id)
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { setStatus(.connected, forID: id) }
            return
        }
        let attempt = UUID()
        inFlight[id] = attempt
        defer { if inFlight[id] == attempt { inFlight.removeValue(forKey: id) } }

        // Re-read the current config from the live array (may have changed since task started)
        guard let config = configs.first(where: { $0.id == id }),
              isActive(config)
        else { return }

        let name         = config.displayName
        let wasConnected = config.connectionStatus == .connected

        // Offline: don't touch the file system (a dead SMB mount can block) and
        // don't count a failure. The network observer re-checks when it's back.
        guard NetworkMonitor.shared.isAvailable else {
            if !wasConnected { setStatus(.offline, forID: id) }
            return
        }

        // Already mounted — nothing to do
        if await mountPointOffMain(for: config) != nil {
            if !wasConnected {
                log.info("[\(name)] Detected mounted")
                NotificationManager.shared.sendMounted(config: config)
            }
            failureCounts[id] = 0
            netAuthSuspected = false
            setStatus(.connected, forID: id)
            return
        }

        // Not mounted — show "connecting" immediately so the UI is responsive
        setStatus(.connecting, forID: id)

        if wasConnected {
            log.warning("[\(name)] Dropped — no longer mounted")
            NotificationManager.shared.sendUnmounted(config: config)
            // Give the SMB client a moment to tear the old session down; remounting
            // immediately after a drop is what tends to leave NetAuth hanging.
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
        } else if (failureCounts[id] ?? 0) == 0 {
            log.info("[\(name)] Not mounted, attempting to mount…")
        }

        // Server down? Don't knock on NetFS (that is what leaves NetAuth hanging
        // and stale mount points behind) and don't count a failure: keep probing
        // the SMB port at the normal interval and mount as soon as it answers.
        guard let host = await reachableHost(among: hosts(for: config)) else {
            if config.connectionStatus != .unreachable {
                log.info("[\(name)] Server does not answer on port \(PortProbe.smbPort) at \(hosts(for: config).joined(separator: ", ")) — will mount when it is back")
            }
            setStatus(.unreachable, forID: id)
            return
        }

        do {
            do {
                try await mount(config, via: host)
            } catch let original where canRetryWithServerCredentials(config, after: original) {
                // Its own credentials failed and its server has some: try those,
                // and keep them for good if they work.
                log.info("[\(name)] Trying the server’s credentials…")
                var inheriting = config
                inheriting.usesServerCredentials = true
                do { try await mount(inheriting, via: host) } catch { throw original }
                log.info("[\(name)] Mounted with the server’s credentials — the share now uses them")
                switchToServerCredentials(id: id)
            }
            log.info("[\(name)] ✅ Mounted successfully")
            NotificationManager.shared.sendMounted(config: config)
            failureCounts[id] = 0
            netAuthSuspected = false
            setStatus(.connected, forID: id)
        } catch MountError.alreadyMounted {
            // Mounted by a concurrent action between our check and mount attempt
            failureCounts[id] = 0
            setStatus(.connected, forID: id)
        } catch is CancellationError {
            // Task cancelled (share disabled, monitors restarted): nothing to record.
            return
        } catch {
            let failures = (failureCounts[id] ?? 0) + 1
            failureCounts[id] = failures

            // A timeout while the server's SMB port answers means NetAuth is stuck
            if case MountError.mountTimedOut = error {
                Task { await self.diagnoseNetAuth(host: host) }
            }

            log.error("[\(name)] ❌ Mount failed (\(failures)×) — \(error.localizedDescription)")
            if wasConnected {
                NotificationManager.shared.sendError(config: config)
            }

            let maxFailures = AppSettings.shared.maxFailuresBeforeDisable
            if failures >= maxFailures {
                log.warning("[\(name)] Disabling after \(failures) consecutive failure(s)")
                setEnabled(false, forID: id)
                NotificationManager.shared.sendAutoDisabled(config: config, failures: failures)
                return
            }
            let problem = MountProblem(error)
            if problem != problems[id] { log.info("[\(name)] Probable cause: \(problem.advice)") }
            setStatus(.error, forID: id)
            problems[id] = problem
        }
    }

    /// Immediately marks a share as disconnecting so the UI can block interaction
    /// before the async unmount begins. Call this synchronously before awaiting unmount().
    func markDisconnecting(id: UUID) {
        setStatus(.disconnecting, forID: id)
    }

    /// Updates only one share's connectionStatus in configs — never touches other shares.
    private func setStatus(_ status: ShareConfig.ConnectionStatus, forID id: UUID) {
        guard let i = configs.firstIndex(where: { $0.id == id }) else { return }
        configs[i].connectionStatus = status
        if status != .error { problems[id] = nil }
    }

    // MARK: - Private: helpers

    private func netFSError(_ status: Int32) -> String {
        switch status {
        case EACCES, EPERM:   return "Authentication failed — check username and password"
        case ENOENT:          return "Share not found — check host and path"
        case ECONNREFUSED:    return "Connection refused — check that SMB is enabled on the server"
        case ETIMEDOUT:       return "Connection timed out — server may be unreachable"
        case -5999:           return "Account is restricted or locked"   // ENETFSACCOUNTRESTRICTED
        case -5998:           return "No share points available"         // ENETFSNOSHARESAVAIL
        case -5997:           return "No supported authentication mechanism" // ENETFSNOAUTHMECHSUPP
        case -128:            return "Mount cancelled"                   // userCanceledErr
        default:
            if status > 0, let msg = String(validatingUTF8: strerror(status)) { return msg }
            return "Error \(status)"
        }
    }

    /// Runs a system tool and returns its combined output and exit code.
    /// Only used by the non-sandboxed NetAuth recovery path.
    private func runProcess(_ executable: String, arguments: [String]) async throws -> (String, Int32) {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (output, process.terminationStatus)
        }.value
    }
}

// MARK: - Helpers

extension ShareConfig {
    var displayName: String { name.isEmpty ? host : name }

    /// Canonical `smb://host/share` string for display and the clipboard.
    var smbURLString: String {
        "smb://\(host)/\(MountManager.normalizedSharePath(path))"
    }
}
