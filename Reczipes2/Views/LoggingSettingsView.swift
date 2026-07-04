//
//  LoggingSettingsView.swift
//  Reczipes2
//
//  Created on February 12, 2026.
//

import SwiftUI

struct LoggingSettingsView: View {
    @State private var settings = LoggingSettings.shared
    @State private var showResetAlert = false
    @State private var showLogViewer = false
    
    var body: some View {
        Form {
            // Overview Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Performance Impact")
                        .font(.headline)
                    
                    PerformanceIndicator(level: settings.loggingLevel)
                    
                    Text("Logging can impact app performance, especially during recipe extraction and image processing. Lower logging levels improve speed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Label("Logging Performance", systemImage: "speedometer")
            }
            
            // Main Logging Level
            Section {
                Picker("Logging Level", selection: $settings.loggingLevel) {
                    ForEach(LoggingSettings.LoggingLevel.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.rawValue)
                            Text(level.description)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(level)
                    }
                }
                .platformNavigationLinkPickerStyle()
                
                Toggle("Save Logs to File", isOn: $settings.enableFileLogging)
                
                if settings.enableFileLogging {
                    Button {
                        showLogViewer = true
                    } label: {
                        HStack {
                            Label("View Log File", systemImage: "doc.text.magnifyingglass")
                            Spacer()
                            Text(DiagnosticLogger.shared.getFormattedLogFileSize())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("General Settings")
            } footer: {
                Text("Choose what gets logged. 'Off' provides best performance, 'All' helps with troubleshooting.")
            }
            
            // Quick Presets
            Section {
                Button {
                    withAnimation {
                        settings.disableAllLogging()
                    }
                } label: {
                    Label("Disable All Logging", systemImage: "bolt.fill")
                        .foregroundStyle(settings.loggingLevel == .off ? .green : .primary)
                }
                
                Button {
                    withAnimation {
                        settings.resetToDefaults()
                    }
                } label: {
                    Label("Balanced (Recommended)", systemImage: "scale.3d")
                        .foregroundStyle(
                            settings.loggingLevel == .errors && 
                            settings.enabledCategories.count == 3 ? .green : .primary
                        )
                }
                
                Button {
                    withAnimation {
                        settings.enableFullLogging()
                    }
                } label: {
                    Label("Enable Full Logging", systemImage: "ladybug.fill")
                        .foregroundStyle(settings.loggingLevel == .debug ? .orange : .primary)
                }
            } header: {
                Text("Quick Presets")
            } footer: {
                Text("Quick presets for common scenarios. Use 'Full Logging' when reporting bugs.")
            }
            
            // Category-Specific Controls
            if settings.loggingLevel != .off {
                Section {
                    ForEach(LoggingSettings.LoggingCategory.allCases) { category in
                        CategoryToggleRow(
                            category: category,
                            isEnabled: settings.enabledCategories.contains(category),
                            onToggle: { enabled in
                                if enabled {
                                    settings.enabledCategories.insert(category)
                                } else {
                                    settings.enabledCategories.remove(category)
                                }
                            }
                        )
                    }
                } header: {
                    Text("Logging Categories")
                } footer: {
                    Text("Enable specific categories to focus on particular areas. More categories = more logging.")
                }
            }
            
            // Log Management
            Section {
                if settings.enableFileLogging {
                    HStack {
                        Label("Log File Size", systemImage: "doc.text")
                        Spacer()
                        Text(DiagnosticLogger.shared.getFormattedLogFileSize())
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        DiagnosticLogger.shared.clearLog()
                    } label: {
                        Label("Clear Log File", systemImage: "trash")
                    }
                }
                
                if let logURL = DiagnosticLogger.shared.getLogFileURL() {
                    ShareLink(item: logURL) {
                        Label("Share Log File", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Log File Management")
            }
            
            // Reset Section
            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Logging Settings")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogViewer) {
            NavigationStack {
                LogFileViewerView()
            }
        }
        .alert("Reset Logging Settings", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                withAnimation {
                    settings.resetToDefaults()
                }
            }
        } message: {
            Text("This will reset all logging settings to their default values.")
        }
    }
}

// MARK: - Supporting Views

struct PerformanceIndicator: View {
    let level: LoggingSettings.LoggingLevel
    
    private var impactColor: Color {
        switch level {
        case .off:
            return .green
        case .errors:
            return .green
        case .warnings:
            return .yellow
        case .info:
            return .orange
        case .debug:
            return .red
        }
    }
    
    private var impactText: String {
        switch level {
        case .off:
            return "No Impact - Logging Disabled"
        case .errors:
            return "Minimal Impact"
        case .warnings:
            return "Slight Impact"
        case .info:
            return "Moderate Impact"
        case .debug:
            return "Significant Impact"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: "speedometer")
                .foregroundStyle(impactColor)
            
            Text(impactText)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            // Visual bar indicator
            HStack(spacing: 2) {
                ForEach(0..<5) { index in
                    Rectangle()
                        .fill(index < impactLevel ? impactColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 20)
                }
            }
        }
    }
    
    private var impactLevel: Int {
        switch level {
        case .off: return 0
        case .errors: return 1
        case .warnings: return 2
        case .info: return 3
        case .debug: return 5
        }
    }
}

struct CategoryToggleRow: View {
    let category: LoggingSettings.LoggingCategory
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { onToggle($0) }
        )) {
            HStack {
                Image(systemName: category.systemImage)
                    .foregroundStyle(isEnabled ? .blue : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.body)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct LogFileViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logContent: String = ""
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading log file...")
            } else {
                ScrollView {
                    Text(logContent)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .navigationTitle("Log File")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if let logURL = DiagnosticLogger.shared.getLogFileURL() {
                    ShareLink(item: logURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            logContent = DiagnosticLogger.shared.getLogContents()
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoggingSettingsView()
    }
}
