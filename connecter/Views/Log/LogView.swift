import SwiftUI

struct LogView: View {
    @ObservedObject private var logManager = LogManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if logManager.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No entries")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Entries list, newest first
                    ScrollViewReader { proxy in
                        List(logManager.entries.reversed()) { entry in
                            LogEntryRow(entry: entry)
                                .listRowSeparator(.hidden)
                                .id(entry.id)
                        }
                        .listStyle(.plain)
                        .onChange(of: logManager.entries.count) { _, _ in
                            if let last = logManager.entries.last {
                                proxy.scrollTo(last.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        logManager.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .help("Clear all log entries")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Log entry row

private struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var textColor: Color {
        switch entry.level {
        case .info:    return .primary
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
