import Foundation

/// Facts about the process that change what the app is allowed to do.
enum AppEnvironment {

    /// `true` when running inside the App Sandbox (Mac App Store builds).
    /// Sandboxed processes cannot signal other processes or run privileged
    /// scripts, so some recovery actions must be left to the user.
    nonisolated static let isSandboxed: Bool =
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Screenshots/QA: `CONNECTER_DEMO=1` shows `DemoData` instead of the
    /// real shares, which are neither read nor written (Debug builds only).
    #if DEBUG
    nonisolated static let isDemo = ProcessInfo.processInfo.environment["CONNECTER_DEMO"] != nil
    #else
    nonisolated static let isDemo = false
    #endif

    /// Marketing version, e.g. "1.0".
    nonisolated static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Build number, e.g. "1".
    nonisolated static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
