//
//  RecipeBookRecipeManagerView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData

struct RecipeBookRecipeManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedRecipes: [RecipeX]
    
    let book: Book
    
    @State private var searchText = ""
    @State private var selectedTab: ManagerTab = .current
    @State private var recipesToRemove = Set<UUID>()
    @State private var recipesToAdd = Set<UUID>()
    @State private var showingRemoveConfirmation = false
    
    enum ManagerTab {
        case current
        case add
    }
    
    // Recipes currently in the book
    private var currentRecipes: [RecipeX] {
        book.recipeIDs?.compactMap { recipeID in
            savedRecipes.first { $0.id == recipeID }
        } ?? []
    }
    
    // Recipes available to add (not currently in book)
    private var availableRecipes: [RecipeX] {
        savedRecipes.filter { recipe in
            guard let recipeID = recipe.id else { return false }
            return !(book.recipeIDs?.contains(recipeID) ?? false)
        }
    }
    
    // Filtered current recipes based on search
    private var filteredCurrentRecipes: [RecipeX] {
        if searchText.isEmpty {
            return currentRecipes
        } else {
            return currentRecipes.filter { recipe in
                recipe.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    // Filtered available recipes based on search
    private var filteredAvailableRecipes: [RecipeX] {
        if searchText.isEmpty {
            return availableRecipes
        } else {
            return availableRecipes.filter { recipe in
                recipe.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    private var bookColor: Color {
        if let colorHex = book.color {
            return Color(hex: colorHex) ?? .blue
        }
        return .blue
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $selectedTab) {
                    Text("Current (\(currentRecipes.count))").tag(ManagerTab.current)
                    Text("Add (\(availableRecipes.count))").tag(ManagerTab.add)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on selected tab
                Group {
                    if selectedTab == .current {
                        currentRecipesView
                    } else {
                        addRecipesView
                    }
                }
            }
            .navigationTitle("Manage Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if selectedTab == .current && !recipesToRemove.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Remove (\(recipesToRemove.count))", role: .destructive) {
                            showingRemoveConfirmation = true
                        }
                    }
                } else if selectedTab == .add && !recipesToAdd.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add (\(recipesToAdd.count))") {
                            addSelectedRecipes()
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove \(recipesToRemove.count) recipe\(recipesToRemove.count == 1 ? "" : "s")?",
                isPresented: $showingRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    removeSelectedRecipes()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the selected recipes from this book. The recipes will not be deleted from your collection.")
            }
        }
    }
    
    // MARK: - Current Recipes View
    
    private var currentRecipesView: some View {
        Group {
            if currentRecipes.isEmpty {
                ContentUnavailableView {
                    Label("No Recipes", systemImage: "book.closed")
                } description: {
                    Text("This book doesn't have any recipes yet")
                } actions: {
                    Button {
                        selectedTab = .add
                    } label: {
                        Label("Add Recipes", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(bookColor)
                }
            } else if filteredCurrentRecipes.isEmpty {
                ContentUnavailableView.search
            } else {
                List(filteredCurrentRecipes) { recipe in
                    RecipeManagementRow(
                        recipe: recipe,
                        isSelected: recipesToRemove.contains(recipe.id ?? UUID()),
                        bookColor: bookColor,
                        mode: .remove
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let recipeID = recipe.id {
                            toggleRemoveSelection(recipeID)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Add Recipes View
    
    private var addRecipesView: some View {
        Group {
            if availableRecipes.isEmpty {
                ContentUnavailableView {
                    Label("No Recipes Available", systemImage: "checkmark.circle")
                } description: {
                    if savedRecipes.isEmpty {
                        Text("Save some recipes first to add them to books")
                    } else {
                        Text("All your recipes are already in this book")
                    }
                }
            } else if filteredAvailableRecipes.isEmpty {
                ContentUnavailableView.search
            } else {
                List(filteredAvailableRecipes) { recipe in
                    RecipeManagementRow(
                        recipe: recipe,
                        isSelected: recipesToAdd.contains(recipe.id ?? UUID()),
                        bookColor: bookColor,
                        mode: .add
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let recipeID = recipe.id {
                            toggleAddSelection(recipeID)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func toggleRemoveSelection(_ recipeID: UUID) {
        if recipesToRemove.contains(recipeID) {
            recipesToRemove.remove(recipeID)
        } else {
            recipesToRemove.insert(recipeID)
        }
    }
    
    private func toggleAddSelection(_ recipeID: UUID) {
        if recipesToAdd.contains(recipeID) {
            recipesToAdd.remove(recipeID)
        } else {
            recipesToAdd.insert(recipeID)
        }
    }
    
    private func removeSelectedRecipes() {
        // Remove the selected recipe IDs from the book
        for recipeID in recipesToRemove {
            book.removeRecipe(recipeID)
        }
        
        do {
            try modelContext.save()
            AppLog.info("Removed \(recipesToRemove.count) recipes from book: \(book.name ?? "Unknown")", category: .recipe)
            recipesToRemove.removeAll()
        } catch {
            AppLog.error("Failed to remove recipes from book: \(error)", category: .recipe)
        }
    }
    
    private func addSelectedRecipes() {
        // Add the selected recipe IDs to the book
        for recipeID in recipesToAdd {
            book.addRecipe(recipeID)
        }
        
        do {
            try modelContext.save()
            AppLog.info("Added \(recipesToAdd.count) recipes to book: \(book.name ?? "Unknown")", category: .recipe)
            recipesToAdd.removeAll()
            // Switch back to current tab to show the newly added recipes
            selectedTab = .current
        } catch {
            AppLog.error("Failed to add recipes to book: \(error)", category: .recipe)
        }
    }
}

// MARK: - Recipe Management Row

struct RecipeManagementRow: View {
    let recipe: RecipeX
    let isSelected: Bool
    let bookColor: Color
    let mode: Mode
    
    enum Mode {
        case add
        case remove
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? bookColor : Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                if isSelected {
                    Circle()
                        .fill(mode == .remove ? .red : bookColor)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: mode == .remove ? "minus" : "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            
            // Recipe thumbnail
            if let imageName = recipe.imageName {
                RecipeImageView(
                    imageName: imageName,
                    size: CGSize(width: 60, height: 60),
                    cornerRadius: 8
                )
                .frame(width: 60, height: 60)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.gray)
                    }
            }
            
            // Recipe info
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title ?? "Untitled Recipe")
                    .font(.headline)
                    .lineLimit(2)
                
                if let headerNotes = recipe.headerNotes {
                    Text(headerNotes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Book.self, RecipeX.self, configurations: config)
    
    // Create a sample book
    let book = Book()
    book.id = UUID()
    book.name = "Favorites"
    book.bookDescription = "My favorite recipes"
    book.color = "FF6B6B"
    
    // Create some sample recipes
    let recipe1 = RecipeX()
    recipe1.id = UUID()
    recipe1.title = "Chocolate Chip Cookies"
    recipe1.headerNotes = "Classic homemade cookies"
    recipe1.recipeYield = "24 cookies"
    recipe1.dateAdded = Date()
    
    let recipe2 = RecipeX()
    recipe2.id = UUID()
    recipe2.title = "Apple Pie"
    recipe2.headerNotes = "Traditional American dessert"
    recipe2.recipeYield = "8 servings"
    recipe2.dateAdded = Date()
    
    let recipe3 = RecipeX()
    recipe3.id = UUID()
    recipe3.title = "Spaghetti Carbonara"
    recipe3.headerNotes = "Italian pasta classic"
    recipe3.recipeYield = "4 servings"
    recipe3.dateAdded = Date()
    
    // Add some recipes to the book
    book.recipeIDs = [recipe1.id, recipe2.id].compactMap { $0 }
    
    container.mainContext.insert(book)
    container.mainContext.insert(recipe1)
    container.mainContext.insert(recipe2)
    container.mainContext.insert(recipe3)
    
    return RecipeBookRecipeManagerView(book: book)
        .modelContainer(container)
}
