//
//  RecipeNutritionalSection.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/2/26.
//  A reusable section for showing nutritional information in RecipeDetailView
//

import SwiftUI

/// Section showing nutritional analysis for a recipe based on user's goals
struct RecipeNutritionalSection: View {
    let recipe: RecipeX
    let profile: UserAllergenProfile?
    let servings: Int
    
    @State private var nutritionalScore: NutritionalScore?
    @State private var isExpanded: Bool = false
    
    init(recipe: RecipeX, profile: UserAllergenProfile?, servings: Int = 1) {
        self.recipe = recipe
        self.profile = profile
        self.servings = servings
    }
    
    var body: some View {
        Group {
            if let profile = profile, let goals = profile.nutritionalGoals {
                // User has goals set - show analysis
                Section {
                    if let score = nutritionalScore {
                        nutritionalAnalysisView(score: score)
                    } else {
                        ProgressView("Analyzing nutrition...")
                    }
                } header: {
                    HStack {
                        Label("Nutritional Fit", systemImage: "heart.text.square.fill")
                        Spacer()
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                    }
                }
                .task {
                    // Analyze when view appears
                    nutritionalScore = NutritionalAnalyzer.shared.analyzeRecipe(
                        recipe,
                        goals: goals,
                        servings: servings
                    )
                }
                .onChange(of: servings) { _, newServings in
                    // Recalculate when servings change
                    nutritionalScore = NutritionalAnalyzer.shared.analyzeRecipe(
                        recipe,
                        goals: goals,
                        servings: newServings
                    )
                }
            } else {
                // No goals set - show prompt
                Section {
                    noGoalsPrompt
                } header: {
                    Label("Nutritional Information", systemImage: "heart.text.square")
                }
            }
        }
    }
    
    // MARK: - Nutritional Analysis View
    
    @ViewBuilder
    private func nutritionalAnalysisView(score: NutritionalScore) -> some View {
        // Compatibility score
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compatibility Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    Image(systemName: compatibilityIcon(for: score.compatibilityScore))
                        .foregroundStyle(compatibilityColor(for: score.compatibilityScore))
                    
                    Text("\(Int(score.compatibilityScore))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(compatibilityColor(for: score.compatibilityScore))
                    
                    Text(compatibilityText(for: score.compatibilityScore))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        
        if isExpanded {
            // Daily percentages
            if !score.dailyPercentages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Percentage of Daily Goals")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(sortedPercentages(score.dailyPercentages), id: \.key) { item in
                        percentageBar(nutrient: item.key, percentage: item.value)
                    }
                }
                .padding(.top, 4)
            }
            
