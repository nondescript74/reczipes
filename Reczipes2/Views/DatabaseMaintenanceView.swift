//
//  DatabaseMaintenanceView.swift
//  Reczipes2
//
//  Comprehensive database maintenance and cleanup tools
//  Created by Zahirudeen Premji on 1/19/26.
//

import SwiftUI
import SwiftData

struct DatabaseMaintenanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecipes: [RecipeX]
    @Query private var allAssignments: [RecipeImageAssignment]
    
    @StateObject private var duplicateMonitor = CloudKitDuplicateMonitor.shared
    
    @State private var cleanupReport: CleanupReport?
    @State private var isGeneratingReport = false
    @State private var isCleaningUp = false
    @State private var showingFullCleanupAlert = false
    @State private var cleanupResult: CleanupResult?
    
    var body: some View {
        List {
            // Quick Stats
            Section {
                StatRow(label: "Total Recipes", value: "\(allRecipes.count)", icon: "book.fill")
                StatRow(label: "Image Assignments", value: "\(allAssignments.count)", icon: "photo.fill")
                
                if let report = cleanupReport {
                    if report.orphanedAssignments > 0 {
                        StatRow(
                            label: "Orphaned Assignments",
                            value: "\(report.orphanedAssignments)",
                            icon: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                    
                    if report.totalDuplicateRecipes > 0 {
                        StatRow(
                            label: "Duplicate Recipes",
                            value: "\(report.totalDuplicateRecipes)",
                            icon: "doc.on.doc.fill",
                            color: .red
                        )
                    }
                }
            } header: {
                Text("Database Statistics")
            }
            
            // Analysis
            Section {
                Button {
                    generateReport()
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Analyze Database")
                        Spacer()
                        if isGeneratingReport {
                            ProgressView()
                        }
                    }
                }
                .disabled(isGeneratingReport)
                
                if let report = cleanupReport {
                    NavigationLink {
                        ReportDetailView(report: report)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("View Full Report")
                            Spacer()
                            if report.hasIssues {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.appWarning)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appSuccess)
                            }
                        }
                    }
                }
            } header: {
                Text("Analysis")
            }
            
            // Cleanup Tools
            Section {
                NavigationLink("Duplicate Recipe Detector") {
                    DuplicateRecipeDetectorView()
                }
                
                Button {
                    cleanupOrphanedAssignments()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clean Up Orphaned Assignments")
                        if let report = cleanupReport {
                            Spacer()
                            Text("(\(report.orphanedAssignments))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(cleanupReport?.orphanedAssignments == 0)
                
                Button(role: .destructive) {
                    showingFullCleanupAlert = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Execute Full Cleanup")
                    }
                }
                .disabled(!(cleanupReport?.hasIssues ?? false))
            } header: {
                Text("Cleanup Tools")
            } footer: {
                if let result = cleanupResult {
                    Text(result.summary)
                        .font(.caption)
                }
            }
            
            // CloudKit Sync Status
            Section {
                HStack {
                    Text("Sync Status")
                    Spacer()
                    if duplicateMonitor.isSyncing {
                        Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.appInfo)
                    } else {
                        Label("Idle", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                    }
                }
                
                if let lastReset = duplicateMonitor.lastSyncReset {
                    HStack {
                        Text("Last Sync Reset")
                        Spacer()
                        Text(lastReset, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if duplicateMonitor.duplicatesDetected > 0 {
                    HStack {
                        Text("Duplicates Detected")
                        Spacer()
                        Text("\(duplicateMonitor.duplicatesDetected)")
                            .foregroundStyle(Color.appCritical)
                            .fontWeight(.bold)
                    }
                }
            } header: {
                Text("CloudKit Status")
            }
        }
        .navigationTitle("Database Maintenance")
        .platformNavigationBarTitleDisplayMode(.inline)
        .alert("Full Cleanup", isPresented: $showingFullCleanupAlert) {
            Button("Execute Cleanup", role: .destructive) {
                executeFullCleanup()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all duplicate recipes and orphaned assignments. This action cannot be undone. Are you sure?")
        }
        .onAppear {
            duplicateMonitor.configure(with: modelContext)
            generateReport()
        }
    }
    
    // MARK: - Actions
    
    private func generateReport() {
        isGeneratingReport = true
        
        Task {
            do {
                let report = try await OrphanedDataCleanupUtility.generateCleanupReport(context: modelContext)
                
                await MainActor.run {
                    cleanupReport = report
                    isGeneratingReport = false
                    print(report.summary)
                }
            } catch {
                await MainActor.run {
                    isGeneratingReport = false
                    print("❌ Failed to generate report: \(error)")
                }
            }
        }
    }
    
    private func cleanupOrphanedAssignments() {
        isCleaningUp = true
        
        Task {
            do {
                try await OrphanedDataCleanupUtility.cleanupOrphanedImageAssignments(context: modelContext)
                
                await MainActor.run {
                    isCleaningUp = false
                    // Refresh report
                    generateReport()
                }
            } catch {
                await MainActor.run {
                    isCleaningUp = false
                    print("❌ Cleanup failed: \(error)")
                }
            }
        }
    }
    
    private func executeFullCleanup() {
        isCleaningUp = true
        
        Task {
            do {
                let result = try await OrphanedDataCleanupUtility.executeFullCleanup(context: modelContext)
                
                await MainActor.run {
                    cleanupResult = result
                    isCleaningUp = false
                    
                    // Refresh report
                    generateReport()
                    
                    // Update monitor
                    duplicateMonitor.duplicatesDetected = 0
                }
            } catch {
                await MainActor.run {
                    isCleaningUp = false
                    print("❌ Full cleanup failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    var color: Color = .blue
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

struct ReportDetailView: View {
    let report: CleanupReport
    
    var body: some View {
        List {
            Section {
                Text(report.summary)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } header: {
                Text("Full Report")
            }
            
            Section {
                if report.hasIssues {
                    Label("Issues detected in database", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appWarning)
                } else {
                    Label("Database is clean", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                }
            } header: {
                Text("Status")
            }
            
            Section {
                Text("Total Recipes")
                    .badge("\(report.totalRecipes)")
                Text("Total Image Assignments")
                    .badge("\(report.totalImageAssignments)")
            } header: {
                Text("Counts")
            }
            
            if report.hasIssues {
                Section {
                    if report.orphanedAssignments > 0 {
                        Label {
                            Text("Orphaned Assignments")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.appWarning)
                        }
                        .badge("\(report.orphanedAssignments)")
                    }
                    
                    if report.totalDuplicateRecipes > 0 {
                        Label {
                            Text("Duplicate Recipes")
                        } icon: {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundStyle(Color.appCritical)
                        }
                        .badge("\(report.totalDuplicateRecipes)")
                    }
                } header: {
                    Text("Issues")
                }
            }
        }
        .navigationTitle("Database Report")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DatabaseMaintenanceView()
            .modelContainer(for: RecipeX.self, inMemory: true)
    }
}
