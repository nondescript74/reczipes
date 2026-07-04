//
//  EmptyRecipeCleanupView.swift
//  Reczipes2
//
//  View for identifying and deleting recipes with no ingredients and no instructions
//

import SwiftUI
import SwiftData

/// View for cleaning up recipes that have neither ingredients nor instructions
struct EmptyRecipeCleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var allRecipes: [RecipeX]
    @Query private var allBooks: [Book]
    
    @State private var emptyRecipes: [RecipeX] = []
    @State private var isScanning = false
    @State private var isDeleting = false
    @State private var scanResults: String = ""
    @State private var currentProgress: Double = 0.0
    @State private var currentRecipeName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var deletionResults: String = ""
    
    // Helper computed properties for complex views
    private var warningText: some View {
        Text("⚠️ This operation will:")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appWarning)
    }
    
    private var operationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• Remove recipes from all books")
            Text("• Unshare recipes from CloudKit")
            Text("• Delete from local storage and iCloud")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Empty Recipe Cleanup")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("This tool finds and removes recipes that have neither ingredients nor instructions. These are typically failed extractions or incomplete imports.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        warningText
                        
                        operationList
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Scan Results") {
                    if isScanning {
                        HStack {
                            ProgressView()
                            Text("Scanning recipes...")
                                .foregroundStyle(.secondary)
                        }
                    } else if scanResults.isEmpty {
                        Text("No scan performed yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        Text(scanResults)
                            .font(.subheadline)
                    }
                    
                    Button {
                        Task {
                            await scanForEmptyRecipes()
                        }
                    } label: {
                        Label("Scan for Empty Recipes", systemImage: "magnifyingglass")
                    }
                    .disabled(isScanning || isDeleting)
                }
                
                if !emptyRecipes.isEmpty {
                    Section("Empty Recipes Found (\(emptyRecipes.count))") {
                        ForEach(emptyRecipes) { recipe in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.title ?? "Untitled")
                                    .font(.headline)
                                
                                HStack(spacing: 12) {
                                    // Show book assignments
                                    let bookCount = booksContainingRecipe(recipe).count
                                    if bookCount > 0 {
                                        Label("\(bookCount) book\(bookCount == 1 ? "" : "s")", systemImage: "book.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.appInfo)
                                    }
                                    
                                    // Show sharing status
                                    if recipe.cloudRecordID != nil {
                                        Label("Shared", systemImage: "icloud.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.appSuccess)
                                    }
                                    
                                    // Show dates
                                    if let dateAdded = recipe.dateAdded {
                                        Text(dateAdded, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete All Empty Recipes", systemImage: "trash.fill")
                        }
                        .disabled(isScanning || isDeleting)
                        
                        if !deletionResults.isEmpty {
                            Text(deletionResults)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Progress section during deletion
                if isDeleting {
                    Section("Deletion Progress") {
                        VStack(spacing: 12) {
                            ProgressView(value: currentProgress, total: 1.0) {
                                Text("Processing: \(currentRecipeName)")
                                    .font(.subheadline)
                            }
                            .progressViewStyle(.linear)
                            
                            Text("\(Int(currentProgress * 100))% complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Empty Recipe Cleanup")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Empty Recipes", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    Task {
                        await deleteEmptyRecipes()
                    }
                }
            } message: {
                Text("Are you sure you want to delete \(emptyRecipes.count) empty recipe\(emptyRecipes.count == 1 ? "" : "s")? This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Scanning
    
    @MainActor
    private func scanForEmptyRecipes() async {
        isScanning = true
        emptyRecipes.removeAll()
        
        var emptyCount = 0
        
        for recipe in allRecipes {
            // Check if recipe has neither ingredients nor instructions
            let hasIngredients = recipe.ingredientSectionsData != nil && !recipe.ingredientSections.isEmpty
            let hasInstructions = recipe.instructionSectionsData != nil && !recipe.instructionSections.isEmpty
            
            if !hasIngredients && !hasInstructions {
                emptyRecipes.append(recipe)
                emptyCount += 1
            }
        }
        
        // Build scan results message
        var resultsMessage = "Scanned \(allRecipes.count) recipes.\n\n"
        
        if emptyCount == 0 {
            resultsMessage += "✅ No empty recipes found!"
        } else {
            resultsMessage += "Found \(emptyCount) empty recipe\(emptyCount == 1 ? "" : "s") that can be deleted.\n\n"
            resultsMessage += "These recipes have neither ingredients nor instructions."
        }
        
        scanResults = resultsMessage
        isScanning = false
        
        AppLog.info("📊 Empty recipe scan complete: \(emptyCount) empty recipes found out of \(allRecipes.count) total", category: .storage)
    }
    
    // MARK: - Deletion
    
    @MainActor
    private func deleteEmptyRecipes() async {
        guard !emptyRecipes.isEmpty else { return }
        
        isDeleting = true
        currentProgress = 0.0
        
        var deletedCount = 0
        var failedCount = 0
        var removedFromBooks = 0
        var unsharedCount = 0
        
        let totalRecipes = emptyRecipes.count
        
        for (index, recipe) in emptyRecipes.enumerated() {
            currentRecipeName = recipe.title ?? "Untitled"
            currentProgress = Double(index) / Double(totalRecipes)
            
            AppLog.info("🗑️ Deleting empty recipe: \(currentRecipeName)", category: .storage)
            
            do {
                // Step 1: Remove from all books
                let booksContaining = booksContainingRecipe(recipe)
                for book in booksContaining {
                    if let recipeID = recipe.id {
                        book.removeRecipe(recipeID)
                        removedFromBooks += 1
                        AppLog.info("📚 Removed recipe from book: \(book.displayName)", category: .storage)
                    }
                }
                
                // Step 2: Unshare from CloudKit if shared
                if let cloudRecordID = recipe.cloudRecordID {
                    do {
                        try await CloudKitSharingService.shared.unshareRecipe(
                            cloudRecordID: cloudRecordID,
                            modelContext: modelContext
                        )
                        unsharedCount += 1
                        AppLog.info("☁️ Unshared recipe from CloudKit", category: .storage)
                    } catch {
                        AppLog.error("Failed to unshare recipe \(currentRecipeName): \(error)", category: .storage)
                        // Continue with deletion even if unsharing fails
                    }
                }
                
                // Step 3: Delete from local storage
                modelContext.delete(recipe)
                deletedCount += 1
                
                // Save after each deletion to ensure progress is persisted
                try modelContext.save()
                
                AppLog.info("✅ Successfully deleted empty recipe: \(currentRecipeName)", category: .storage)
                
            } catch {
                AppLog.error("❌ Failed to delete recipe \(currentRecipeName): \(error)", category: .storage)
                failedCount += 1
            }
            
            // Small delay to allow UI to update
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        
        currentProgress = 1.0
        
        // Build deletion results message
        var resultsMessage = ""
        if deletedCount > 0 {
            resultsMessage += "✅ Successfully deleted \(deletedCount) recipe\(deletedCount == 1 ? "" : "s").\n"
        }
        if removedFromBooks > 0 {
            resultsMessage += "📚 Removed from \(removedFromBooks) book assignment\(removedFromBooks == 1 ? "" : "s").\n"
        }
        if unsharedCount > 0 {
            resultsMessage += "☁️ Unshared \(unsharedCount) recipe\(unsharedCount == 1 ? "" : "s") from CloudKit.\n"
        }
        if failedCount > 0 {
            resultsMessage += "\n⚠️ \(failedCount) recipe\(failedCount == 1 ? "" : "s") could not be deleted."
        }
        
        deletionResults = resultsMessage
        isDeleting = false
        
        // Clear empty recipes list and rescan
        emptyRecipes.removeAll()
        await scanForEmptyRecipes()
        
        AppLog.info("📊 Cleanup complete: \(deletedCount) deleted, \(failedCount) failed, \(removedFromBooks) book removals, \(unsharedCount) unshared", category: .storage)
    }
    
    // MARK: - Helpers
    
    private func booksContainingRecipe(_ recipe: RecipeX) -> [Book] {
        guard let recipeID = recipe.id else { return [] }
        return allBooks.filter { book in
            book.recipeIDs?.contains(recipeID) ?? false
        }
    }
}

#Preview {
    EmptyRecipeCleanupView()
        .modelContainer(for: [RecipeX.self, Book.self], inMemory: true)
}
