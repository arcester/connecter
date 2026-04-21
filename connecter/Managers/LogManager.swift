import Foundation
import Combine

/// A single log entry produced by the app.
struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    enum Level {
        case info, warning, error
    }
}

/// Centralised event log, published for SwiftUI observation.
/// Also writes each entry to ~/Library/Logs/Connecter/connecter.log (rotates at 1 MB).
@MainActor
final class LogManager: ObservableObject {

    static let shared = LogManager()

    @Published private(set) var entries: [LogEntry] = []

    private let maxEntries = 500
    private let logFileURL: URL

    private init() {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/Connecter")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logFileURL = logDir.appendingPathComponent("connecter.log")
    }

    func info(_ message: String) {
        add(message, level: .info)
    }

    func warning(_ message: String) {
        add(message, level: .warning)
    }

    func error(_ message: String) {
        add(message, level: .error)
    }

    func clear() {
        entries.removeAll()
    }

    private func add(_ message: String, level: LogEntry.Level) {
        let entry = LogEntry(date: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        appendToFile(entry)
    }

    // MARK: - File logging

    private func appendToFile(_ entry: LogEntry) {
        let line = formatEntry(entry) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logFileURL

        Task.detached(priority: .background) {
            if FileManager.default.fileExists(atPath: url.path) {
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()

                // Rotate when file exceeds 1 MB
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 1_000_000 {
                    let archive = url.deletingLastPathComponent()
                        .appendingPathComponent("connecter.log.1")
                    try? FileManager.default.removeItem(at: archive)
                    try? FileManager.default.moveItem(at: url, to: archive)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func formatEntry(_ entry: LogEntry) -> String {
        let ts = ISO8601DateFormatter().string(from: entry.date)
        let level: String
        switch entry.level {
        case .info:    level = "INFO "
        case .warning: level = "WARN "
        case .error:   level = "ERROR"
        }
        return "[\(ts)] [\(level)] \(entry.message)"
    }
}
