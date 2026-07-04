//
//  RecipeSearchView.swift
//  Reczipes2
//
//  Created for comprehensive recipe searching
//

import SwiftUI
import SwiftData
import Combine

struct RecipeSearchView: View {
    @Binding var recipes: [RecipeX]
    @Binding var selectedRecipe: RecipeX?
    
    @Environment(\.modelContext) private var modelContext
    @Query private var recipeXEntities: [RecipeX]
    
    @State private var searchService = RecipeSearchService()
    @State private var searchText = ""
    @State private var authorFilter = ""
    @State private var selectedDishTypes: Set<RecipeSearchService.DishType> = []
    @State private var maxCookingTime: Double? = nil
    @State private var showingFilters = false
    @State private var useCookingTimeFilter = false
    
    private var searchResults: [RecipeX] {
        let criteria = RecipeSearchService.SearchCriteria(
            searchText: searchText,
            dishTypes: selectedDishTypes,
            maxCookingTime: useCookingTimeFilter ? Int(maxCookingTime ?? 120) : nil,
            author: authorFilter.isEmpty ? nil : authorFilter
        )
        
        return searchService.searchRecipes(recipes: recipes, criteria: criteria)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
            
            // Active filters display
            if hasActiveFilters {
                activeFiltersBar
            }
            
            // Results list
            List(searchResults) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    recipeRow(recipe: recipe)
                }
            }
            .listStyle(.plain)
            .overlay {
                if searchResults.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Found",
                        systemImage: "magnifyingglass",
                        description: Text("Try adjusting your search criteria")
                    )
                }
            }
        }
        .navigationTitle("Search Recipes")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFilters) {
            filterSheet
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search recipes...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.appGray6)
                .cornerRadius(10)
                
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(hasActiveFilters ? .blue : .secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
        }
    }
    
    // MARK: - Active Filters Bar
    
    private var hasActiveFilters: Bool {
        !authorFilter.isEmpty || !selectedDishTypes.isEmpty || useCookingTimeFilter
    }
    
    private var activeFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !authorFilter.isEmpty {
                    filterChip(text: "Author: \(authorFilter)") {
                        authorFilter = ""
                    }
                }
                
                ForEach(Array(selectedDishTypes), id: \.self) { dishType in
                    filterChip(text: dishType.displayName) {
                        selectedDishTypes.remove(dishType)
                    }
                }
                
                if useCookingTimeFilter, let time = maxCookingTime {
                    filterChip(text: "≤ \(Int(time)) min") {
                        useCookingTimeFilter = false
                    }
                }
                
                Button {
                    clearAllFilters()
                } label: {
                    Text("Clear All")
                        .font(.caption)
                        .foregroundStyle(Color.appCritical)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.appGray6)
    }
    
    private func filterChip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .foregroundStyle(Color.appInfo)
        .cornerRadius(16)
    }
    
    private func clearAllFilters() {
        authorFilter = ""
        selectedDishTypes.removeAll()
        useCookingTimeFilter = false
    }
    
    // MARK: - Recipe Row
    
    private func recipeRow(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Thumbnail
                if let imageData = recipe.imageData, let uiImage = PlatformImage(data: imageData) {
                    Image(platformImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let imageName = recipe.imageName {
                    RecipeImageView(
                        imageName: imageName,
                        size: CGSize(width: 60, height: 60),
                        cornerRadius: 8
                    )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.safeTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    if let headerNotes = recipe.headerNotes {
                        Text(headerNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Metadata row
                    HStack(spacing: 12) {
                        if let reference = recipe.reference {
                            Label(reference, systemImage: "person.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        if let cookingTime = searchService.getCookingTimeString(for: recipe) {
                            Label(cookingTime, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Dish type tags
            let dishTypes = searchService.detectAllDishTypes(for: recipe)
            if !dishTypes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(dishTypes.prefix(3)) { dishType in
                            Text(dishType.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(Color.appInfo)
                                .cornerRadius(6)
                        }
                        
                        if dishTypes.count > 3 {
                            Text("+\(dishTypes.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Methods
    
    // No longer needed - recipes are already RecipeX entities in SwiftData
    // If you need to save a recipe, it's already in the database
    
    // MARK: - Filter Sheet
    
    private var filterSheet: some View {
        NavigationStack {
            Form {
                // Author filter
                Section {
                    TextField("Filter by author...", text: $authorFilter)
                } header: {
                    Label("Author", systemImage: "person.fill")
                } footer: {
                    Text("Search recipes by author or source (e.g., name in reference field)")
                }
                
                // Dish type filter
                Section {
                    ForEach(RecipeSearchService.DishType.allCases) { dishType in
                        Toggle(isOn: Binding(
                            get: { selectedDishTypes.contains(dishType) },
                            set: { isSelected in
                                if isSelected {
                                    selectedDishTypes.insert(dishType)
                                } else {
                                    selectedDishTypes.remove(dishType)
                                }
                            }
                        )) {
                            Text(dishType.displayName)
                        }
                    }
                } header: {
                    Label("Dish Type", systemImage: "fork.knife")
                } footer: {
                    Text("Select one or more dish types to filter recipes")
                }
                
                // Cooking time filter
                Section {
                    Toggle("Enable cooking time filter", isOn: $useCookingTimeFilter)
                    
                    if useCookingTimeFilter {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum: \(Int(maxCookingTime ?? 120)) minutes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Slider(value: Binding(
                                get: { maxCookingTime ?? 120 },
                                set: { maxCookingTime = $0 }
                            ), in: 5...240, step: 5)
                        }
                    }
                } header: {
                    Label("Cooking Time", systemImage: "clock")
                } footer: {
                    Text("Find recipes that can be prepared within a specific time")
                }
                
                // Quick actions
                Section {
                    Button(role: .destructive) {
                        clearAllFilters()
                    } label: {
                        Label("Clear All Filters", systemImage: "trash")
                    }
                    .disabled(!hasActiveFilters)
                }
            }
            .navigationTitle("Filter Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingFilters = false
                    }
                }
            }
        }
    }
}

// MARK: - Standalone Search View

/// A full-screen search view that can be presented modally
struct RecipeSearchModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var recipes: [any RecipeDisplayProtocol]
    @Binding var selectedRecipe: (any RecipeDisplayProtocol)?
    
    // Extract RecipeX objects for the search view (which only works with RecipeX)
    private var recipeXObjects: [RecipeX] {
        recipes.compactMap { $0 as? RecipeX }
    }
    
    // Binding adapter to convert between protocols
    private var recipeXSelection: Binding<RecipeX?> {
        Binding(
            get: { selectedRecipe as? RecipeX },
            set: { selectedRecipe = $0 }
        )
    }
    
    var body: some View {
        NavigationStack {
            RecipeSearchView(recipes: .constant(recipeXObjects), selectedRecipe: recipeXSelection)
                .toolbar {
                    ToolbarItem(placement: .platformNavBarTrailing) {
                        CloudKitSyncBadge()
                    }
                    
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RecipeX.self, configurations: config)
    let context = ModelContext(container)
    
    // Create a sample recipe
    let sampleRecipe = RecipeX(
        title: "Classic Tomato Soup",
        headerNotes: "A warm and comforting soup perfect for cold days",
        recipeYield: "4 servings",
        reference: "Julia Child"
    )
    
    // Encode sample data
    let encoder = JSONEncoder()
    if let ingredientsData = try? encoder.encode([
        IngredientSection(ingredients: [
            Ingredient(quantity: "2", unit: "lbs", name: "tomatoes"),
            Ingredient(quantity: "1", unit: "cup", name: "cream")
        ])
    ]) {
        sampleRecipe.ingredientSectionsData = ingredientsData
    }
    
    if let instructionsData = try? encoder.encode([
        InstructionSection(steps: [
            InstructionStep(stepNumber: 1, text: "Cook for 30 minutes")
        ])
    ]) {
        sampleRecipe.instructionSectionsData = instructionsData
    }
    
    context.insert(sampleRecipe)
    
    return NavigationStack {
        RecipeSearchView(
            recipes: .constant([sampleRecipe]),
            selectedRecipe: .constant(nil)
        )
    }
    .modelContainer(container)
}
