//
//  ReadOnlyRecipeDetailView.swift
//  Reczipes2
//
//  Created on 1/25/26.
//

import SwiftUI
import SwiftData
import SafariServices

/// Read-only view for displaying shared recipes
/// Shows full recipe details without edit/save functionality
/// Includes cooking mode, shopping list, and optional import
struct ReadOnlyRecipeDetailView: View {
    let recipe: CloudKitRecipe
    let preview: CloudKitRecipePreview
    
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingCookingMode = false
    @State private var showingImportSheet = false
    @State private var currentServings: Double = 1.0
    @State private var showingSafariView = false
    @State private var safariURL: URL?
    @State private var importSuccess = false
    @State private var importError: Error?
    @State private var showingImportAlert = false
    
    private var scaledRecipe: CloudKitRecipe {
        // Scale ingredients based on servings multiplier
        let multiplier = currentServings / parseYield(recipe.yield ?? "1")
        
        // Scale ingredient sections
        let scaledSections = recipe.ingredientSections.map { section in
            let scaledIngredients = section.ingredients.map { ingredient in
                // Parse quantity string and scale it
                if let quantity = ingredient.quantity,
                   let numericValue = Double(quantity.trimmingCharacters(in: .whitespaces)) {
                    let scaledValue = numericValue * multiplier
                    let scaledQuantity = String(format: "%.1f", scaledValue)
                    
                    // Create new ingredient with scaled quantity
                    return Ingredient(
                        id: ingredient.id,
                        quantity: scaledQuantity,
                        unit: ingredient.unit,
                        name: ingredient.name,
                        preparation: ingredient.preparation,
                        metricQuantity: ingredient.metricQuantity,
                        metricUnit: ingredient.metricUnit
                    )
                }
                return ingredient
            }
            
            // Create new section with scaled ingredients
            return IngredientSection(
                id: section.id,
                title: section.title,
                ingredients: scaledIngredients,
                transitionNote: section.transitionNote
            )
        }
        
        // Create new CloudKitRecipe with scaled ingredients
        return CloudKitRecipe(
            id: recipe.id,
            title: recipe.title,
            headerNotes: recipe.headerNotes,
            yield: recipe.yield,
            ingredientSections: scaledSections,
            instructionSections: recipe.instructionSections,
            notes: recipe.notes,
            reference: recipe.reference,
            imageName: recipe.imageName,
            additionalImageNames: recipe.additionalImageNames,
            sharedByUserID: recipe.sharedByUserID,
            sharedByUserName: recipe.sharedByUserName,
            sharedDate: recipe.sharedDate
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Recipe header with image
                recipeHeaderView
                
                // Shared by info
                sharedByView
                
                // Yield scaler
                yieldScalerView
                
                Divider()
                
                // Ingredients
                ingredientsView
                
                Divider()
                
                // Instructions
                instructionsView
                
                // Notes
                if !(recipe.notes.isEmpty) {
                    Divider()
                    notesView
                }
                
                // Reference
                if let reference = recipe.reference, !reference.isEmpty {
                    Divider()
                    referenceView(reference)
                }
            }
            .padding()
        }
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingCookingMode = true
                    } label: {
                        Label("Start Cooking", systemImage: "flame")
                    }
                    
                    Button {
                        addToShoppingList()
                    } label: {
                        Label("Add to Shopping List", systemImage: "cart")
                    }
                    
                    Divider()
                    
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("Import to My Recipes", systemImage: "square.and.arrow.down")
                    }
                    
                    if let reference = recipe.reference, !reference.isEmpty,
                       let url = URL(string: reference) {
                        Button {
                            safariURL = url
                            showingSafariView = true
                        } label: {
                            Label("View Source", systemImage: "link")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCookingMode) {
            CookingModeView(recipe: toRecipeX(scaledRecipe))
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportSharedRecipeView(
                recipe: recipe,
                onImport: { importedRecipe in
                    handleImport(importedRecipe)
                }
            )
        }
        .sheet(isPresented: $showingSafariView) {
            if let url = safariURL {
                SafariView(url: url, entersReaderIfAvailable: true)
            }
        }
        .alert("Recipe Imported", isPresented: $showingImportAlert) {
            if importSuccess {
                Button("OK") {
                    dismiss()
                }
            } else {
                Button("OK") {}
            }
        } message: {
            if importSuccess {
                Text("'\(recipe.title)' has been added to your recipes.")
            } else if let error = importError {
                Text("Failed to import: \(error.localizedDescription)")
            }
        }
        .onAppear {
            // Set initial servings from recipe yield
            currentServings = parseYield(recipe.yield ?? "1")
        }
    }
    
    // MARK: - Recipe Header
    
    private var recipeHeaderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image
            if let imageData = preview.imageData,
               let uiImage = PlatformImage(data: imageData) {
                Image(platformImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let imageName = recipe.imageName {
                AsyncImage(url: imageURL(for: imageName)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Title
            Text(recipe.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Header notes
            if let headerNotes = recipe.headerNotes, !headerNotes.isEmpty {
                Text(headerNotes)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Shared By Info
    
    private var sharedByView: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(Color.appInfo)
            
            Text("Shared by")
                .foregroundStyle(.secondary)
            
            Text(recipe.sharedByUserName ?? "Unknown")
                .fontWeight(.medium)
            
            Spacer()
            
            Text(recipe.sharedDate.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - Yield Scaler
    
    private var yieldScalerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servings")
                .font(.headline)
            
            HStack {
                Button {
                    if currentServings > 0.5 {
                        currentServings -= 0.5
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }
                .disabled(currentServings <= 0.5)
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("\(currentServings, specifier: "%.1f")")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let originalYield = recipe.yield {
                        Text("Original: \(originalYield)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    currentServings += 0.5
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
            .frame(maxWidth: 300)
        }
        .padding()
        .background(.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Ingredients
    
    private var ingredientsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Ingredients", systemImage: "list.bullet")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(scaledRecipe.ingredientSections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = section.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(section.ingredients) { ingredient in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                            
                            Text(formatIngredient(ingredient))
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper for formatting ingredients
    
    private func formatIngredient(_ ingredient: Ingredient) -> String {
        var parts: [String] = []
        
        if let quantity = ingredient.quantity, !quantity.isEmpty {
            parts.append(quantity)
        }
        
        if let unit = ingredient.unit, !unit.isEmpty {
            parts.append(unit)
        }
        
        parts.append(ingredient.name)
        
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            parts.append("(\(preparation))")
        }
        
        return parts.joined(separator: " ")
    }
    
    // MARK: - Instructions
    
    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Instructions", systemImage: "list.number")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(recipe.instructionSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if let title = section.title, !title.isEmpty {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(Color.onTint)
                                .frame(width: 28, height: 28)
                                .background(.blue)
                                .clipShape(Circle())
                            
                            Text(step.text)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Notes
    
    private var notesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(recipe.notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    // Note type as badge
                    HStack {
                        Text(note.type.rawValue.capitalized)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(colorForNoteType(note.type))
                            .foregroundStyle(Color.onTint)
                            .clipShape(Capsule())
                        
                        Spacer()
                    }
                    
                    Text(note.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
    
    // Helper to get color for note type
    private func colorForNoteType(_ type: RecipeNoteType) -> Color {
        switch type {
        case .tip:
            return .blue
        case .substitution:
            return .green
        case .warning:
            return .red
        case .timing:
            return .orange
        case .general:
            return .gray
        }
    }
    
    // MARK: - Reference
    
    private func referenceView(_ reference: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Source", systemImage: "link")
                .font(.headline)
            
            if let url = URL(string: reference) {
                Button {
                    safariURL = url
                    showingSafariView = true
                } label: {
                    HStack {
                        Text(reference)
                            .font(.caption)
                            .foregroundStyle(Color.appInfo)
                            .lineLimit(1)
                        
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
            } else {
                Text(reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Actions
    
    private func addToShoppingList() {
        // TODO: Implement shopping list integration
        print("[Sharing] Adding shared recipe to shopping list")
    }
    
    private func handleImport(_ importedRecipe: RecipeX) {
        importSuccess = true
        showingImportAlert = true
        print("[Sharing] Successfully imported shared recipe: '\(recipe.title)'")
    }
    
    // MARK: - Helpers
    
    private func parseYield(_ yieldString: String) -> Double {
        // Extract number from yield string (e.g., "4 servings" -> 4.0)
        let numbers = yieldString.components(separatedBy: CharacterSet.decimalDigits.inverted)
        if let firstNumber = numbers.first(where: { !$0.isEmpty }),
           let value = Double(firstNumber) {
            return value
        }
        return 1.0
    }
    
    private func imageURL(for filename: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
    }
    
    private func toRecipeX(_ cloudRecipe: CloudKitRecipe) -> RecipeX {
        
        // Properly encode the data
        let ingredientSectionsData = try? encoder.encode(cloudRecipe.ingredientSections)
        let instructionSectionsData = try? encoder.encode(cloudRecipe.instructionSections)
        let notesData = try? encoder.encode(cloudRecipe.notes)
        
        return RecipeX(
            id: cloudRecipe.id,
            title: cloudRecipe.title,
            headerNotes: cloudRecipe.headerNotes,
            recipeYield: cloudRecipe.yield,
            reference: cloudRecipe.reference,
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            notesData: notesData,
            imageName: cloudRecipe.imageName,
            additionalImageNames: cloudRecipe.additionalImageNames
        )
    }
}

// MARK: - Import Sheet

struct ImportSharedRecipeView: View {
    let recipe: CloudKitRecipe
    let onImport: (RecipeX) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var recipeTitle: String
    @State private var includeNotes = true
    @State private var isImporting = false
    
    init(recipe: CloudKitRecipe, onImport: @escaping (RecipeX) -> Void) {
        self.recipe = recipe
        self.onImport = onImport
        _recipeTitle = State(initialValue: recipe.title)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe Name") {
                    TextField("Title", text: $recipeTitle)
                }
                
                Section {
                    Toggle("Include Notes", isOn: $includeNotes)
                } footer: {
                    Text("Import the recipe's notes along with ingredients and instructions")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shared by \(recipe.sharedByUserName ?? "Unknown")", systemImage: "person.crop.circle")
                            .font(.caption)
                        
                        Label("\(recipe.ingredientSections.reduce(0) { $0 + $1.ingredients.count }) ingredients", systemImage: "list.bullet")
                            .font(.caption)
                        
                        Label("\(recipe.instructionSections.reduce(0) { $0 + $1.steps.count }) steps", systemImage: "list.number")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importRecipe()
                    }
                    .disabled(recipeTitle.isEmpty || isImporting)
                }
            }
        }
    }
    
    private func importRecipe() {
        isImporting = true
        
        // Encode the sections as Data
        let encoder = JSONEncoder()
        let ingredientSectionsData = try? encoder.encode(recipe.ingredientSections)
        let instructionSectionsData = try? encoder.encode(recipe.instructionSections)
        let notesData = includeNotes ? try? encoder.encode(recipe.notes) : nil
        
        // Create a new recipe with a new ID
        let recipea = RecipeX(
            id: UUID(), // New ID to avoid conflicts
            title: recipeTitle,
            headerNotes: recipe.headerNotes,
            recipeYield: recipe.yield,
            reference: recipe.reference,
            ingredientSectionsData: ingredientSectionsData,
            instructionSectionsData: instructionSectionsData,
            notesData: notesData,
            imageName: recipe.imageName,
            additionalImageNames: recipe.additionalImageNames
        )
        
        modelContext.insert(recipea)
        
        do {
            try modelContext.save()
            onImport(recipea)
            dismiss()
        } catch {
            print("[Sharing] Failed to import recipe: \(error)")
            isImporting = false
        }
    }
}


// MARK: - Preview

#Preview("Read-Only Recipe Detail") {
    let recipe = CloudKitRecipe(
        id: UUID(),
        title: "Classic Pasta Carbonara",
        headerNotes: "A traditional Italian pasta dish with eggs, cheese, and guanciale",
        yield: "4 servings",
        ingredientSections: [
            IngredientSection(
                title: "Pasta",
                ingredients: [
                    Ingredient(quantity: "400", unit: "g", name: "spaghetti")
                ]
            ),
            IngredientSection(
                title: "Sauce",
                ingredients: [
                    Ingredient(quantity: "4", unit: nil, name: "egg yolks"),
                    Ingredient(quantity: "100", unit: "g", name: "pecorino romano", preparation: "grated"),
                    Ingredient(quantity: "150", unit: "g", name: "guanciale", preparation: "diced")
                ]
            )
        ],
        instructionSections: [
            InstructionSection(
                title: nil,
                steps: [
                    InstructionStep(stepNumber: 1, text: "Bring a large pot of salted water to a boil and cook the spaghetti until al dente."),
                    InstructionStep(stepNumber: 2, text: "While pasta cooks, fry the guanciale in a pan until crispy."),
                    InstructionStep(stepNumber: 3, text: "Whisk egg yolks with grated pecorino in a bowl."),
                    InstructionStep(stepNumber: 4, text: "Drain pasta, reserving 1 cup of pasta water. Add hot pasta to the guanciale pan."),
                    InstructionStep(stepNumber: 5, text: "Remove from heat and quickly stir in the egg mixture, adding pasta water to create a creamy sauce.")
                ]
            )
        ],
        notes: [
            RecipeNote(type: .tip, text: "The key is to work quickly off the heat to prevent the eggs from scrambling.")
        ],
        reference: "https://example.com/carbonara",
        imageName: nil,
        additionalImageNames: nil,
        sharedByUserID: "user123",
        sharedByUserName: "Maria Rossi",
        sharedDate: Date()
    )
    
    let preview = CloudKitRecipePreview(
        id: recipe.id,
        title: recipe.title,
        headerNotes: recipe.headerNotes,
        imageName: nil,
        imageData: nil,
        sharedByUserID: recipe.sharedByUserID ?? "no user id",
        sharedByUserName: recipe.sharedByUserName,
        recipeYield: recipe.yield,
        bookID: UUID(),
        cloudRecordID: nil
    )
    
    NavigationStack {
        ReadOnlyRecipeDetailView(recipe: recipe, preview: preview)
    }
    .modelContainer(for: RecipeX.self)
}
