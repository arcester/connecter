import Foundation
import Combine

// MARK: - Errors

enum MountError: LocalizedError {
    case invalidURL
    case mountFailed(String)
    case unmountFailed(String)
    case alreadyMounted
    case notMounted

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid SMB URL"
        case .mountFailed(let msg):     return "Mount failed: \(msg)"
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

    private enum Constants {
        /// Nanoseconds between mount-poll attempts while waiting for the volume to appear.
        static let mountPollInterval: UInt64 = 250_000_000
        /// Maximum number of poll attempts (250 ms × 20 = 5 s total).
        static let maxMountAttempts = 20
    }

    private let log = LogManager.shared

    @Published private(set) var configs: [ShareConfig] = ShareConfig.loadAll()

    /// One task per share ID. Each task checks and mounts its share independently.
    private var shareTasks: [UUID: Task<Void, Never>] = [:]

    /// Consecutive failure count per share. Reset to 0 on success or manual retry.
    private var failureCounts: [UUID: Int] = [:]

    init() {
        log.info("MountManager started")
    }

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

        guard let smbURL = smbOpenURL(for: config) else {
            log.error("Invalid SMB URL for \(config.displayName)")
            throw MountError.invalidURL
        }

        let safeURL = config.password.isEmpty
            ? smbURL
            : smbURL.replacingOccurrences(of: config.password, with: "***")
        log.info("Mounting via Finder: \(safeURL)")

        let script = "mount volume \"\(smbURL)\""
        let (output, exitCode) = try await runProcess("/usr/bin/osascript", arguments: ["-e", script])

        if exitCode != 0 {
            log.error("osascript failed (\(exitCode)): \(output.isEmpty ? "(no output)" : output)")
            throw MountError.mountFailed(humanReadableMountError(output: output, exitCode: exitCode))
        }

        // osascript may return before the volume is registered in the kernel — poll up to 5 s
        for _ in 0..<Constants.maxMountAttempts {
            if isMounted(config) { return }
            try? await Task.sleep(nanoseconds: Constants.mountPollInterval)
        }

        log.error("Volume did not appear after mount command")
        throw MountError.mountFailed("Volume did not appear after mounting")
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

    private func smbOpenURL(for config: ShareConfig) -> String? {
        // Prefer password from config (already populated from app Keychain by loadAll).
        // Fall back to the system Keychain (entries saved by Finder / the OS).
        var password = config.password
        if password.isEmpty {
            password = KeychainManager.findSystemPassword(
                server: config.host, username: config.username
            ) ?? ""
        }

        let allowed = CharacterSet.urlPasswordAllowed
        guard
            let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: allowed),
            let encodedUser     = config.username.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return nil }

        let path = config.path.hasPrefix("/") ? config.path : "/\(config.path)"
        if config.username.isEmpty {
            return "smb://\(config.host)\(path)"
        }
        return "smb://\(encodedUser):\(encodedPassword)@\(config.host)\(path)"
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

    /// Maps raw osascript/mount error output to a user-readable message.
    private func humanReadableMountError(output: String, exitCode: Int32) -> String {
        let lower = output.lowercased()
        if lower.contains("authentication") || lower.contains("incorrect user name or password")
            || lower.contains("invalid credentials") || lower.contains("wrong password") {
            return "Authentication failed — check username and password"
        }
        if lower.contains("unable to connect") || lower.contains("there was a problem connecting")
            || lower.contains("connection refused") {
            return "Could not connect to server — check host name and that SMB is enabled"
        }
        if lower.contains("timed out") || lower.contains("time out") || lower.contains("timeout") {
            return "Connection timed out — server may be unreachable"
        }
        if lower.contains("no such file") || lower.contains("share") && lower.contains("not found") {
            return "Share not found on server — check path"
        }
        return output.isEmpty ? "Unknown error (exit \(exitCode))" : output
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
