//
//  CommunitySharingCleanupView.swift
//  Reczipes2
//
//  Created on 1/18/26.
//

import SwiftUI
import SwiftData

struct CommunitySharingCleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isRunningDiagnostic = false
    @State private var isRunningCleanup = false
    @State private var isRunningOrphanCleanup = false
    @State private var diagnosticResults: String = ""
    @State private var cleanupResults: String = ""
    @State private var orphanCleanupResults: String = ""
    @State private var showCleanupConfirmation = false
    @State private var showOrphanCleanupConfirmation = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Community Sharing Maintenance", systemImage: "wrench.and.screwdriver.fill")
                        .font(.headline)
                    
                    Text("Use these tools to fix issues with shared recipes showing incorrect counts or duplicate entries.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // MARK: - Diagnostic Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run this to check your CloudKit public database status without making any changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button(action: runDiagnostic) {
                        HStack {
                            Image(systemName: "stethoscope")
                            Text("Run Diagnostic")
                            Spacer()
                            if isRunningDiagnostic {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunningDiagnostic)
                    
                    if !diagnosticResults.isEmpty {
                        ScrollView {
                            Text(diagnosticResults)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.appGray6)
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("1. Diagnostic Check", systemImage: "1.circle.fill")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run Debug shared recipes fetch to verify they're working as expected.")
                }
                Button("Debug Shared Recipes") {
                    Task {
                        do {
                            let recipes = try await CloudKitSharingService.shared.fetchSharedRecipes()
                            print("🔍 Fetched \(recipes.count) recipes from CloudKit")
                            
                            for recipe in recipes.prefix(5) {
                                print("  - \(recipe.title) by \(recipe.sharedByUserName ?? "Unknown")")
                            }
                        } catch {
                            print("❌ Error: \(error)")
                        }
                    }
                }
            }
            
            // MARK: - Cleanup Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ This will delete duplicate CloudKit records and rebuild your local tracking. Only use this if you're seeing incorrect recipe counts.")
                        .font(.caption)
                        .foregroundStyle(Color.appWarning)
                    
                    Button(action: {
                        showCleanupConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Clean Up & Resync")
                            Spacer()
                            if isRunningCleanup {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunningCleanup)
                    .tint(.orange)
                    
                    if !cleanupResults.isEmpty {
                        ScrollView {
                            Text(cleanupResults)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.appGray6)
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("2. Cleanup & Resync", systemImage: "2.circle.fill")
            }
            
            // MARK: - Orphan Cleanup Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🗑️ Remove recipes from CloudKit that don't belong to any user (orphaned records). Use this if you see recipes from unknown users.")
                        .font(.caption)
                        .foregroundStyle(Color.appCritical)
                    
                    Button(action: {
                        showOrphanCleanupConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Remove Orphaned Recipes")
                            Spacer()
                            if isRunningOrphanCleanup {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRunningOrphanCleanup)
                    .tint(.red)
                    
                    if !orphanCleanupResults.isEmpty {
                        ScrollView {
                            Text(orphanCleanupResults)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.appGray6)
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Label("3. Remove Orphans", systemImage: "3.circle.fill")
            }
            
            // MARK: - Expected Results
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("Your shared recipes:")
                        Spacer()
                        Text("Mine tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "person.3.fill")
                        Text("All community recipes:")
                        Spacer()
                        Text("Shared tab")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    Text("After cleanup, your counts should be accurate with no duplicates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Expected Results")
            }
            
            // MARK: - Help Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    helpItem(
                        icon: "questionmark.circle",
                        title: "When to use Diagnostic",
                        description: "Check how many recipes are in CloudKit and identify duplicate entries."
                    )
                    
                    Divider()
                    
                    helpItem(
                        icon: "exclamationmark.triangle",
                        title: "When to use Cleanup",
                        description: "Use when seeing wrong counts (e.g., 421 instead of 208) or missing recipes."
                    )
                    
                    Divider()
                    
                    helpItem(
                        icon: "trash.circle",
                        title: "When to use Remove Orphans",
                        description: "Use when seeing recipes from unknown users or recipes with no owner."
                    )
                    
                    Divider()
                    
                    helpItem(
                        icon: "info.circle",
                        title: "What happens during cleanup",
                        description: "1. Removes local tracking\n2. Fetches CloudKit records\n3. Deletes duplicates\n4. Rebuilds clean tracking"
                    )
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle("Sharing Cleanup")
        .platformNavigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clean Up Sharing Data",
            isPresented: $showCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Up & Resync", role: .destructive) {
                runCleanup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete duplicate CloudKit records and rebuild your local sharing data. This operation cannot be undone.\n\nOnly proceed if you're experiencing incorrect recipe counts.")
        }
        .confirmationDialog(
            "Remove Orphaned Recipes",
            isPresented: $showOrphanCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Orphans", role: .destructive) {
                runOrphanCleanup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all recipes in CloudKit that don't have a valid owner (sharedByUserID). This operation cannot be undone.\n\nOnly proceed if you're seeing recipes from unknown users.")
        }
    }
    
    // MARK: - Actions
    
    private func runDiagnostic() {
        isRunningDiagnostic = true
        diagnosticResults = "Running diagnostic...\n"
        
        Task {
            // Capture log output
            let startTime = Date()
            
            await CloudKitSharingService.shared.diagnoseSharedRecipes()
            
            // Simulate waiting for logs to populate
            try? await Task.sleep(for: .seconds(1))
            
            await MainActor.run {
                diagnosticResults = """
                ✅ Diagnostic complete
                
                Check the diagnostic logs in Settings → Advanced Diagnostics for detailed results.
                
                Look for:
                • Total recipes fetched
                • Recipes per user
                • Duplicate recipe IDs
                
                Completed in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s
                """
                isRunningDiagnostic = false
            }
        }
    }
    
    private func runCleanup() {
        isRunningCleanup = true
        cleanupResults = "Starting cleanup...\n"
        
        Task {
            do {
                let startTime = Date()
                
                try await CloudKitSharingService.shared.cleanupAndResyncSharing(modelContext: modelContext)
                
                await MainActor.run {
                    cleanupResults = """
                    ✅ Cleanup complete!
                    
                    Your sharing data has been cleaned and resynced.
                    
                    Check the logs for details:
                    • Duplicates removed
                    • Clean records kept
                    • Local tracking rebuilt
                    
                    Go to the Shared tab to verify your recipes are showing correctly.
                    
                    Completed in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s
                    """
                    isRunningCleanup = false
                }
            } catch {
                await MainActor.run {
                    cleanupResults = """
                    ❌ Cleanup failed
                    
                    Error: \(error.localizedDescription)
                    
                    Please check:
                    • You're signed into iCloud
                    • You have internet connection
                    • CloudKit is available
                    
                    Try running the diagnostic first to identify the issue.
                    """
                    isRunningCleanup = false
                }
            }
        }
    }
    
    private func runOrphanCleanup() {
        isRunningOrphanCleanup = true
        orphanCleanupResults = "Starting orphan cleanup...\n"
        
        Task {
            do {
                let startTime = Date()
                
                try await CloudKitSharingService.shared.removeOrphanedRecipes()
                
                await MainActor.run {
                    orphanCleanupResults = """
                    ✅ Orphan cleanup complete!
                    
                    Orphaned recipes have been removed from CloudKit.
                    
                    Check the logs for details:
                    • Number of orphans found
                    • Records deleted
                    • Valid users remaining
                    
                    Go to the Shared tab to verify the orphaned recipes are gone.
                    
                    Completed in \(String(format: "%.1f", Date().timeIntervalSince(startTime)))s
                    """
                    isRunningOrphanCleanup = false
                }
            } catch {
                await MainActor.run {
                    orphanCleanupResults = """
                    ❌ Orphan cleanup failed
                    
                    Error: \(error.localizedDescription)
                    
                    Please check:
                    • You're signed into iCloud
                    • You have internet connection
                    • CloudKit is available
                    
                    Try running the diagnostic first to identify the issue.
                    """
                    isRunningOrphanCleanup = false
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func helpItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.appInfo)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CommunitySharingCleanupView()
    }
}
