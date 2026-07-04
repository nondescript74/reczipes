//
//  FODMAPSubstitutionView.swift
//  Reczipes2
//
//  View for displaying FODMAP substitutions in recipe detail
//  Created on 12/20/25.
//

import SwiftUI

// MARK: - Main FODMAP Substitution Section

/// Display FODMAP substitutions inline with ingredients
struct FODMAPSubstitutionSection: View {
    let analysis: RecipeFODMAPSubstitutions
    @State private var expandedSubstitutions: Set<UUID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Label("FODMAP Substitutions", systemImage: "arrow.triangle.swap")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appWarning)
                
                Spacer()
                
                FODMAPLevelBadge(level: analysis.overallFODMAPScore)
            }
            
            // Info text
            if analysis.isSafeWithoutSubstitutions {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                    Text("This recipe is already low FODMAP!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Color.appWarning)
                    Text("\(analysis.totalHighFODMAPIngredients) ingredient\(analysis.totalHighFODMAPIngredients == 1 ? "" : "s") can be substituted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Substitution groups
            ForEach(analysis.substitutions) { group in
                IngredientSubstitutionCard(
                    group: group,
                    isExpanded: expandedSubstitutions.contains(group.id)
                ) {
                    toggleExpanded(group.id)
                }
            }
        }
    }
    
    private func toggleExpanded(_ id: UUID) {
        if expandedSubstitutions.contains(id) {
            expandedSubstitutions.remove(id)
        } else {
            expandedSubstitutions.insert(id)
        }
    }
}

// MARK: - Individual Substitution Card

struct IngredientSubstitutionCard: View {
    let group: IngredientSubstitutionGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - Original Ingredient
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // FODMAP warning icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appWarning)
                    
                    // Original ingredient info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let quantity = group.originalIngredient.quantity {
                                Text(quantity)
                                    .fontWeight(.semibold)
                            }
                            if let unit = group.originalIngredient.unit {
                                Text(unit)
                                    .fontWeight(.medium)
                            }
                            Text(group.originalIngredient.name)
                                .fontWeight(.bold)
                        }
                        .font(.body)
                        
                        // FODMAP categories
                        HStack(spacing: 6) {
                            ForEach(group.substitution.fodmapCategories, id: \.self) { category in
                                Text(category.icon)
                                    .font(.caption2)
                                Text(category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/collapse icon
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appInfo)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                
                // Explanation
                Text(group.substitution.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                
                // Portion note (if any)
                if let portionNote = group.substitution.portionNote {
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.caption)
                        Text(portionNote)
                            .font(.caption)
                            .italic()
                    }
                    .foregroundStyle(Color.appWarning)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                Divider()
                
                // Substitute options
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("Substitute with:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ForEach(group.substitution.substitutes) { substitute in
                        SubstituteOptionRow(substitute: substitute)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appSystemBackground)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
        )
    }
}

// MARK: - Substitute Option Row

