//
//  DatabaseDiagnosticsView.swift
//  Reczipes2
//
//  User-facing view for database diagnostics and recovery history
//  Created on 1/23/26
//

import SwiftUI

struct DatabaseDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var statistics: DatabaseRecoveryLogger.RecoveryStatistics?
    @State private var showClearConfirmation = false
    @State private var isRunningCheck = false
    @State private var showResultAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    // Current Status Section
                    Section("Current Status") {
                        StatusRow_DDV(
                            title: "Container Health",
                            value: "Healthy",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        StatusRow_DDV(
                            title: "CloudKit Sync",
                            value: ModelContainerManager.shared.isCloudKitEnabled ? "Enabled" : "Local Only",
                            icon: ModelContainerManager.shared.isCloudKitEnabled ? "icloud.fill" : "internaldrive",
                            color: ModelContainerManager.shared.isCloudKitEnabled ? .blue : .orange
                        )
                        
                        StatusRow_DDV(
                            title: "Schema Version",
                            value: SchemaVersionManager.versionString(SchemaVersionManager.currentVersion),
                            icon: "doc.text.fill",
                            color: .purple
                        )
                    }
                    
                    // Recovery Statistics Section
                    if let stats = statistics {
                        Section("Recovery History") {
                            StatRow_DDV(title: "Total Attempts", value: "\(stats.totalAttempts)")
                            StatRow_DDV(title: "Successful", value: "\(stats.successfulAttempts)", color: .green)
                            StatRow_DDV(title: "Failed", value: "\(stats.failedAttempts)", color: stats.failedAttempts > 0 ? .red : .secondary)
                            StatRow_DDV(
                                title: "Success Rate",
                                value: "\(Int(stats.successRate * 100))%",
                                color: stats.successRate > 0.8 ? .green : .orange
                            )
                            StatRow_DDV(
                                title: "Avg Duration",
                                value: String(format: "%.2fs", stats.averageDurationSeconds)
                            )
                            
                            if let last = stats.lastAttempt {
                                LastAttemptRow(attempt: last)
                            }
                        }
                        
                        if stats.hasRecentFailures {
                            Section {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.appWarning)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Recent Recovery Failures")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("Consider reinstalling the app if issues persist")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // Actions Section
                    Section("Diagnostics Actions") {
                        Button {
                            Task {
                                await performHealthCheck()
                            }
                        } label: {
                            Label("Run Health Check", systemImage: "stethoscope")
                        }
                        .disabled(isRunningCheck)
                        
                        Button {
                            Task {
                                await logFullDiagnostics()
                            }
                        } label: {
                            Label("Show Full Diagnostics", systemImage: "doc.text.magnifyingglass")
                        }
                        .disabled(isRunningCheck)
                        
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear Recovery History", systemImage: "trash")
                        }
                        .disabled(isRunningCheck)
                    }
                    
                    // Information Section
                    Section("About Database Recovery") {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoBlock(
                                icon: "info.circle.fill",
                                title: "Automatic Recovery",
                                description: "If your database becomes incompatible with the current app version, Reczipes automatically recreates it. Your iCloud data will sync back."
                            )
                            
                            Divider()
                            
                            InfoBlock(
                                icon: "icloud.fill",
                                title: "Data Safety",
                                description: "When iCloud sync is enabled, your recipes are always backed up. Local database files can be safely deleted and recreated."
                            )
                            
                            Divider()
                            
                            InfoBlock(
                                icon: "exclamationmark.triangle.fill",
                                title: "When to Worry",
                                description: "Multiple failed recovery attempts may indicate a deeper issue. Consider reinstalling the app or contacting support."
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }
                .disabled(isRunningCheck)
                
                // Progress overlay
                if isRunningCheck {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        Text("Running diagnostics...")
                            .font(.headline)
                            .foregroundStyle(Color.onTint)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                    )
                    .shadow(radius: 20)
                }
            }
            .navigationTitle("Database Diagnostics")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear Recovery History?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    DatabaseRecoveryLogger.shared.clearHistory()
                    loadStatistics()
                }
            } message: {
                Text("This will delete the record of past database recovery attempts. This cannot be undone.")
            }
            .alert(alertTitle, isPresented: $showResultAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                loadStatistics()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadStatistics() {
        statistics = DatabaseRecoveryLogger.shared.getRecoveryStatistics()
    }
    
    private func performHealthCheck() async {
        isRunningCheck = true
        AppLog.info("🔍 User-initiated health check", category: .storage)
        
        let isHealthy = await ModelContainerManager.shared.verifyContainerHealth()
        
        let cloudKitStatus = ModelContainerManager.shared.isCloudKitEnabled ? "Enabled" : "Local Only"
        let schemaVersion = SchemaVersionManager.versionString(SchemaVersionManager.currentVersion)
        
        if isHealthy {
            AppLog.info("✅ Health check passed", category: .storage)
            alertTitle = "✅ Health Check Passed"
            alertMessage = """
            Container Status: Healthy
            CloudKit Sync: \(cloudKitStatus)
            Schema Version: \(schemaVersion)
            
            Your database is functioning correctly with no issues detected.
            """
        } else {
            AppLog.warning("⚠️ Health check failed", category: .storage)
            alertTitle = "⚠️ Health Issues Detected"
            alertMessage = """
            Container Status: Warning
            CloudKit Sync: \(cloudKitStatus)
            Schema Version: \(schemaVersion)
            
            Some issues were detected with your database. Check the console logs for details or try restarting the app.
            """
        }
        
        isRunningCheck = false
        showResultAlert = true
    }
    
    private func logFullDiagnostics() async {
        isRunningCheck = true
        AppLog.info("📊 User-initiated full diagnostics", category: .storage)
        
        await ModelContainerManager.shared.logDiagnosticInfo()
        let stats = DatabaseRecoveryLogger.shared.getRecoveryStatistics()
        
        let cloudKitStatus = ModelContainerManager.shared.isCloudKitEnabled ? "Enabled" : "Local Only"
        let schemaVersion = SchemaVersionManager.versionString(SchemaVersionManager.currentVersion)
        
        var message = """
        📊 Database Diagnostics Report
        
        Container Info:
          CloudKit: \(cloudKitStatus)
          Schema: \(schemaVersion)
        
        Recovery Statistics:
          Total Attempts: \(stats.totalAttempts)
          Successful: \(stats.successfulAttempts)
          Failed: \(stats.failedAttempts)
          Success Rate: \(Int(stats.successRate * 100))%
        """
        
        if let last = stats.lastAttempt {
            let timeAgo = formatTimeAgo(last.timestamp)
            message += """
            
            
            Last Recovery:
              Status: \(last.success ? "✅ Success" : "❌ Failed")
              Time: \(timeAgo)
              Duration: \(String(format: "%.2fs", last.recoveryDurationSeconds))
              Files Deleted: \(last.filesDeleted.count)
            """
        }
        
        if stats.hasRecentFailures {
            message += "\n\n⚠️ Recent failures detected. Consider reinstalling if issues persist."
        }
        
        alertTitle = "📊 Full Diagnostics"
        alertMessage = message
        
        isRunningCheck = false
        showResultAlert = true
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
}

// MARK: - Supporting Views

struct StatusRow_DDV: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

struct StatRow_DDV: View {
    let title: String
    let value: String
    var color: Color = .secondary
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.medium)
        }
    }
}

private struct LastAttemptRow: View {
    let attempt: DatabaseRecoveryLogger.RecoveryAttempt
    
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(attempt.timestamp)
        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h ago"
        } else {
            return "\(Int(interval / 86400))d ago"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Attempt")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: attempt.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(attempt.success ? "Success" : "Failed")
                }
                .font(.caption)
                .foregroundStyle(attempt.success ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((attempt.success ? Color.green : Color.red).opacity(0.1))
                .clipShape(Capsule())
            }
            
            Group {
                HStack {
                    Text("Time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeAgo)
                        .font(.caption)
                }
                
                HStack {
                    Text("Duration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fs", attempt.recoveryDurationSeconds))
                        .font(.caption)
                }
                
                HStack {
                    Text("Files Deleted:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(attempt.filesDeleted.count)")
                        .font(.caption)
                }
                
                if let sizeMB = attempt.databaseSizeMB {
                    HStack {
                        Text("Database Size:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MB", sizeMB))
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct InfoBlock: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.appInfo)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    DatabaseDiagnosticsView()
}
