//
//  CookingModeView.swift
//  Reczipes2
//
//  Dedicated cooking mode view for step-by-step recipe following
//

import SwiftUI

struct CookingModeView: View {
    let recipe: RecipeX
    
    @State private var completedSteps: Set<Int> = []
    @State private var servingMultiplier: Double = 1.0
    @Environment(\.dismiss) private var dismiss
    
    init(recipe: RecipeX) {
        self.recipe = recipe
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Recipe Header
                recipeHeader
                
                // Serving Controls
                servingControls
                
                // Ingredients Section
                if !recipe.ingredientSections.isEmpty {
                    ingredientsSection
                }
                
                // Instructions Section
                if !recipe.instructionSections.isEmpty {
                    instructionsSection
                }
                
                // Notes Section
                if !recipe.notes.isEmpty {
                    notesSection
                }
            }
            .padding()
        }
        .background(Color.appSystemBackground)
        .navigationTitle("Cooking Mode")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Recipe Header
    
    @ViewBuilder
    private var recipeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.safeTitle)
                .font(.largeTitle.bold())
            
            HStack(spacing: 16) {
                if let cuisine = recipe.cuisine {
                    Label(cuisine, systemImage: "flag.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let servings = recipe.servings, servings > 0 {
                    Label("\(servings) servings", systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let prepTime = formatTime(minutes: recipe.prepTimeMinutes) {
                    Label(prepTime, systemImage: "clock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Serving Controls
    
    @ViewBuilder
    private var servingControls: some View {
        if let servings = recipe.servings, servings > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Adjust Servings")
                    .font(.headline)
                
                HStack {
                    Button {
                        if servingMultiplier > 0.5 {
                            servingMultiplier -= 0.5
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                    }
                    .disabled(servingMultiplier <= 0.5)
                    
                    Spacer()
                    
                    VStack(spacing: 4) {
                        Text("\(Int(Double(servings) * servingMultiplier))")
                            .font(.title.bold())
                        Text("servings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        servingMultiplier += 0.5
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
                .padding()
                .background(Color.appGray6)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // MARK: - Ingredients Section
    
    @ViewBuilder
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(recipe.ingredientSections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if let title = section.title {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(Color.appInfo)
                        }
                        
                        ForEach(section.ingredients) { ingredient in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                
                                Text(scaledIngredient(ingredient))
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.appGray6)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Instructions Section
    
    @ViewBuilder
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(recipe.instructionSections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = section.title {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(Color.appSuccess)
                                .padding(.top, 8)
                        }
                        
                        ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                            instructionRow(globalIndex: calculateGlobalIndex(section: section, localIndex: index), step: step)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func instructionRow(globalIndex: Int, step: InstructionStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggleStepCompletion(globalIndex)
            } label: {
                Image(systemName: completedSteps.contains(globalIndex) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(completedSteps.contains(globalIndex) ? .green : .secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if step.stepNumber > 0 {
                    Text("Step \(step.stepNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                
                Text(step.text)
                    .font(.body)
                    .strikethrough(completedSteps.contains(globalIndex))
                    .foregroundStyle(completedSteps.contains(globalIndex) ? .secondary : .primary)
            }
        }
        .padding()
        .background(
            completedSteps.contains(globalIndex) ? Color.appGray6 : Color.appGray5
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Notes Section
    
    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)
            
            ForEach(Array(recipe.notes.enumerated()), id: \.offset) { index, note in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconForNoteType(note.type))
                        .font(.title3)
                        .foregroundStyle(colorForNoteType(note.type))
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.type.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(colorForNoteType(note.type))
                        
                        Text(note.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(12)
                .background(colorForNoteType(note.type).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Helper Methods
    
    private func calculateGlobalIndex(section: InstructionSection, localIndex: Int) -> Int {
        // Calculate the global step index across all sections
        var globalIndex = 0
        for instructionSection in recipe.instructionSections {
            if instructionSection.id == section.id {
                return globalIndex + localIndex
            }
            globalIndex += instructionSection.steps.count
        }
        return globalIndex + localIndex
    }
    
    private func toggleStepCompletion(_ index: Int) {
        if completedSteps.contains(index) {
            completedSteps.remove(index)
        } else {
            completedSteps.insert(index)
        }
    }
    
    private func scaledIngredient(_ ingredient: Ingredient) -> String {
        // Format ingredient with scaling
        var parts: [String] = []
        
        // Scale quantity if multiplier is not 1.0
        if let quantity = ingredient.quantity, !quantity.isEmpty {
            if servingMultiplier != 1.0, let numericQuantity = parseQuantity(quantity) {
                let scaled = numericQuantity * servingMultiplier
                let formatted = formatQuantity(scaled)
                parts.append(formatted)
            } else {
                parts.append(quantity)
            }
        }
        
        // Add unit
        if let unit = ingredient.unit, !unit.isEmpty {
            parts.append(unit)
        }
        
        // Add name
        parts.append(ingredient.name)
        
        // Add preparation if present
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            parts.append("(\(preparation))")
        }
        
        return parts.joined(separator: " ")
    }
    
    private func parseQuantity(_ quantity: String) -> Double? {
        // Handle fractions like "1/2", "1 1/2", etc.
        let trimmed = quantity.trimmingCharacters(in: .whitespaces)
        
        // Try simple double first
        if let value = Double(trimmed) {
            return value
        }
        
        // Handle fractions
        let components = trimmed.components(separatedBy: .whitespaces)
        var total = 0.0
        
        for component in components {
            if component.contains("/") {
                let parts = component.split(separator: "/")
                if parts.count == 2,
                   let numerator = Double(parts[0]),
                   let denominator = Double(parts[1]),
                   denominator != 0 {
                    total += numerator / denominator
                }
            } else if let value = Double(component) {
                total += value
            }
        }
        
        return total > 0 ? total : nil
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "")
        }
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
    
    private func formatTime(minutes: Int?) -> String? {
        guard let minutes = minutes, minutes > 0 else { return nil }
        
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            } else {
                return "\(hours) hr \(remainingMinutes) min"
            }
        }
    }
}

#Preview {
    NavigationStack {
        CookingModeView(recipe: RecipeX.preview)
    }
}
