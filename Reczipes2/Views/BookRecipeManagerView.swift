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
    @Query private var allBooks: [Book]
    
    let book: Book
    
    @State private var searchText = ""
    @State private var selectedRecipeIDs: Set<UUID> = []
    /// Day used by "Add all added on…" to bulk-add one import session (e.g. a batch extraction).
    @State private var addedOnDay = Date()
    /// Off by default: the picker offers only recipes that aren't in any book yet.
    @State private var includeRecipesInOtherBooks = false
    
    // Get recipes currently in the book
    private var bookRecipeIDs: Set<UUID> {
        Set(book.recipeIDs ?? [])
    }
    
    /// Recipe ids already filed in any book (this one included).
    private var recipeIDsInAnyBook: Set<UUID> {
        Set(allBooks.flatMap { $0.recipeIDs ?? [] })
    }

    /// Content fingerprints of recipes already in a book. A library merge can leave an exact
    /// copy of a filed recipe under a new id (2026-10-15: Mac library merged into Production);
    /// that copy is "already in the book" to the user even though its id is not.
    private var fingerprintsInAnyBook: Set<String> {
        let filed = recipeIDsInAnyBook
        return Set(allRecipes.filter { filed.contains($0.id ?? UUID()) }.compactMap { $0.contentFingerprint })
    }

    /// Returns a predicate for recipes that may be offered for adding to this book.
    /// Builds the lookup sets once per list evaluation (≈600 recipes).
    private func offerablePredicate() -> (RecipeX) -> Bool {
        let inThisBook = bookRecipeIDs
        let include = includeRecipesInOtherBooks
        let inAnyBook = include ? [] : recipeIDsInAnyBook
        let filedPrints = include ? [] : fingerprintsInAnyBook
        return { recipe in
            let id = recipe.id ?? UUID()
            if inThisBook.contains(id) { return false }
            if include { return true }
            if inAnyBook.contains(id) { return false }
            if let fp = recipe.contentFingerprint, filedPrints.contains(fp) { return false }
            return true
        }
    }

    // Filter recipes based on search
    private var filteredRecipes: [RecipeX] {
        if searchText.isEmpty {
            return allRecipes
        } else {
            // Title or source URL, so e.g. "seriouseats" finds every Serious Eats recipe.
            return allRecipes.filter { recipe in
                (recipe.title?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (recipe.reference?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    // Recipes not in the book, newest first so one import session sits together
    private var availableRecipes: [RecipeX] {
        filteredRecipes
            .filter(offerablePredicate())
            .sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
    }

    /// Recipes not yet in the book whose dateAdded falls on `addedOnDay` (local calendar).
    /// Ignores the search text so the count always reflects the whole day.
    private var recipesAddedOnSelectedDay: [RecipeX] {
        let calendar = Calendar.current
        return allRecipes
            .filter(offerablePredicate())
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
                Section {
                    Toggle("Include recipes already in other books", isOn: $includeRecipesInOtherBooks)
                } footer: {
                    Text(includeRecipesInOtherBooks
                         ? "Showing every recipe not in this book."
                         : "Showing only recipes that aren't in any book yet (exact copies of filed recipes are hidden too).")
                }

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
                    Text("Adds every recipe you added on the chosen day that isn't already in a book (or this book, with the switch on) — handy after a batch extraction.")
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
                                description: Text(includeRecipesInOtherBooks ? "All your recipes are already in this book" : "Every recipe is already in a book. Turn on \"Include recipes already in other books\" to see them.")
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
                    HStack {
                        Text("Available Recipes (\(availableRecipes.count))")
                        Spacer()
                        if !searchText.isEmpty && !availableRecipes.isEmpty {
                            Button("Add all \(distinctAvailable.count) matching") {
                                addAllMatching()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Manage Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search title or source URL")
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
    
    /// Available recipes with exact copies (same contentFingerprint) collapsed to one, so a
    /// bulk add files each recipe once even when the library merge left duplicates.
    private var distinctAvailable: [RecipeX] {
        var seen = Set<String>()
        return availableRecipes.filter { recipe in
            guard let fp = recipe.contentFingerprint else { return true }
            return seen.insert(fp).inserted
        }
    }

    /// Adds every recipe currently matching the search (one per exact-copy group).
    private func addAllMatching() {
        let recipes = distinctAvailable
        guard !recipes.isEmpty else { return }
        withAnimation {
            for recipe in recipes {
                if let recipeID = recipe.id { book.addRecipe(recipeID) }
            }
            do {
                try modelContext.save()
                AppLog.info("Added \(recipes.count) recipes matching '\(searchText)' to book '\(book.displayName)'", category: .recipe)
            } catch {
                AppLog.error("Failed to bulk-add matching recipes to book: \(error)", category: .recipe)
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
