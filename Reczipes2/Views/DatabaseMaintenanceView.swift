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
    // Old public book copies (2026-11-05)
    @State private var retirable: [CloudKitSharingService.RetirableBook]?
    @State private var retireSelection = Set<UUID>()
    @State private var isFindingRetirable = false
    @State private var isRetiring = false
    @State private var showingRetireAlert = false
    @State private var retireMessage: String?
    @State private var bookGroups: [BookDuplicateGroup]?
    @State private var keepChoice: [String: UUID] = [:]
    @State private var groupToMerge: BookDuplicateGroup?
    @State private var bookMergeMessage: String?
    
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
            
            // Duplicate books (same name)
            Section {
                Button {
                    findDuplicateBooks()
                } label: {
                    Label("Find Duplicate Books", systemImage: "rectangle.stack")
                }

                if let bookGroups {
                    if bookGroups.isEmpty {
                        Text("No two of your books share a name.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(bookGroups) { group in
                        let all = [group.keep] + group.extras
                        let keepID = keepChoice[group.key] ?? group.keep.id
                        let keptRecipes = Set(all.first { $0.id == keepID }?.recipeIDs ?? [])
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(group.keep.name) — \(all.count) copies")
                                .font(.headline)
                            Picker("Keep", selection: Binding(
                                get: { keepChoice[group.key] ?? group.keep.id },
                                set: { keepChoice[group.key] = $0 }
                            )) {
                                ForEach(all) { copy in
                                    Text("\(copy.recipeIDs.count) recipes\(copy.dateCreated.map { ", made \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                                        .tag(copy.id)
                                }
                            }
                            ForEach(all.filter { $0.id != keepID }) { copy in
                                let added = Set(copy.recipeIDs).subtracting(keptRecipes).count
                                Text(added == 0
                                     ? "• Copy with \(copy.recipeIDs.count) recipes: adds nothing"
                                     : "• Copy with \(copy.recipeIDs.count) recipes: adds \(added) recipes")
                                    .font(.caption)
                                    .foregroundStyle(added == 0 ? Color.secondary : Color.appWarning)
                            }
                            Button("Merge Into Kept Book") { groupToMerge = group }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Duplicate Books")
            } footer: {
                Text(bookMergeMessage ?? "Your books that share a name. Merging moves every recipe and picture into the book you keep, then removes the other copies from your library and marks their public copies replaced, so every device and the website show one book. No recipe is deleted.")
            }

            // Old public book copies
            Section {
                Button {
                    Task { await findRetirable() }
                } label: {
                    HStack {
                        Label("Find Old Public Book Copies", systemImage: "books.vertical")
                        if isFindingRetirable { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isFindingRetirable || isRetiring)

                if let retirable {
                    if retirable.isEmpty {
                        Text("No old copies: every public book of yours is a book in this library.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(retirable) { item in
                            Toggle(isOn: Binding(
                                get: { retireSelection.contains(item.id) },
                                set: { on in
                                    if on { retireSelection.insert(item.id) } else { retireSelection.remove(item.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text("Old copy: \(item.recipeCount) recipes, shared \(item.sharedDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let count = item.replacementRecipeCount {
                                        Text(item.recipeCount > 0
                                             ? "All \(item.recipeCount) are in current book \u{201C}\(item.replacementName ?? "")\u{201D} (\(count) recipes)"
                                             : "Empty; current book \u{201C}\(item.replacementName ?? "")\u{201D} has \(count) recipes")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No single current book holds all its recipes")
                                            .font(.caption)
                                            .foregroundStyle(Color.appWarning)
                                    }
                                }
                            }
                        }

                        Button(role: .destructive) {
                            showingRetireAlert = true
                        } label: {
                            HStack {
                                Label("Retire \(retireSelection.count) Old Copies", systemImage: "archivebox")
                                if isRetiring { Spacer(); ProgressView().controlSize(.small) }
                            }
                        }
                        .disabled(retireSelection.isEmpty || isRetiring)
                    }
                }
            } header: {
                Text("Old Public Book Copies")
            } footer: {
                if let retireMessage {
                    Text(retireMessage)
                } else {
                    Text("Public copies of books that are no longer in your library (left by a merge). They never update, so the website shows them stale beside the current book. Retiring marks them deleted by you: nothing is removed, and people who already have them keep them, marked User Deleted.")
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
        .alert("Merge Books", isPresented: Binding(
            get: { groupToMerge != nil },
            set: { if !$0 { groupToMerge = nil } }
        )) {
            Button("Merge", role: .destructive) {
                if let group = groupToMerge { mergeGroup(group) }
                groupToMerge = nil
            }
            Button("Cancel", role: .cancel) { groupToMerge = nil }
        } message: {
            Text("All copies of \u{201C}\(groupToMerge?.keep.name ?? "")\u{201D} become one book. No recipe is deleted.")
        }
        .alert("Retire Old Copies", isPresented: $showingRetireAlert) {
            Button("Retire \(retireSelection.count)", role: .destructive) {
                Task { await retireSelected() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The \(retireSelection.count) selected old public copies will be marked deleted by you and leave the website. Your current books are not touched.")
        }
        .onAppear {
            duplicateMonitor.configure(with: modelContext)
            generateReport()
        }
    }
    
    // MARK: - Actions

    private func findDuplicateBooks() {
        bookMergeMessage = nil
        let groups = BookMerger.duplicateGroups(in: modelContext)
        bookGroups = groups
        keepChoice = Dictionary(uniqueKeysWithValues: groups.map { ($0.key, $0.keep.id) })
    }

    private func mergeGroup(_ group: BookDuplicateGroup) {
        let all = [group.keep] + group.extras
        let keepID = keepChoice[group.key] ?? group.keep.id
        let merged = BookMerger.merge(keepID: keepID, extraIDs: all.map(\.id).filter { $0 != keepID }, in: modelContext)
        findDuplicateBooks()
        bookMergeMessage = String(localized: "Merged \(merged) copies of \u{201C}\(group.keep.name)\u{201D}. The website drops the old copies on its next refresh (about 5 minutes).", bundle: .appLanguage)
    }

    private func findRetirable() async {
        isFindingRetirable = true
        defer { isFindingRetirable = false }
        retireMessage = nil
        guard let found = await CloudKitSharingService.shared.findRetirableBooks(modelContext: modelContext) else {
            retirable = nil
            retireMessage = String(localized: "Couldn't read your public books completely. Nothing was changed; try again.", bundle: .appLanguage)
            return
        }
        retirable = found
        // Preselect only old copies that have exactly one current book of the same name.
        retireSelection = Set(found.filter { $0.replacementID != nil }.map(\.id))
    }

    private func retireSelected() async {
        guard let retirable else { return }
        isRetiring = true
        defer { isRetiring = false }
        let chosen = retirable.filter { retireSelection.contains($0.id) }
        let done = await CloudKitSharingService.shared.retireBooks(chosen, modelContext: modelContext)
        retireMessage = done == chosen.count
            ? "Retired \(done) old copies. The website drops them on its next refresh (within about 5 minutes)."
            : "Retired \(done) of \(chosen.count); the rest stay queued and are retried on the next sync."
        await findRetirable()
        if done == chosen.count {
            retireMessage = String(localized: "Retired \(done) old copies. The website drops them on its next refresh (within about 5 minutes).", bundle: .appLanguage)
        }
    }

    
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