struct SubstituteOptionRow: View {
    let substitute: SubstituteOption
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Confidence indicator
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Substitute name
                HStack {
                    Text(substitute.name)
                        .font(.body)
                        .fontWeight(.semibold)
                    
                    // Confidence badge
                    Text(substitute.confidence.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(confidenceColor.opacity(0.2))
                        .foregroundStyle(confidenceColor)
                        .clipShape(Capsule())
                }
                
                // Quantity
                if let quantity = substitute.quantity {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.caption2)
                        Text(quantity)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                // Notes
                if let notes = substitute.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var confidenceColor: Color {
        switch substitute.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

// MARK: - FODMAP Level Badge

struct FODMAPLevelBadge: View {
    let level: FODMAPLevel
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            Text(level.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(levelColor.opacity(0.2))
        .foregroundStyle(levelColor)
        .clipShape(Capsule())
    }
    
    private var levelColor: Color {
        switch level {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Compact Summary View (for Ingredient Section)

/// Compact inline view for showing a substitute next to an ingredient
struct InlineSubstituteSuggestion: View {
    let substitution: FODMAPSubstitution
    @State private var showingDetail = false
    
    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.caption)
                Text("FODMAP substitute available")
                    .font(.caption)
                Image(systemName: "chevron.right")
                    .font(.caption2)
            }
            .foregroundStyle(Color.appWarning)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .adaptiveToneBackground(.warning, baseOpacity: 0.15)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            SubstitutionDetailSheet(substitution: substitution)
        }
    }
}

// MARK: - Full Substitution Detail Sheet

struct SubstitutionDetailSheet: View {
    let substitution: FODMAPSubstitution
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Original ingredient header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(Color.appWarning)
                            Text(substitution.originalIngredient)
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        // FODMAP categories
                        HStack(spacing: 12) {
                            ForEach(substitution.fodmapCategories, id: \.self) { category in
                                VStack(spacing: 4) {
                                    Text(category.icon)
                                        .font(.title3)
                                    Text(category.rawValue)
                                        .font(.caption)
                                }
                                .padding(8)
                                .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Why Substitute?", systemImage: "info.circle")
                            .font(.headline)
                        Text(substitution.explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    
                    // Portion note
                    if let portionNote = substitution.portionNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Portion Guidance", systemImage: "ruler")
                                .font(.headline)
                                .foregroundStyle(Color.appWarning)
                            Text(portionNote)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .adaptiveToneBackground(.warning, baseOpacity: 0.1)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Substitutes
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Substitute Options", systemImage: "arrow.triangle.swap")
                            .font(.headline)
                            .foregroundStyle(Color.appSuccess)
                        
                        ForEach(substitution.substitutes) { substitute in
                            SubstituteOptionDetailCard(substitute: substitute)
                        }
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("FODMAP Substitute")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Detailed Substitute Card

struct SubstituteOptionDetailCard: View {
    let substitute: SubstituteOption
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(substitute.name)
                        .font(.headline)
                    
                    if let quantity = substitute.quantity {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar")
                                .font(.caption)
                            Text(quantity)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Confidence badge
                VStack(spacing: 2) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 12, height: 12)
                    Text(substitute.confidence.rawValue)
                        .font(.caption2)
                        .foregroundStyle(confidenceColor)
                }
            }
            
            if let notes = substitute.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appSecondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(confidenceColor.opacity(0.3), lineWidth: 2)
        )
    }
    
    private var confidenceColor: Color {
        switch substitute.confidence {
        case .high: return .green
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

// MARK: - Enhanced Ingredient Display with FODMAP Info

struct IngredientRowWithFODMAP: View {
    let ingredient: Ingredient
    let substitution: FODMAPSubstitution?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Original ingredient display
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(substitution != nil ? Color.orange : Color.blue)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let quantity = ingredient.quantity, !quantity.isEmpty {
                            Text(quantity)
                                .fontWeight(.semibold)
                        }
                        if let unit = ingredient.unit, !unit.isEmpty {
                            Text(unit)
                                .fontWeight(.medium)
                        }
                        Text(ingredient.name)
                        
                        // FODMAP indicator
                        if substitution != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.appWarning)
                        }
                    }
                    
                    if let prep = ingredient.preparation {
                        Text(prep)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    
                    if let metricQuantity = ingredient.metricQuantity,
                       let metricUnit = ingredient.metricUnit {
                        Text("(\(metricQuantity) \(metricUnit))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            
            // Show substitution suggestion inline
            if let substitution = substitution {
                InlineSubstituteSuggestion(substitution: substitution)
                    .padding(.leading, 14)
            }
        }
    }
}

// MARK: - Preview

#Preview("Substitution Section") {
    let ingredientSections = [
        IngredientSection(
            ingredients: [
                Ingredient(quantity: "1", unit: "medium", name: "onion"),
                Ingredient(quantity: "3", unit: "cloves", name: "garlic"),
                Ingredient(quantity: "1", unit: "cup", name: "milk")
            ]
        )
    ]
    
    let recipe = RecipeX()
    recipe.id = UUID()
    recipe.title = "Test Recipe"
    recipe.ingredientSectionsData = try? JSONEncoder().encode(ingredientSections)
    recipe.instructionSectionsData = try? JSONEncoder().encode([InstructionSection]())
    
    let analysis = FODMAPSubstitutionDatabase.shared.analyzeRecipe(recipe)
    
    return ScrollView {
        FODMAPSubstitutionSection(analysis: analysis)
            .padding()
    }
}

#Preview("Single Substitution Card") {
    let ingredient = Ingredient(quantity: "1", unit: "medium", name: "onion")
    let substitution = FODMAPSubstitution(
        originalIngredient: "onion",
        fodmapCategories: [.oligosaccharides],
        substitutes: [
            SubstituteOption(
                name: "Green tops of spring onions only",
                quantity: "Use green part only",
                notes: "Discard white bulb which is high FODMAP",
                confidence: .high
            )
        ],
        explanation: "Onions are very high in fructans",
        portionNote: "No safe portion - avoid completely"
    )
    
    let group = IngredientSubstitutionGroup(
        originalIngredient: ingredient,
        substitution: substitution
    )
    
    return IngredientSubstitutionCard(group: group, isExpanded: true, onToggle: {})
        .padding()
}
