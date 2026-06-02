//
//  RecipeBookRecipeSelectorView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI
import SwiftData

struct RecipeBookRecipeSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var savedRecipes: [RecipeX]
    
    let book: Book
    
    @State private var searchText = ""
    @State private var selectedRecipeIDs = Set<UUID>()
    
    // Filter recipes that aren't already in the book
    private var availableRecipes: [RecipeX] {
        savedRecipes.filter { recipe in
            guard let recipeID = recipe.id else { return false }
            return !(book.recipeIDs?.contains(recipeID) ?? false)
        }
    }
    
    private var filteredRecipes: [RecipeX] {
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
            Group {
                if availableRecipes.isEmpty {
                    emptyStateView
                } else {
                    recipeListView
                }
            }
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedRecipeIDs.count))") {
                        addSelectedRecipes()
                    }
                    .disabled(selectedRecipeIDs.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Recipes Available", systemImage: "tray")
        } description: {
            if savedRecipes.isEmpty {
                Text("Save some recipes first to add them to books")
            } else {
                Text("All your recipes are already in this book")
            }
        }
    }
    
    // MARK: - Recipe List View
    
    private var recipeListView: some View {
        List(filteredRecipes) { recipe in
            RecipeSelectionRow(
                recipe: recipe,
                isSelected: selectedRecipeIDs.contains(recipe.id ?? UUID()),
                bookColor: bookColor
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if let recipeID = recipe.id {
                    toggleSelection(recipeID)
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Helper Methods
    
    private func toggleSelection(_ recipeID: UUID) {
        if selectedRecipeIDs.contains(recipeID) {
            selectedRecipeIDs.remove(recipeID)
        } else {
            selectedRecipeIDs.insert(recipeID)
        }
    }
    
    private func addSelectedRecipes() {
        // Add the selected recipe IDs to the book
        for recipeID in selectedRecipeIDs {
            if let bookRecipeIDs = book.recipeIDs {
                if !bookRecipeIDs.contains(recipeID) {
                    book.recipeIDs?.append(recipeID)
                }
            } else {
                book.recipeIDs = [recipeID]
            }
        }
        
        book.dateModified = Date()
        
        do {
            try modelContext.save()
            AppLog.info("Added \(selectedRecipeIDs.count) recipes to book: \(String(describing: book.name))", category: .recipe)
            dismiss()
        } catch {
            AppLog.error("Failed to add recipes to book: \(error)", category: .recipe)
        }
    }
}

// MARK: - Recipe Selection Row

struct RecipeSelectionRow: View {
    let recipe: RecipeX
    let isSelected: Bool
    let bookColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? bookColor : Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                if isSelected {
                    Circle()
                        .fill(bookColor)
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "checkmark")
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
    let book = Book(
        name: "Favorites",
        bookDescription: "My favorite recipes",
        color: "FF6B6B"
    )
    
    // Create some sample recipes
    let recipe1 = RecipeX(
        id: UUID(),
        title: "Chocolate Chip Cookies",
        headerNotes: "Classic homemade cookies",
        recipeYield: "24 cookies",
        reference: nil,
        imageName: nil,
        dateAdded: Date()
    )
    
    let recipe2 = RecipeX(
        id: UUID(),
        title: "Apple Pie",
        headerNotes: "Traditional American dessert",
        recipeYield: "8 servings",
        reference: nil,
        imageName: nil,
        dateAdded: Date()
    )
    
    container.mainContext.insert(book)
    container.mainContext.insert(recipe1)
    container.mainContext.insert(recipe2)
    
    return RecipeBookRecipeSelectorView(book: book)
        .modelContainer(container)
}
