import Foundation
import Combine

/// A single log entry produced by the app.
struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    enum Level: Int, Comparable {
        case debug, info, warning, error

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

/// Centralised event log, published for SwiftUI observation.
///
/// Every entry is also appended to `Logs/Connecter/connecter.log` inside the
/// app's Library folder (the sandbox container when sandboxed). The file
/// rotates to `connecter.log.1` once it exceeds 1 MB. Writes go through a
/// serial queue so lines never interleave. `.debug` entries reach the file
/// only in debug builds; release builds keep them in memory only.
@MainActor
final class LogManager: ObservableObject {

    static let shared = LogManager()

    @Published private(set) var entries: [LogEntry] = []

    /// Location of the on-disk log, for “Reveal in Finder”.
    let logFileURL: URL

    private let maxEntries = 500
    private let writer: FileWriter

    private init() {
        let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Logs/Connecter", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logFileURL = logDir.appendingPathComponent("connecter.log")
        writer = FileWriter(url: logFileURL)
    }

    func debug(_ message: String) { add(message, level: .debug) }
    func info(_ message: String) { add(message, level: .info) }
    func warning(_ message: String) { add(message, level: .warning) }
    func error(_ message: String) { add(message, level: .error) }

    /// Clears the in-memory list shown in the Activity Log window.
    /// The on-disk file is kept for troubleshooting.
    func clear() {
        entries.removeAll()
    }

    private func add(_ message: String, level: LogEntry.Level) {
        let entry = LogEntry(date: Date(), level: level, message: message)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        #if !DEBUG
        if level == .debug { return }
        #endif
        writer.append(Self.format(entry))
    }

    private nonisolated static func format(_ entry: LogEntry) -> String {
        let level: String
        switch entry.level {
        case .debug:   level = "DEBUG"
        case .info:    level = "INFO "
        case .warning: level = "WARN "
        case .error:   level = "ERROR"
        }
        let timestamp = entry.date.formatted(.iso8601)
        return "[\(timestamp)] [\(level)] \(entry.message)\n"
    }
}

// MARK: - Serial file writer

/// Appends lines to a file from a single background queue and rotates it
/// when it grows past `maxSize`. The handle stays open between writes and the
/// size is tracked in memory, so a log line costs one write syscall.
/// Only touched on `queue`.
private final class FileWriter: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "es.guzman.connecter.log", qos: .utility)
    private let maxSize = 1_000_000
    private var handle: FileHandle?
    private var currentSize = 0

    init(url: URL) {
        self.url = url
        queue.async { [self] in openOrCreate() }
    }

    func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [self] in
            if handle == nil { openOrCreate() }
            guard let handle else { return }
            do {
                try handle.write(contentsOf: data)
            } catch {
                // Retry with a fresh handle on the next line (file deleted, disk full…).
                try? handle.close()
                self.handle = nil
                return
            }
            currentSize += data.count
            if currentSize > maxSize { rotate() }
        }
    }

    private func openOrCreate() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        // seekToEnd() returns the file size; URL resource values may be cached.
        currentSize = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        let archive = url.deletingLastPathComponent().appendingPathComponent("connecter.log.1")
        try? fm.removeItem(at: archive)
        try? fm.moveItem(at: url, to: archive)
        openOrCreate()
    }
}
