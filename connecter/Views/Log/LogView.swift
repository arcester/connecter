import SwiftUI

struct LogView: View {
    @ObservedObject private var logManager = LogManager.shared
    @State private var filter: LogFilter = .all

    enum LogFilter: String, CaseIterable, Identifiable {
        case all, warnings, errors
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .all:      "All"
            case .warnings: "Warnings"
            case .errors:   "Errors"
            }
        }

        func includes(_ level: LogEntry.Level) -> Bool {
            switch self {
            case .all:      true
            case .warnings: level >= .warning
            case .errors:   level == .error
            }
        }
    }

    private var visibleEntries: [LogEntry] {
        logManager.entries.filter { filter.includes($0.level) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("No entries")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        List(visibleEntries.reversed()) { entry in
                            LogEntryRow(entry: entry)
                                .listRowSeparator(.hidden)
                                .id(entry.id)
                        }
                        .listStyle(.plain)
                        .contextMenu {
                            Button {
                                copyVisibleEntries()
                            } label: {
                                Label("Copy log", systemImage: "doc.on.doc")
                            }
                            Button(role: .destructive) {
                                logManager.clear()
                            } label: {
                                Label("Clear log", systemImage: "trash")
                            }
                        }
                        .onChange(of: logManager.entries.count) { _, _ in
                            if let last = visibleEntries.last {
                                proxy.scrollTo(last.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity Log")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Picker("Filter", selection: $filter) {
                        ForEach(LogFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Filter entries by level")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([logManager.logFileURL])
                    } label: {
                        Label("Reveal Log File", systemImage: "folder")
                    }
                    .help("Show the log file in Finder")

                    Button {
                        logManager.clear()
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                    .help("Clear all log entries")
                    .disabled(logManager.entries.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modalWindowStyle()
    }

    private func copyVisibleEntries() {
        let text = visibleEntries
            .map { "\(LogEntryRow.timeFormatter.string(from: $0.date))  \($0.message)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Log entry row

private struct LogEntryRow: View {
    let entry: LogEntry

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, height: nil, alignment: .leading)

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
