//
//  RecipeShareCardView.swift
//  Reczipes2
//
//  Created for recipe sharing card display
//

import SwiftUI

/// A beautifully styled card view for sharing recipes via email, text, or other methods
struct RecipeShareCardView: View {
    let recipe: RecipeX
    let sourceType: RecipeSourceType
    
    enum RecipeSourceType {
        case email
        case text
        case app
        
        var color: Color {
            switch self {
            case .email: return .blue
            case .text: return .green
            case .app: return .purple
            }
        }
        
        var icon: String {
            switch self {
            case .email: return "envelope.fill"
            case .text: return "message.fill"
            case .app: return "square.and.arrow.up.fill"
            }
        }
        
        var label: String {
            switch self {
            case .email: return "Shared via Email"
            case .text: return "Shared via Text"
            case .app: return "Shared from Reczipes"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with gradient
            VStack(spacing: 12) {
                // Source badge
                HStack(spacing: 6) {
                    Image(systemName: sourceType.icon)
                        .font(.caption)
                    Text(sourceType.label)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.25))
                .clipShape(Capsule())
                
                // Title
                Text(recipe.title ?? "No Name")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.onTint)
                
                // Header notes
                if let headerNotes = recipe.headerNotes {
                    Text(headerNotes)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.onTint.opacity(0.9))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [sourceType.color, sourceType.color.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Stats bar
            HStack(spacing: 0) {
                StatView(
                    value: "\(ingredientCount)",
                    label: "Ingredients"
                )
                
                Divider()
                    .frame(height: 40)
                
                StatView(
                    value: "\(stepCount)",
                    label: "Steps"
                )
                
                if !recipe.notes.isEmpty {
                    Divider()
                        .frame(height: 40)
                    
                    StatView(
                        value: "\(recipe.notes.count)",
                        label: "Notes"
                    )
                }
            }
            .padding(.vertical, 16)
            .background(Color.appGray6)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Yield
                    if let yield = recipe.yield {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .foregroundStyle(sourceType.color)
                            Text(yield)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(sourceType.color.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    // Ingredients
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeaderView(title: "Ingredients", icon: "list.bullet")
                        
                        ForEach(recipe.ingredientSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.headline)
                                        .foregroundStyle(sourceType.color)
                                }
                                
                                ForEach(section.ingredients) { ingredient in
                                    IngredientRowView(ingredient: ingredient)
                                }
                                
                                if let transitionNote = section.transitionNote {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Color.appWarning)
                                            .font(.caption)
                                        Text(transitionNote)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeaderView(title: "Instructions", icon: "list.number")
                        
                        ForEach(recipe.instructionSections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                if let title = section.title {
                                    Text(title)
                                        .font(.headline)
                                        .foregroundStyle(sourceType.color)
                                }
                                
                                ForEach(section.steps) { step in
                                    InstructionStepView(step: step, color: sourceType.color)
                                }
                            }
                        }
                    }
                    
                    // Notes
                    if !recipe.notes.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeaderView(title: "Notes", icon: "lightbulb.fill")
                            
                            ForEach(recipe.notes) { note in
                                NoteCardView(note: note)
                            }
                        }
                    }
                    
                    // Reference
                    if let reference = recipe.reference {
                        Divider()
                        
                        HStack(spacing: 8) {
                            Image(systemName: "book.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Reference: \(reference)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                    }
                }
                .padding(20)
            }
            
            // Footer
            VStack(spacing: 4) {
                Text("🍽️ Reczipes")
                    .font(.headline)
                Text("Your Personal Recipe Collection")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.appGray6)
        }
        .background(Color.appSystemBackground)
    }
    
    // MARK: - Computed Properties
    
    private var ingredientCount: Int {
        recipe.ingredientSections.reduce(0) { $0 + $1.ingredients.count }
    }
    
    private var stepCount: Int {
        recipe.instructionSections.reduce(0) { $0 + $1.steps.count }
    }
}

// MARK: - Supporting Views

private struct StatView: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SectionHeaderView: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

