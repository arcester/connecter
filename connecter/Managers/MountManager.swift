import Foundation
import Combine
import NetFS
import AppKit

// MARK: - Errors

enum MountError: LocalizedError {
    case invalidURL
    case mountFailed(String)
    case mountTimedOut(TimeInterval)
    case unmountFailed(String)
    case alreadyMounted
    case notMounted

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid SMB URL"
        case .mountFailed(let msg):     return "Mount failed: \(msg)"
        case .mountTimedOut(let secs):
            return "Mount did not complete within \(Int(secs)) s — check the share's username and password"
        case .unmountFailed(let msg):   return "Unmount failed: \(msg)"
        case .alreadyMounted:           return "Volume is already mounted"
        case .notMounted:               return "Volume is not mounted"
        }
    }
}

// MARK: - Manager

/// Manages SMB shares with one independent monitoring task per share.
/// Each share's status is updated in isolation — no global check loop,
/// no shared mutable state between shares.
@MainActor
final class MountManager: ObservableObject {

    static let shared = MountManager()

    private let log = LogManager.shared

    @Published private(set) var configs: [ShareConfig] = ShareConfig.loadAll()

    /// One task per share ID. Each task checks and mounts its share independently.
    private var shareTasks: [UUID: Task<Void, Never>] = [:]

    /// Consecutive failure count per share. Reset to 0 on success or manual retry.
    private var failureCounts: [UUID: Int] = [:]

    /// Observer for system wake-from-sleep notification.
    private var wakeObserver: NSObjectProtocol?

    /// Shares with a check/mount currently in progress. Prevents overlapping
    /// mount attempts for the same share (e.g. refresh pressed while connecting).
    private var inFlight: Set<UUID> = []

    /// Hard limit for a single NetFS mount attempt. On macOS 27, a failed
    /// authentication with `UIOption = NoUI` never returns from NetAuth, so
    /// without this the share would stay "connecting" forever.
    private static let mountTimeout: TimeInterval = 45

    // TODO: iCloud — descomentar cuando haya cuenta de desarrollador con iCloud habilitado
    // private var cloudObserver: NSObjectProtocol?

    init() {
        log.info("MountManager started")
        startWakeObserver()
        // if AppSettings.shared.iCloudSync { startCloudObserver() }
    }

    // MARK: - iCloud sync observer (desactivado hasta tener cuenta de desarrollador)

    // func startCloudObserver() {
    //     guard cloudObserver == nil else { return }
    //     NSUbiquitousKeyValueStore.default.synchronize()
    //     cloudObserver = NotificationCenter.default.addObserver(
    //         forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
    //         object: NSUbiquitousKeyValueStore.default,
    //         queue: .main
    //     ) { [weak self] _ in
    //         self?.reloadConfigs()
    //     }
    //     log.info("iCloud sync observer started")
    // }

    // func stopCloudObserver() {
    //     if let obs = cloudObserver {
    //         NotificationCenter.default.removeObserver(obs)
    //         cloudObserver = nil
    //         log.info("iCloud sync observer stopped")
    //     }
    // }

    // MARK: - Monitoring lifecycle

    /// Starts independent monitoring tasks for all enabled shares.
    func startMonitoring() {
        syncTasks()
        log.info("Monitor started (\(shareTasks.count) task(s), interval: \(Int(AppSettings.shared.monitorInterval))s)")
    }

    func stopMonitoring() {
        for task in shareTasks.values { task.cancel() }
        shareTasks.removeAll()
        log.info("Monitor stopped")
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
        log.info("System wake detected — restarting monitors in 5 s")

        for task in shareTasks.values { task.cancel() }
        shareTasks.removeAll()
        failureCounts.removeAll()

        // Mark enabled shares as connecting so the UI reflects the real state
        for i in configs.indices where configs[i].isEnabled {
            configs[i].connectionStatus = .connecting
        }

        try? await Task.sleep(for: .seconds(5))
        syncTasks()
        log.info("Monitors restarted after wake (\(shareTasks.count) task(s))")
    }

    // MARK: - Config management

