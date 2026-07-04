//
//  DiagnosticLogView.swift
//  Reczipes
//
//  Created on December 19, 2025.
//

import SwiftUI

/// View for displaying and managing the diagnostic log
struct DiagnosticLogView: View {
    
    @State private var logEntries: [LogEntry] = []
    @State private var isLoading = true
    @State private var showClearConfirmation = false
    @State private var showShareSheet = false
    @State private var fileSize: String = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                // Log contents
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading log...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if logEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("No logs yet")
                            .font(.headline)
                        Text("Diagnostic logs will appear here as you use the app")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Info header
                        if !fileSize.isEmpty {
                            Section {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    Text("Log file size: \(fileSize)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        // Log entries
                        Section {
                            ForEach(logEntries.reversed()) { entry in
                                LogEntryRow(entry: entry)
                            }
                        } header: {
                            Text("\(logEntries.count) entries")
                        }
                    }
                    .platformInsetGroupedListStyle()
                }
            }
            .navigationTitle("Diagnostic Log")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
                    // Refresh button
                    Button {
                        loadLog()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    
                    // Share button
                    if !logEntries.isEmpty {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    // Clear button
                    if !logEntries.isEmpty {
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                }
            }
            .task {
                loadLog()
            }
            .confirmationDialog(
                "Clear Diagnostic Log?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Log", role: .destructive) {
                    clearLog()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all diagnostic log entries. This action cannot be undone.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = DiagnosticLogger.shared.getLogFileURL() {
                    ShareSheet_DLV(items: [url])
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadLog() {
        isLoading = true
        
        Task {
            // Run file I/O on background
            let contents = await Task.detached {
                await DiagnosticLogger.shared.getLogContents()
            }.value
            
            let size = await Task.detached {
                await DiagnosticLogger.shared.getFormattedLogFileSize()
            }.value
            
            let entries = await Task.detached {
                await LogEntry.parseLogContents(contents)
            }.value
            
            await MainActor.run {
                self.logEntries = entries
                self.fileSize = size
                self.isLoading = false
            }
        }
    }
    
    private func clearLog() {
        Task {
            await Task.detached {
                await DiagnosticLogger.shared.clearLog()
            }.value
            
            // Wait a moment for the file to be cleared
            try? await Task.sleep(for: .milliseconds(100))
            
            loadLog()
        }
    }
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet_DLV: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
#else
struct ShareSheet_DLV: View {
    let items: [Any]
    var body: some View { MacShareView(items: items) }
}
#endif

// MARK: - Log Entry Model

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let fileName: String
    let lineNumber: Int
    let function: String
    let message: String
    
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        case notice = "NOTICE"
        
        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .critical: return .purple
            case .notice: return .green
            }
        }
        
        var icon: String {
            switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .critical: return "exclamationmark.octagon"
            case .notice: return "bell"
            }
        }
    }
    
    // Parse log file contents into structured entries
    static func parseLogContents(_ contents: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        
        var i = 0
        while i < lines.count {
            let line = String(lines[i])
            
            // Look for log entry pattern: [timestamp] [level] [category] [filename:line] function
            if line.hasPrefix("["), line.contains("] [") {
                // Parse the header line
                let components = line.split(separator: "]", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "[")) }
                
                guard components.count >= 4 else {
                    i += 1
                    continue
                }
                
                // Extract timestamp
                let timestampString = components[0]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "M/d/yy, h:mm:ss a"
                let timestamp = dateFormatter.date(from: timestampString) ?? Date()
                
                // Extract level
                let levelString = components[1]
                let level = LogLevel(rawValue: levelString) ?? .notice
                
                // Extract category
                let category = components[2]
                
                // Extract file and line
                let fileLineString = components[3]
                let fileLineParts = fileLineString.split(separator: ":")
                let fileName = fileLineParts.first.map(String.init) ?? ""
                let lineNumber = fileLineParts.last.flatMap { Int($0) } ?? 0
                
                // Extract function (rest of the line after the last "]")
                let functionStartIndex = line.lastIndex(of: "]") ?? line.startIndex
                let function = String(line[line.index(after: functionStartIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                
                // Look for message on next line (starts with "  → ")
                var message = ""
                if i + 1 < lines.count {
                    let nextLine = String(lines[i + 1])
                    if nextLine.hasPrefix("  → ") {
                        message = String(nextLine.dropFirst(4))
                        i += 1 // Skip the message line
                    }
                }
                
                // Create entry
                let entry = LogEntry(
                    timestamp: timestamp,
                    level: level,
                    category: category,
                    fileName: fileName,
                    lineNumber: lineNumber,
                    function: function,
                    message: message
                )
                entries.append(entry)
            }
            
            i += 1
        }
        
        return entries
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail with date and time
                VStack(spacing: 4) {
                    // Time icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(entry.level.color.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        VStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(entry.level.color)
                            
                            Text(entry.timestamp, style: .time)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(entry.level.color)
                        }
                    }
                    
                    // Date below
                    Text(entry.timestamp, style: .date)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Level and category
                    HStack(spacing: 6) {
                        Image(systemName: entry.level.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(entry.level.color)
                        
                        Text(entry.level.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(entry.level.color)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        
                        Text(entry.category.uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    // Message
                    Text(entry.message)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    
                    // Context (expanded)
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 4) {
                            Divider()
                                .padding(.vertical, 4)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(entry.fileName)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(":")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Text("\(entry.lineNumber)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "function")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                Text(entry.function)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Expand indicator
                    HStack {
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Preview

#Preview {
    DiagnosticLogView()
}