private struct IngredientRowView: View {
    let ingredient: Ingredient
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                if let quantity = ingredient.quantity, !quantity.isEmpty {
                    Text(quantity)
                        .fontWeight(.semibold)
                }
                if let unit = ingredient.unit, !unit.isEmpty {
                    Text(unit)
                }
                Text(ingredient.name)
                if let prep = ingredient.preparation {
                    Text("(\(prep))")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

private struct InstructionStepView: View {
    let step: InstructionStep
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if step.stepNumber > 0 {
                ZStack {
                    Circle()
                        .fill(color)
                        .frame(width: 32, height: 32)
                    Text("\(step.stepNumber)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.onTint)
                }
            } else {
                Text("•")
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
            
            Text(step.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct NoteCardView: View {
    let note: RecipeNote
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconForNoteType)
                .foregroundStyle(colorForNoteType)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(note.type.rawValue.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(colorForNoteType)
                
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorForNoteType.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var iconForNoteType: String {
        switch note.type {
        case .tip: return "lightbulb.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .warning: return "exclamationmark.triangle.fill"
        case .timing: return "clock.fill"
        case .general: return "info.circle.fill"
        }
    }
    
    private var colorForNoteType: Color {
        switch note.type {
        case .tip: return .blue
        case .substitution: return .orange
        case .warning: return .red
        case .timing: return .purple
        case .general: return .gray
        }
    }
}

// MARK: - Preview

#Preview("Email Share") {
    let ingredientSections = [
        IngredientSection(
            title: "Dry Ingredients",
            ingredients: [
                Ingredient(quantity: "2¼", unit: "cups", name: "all-purpose flour"),
                Ingredient(quantity: "1", unit: "tsp", name: "baking soda"),
                Ingredient(quantity: "1", unit: "tsp", name: "salt")
            ]
        ),
        IngredientSection(
            title: "Wet Ingredients",
            ingredients: [
                Ingredient(quantity: "1", unit: "cup", name: "butter", preparation: "softened"),
                Ingredient(quantity: "¾", unit: "cup", name: "granulated sugar"),
                Ingredient(quantity: "¾", unit: "cup", name: "brown sugar", preparation: "packed"),
                Ingredient(quantity: "2", unit: "", name: "large eggs"),
                Ingredient(quantity: "2", unit: "tsp", name: "vanilla extract")
            ]
        ),
        IngredientSection(
            ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "chocolate chips")
            ]
        )
    ]
    
    let instructionSections = [
        InstructionSection(
            steps: [
                InstructionStep(stepNumber: 1, text: "Preheat oven to 375°F (190°C)."),
                InstructionStep(stepNumber: 2, text: "In a medium bowl, whisk together flour, baking soda, and salt. Set aside."),
                InstructionStep(stepNumber: 3, text: "In a large bowl, beat butter and both sugars until creamy, about 2-3 minutes."),
                InstructionStep(stepNumber: 4, text: "Add eggs one at a time, beating well after each addition. Stir in vanilla."),
                InstructionStep(stepNumber: 5, text: "Gradually blend in the flour mixture. Fold in chocolate chips."),
                InstructionStep(stepNumber: 6, text: "Drop rounded tablespoons of dough onto ungreased cookie sheets, spacing them 2 inches apart."),
                InstructionStep(stepNumber: 7, text: "Bake for 9-11 minutes or until golden brown. Cool on baking sheet for 2 minutes before transferring to a wire rack.")
            ]
        )
    ]
    
    let notes = [
        RecipeNote(type: .tip, text: "For chewier cookies, slightly underbake them and let them finish cooking on the hot pan."),
        RecipeNote(type: .timing, text: "Cookies can be stored in an airtight container for up to 5 days."),
        RecipeNote(type: .substitution, text: "You can use dark chocolate chips or a mix of chocolate chips and nuts.")
    ]
    
    return RecipeShareCardView(
        recipe: RecipeX(
            title: "Classic Chocolate Chip Cookies",
            headerNotes: "The perfect chewy cookie with crispy edges",
            recipeYield: "Makes 24 cookies",
            reference: "Adapted from the classic Toll House recipe",
            ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
            instructionSectionsData: try? JSONEncoder().encode(instructionSections),
            notesData: try? JSONEncoder().encode(notes)
        ),
        sourceType: .email
    )
    .frame(width: 390, height: 844)
}

#Preview("Text Share") {
    let ingredientSections = [
        IngredientSection(
            ingredients: [
                Ingredient(quantity: "¾", unit: "cup", name: "plain yogurt"),
                Ingredient(quantity: "1", unit: "cup", name: "water"),
                Ingredient(quantity: "⅛", unit: "tsp", name: "salt"),
                Ingredient(quantity: "⅛", unit: "tsp", name: "ground black pepper"),
                Ingredient(quantity: "⅛", unit: "tsp", name: "cumin powder"),
                Ingredient(quantity: "", unit: "", name: "ice cubes")
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
    
    return RecipeShareCardView(
        recipe: RecipeX(
            title: "Lassi",
            headerNotes: "Yogurt Sherbet - Very refreshing and cooling.",
            recipeYield: "Serves 1 to 2",
            reference: "Traditional Indian drink",
            ingredientSectionsData: try? JSONEncoder().encode(ingredientSections),
            instructionSectionsData: try? JSONEncoder().encode(instructionSections),
            notesData: try? JSONEncoder().encode(notes)
        ),
        sourceType: .text
    )
    .frame(width: 390, height: 844)
}
