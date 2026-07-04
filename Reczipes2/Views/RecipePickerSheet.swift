//
//  RecipePickerSheet.swift
//  reczipes2-imageextract
//
//  Sheet for selecting a recipe for cooking mode
//

import SwiftUI
import SwiftData

struct RecipePickerSheet: View {
    let currentRecipeID: UUID?
    let onSelect: (RecipeX) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \RecipeX.title) private var allRecipes: [RecipeX]
    
    @State private var searchText = ""
    @State private var selectedCuisine: String?
    
    private var filteredRecipes: [RecipeX] {
        var recipes = allRecipes
        
        // Filter out currently selected recipe
        if let currentID = currentRecipeID {
            recipes = recipes.filter { $0.id != currentID }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            recipes = recipes.filter { recipe in
                recipe.title?.localizedCaseInsensitiveContains(searchText) == true ||
                recipe.cuisine?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        
        // Apply cuisine filter
        if let cuisine = selectedCuisine {
            recipes = recipes.filter { $0.cuisine == cuisine }
        }
        
        return recipes
    }
    
    private var availableCuisines: [String] {
        let cuisines = Set(allRecipes.compactMap { $0.cuisine })
        return cuisines.sorted()
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredRecipes.isEmpty {
                    emptyStateView
                } else {
                    recipeList
                }
            }
            .navigationTitle("Choose Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if !availableCuisines.isEmpty {
                        cuisineFilterMenu
                    }
                }
            }
        }
    }
    
    // MARK: - Recipe List
    
    @ViewBuilder
    private var recipeList: some View {
        List {
            ForEach(filteredRecipes) { recipe in
                Button {
                    onSelect(recipe)
                } label: {
                    RecipeRow(recipe: recipe)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Recipes Found", systemImage: "magnifyingglass")
        } description: {
            if searchText.isEmpty {
                Text("You don't have any recipes yet")
            } else {
                Text("Try a different search term")
            }
        }
    }
    
    // MARK: - Cuisine Filter Menu
    
    @ViewBuilder
    private var cuisineFilterMenu: some View {
        Menu {
            Button {
                selectedCuisine = nil
            } label: {
                Label("All Cuisines", systemImage: selectedCuisine == nil ? "checkmark" : "")
            }
            
            Divider()
            
            ForEach(availableCuisines, id: \.self) { cuisine in
                Button {
                    selectedCuisine = cuisine
                } label: {
                    Label(cuisine, systemImage: selectedCuisine == cuisine ? "checkmark" : "")
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

// MARK: - Recipe Row

struct RecipeRow: View {
    let recipe: RecipeX
    
    var body: some View {
        HStack(spacing: 12) {
            // Recipe thumbnail or placeholder
            if let imageData = recipe.imageData,
               let uiImage = PlatformImage(data: imageData) {
                Image(platformImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appGray5)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title ?? "Untitled Recipe")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                if let cuisine = recipe.cuisine {
                    Text(cuisine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let servings = recipe.servings, servings > 0 {
                    Text("\(servings) servings")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    RecipePickerSheet(
        currentRecipeID: nil,
        onSelect: { _ in }
    )
    .modelContainer(for: RecipeX.self, inMemory: true)
}
