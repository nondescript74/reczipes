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
    
    // Compact layout (2026-11-05): level, presets and every category fit on one
    // screen — categories are a grid of check chips (description on hover / long
    // press) instead of one tall row each. File and reset tools sit below.
    private let categoryColumns = [GridItem(.adaptive(minimum: 170), spacing: 8, alignment: .leading)]

    var body: some View {
        Form {
            // Level + presets
            Section {
                Picker("Level", selection: $settings.loggingLevel) {
                    ForEach(LoggingSettings.LoggingLevel.allCases) { level in
                        Text(level.rawValue).tag(level)
                    }
                }

                HStack(spacing: 8) {
                    presetButton("Off", systemImage: "bolt.fill",
                                 isCurrent: settings.loggingLevel == .off) { settings.disableAllLogging() }
                    presetButton("Balanced", systemImage: "scale.3d",
                                 isCurrent: settings.loggingLevel == .errors && settings.enabledCategories.count == 3) { settings.resetToDefaults() }
                    presetButton("Full", systemImage: "ladybug.fill",
                                 isCurrent: settings.loggingLevel == .debug) { settings.enableFullLogging() }
                }

                PerformanceIndicator(level: settings.loggingLevel)
            } header: {
                Label("Logging Level", systemImage: "speedometer")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.loggingLevel.description)
                    Text("Balanced logs errors only; use Info or Full to see sharing and sync progress.")
                }
            }

            // Categories — all visible at once
            if settings.loggingLevel != .off {
                Section {
                    LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: 6) {
                        ForEach(LoggingSettings.LoggingCategory.allCases) { category in
                            CategoryChip(
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
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack {
                        Text("Logging Categories (\(settings.enabledCategories.count) of \(LoggingSettings.LoggingCategory.allCases.count))")
                        Spacer()
                        Button("All") { settings.enabledCategories = Set(LoggingSettings.LoggingCategory.allCases) }
                            .buttonStyle(.borderless)
                        Button("None") { settings.enabledCategories = [] }
                            .buttonStyle(.borderless)
                    }
                }
            }

            // Log file + reset
            Section {
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

                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Log File")
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

extension LoggingSettingsView {
    fileprivate func presetButton(_ title: String, systemImage: String, isCurrent: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isCurrent ? .accentColor : .secondary)
    }
}

/// One category as a compact check chip; the description shows on hover (macOS)
/// or as the accessibility hint.
struct CategoryChip: View {
    let category: LoggingSettings.LoggingCategory
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isEnabled)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                Image(systemName: category.systemImage)
                    .foregroundStyle(isEnabled ? .blue : .secondary)
                    .frame(width: 18)
                Text(category.rawValue)
                    .font(.callout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(category.description)
        .accessibilityAddTraits(isEnabled ? .isSelected : [])
        .accessibilityHint(category.description)
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
