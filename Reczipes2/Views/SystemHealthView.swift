//
//  SystemHealthView.swift
//  Reczipes2
//
//  Created on 1/19/26.
//  Quick system health overview with diagnostic access
//

import SwiftUI

/// A compact view showing system health status with quick access to diagnostics
struct SystemHealthView: View {
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    @StateObject private var containerManager = ModelContainerManager.shared
    @Environment(\.showDiagnostics) private var showDiagnostics
    
    var body: some View {
        VStack(spacing: 16) {
            // Overall Status
            HStack {
                Image(systemName: overallStatusIcon)
                    .font(.title2)
                    .foregroundStyle(overallStatusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Status")
                        .font(.headline)
                    Text(overallStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if hasIssues {
                    Text("\(diagnosticManager.unresolvedFailures.count)")
                        .font(.caption.bold())
                        .statusBadgeStyle(tone: .critical)
                }
            }
            .padding()
            .background(overallStatusColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Component Status
            VStack(spacing: 12) {
                ComponentStatusRow(
                    title: "Storage",
                    icon: "internaldrive",
                    status: storageStatus,
                    color: storageColor
                )
                
                ComponentStatusRow(
                    title: "iCloud Sync",
                    icon: "icloud",
                    status: cloudKitStatus,
                    color: cloudKitColor
                )
                
                ComponentStatusRow(
                    title: "Network",
                    icon: "network",
                    status: networkStatus,
                    color: networkColor
                )
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                Button {
                    showDiagnostics()
                } label: {
                    Label("View Diagnostics", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                if hasIssues {
                    Button {
                        Task {
                            await attemptAutoFix()
                        }
                    } label: {
                        Label("Auto Fix", systemImage: "wrench.and.screwdriver")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Status Computation
    
    private var hasIssues: Bool {
        !diagnosticManager.unresolvedFailures.isEmpty
    }
    
    private var overallStatusIcon: String {
        if diagnosticManager.unresolvedFailures.contains(where: { $0.severity == .critical }) {
            return "exclamationmark.octagon.fill"
        } else if !diagnosticManager.unresolvedFailures.isEmpty {
            return "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private var overallStatusColor: Color {
        if diagnosticManager.unresolvedFailures.contains(where: { $0.severity == .critical }) {
            return .purple
        } else if !diagnosticManager.unresolvedFailures.isEmpty {
            return .red
        } else {
            return .green
        }
    }
    
    private var overallStatusText: String {
        if diagnosticManager.unresolvedFailures.contains(where: { $0.severity == .critical }) {
            return "Critical Issues Detected"
        } else if !diagnosticManager.unresolvedFailures.isEmpty {
            return "\(diagnosticManager.unresolvedFailures.count) Issues Need Attention"
        } else {
            return "All Systems Operational"
        }
    }
    
    private var storageStatus: String {
        let storageIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .storage }
        if !storageIssues.isEmpty {
            return "Issues Detected"
        }
        return "Operational"
    }
    
    private var storageColor: Color {
        let storageIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .storage }
        return storageIssues.isEmpty ? .green : .red
    }
    
    private var cloudKitStatus: String {
        if containerManager.isCloudKitEnabled {
            let cloudKitIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .cloudKit }
            return cloudKitIssues.isEmpty ? "Active" : "Issues Detected"
        }
        return "Disabled"
    }
    
    private var cloudKitColor: Color {
        if !containerManager.isCloudKitEnabled {
            return .orange
        }
        let cloudKitIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .cloudKit }
        return cloudKitIssues.isEmpty ? .green : .red
    }
    
    private var networkStatus: String {
        let networkIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .network }
        return networkIssues.isEmpty ? "Connected" : "Issues Detected"
    }
    
    private var networkColor: Color {
        let networkIssues = diagnosticManager.unresolvedFailures.filter { $0.category == .network }
        return networkIssues.isEmpty ? .green : .red
    }
    
    // MARK: - Auto Fix
    
    private func attemptAutoFix() async {
        // Check for common fixable issues
        let failures = diagnosticManager.unresolvedFailures
        
        // Storage issues - try container recreation
        if failures.contains(where: { $0.category == .storage }) {
            await containerManager.manuallyRecreateContainer()
        }
        
        // CloudKit issues - verify status
        if failures.contains(where: { $0.category == .cloudKit }) {
            await containerManager.recreateContainer()
        }
    }
}

// MARK: - Component Status Row

private struct ComponentStatusRow: View {
    let title: String
    let icon: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal)
    }
}

// MARK: - Compact System Health Badge

/// A small badge showing system health - perfect for toolbars or status bars
struct SystemHealthBadge: View {
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    @Environment(\.showDiagnostics) private var showDiagnostics
    
    private var status: Status {
        if diagnosticManager.unresolvedFailures.contains(where: { $0.severity == .critical }) {
            return .critical
        } else if !diagnosticManager.unresolvedFailures.isEmpty {
            return .warning
        } else {
            return .healthy
        }
    }
    
    enum Status {
        case healthy, warning, critical
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .healthy: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }
    
    var body: some View {
        Button {
            showDiagnostics()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.caption)
                
                if status != .healthy {
                    Text("\(diagnosticManager.unresolvedFailures.count)")
                        .font(.caption2.bold())
                }
            }
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("System Health View - Healthy") {
    SystemHealthView()
        .diagnosticsCapable()
}

#Preview("System Health View - With Issues") {
    SystemHealthView()
        .diagnosticsCapable()
        .onAppear {
            DiagnosticManager.shared.addEvent(.containerHealthCheckFailed(error: "Sample error"))
            DiagnosticManager.shared.addEvent(.networkError(operation: "sync", error: "Timeout"))
        }
}

#Preview("System Health Badge") {
    VStack(spacing: 20) {
        Text("Healthy State")
        SystemHealthBadge()
        
        Text("With Issues")
        SystemHealthBadge()
            .onAppear {
                DiagnosticManager.shared.addEvent(.containerHealthCheckFailed(error: "Sample error"))
            }
    }
    .padding()
    .diagnosticsCapable()
}

#Preview("In Settings Context") {
    NavigationStack {
        Form {
            Section {
                NavigationLink("Profile") {
                    Text("Profile")
                }
                NavigationLink("Preferences") {
                    Text("Preferences")
                }
            }
            
            Section("System") {
                NavigationLink {
                    SystemHealthView()
                } label: {
                    HStack {
                        Label("System Health", systemImage: "heart.text.square")
                        Spacer()
                        SystemHealthBadge()
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
    .diagnosticsCapable()
    .onAppear {
        DiagnosticManager.shared.addEvent(.cloudKitUnavailable(reason: "No account"))
    }
}
