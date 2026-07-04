//
//  RecipePanel.swift
//  reczipes2-imageextract
//
//  Individual recipe display panel for cooking mode
//

import SwiftUI
import SwiftData

struct RecipePanel: View {
    let recipe: RecipeX?
    let slot: Int
    let viewModel: CookingViewModel
    
    @State private var showRecipePicker = false
    
    var body: some View {
        Group {
            if let recipe = recipe {
                RecipeDetailView(recipe: recipe)
                    .overlay(alignment: .topTrailing) {
                        recipeControls
                    }
            } else {
                EmptyRecipeSlot {
                    showRecipePicker = true
                }
            }
        }
        .onChange(of: recipe?.id) { oldValue, newValue in
            // When a recipe is selected, ensure the picker is dismissed
            if oldValue != newValue && newValue != nil {
                showRecipePicker = false
            }
        }
        .sheet(isPresented: $showRecipePicker) {
            RecipePickerSheet(
                currentRecipeID: recipe?.id,
                onSelect: { selected in
                    viewModel.selectRecipe(selected, slot: slot)
                }
            )
        }
    }
    
    // MARK: - Recipe Controls
    
    @ViewBuilder
    private var recipeControls: some View {
        HStack(spacing: 12) {
            Button {
                showRecipePicker = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
            }
            
            Button(role: .destructive) {
                viewModel.clearRecipe(slot: slot)
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding()
    }
}

// MARK: - Empty Recipe Slot

struct EmptyRecipeSlot: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 20) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.appInfo)
                
                VStack(spacing: 8) {
                    Text("Select a Recipe")
                        .font(.title2.weight(.medium))
                    
                    Text("Tap to choose from your recipes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appGroupedBackground)
        }
        .buttonStyle(.plain)
    }
}

#Preview("With Recipe") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RecipeX.self, configurations: config)
    let context = ModelContext(container)
    
    // Create a sample RecipeX for preview
    let sampleRecipe = RecipeX(
        title: "Sample Recipe",
        ingredientSectionsData: Data("[]".utf8),
        instructionSectionsData: Data("[]".utf8)
    )
    context.insert(sampleRecipe)
    
    return RecipePanel(
        recipe: sampleRecipe,
        slot: 0,
        viewModel: CookingViewModel(modelContext: context)
    )
    .modelContainer(container)
}

#Preview("Empty Slot") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RecipeX.self, configurations: config)
    let context = ModelContext(container)
    
    return RecipePanel(
        recipe: nil,
        slot: 0,
        viewModel: CookingViewModel(modelContext: context)
    )
    .modelContainer(container)
}
