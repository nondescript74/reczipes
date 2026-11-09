//
//  NutritionalBadge.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/2/26.
//

import SwiftUI

/// Badge showing nutritional compatibility score for a recipe
struct NutritionalBadge: View {
    let score: NutritionalScore
    let compact: Bool
    
    init(score: NutritionalScore, compact: Bool = true) {
        self.score = score
        self.compact = compact
    }
    
    var body: some View {
        if compact {
            compactBadge
        } else {
            expandedBadge
        }
    }
    
    // MARK: - Compact Badge
    
    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: severityIcon)
                .font(.caption2)
                .foregroundStyle(severityColor)
            
            Text("\(Int(score.compatibilityScore))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(severityColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(severityColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    // MARK: - Expanded Badge
    
    private var expandedBadge: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with score
            HStack {
                Label("Nutritional Fit", systemImage: "heart.text.square.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(severityColor)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: severityIcon)
                    Text("\(Int(score.compatibilityScore))%")
                        .fontWeight(.bold)
                }
                .foregroundStyle(severityColor)
            }
            
            // Key percentages
            if !score.dailyPercentages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sortedPercentages(), id: \.key) { item in
                        PercentageRow(
                            nutrient: item.key,
                            percentage: item.value,
                            isWarning: item.value > 50
                        )
                    }
                }
            }
            
            // Alerts
            if !score.alerts.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(score.alerts.prefix(3)) { alert in
                        AlertRow(alert: alert)
                    }
                    
                    if score.alerts.count > 3 {
                        Text("+ \(score.alerts.count - 3) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Estimated disclaimer
            if score.nutrition.isEstimated {
                Divider()
                
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Nutritional values are estimated")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(severityColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Views
    
    private func sortedPercentages() -> [(key: String, value: Double)] {
        score.dailyPercentages.sorted { $0.value > $1.value }
    }
    
    // MARK: - Computed Properties
    
    private var severityIcon: String {
        if score.compatibilityScore >= 80 {
            return "checkmark.seal.fill"
        } else if score.compatibilityScore >= 60 {
            return "checkmark.circle.fill"
        } else if score.compatibilityScore >= 40 {
            return "exclamationmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var severityColor: Color {
        if score.compatibilityScore >= 80 {
            return .green
        } else if score.compatibilityScore >= 60 {
            return .mint
        } else if score.compatibilityScore >= 40 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Percentage Row

struct PercentageRow: View {
    let nutrient: String
    let percentage: Double
    let isWarning: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isWarning ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            
            Text(nutrientDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(Int(percentage))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isWarning ? .orange : .primary)
        }
    }
    
    private var nutrientDisplayName: String {
        switch nutrient.lowercased() {
        case "calories": return String(localized: "Calories", bundle: .appLanguage)
        case "sodium": return String(localized: "Sodium", bundle: .appLanguage)
        case "saturatedfat": return String(localized: "Sat. Fat", bundle: .appLanguage)
        case "sugar": return String(localized: "Sugar", bundle: .appLanguage)
        case "fiber": return String(localized: "Fiber", bundle: .appLanguage)
        case "protein": return String(localized: "Protein", bundle: .appLanguage)
        case "carbohydrates": return String(localized: "Carbs", bundle: .appLanguage)
        default: return nutrient.capitalized
        }
    }
}

// MARK: - Alert Row

struct AlertRow: View {
    let alert: NutritionAlert
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: alert.severity.icon)
                .font(.caption)
                .foregroundStyle(severityColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                
                if let recommendation = alert.recommendation {
                    Text(recommendation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var severityColor: Color {
        switch alert.severity {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .red
        case .positive: return .blue
        }
    }
}

// MARK: - Placeholder Badge

/// Shows when nutritional goals aren't set
struct NutritionalPlaceholderBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.text.square")
                .font(.caption2)
            Text("Set goals")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview("Compact - High Compatibility") {
    let nutrition = RecipeNutrition(
        calories: 350,
        saturatedFat: 3,
        sodium: 400,
        sugar: 8,
        fiber: 6
    )
    
    let score = NutritionalScore(
        recipeID: UUID(),
        nutrition: nutrition,
        dailyPercentages: ["calories": 17.5, "sodium": 17.4, "fiber": 20],
        alerts: [
            NutritionAlert(
                nutrient: "Fiber",
                severity: .positive,
                message: "✅ Excellent fiber content",
                recommendation: "Great for digestive health"
            )
        ],
        compatibilityScore: 85,
        servings: 1
    )
    
    NutritionalBadge(score: score, compact: true)
        .padding()
}

#Preview("Compact - Low Compatibility") {
    let nutrition = RecipeNutrition(
        calories: 800,
        saturatedFat: 15,
        sodium: 1500,
        sugar: 35
    )
    
    let score = NutritionalScore(
        recipeID: UUID(),
        nutrition: nutrition,
        dailyPercentages: ["calories": 40, "sodium": 65, "saturatedFat": 75],
        alerts: [
            NutritionAlert(
                nutrient: "Sodium",
                severity: .high,
                message: "⚠️ Very high sodium",
                recommendation: "Reduce salt"
            )
        ],
        compatibilityScore: 25,
        servings: 1
    )
    
    NutritionalBadge(score: score, compact: true)
        .padding()
}

#Preview("Expanded") {
    let nutrition = RecipeNutrition(
        calories: 450,
        saturatedFat: 8,
        sodium: 800,
        sugar: 12,
        fiber: 5,
        isEstimated: true
    )
    
    let score = NutritionalScore(
        recipeID: UUID(),
        nutrition: nutrition,
        dailyPercentages: ["calories": 22.5, "sodium": 35, "saturatedFat": 40, "sugar": 33],
        alerts: [
            NutritionAlert(
                nutrient: "Sodium",
                severity: .moderate,
                message: "Moderate sodium: 800mg (35% of daily limit)",
                recommendation: "Be mindful of sodium in other meals"
            ),
            NutritionAlert(
                nutrient: "Saturated Fat",
                severity: .moderate,
                message: "Moderate saturated fat: 8g",
                recommendation: nil
            )
        ],
        compatibilityScore: 65,
        servings: 1
    )
    
    NutritionalBadge(score: score, compact: false)
        .padding()
}

#Preview("Placeholder") {
    NutritionalPlaceholderBadge()
        .padding()
}
