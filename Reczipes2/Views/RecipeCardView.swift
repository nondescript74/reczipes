//
//  RecipeCardView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI

struct RecipeCardView: View {
    let recipe: RecipeX
    let isSaved: Bool
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title ?? "No title")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let headerNotes = recipe.headerNotes {
                        Text(headerNotes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    
                    if let yield = recipe.yield {
                        Label(yield, systemImage: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: onSave) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isSaved ? .green : .blue)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
            }
            
            Divider()
            
            // Ingredients Preview
            VStack(alignment: .leading, spacing: 8) {
                Label("Ingredients", systemImage: "list.bullet")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                ForEach(recipe.ingredientSections.prefix(1)) { section in
                    if let title = section.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(section.ingredients.prefix(3)) { ingredient in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                if let quantity = ingredient.quantity, !quantity.isEmpty {
                                    Text(quantity)
                                }
                                if let unit = ingredient.unit, !unit.isEmpty {
                                    Text(unit)
                                }
                                Text(ingredient.name)
                            }
                            .font(.subheadline)
                            if let prep = ingredient.preparation {
                                Text("(\(prep))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    if section.ingredients.count > 3 {
                        Text("+ \(section.ingredients.count - 3) more ingredients")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if recipe.ingredientSections.count > 1 {
                    Text("+ \(recipe.ingredientSections.count - 1) more section(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Instructions Preview
            VStack(alignment: .leading, spacing: 8) {
                Label("Instructions", systemImage: "list.number")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                ForEach(recipe.instructionSections.prefix(1)) { section in
                    if let title = section.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(section.steps.prefix(2)) { step in
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(step.stepNumber).")
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Text(step.text)
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                    }
                    
                    if section.steps.count > 2 {
                        Text("+ \(section.steps.count - 2) more steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if recipe.instructionSections.count > 1 {
                    Text("+ \(recipe.instructionSections.count - 1) more section(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Notes Preview
            if !recipe.notes.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipe.notes.prefix(2)) { note in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: iconForNoteType(note.type))
                                .font(.caption)
                                .foregroundStyle(colorForNoteType(note.type))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.type.rawValue.capitalized)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(colorForNoteType(note.type))
                                
                                Text(note.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            
            // Reference
            if let reference = recipe.reference {
                Text(reference)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding()
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private func iconForNoteType(_ type: RecipeNoteType) -> String {
        switch type {
        case .tip: return "lightbulb.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .warning: return "exclamationmark.triangle.fill"
        case .timing: return "clock.fill"
        case .general: return "info.circle.fill"
        }
    }
    
    private func colorForNoteType(_ type: RecipeNoteType) -> Color {
        switch type {
        case .tip: return .blue
        case .substitution: return .orange
        case .warning: return .red
        case .timing: return .purple
        case .general: return .gray
        }
    }
}

#Preview {
    let ingredientSections = [
        IngredientSection(
            ingredients: [
                Ingredient(quantity: "¾", unit: "cup", name: "plain yogurt", metricQuantity: "175", metricUnit: "mL"),
                Ingredient(quantity: "1", unit: "cup", name: "water", metricQuantity: "250", metricUnit: "mL"),
                Ingredient(quantity: "⅛", unit: "tsp.", name: "salt", metricQuantity: "0.5", metricUnit: "mL"),
                Ingredient(quantity: "⅛", unit: "tsp.", name: "ground black pepper", metricQuantity: "0.5", metricUnit: "mL"),
                Ingredient(quantity: "⅛", unit: "tsp.", name: "cumin powder", metricQuantity: "0.5", metricUnit: "mL"),
                Ingredient(name: "ice cubes")
            ]
        )
    ]
    
    let instructionSections = [
        InstructionSection(
            steps: [
                InstructionStep(stepNumber: 1, text: "Combine all ingredients in the blender and blend until smooth."),
                InstructionStep(stepNumber: 2, text: "Serve cold. Sugar can be added instead of salt and pepper, if preferred.")
            ]
        )
    ]
    
    let notes = [
        RecipeNote(type: .tip, text: "Very refreshing on a hot day!")
    ]
    
    let recipe = RecipeX(
        title: "Lassi",
        headerNotes: "Yogurt Sherbet - Very refreshing and cooling.",
        recipeYield: "Serves 1 to 2",
        reference: "Traditional Indian drink",
        ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
        instructionSectionsData: try? JSONEncoder().encode(instructionSections),
        notesData: try? JSONEncoder().encode(notes)
    )
    
    return RecipeCardView(
        recipe: recipe,
        isSaved: false,
        onSave: {}
    )
    .padding()
}