            // Alerts
            if !score.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Health Alerts")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(score.alerts) { alert in
                        alertCard(alert)
                    }
                }
                .padding(.top, 4)
            }
            
            // Estimated disclaimer
            if score.nutrition.isEstimated {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Nutritional values are estimated based on ingredients")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - No Goals Prompt
    
    private var noGoalsPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .font(.title3)
                    .foregroundStyle(.blue)
                
                Text("Set Nutritional Goals")
                    .font(.headline)
            }
            
            Text("Track how recipes fit your daily targets for calories, sodium, fat, sugar, and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if profile != nil {
                NavigationLink {
                    // Navigate to goals setting
                    // You'll need to implement this navigation
                    Text("Nutritional Goals View")
                } label: {
                    Label("Set Up Goals", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Create a profile first to set nutritional goals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Helper Views
    
    private func percentageBar(nutrient: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nutrientDisplayName(nutrient))
                    .font(.caption)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(percentageColor(percentage))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    // Filled portion
                    RoundedRectangle(cornerRadius: 2)
                        .fill(percentageColor(percentage))
                        .frame(width: min(geometry.size.width * (percentage / 100), geometry.size.width), height: 4)
                }
            }
            .frame(height: 4)
        }
    }
    
    private func alertCard(_ alert: NutritionAlert) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: alert.severity.icon)
                .font(.caption)
                .foregroundStyle(alertColor(alert.severity))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                
                if let recommendation = alert.recommendation {
                    Text(recommendation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(8)
        .background(alertColor(alert.severity).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - Helper Methods
    
    private func sortedPercentages(_ dict: [String: Double]) -> [(key: String, value: Double)] {
        dict.sorted { $0.value > $1.value }
    }
    
    private func nutrientDisplayName(_ key: String) -> String {
        switch key.lowercased() {
        case "calories": return String(localized: "Calories", bundle: .appLanguage)
        case "sodium": return String(localized: "Sodium", bundle: .appLanguage)
        case "saturatedfat": return String(localized: "Saturated Fat", bundle: .appLanguage)
        case "sugar": return String(localized: "Sugar", bundle: .appLanguage)
        case "fiber": return String(localized: "Fiber", bundle: .appLanguage)
        case "protein": return String(localized: "Protein", bundle: .appLanguage)
        case "carbohydrates": return String(localized: "Carbohydrates", bundle: .appLanguage)
        case "totalfat": return String(localized: "Total Fat", bundle: .appLanguage)
        default: return key.capitalized
        }
    }
    
    private func percentageColor(_ percentage: Double) -> Color {
        if percentage > 66 {
            return .red
        } else if percentage > 33 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func alertColor(_ severity: AlertSeverity) -> Color {
        switch severity {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .red
        case .positive: return .blue
        }
    }
    
    private func compatibilityIcon(for score: Double) -> String {
        if score >= 80 {
            return "checkmark.seal.fill"
        } else if score >= 60 {
            return "checkmark.circle.fill"
        } else if score >= 40 {
            return "exclamationmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private func compatibilityColor(for score: Double) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .mint
        } else if score >= 40 {
            return .yellow
        } else {
            return .orange
        }
    }
    
    private func compatibilityText(for score: Double) -> String {
        if score >= 80 {
            return String(localized: "Excellent fit", bundle: .appLanguage)
        } else if score >= 60 {
            return String(localized: "Good fit", bundle: .appLanguage)
        } else if score >= 40 {
            return String(localized: "Moderate fit", bundle: .appLanguage)
        } else {
            return String(localized: "Poor fit", bundle: .appLanguage)
        }
    }
}

// MARK: - Usage in RecipeDetailView

/*
 HOW TO USE:
 
 In your RecipeDetailView, simply add this section:
 
 ```swift
 struct RecipeDetailView: View {
     let recipe: RecipeX
     @Query private var profiles: [UserAllergenProfile]
     @State private var servingSize: Int = 1
     
     private var activeProfile: UserAllergenProfile? {
         profiles.first { $0.isActive }
     }
     
     var body: some View {
         List {
             // ... existing sections ...
             
             // Add nutritional section
             RecipeNutritionalSection(
                 recipe: recipe,
                 profile: activeProfile,
                 servings: servingSize
             )
             
             // ... more sections ...
         }
     }
 }
 ```
 
 FEATURES:
 - ✅ Shows compatibility score (0-100%)
 - ✅ Expandable/collapsible details
 - ✅ Percentage bars for daily values
 - ✅ Health alerts with recommendations
 - ✅ Responsive to serving size changes
 - ✅ Prompts user to set goals if not configured
 - ✅ Estimated nutrition disclaimer
 
 */

// MARK: - Preview

#Preview("With Goals - Good Fit") {
    let ingredients: [Ingredient] = [
        Ingredient(
            id: UUID(),
            quantity: "2",
            unit: "cups",
            name: "mixed greens",
            preparation: "washed",
            metricQuantity: nil,
            metricUnit: nil
        ),
        Ingredient(
            id: UUID(),
            quantity: "8",
            unit: "oz",
            name: "grilled chicken breast",
            preparation: "sliced",
            metricQuantity: nil,
            metricUnit: nil
        )
    ]
    
    let ingredientSection = IngredientSection(
        id: UUID(),
        title: "Salad",
        ingredients: ingredients,
        transitionNote: nil
    )
    
    let steps = [
        InstructionStep(id: UUID(), stepNumber: 1, text: "Arrange greens on plate"),
        InstructionStep(id: UUID(), stepNumber: 2, text: "Top with sliced chicken")
    ]
    
    let instructionSection = InstructionSection(
        id: UUID(),
        title: "Assembly",
        steps: steps
    )
    
    let notes = [
        RecipeNote(id: UUID(), type: .tip, text: "Great for meal prep")
    ]
    
    // Encode sections to Data for RecipeX
    let ingredientSectionsData = try? JSONEncoder().encode([ingredientSection])
    let instructionSectionsData = try? JSONEncoder().encode([instructionSection])
    let notesData = try? JSONEncoder().encode(notes)
    
    let recipe = RecipeX(
        id: UUID(),
        title: "Grilled Chicken Salad",
        headerNotes: "A healthy, protein-rich meal",
        recipeYield: "Serves 4",
        reference: nil,
        ingredientSectionsData: ingredientSectionsData,
        instructionSectionsData: instructionSectionsData,
        notesData: notesData
    )
    
    let profile = UserAllergenProfile(
        name: "Test User",
        isActive: true,
        nutritionalGoals: NutritionalGoals.preset(for: .generalHealth)
    )
    
    NavigationStack {
        List {
            RecipeNutritionalSection(recipe: recipe, profile: profile, servings: 1)
        }
        .navigationTitle("Recipe")
    }
}

#Preview("No Goals Set") {
    let ingredients: [Ingredient] = [
        Ingredient(id: UUID(), quantity: nil, unit: nil, name: "test ingredient", preparation: nil, metricQuantity: nil, metricUnit: nil)
    ]
    
    let ingredientSection = IngredientSection(id: UUID(), title: nil, ingredients: ingredients, transitionNote: nil)
    
    let steps = [
        InstructionStep(id: UUID(), stepNumber: 1, text: "Cook the dish")
    ]
    
    let instructionSection = InstructionSection(id: UUID(), title: nil, steps: steps)
    
    // Encode sections to Data for RecipeX
    let ingredientSectionsData = try? JSONEncoder().encode([ingredientSection])
    let instructionSectionsData = try? JSONEncoder().encode([instructionSection])
    
    let recipe = RecipeX(
        id: UUID(),
        title: "Test Recipe",
        headerNotes: nil,
        recipeYield: "Serves 2",
        reference: nil,
        ingredientSectionsData: ingredientSectionsData,
        instructionSectionsData: instructionSectionsData,
        notesData: nil
    )
    
    let profile = UserAllergenProfile(name: "Test User", isActive: true)
    // No goals set
    
    NavigationStack {
        List {
            RecipeNutritionalSection(recipe: recipe, profile: profile, servings: 1)
        }
        .navigationTitle("Recipe")
    }
}