    /// Call after adding, editing, or deleting shares (caller handles persistence).
    /// Syncs the task list and preserves current connection statuses.
    func reloadConfigs() {
        let stored = ShareConfig.loadAll()

        // Cancel tasks and remove Keychain passwords for deleted shares
        let storedIDs = Set(stored.map(\.id))
        for id in shareTasks.keys where !storedIDs.contains(id) {
            shareTasks[id]?.cancel()
            shareTasks.removeValue(forKey: id)
            failureCounts.removeValue(forKey: id)
            KeychainManager.delete(forID: id)
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

    /// Enables or disables a single share. Starts or stops its task accordingly.
    func setEnabled(_ enabled: Bool, forID id: UUID) {
        var stored = ShareConfig.loadAll()
        guard let index = stored.firstIndex(where: { $0.id == id }) else { return }
        stored[index].isEnabled = enabled
        ShareConfig.saveAll(stored)

        guard let i = configs.firstIndex(where: { $0.id == id }) else { return }
        let name = configs[i].displayName
        configs[i].isEnabled = enabled
        log.info("Share \"\(name)\" \(enabled ? "enabled" : "disabled")")

        if enabled {
            startTask(for: configs[i])
        } else {
            configs[i].connectionStatus = .disconnected
            shareTasks[id]?.cancel()
            shareTasks.removeValue(forKey: id)
            failureCounts.removeValue(forKey: id)
        }
    }

    // MARK: - Public: immediate actions

    /// Triggers an immediate check for one share (used after trigger fire or manual mount).
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

    func mount(_ config: ShareConfig) async throws {
        guard !isMounted(config) else { throw MountError.alreadyMounted }

        let path = config.path.hasPrefix("/") ? config.path : "/\(config.path)"
        let urlString = "smb://\(config.host)\(path)"
        guard let url = URL(string: urlString) else {
            log.error("Invalid SMB URL for \(config.displayName)")
            throw MountError.invalidURL
        }

        // Prefer password from config; fall back to system Keychain (Finder-saved entries)
        var password = config.password
        var passwordSource = "app keychain"
        if password.isEmpty {
            password = KeychainManager.findSystemPassword(
                server: config.host, username: config.username
            ) ?? ""
            passwordSource = password.isEmpty ? "none" : "system keychain"
        }

        let userLabel = config.username.isEmpty ? "(guest)" : config.username
        log.info("Mounting via NetFS: \(urlString) — user=\(userLabel), password from \(passwordSource)")
        if !config.username.isEmpty && password.isEmpty {
            log.warning("[\(config.displayName)] No stored password — on macOS 27 NetAuth will not answer; re-enter the password in the share settings")
        }

        let user: CFString? = config.username.isEmpty ? nil : (config.username as CFString)
        let pass: CFString? = password.isEmpty ? nil : (password as CFString)

        // "UIOption" = "NoUI" suppresses the NetAuth credential dialog
        let openOpts = NSMutableDictionary(dictionary: ["UIOption": "NoUI"])
        // SoftMount: report errors immediately instead of hanging on unresponsive servers
        let mountOpts = NSMutableDictionary(dictionary: ["SoftMount": true])

        let result = await Self.netFSMount(
            url: url as CFURL, user: user, pass: pass,
            openOptions: openOpts, mountOptions: mountOpts,
            timeout: Self.mountTimeout
        )

        if result.timedOut {
            log.error("NetFS mount timed out after \(Int(Self.mountTimeout)) s (NetAuth did not answer): \(urlString)")
            throw MountError.mountTimedOut(Self.mountTimeout)
        }
        if result.status != 0 {
            let msg = netFSError(result.status)
            log.error("NetFS mount failed (\(result.status)): \(msg)")
            throw MountError.mountFailed(msg)
        }
        // NetFS only completes after the volume is confirmed mounted
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
                nil,        // mountpath: nil → macOS picks /Volumes/…
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

    func unmount(_ config: ShareConfig) async throws {
        guard isMounted(config) else { throw MountError.notMounted }

        guard let mountPoint = actualMountPoint(for: config) else {
            throw MountError.notMounted
        }
        log.info("Unmounting \(mountPoint)…")

        let (output, exitCode) = try await runProcess(
            "/usr/sbin/diskutil",
            arguments: ["unmount", mountPoint]
        )

        if exitCode != 0 {
            let msg = output.isEmpty ? "code \(exitCode)" : output
            log.error("diskutil failed: \(msg)")
            throw MountError.unmountFailed(msg)
        }

        log.info("Unmounted: \(output)")
    }

    // MARK: - Mount status

    func isMounted(_ config: ShareConfig) -> Bool {
        let key = URLResourceKey.volumeURLForRemountingKey
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [key], options: []
        ) else { return false }

        let targetHost = config.host.lowercased()
        let targetPath = (config.path.hasPrefix("/")
            ? String(config.path.dropFirst())
            : config.path).lowercased()

        return volumes.contains { url in
            guard
                let values  = try? url.resourceValues(forKeys: [key]),
                let remount = values.volumeURLForRemounting,
                remount.scheme == "smb",
                let host    = remount.host
            else { return false }
            let urlPath = (remount.path.hasPrefix("/")
                ? String(remount.path.dropFirst())
                : remount.path).lowercased()
            return host.lowercased() == targetHost && urlPath == targetPath
        }
    }

    // MARK: - Private: task management

    /// Ensures every enabled share has a running task; does not restart existing ones.
    private func syncTasks() {
        for config in configs where config.isEnabled {
            if shareTasks[config.id] == nil {
                startTask(for: config)
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
        // Skip check if there is no network connection to avoid accumulating failures
        guard NetworkMonitor.shared.isAvailable else { return }

        // One check at a time per share — a refresh while a mount is in progress
        // must not start a second (possibly hanging) NetFS request.
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }

        // Re-read the current config from the live array (may have changed since task started)
        guard let config = configs.first(where: { $0.id == id }),
              config.isEnabled
        else { return }

        let name         = config.displayName
        let wasConnected = config.connectionStatus == .connected

        // Already mounted — nothing to do
        if isMounted(config) {
            if !wasConnected {
                log.info("[\(name)] Detected mounted")
                NotificationManager.shared.sendMounted(config: config)
            }
            failureCounts[id] = 0
            setStatus(.connected, forID: id)
            return
        }

        // Not mounted — show "connecting" immediately so the UI is responsive
        setStatus(.connecting, forID: id)

        if wasConnected {
            log.warning("[\(name)] Dropped — no longer mounted")
            NotificationManager.shared.sendUnmounted(config: config)
        } else if (failureCounts[id] ?? 0) == 0 {
            log.info("[\(name)] Not mounted, attempting to mount…")
        }

        do {
            try await mount(config)
            log.info("[\(name)] ✅ Mounted successfully")
            NotificationManager.shared.sendMounted(config: config)
            failureCounts[id] = 0
            setStatus(.connected, forID: id)
        } catch MountError.alreadyMounted {
            // Mounted by a concurrent action between our isMounted check and mount attempt
            failureCounts[id] = 0
            setStatus(.connected, forID: id)
        } catch {
            let failures = (failureCounts[id] ?? 0) + 1
            failureCounts[id] = failures

            log.error("[\(name)] ❌ Mount failed (\(failures)×) — \(error.localizedDescription)")
            if wasConnected {
                NotificationManager.shared.sendError(config: config)
            }

            let maxFailures = AppSettings.shared.maxFailuresBeforeDisable
            if failures >= maxFailures {
                log.warning("[\(name)] Disabling after \(failures) consecutive failure(s)")
                setEnabled(false, forID: id)
                return
            }
            setStatus(.error, forID: id)
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

    private func actualMountPoint(for config: ShareConfig) -> String? {
        let key = URLResourceKey.volumeURLForRemountingKey
        guard let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [key], options: []
        ) else { return nil }

        let targetHost = config.host.lowercased()
        let targetPath = (config.path.hasPrefix("/")
            ? String(config.path.dropFirst())
            : config.path).lowercased()

        return volumes.first { url in
            guard
                let values  = try? url.resourceValues(forKeys: [key]),
                let remount = values.volumeURLForRemounting,
                remount.scheme == "smb",
                let host    = remount.host,
                host.lowercased() == targetHost
            else { return false }
            let urlPath = (remount.path.hasPrefix("/")
                ? String(remount.path.dropFirst())
                : remount.path).lowercased()
            return urlPath == targetPath
        }?.path
    }

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
}
