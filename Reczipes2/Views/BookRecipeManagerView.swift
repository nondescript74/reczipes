//
//  BookRecipeManagerView.swift
//  Reczipes2
//
//  Created on 1/28/26.
//

import SwiftUI
import SwiftData

struct BookRecipeManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecipes: [RecipeX]
    @Query private var recipeXEntities: [RecipeX]
    
    let book: Book
    
    @State private var searchText = ""
    @State private var selectedRecipeIDs: Set<UUID> = []
    /// Day used by "Add all added on…" to bulk-add one import session (e.g. a batch extraction).
    @State private var addedOnDay = Date()
    
    // Get recipes currently in the book
    private var bookRecipeIDs: Set<UUID> {
        Set(book.recipeIDs ?? [])
    }
    
    // Filter recipes based on search
    private var filteredRecipes: [RecipeX] {
        if searchText.isEmpty {
            return allRecipes
        } else {
            return allRecipes.filter { recipe in
                recipe.title?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    // Recipes not in the book, newest first so one import session sits together
    private var availableRecipes: [RecipeX] {
        filteredRecipes
            .filter { !bookRecipeIDs.contains($0.id ?? UUID()) }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }

    /// Recipes not yet in the book whose dateAdded falls on `addedOnDay` (local calendar).
    /// Ignores the search text so the count always reflects the whole day.
    private var recipesAddedOnSelectedDay: [RecipeX] {
        let calendar = Calendar.current
        return allRecipes
            .filter { !bookRecipeIDs.contains($0.id ?? UUID()) }
            .filter { recipe in
                guard let added = recipe.dateAdded else { return false }
                return calendar.isDate(added, inSameDayAs: addedOnDay)
            }
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }
    
    // Recipes already in the book
    private var recipesInBook: [RecipeX] {
        guard let recipeIDs = book.recipeIDs else { return [] }
        return recipeIDs.compactMap { recipeID in
            allRecipes.first { $0.id == recipeID }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Bulk add by date
                Section {
                    DatePicker("Added on", selection: $addedOnDay, displayedComponents: .date)
                    Button {
                        addRecipesAddedOnSelectedDay()
                    } label: {
                        Label(
                            "Add all \(recipesAddedOnSelectedDay.count) recipe\(recipesAddedOnSelectedDay.count == 1 ? "" : "s") added that day",
                            systemImage: "plus.rectangle.on.rectangle"
                        )
                    }
                    .disabled(recipesAddedOnSelectedDay.isEmpty)
                } header: {
                    Text("Add by Date")
                } footer: {
                    Text("Adds every recipe you added on the chosen day that isn't already in this book — handy after a batch extraction.")
                }

                // Recipes in book section
                if !recipesInBook.isEmpty {
                    Section {
                        ForEach(recipesInBook) { recipe in
                            BookRecipeRowView(recipe: recipe, isInBook: true) {
                                removeRecipe(recipe)
                            }
                        }
                    } header: {
                        Text("In This Book (\(recipesInBook.count))")
                    }
                }
                
                // Available recipes section
                Section {
                    if availableRecipes.isEmpty {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No More Recipes",
                                systemImage: "book.closed",
                                description: Text("All your recipes are already in this book")
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        ForEach(availableRecipes) { recipe in
                            BookRecipeRowView(recipe: recipe, isInBook: false) {
                                addRecipe(recipe)
                            }
                        }
                    }
                } header: {
                    Text("Available Recipes (\(availableRecipes.count))")
                }
            }
            .navigationTitle("Manage Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 700)
        #endif
    }
    
    // MARK: - Helper Methods
    
    private func addRecipe(_ recipe: RecipeX) {
        guard let recipeID = recipe.id else { return }
        
        withAnimation {
            book.addRecipe(recipeID)
            
            do {
                try modelContext.save()
                AppLog.info("Added recipe '\(recipe.title ?? "Untitled")' to book '\(book.displayName)'", category: .recipe)
            } catch {
                AppLog.error("Failed to add recipe to book: \(error)", category: .recipe)
            }
        }
    }
    
    private func addRecipesAddedOnSelectedDay() {
        let recipes = recipesAddedOnSelectedDay
        guard !recipes.isEmpty else { return }

        withAnimation {
            for recipe in recipes {
                if let recipeID = recipe.id {
                    book.addRecipe(recipeID)
                }
            }

            do {
                try modelContext.save()
                AppLog.info("Added \(recipes.count) recipes added on \(addedOnDay.formatted(date: .abbreviated, time: .omitted)) to book '\(book.displayName)'", category: .recipe)
            } catch {
                AppLog.error("Failed to bulk-add recipes to book: \(error)", category: .recipe)
            }
        }
    }

    private func removeRecipe(_ recipe: RecipeX) {
        guard let recipeID = recipe.id else { return }
        
        withAnimation {
            book.removeRecipe(recipeID)
            
            do {
                try modelContext.save()
                AppLog.info("Removed recipe '\(recipe.title ?? "Untitled")' from book '\(book.displayName)'", category: .recipe)
            } catch {
                AppLog.error("Failed to remove recipe from book: \(error)", category: .recipe)
            }
        }
    }
}

// MARK: - Book Recipe Row View

private struct BookRecipeRowView: View {
    let recipe: RecipeX
    let isInBook: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            // Recipe thumbnail
            if let imageData = recipe.imageData,
               let uiImage = PlatformImage(data: imageData) {
                Image(platformImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title ?? "Untitled Recipe")
                    .font(.body)
                
                if let recipeYield = recipe.recipeYield, !recipeYield.isEmpty {
                    Text(recipeYield)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Add/Remove button
            Button {
                action()
            } label: {
                Image(systemName: isInBook ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isInBook ? .red : .green)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Preview

#Preview {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, RecipeX.self, VersionHistoryRecord.self, configurations: config)
        
        // Create sample data
        let book = Book(name: "My Cookbook")
        container.mainContext.insert(book)
        
        let recipe1 = RecipeX()
        recipe1.title = "Chocolate Chip Cookies"
        recipe1.recipeYield = "24 cookies"
        container.mainContext.insert(recipe1)
        
        let recipe2 = RecipeX()
        recipe2.title = "Banana Bread"
        recipe2.recipeYield = "1 loaf"
        container.mainContext.insert(recipe2)
        
        return BookRecipeManagerView(book: book)
            .modelContainer(container)
    } catch {
        return Text("Failed to create preview: \(error.localizedDescription)")
    }
}
