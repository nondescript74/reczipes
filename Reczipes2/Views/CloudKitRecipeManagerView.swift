//
//  CloudKitRecipeManagerView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/18/26.
//


// CloudKitRecipeManagerView.swift

import SwiftUI
import SwiftData

struct CloudKitRecipeManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sharingService = CloudKitSharingService.shared
    
    @State private var managerData: CloudKitRecipeManagerData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showingDeleteAllConfirmation = false
    
    var filteredRecipes: [CloudKitRecipeStatus] {
        guard let data = managerData else { return [] }
        if searchText.isEmpty {
            return data.recipes
        }
        return data.recipes.filter { $0.recipe.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        List {
            // Status Section
            Section("Status") {
                if let data = managerData {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("\(data.trackedCount) tracked recipes")
                    }
                    
                    if data.orphanedCount > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.appWarning)
                            Text("\(data.orphanedCount) orphaned recipes")
                        }
                    }
                    
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundStyle(Color.appInfo)
                        Text("\(data.totalCount) total in CloudKit")
                    }
                }
            }
            
            // Tracked Recipes
            if let data = managerData, !data.trackedRecipes.isEmpty {
                Section {
                    ForEach(data.trackedRecipes.filter { recipe in
                        searchText.isEmpty || recipe.recipe.title.localizedCaseInsensitiveContains(searchText)
                    }) { status in
                        RecipeStatusRow(
                            status: status,
                            onDelete: { deleteRecipe(status) },
                            onReTrack: nil
                        )
                    }
                } header: {
                    Label("Tracked Recipes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                }
            }
            
            // Orphaned Recipes
            if let data = managerData, !data.orphanedRecipes.isEmpty {
                Section {
                    ForEach(data.orphanedRecipes.filter { recipe in
                        searchText.isEmpty || recipe.recipe.title.localizedCaseInsensitiveContains(searchText)
                    }) { status in
                        RecipeStatusRow(
                            status: status,
                            onDelete: { deleteRecipe(status) },
                            onReTrack: { reTrackRecipe(status) }
                        )
                    }
                } header: {
                    Label("Orphaned Recipes", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appWarning)
                } footer: {
                    Text("These recipes exist in CloudKit but aren't tracked locally. They may be from a previous device or installation.")
                }
            }
            
            // Actions
            Section {
                Button("Refresh from CloudKit") {
                    Task { await loadRecipes() }
                }
                .disabled(isLoading)
                
                if let data = managerData, data.orphanedCount > 0 {
                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All Orphaned (\(data.orphanedCount))", systemImage: "trash")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search recipes")
        .navigationTitle("My CloudKit Recipes")
        .platformNavigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("Loading...")
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
        .alert("Delete All Orphaned Recipes?", isPresented: $showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await deleteAllOrphaned() }
            }
        } message: {
            if let data = managerData {
                Text("This will permanently delete \(data.orphanedCount) orphaned recipes from CloudKit. This cannot be undone.")
            }
        }
        .task {
            await loadRecipes()
        }
    }
    
    // MARK: - Actions
    
    private func loadRecipes() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let data = try await sharingService.fetchMyCloudKitRecipesWithStatus(modelContext: modelContext)
            await MainActor.run {
                managerData = data
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    private func deleteRecipe(_ status: CloudKitRecipeStatus) {
        Task {
            isLoading = true
            
            do {
                try await sharingService.deleteRecipeFromCloudKit(cloudRecordID: status.cloudRecordID)
                
                // If there's a tracking record, mark it inactive
                if let tracking = status.localTrackingRecord {
                    tracking.isActive = false
                    try modelContext.save()
                }
                
                await loadRecipes()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete recipe: \(error.localizedDescription)"
                }
            }
            
            isLoading = false
        }
    }
    
    private func reTrackRecipe(_ status: CloudKitRecipeStatus) {
        Task {
            isLoading = true
            
            do {
                try sharingService.reTrackRecipe(
                    recipe: status.recipe,
                    cloudRecordID: status.cloudRecordID,
                    modelContext: modelContext
                )
                await loadRecipes()
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to re-track recipe: \(error.localizedDescription)"
                }
            }
            
            isLoading = false
        }
    }
    
    private func deleteAllOrphaned() async {
        guard let data = managerData else { return }
        
        isLoading = true
        
        do {
            try await sharingService.deleteAllOrphanedRecipes(orphanedStatuses: data.orphanedRecipes)
            await loadRecipes()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete orphaned recipes: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
}

// MARK: - Supporting Views

struct RecipeStatusRow: View {
    let status: CloudKitRecipeStatus
    let onDelete: () -> Void
    let onReTrack: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: status.statusIcon)
                    .foregroundColor(status.statusColor)
                
                Text(status.recipe.title)
                    .font(.headline)
                
                Spacer()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Text("Delete")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
            
            Text("Shared: \(status.sharedDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(status.statusDescription)
                    .font(.caption)
                    .foregroundColor(status.statusColor)
            }
            
            if let onReTrack = onReTrack {
                Button {
                    onReTrack()
                } label: {
                    Label("Re-Track This Recipe", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        CloudKitRecipeManagerView()
    }
}