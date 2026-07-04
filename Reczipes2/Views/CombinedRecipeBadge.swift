//
//  CombinedRecipeBadge.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import SwiftUI

struct CombinedRecipeBadge: View {
    let score: CombinedRecipeScore
    let compact: Bool
    
    init(score: CombinedRecipeScore, compact: Bool = false) {
        self.score = score
        self.compact = compact
    }
    
    var body: some View {
        if compact {
            compactBadge
        } else {
            fullBadge
        }
    }
    
    private var compactBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeIcon)
                .font(.caption2)
            
            if !score.isSafe {
                Text(score.displayText)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(Color.onTint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(badgeBackgroundColor)
        )
    }
    
    private var fullBadge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: badgeIcon)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.displayText)
                        .font(.headline)
                    
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Show details based on filter mode
            if score.filterMode != .none {
                detailsSection
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appSecondaryBackground)
        )
    }
    
    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if score.filterMode.includesAllergenFilter, let allergenScore = score.allergenScore {
                allergenDetailRow(allergenScore)
            }
            
            if score.filterMode.includesDiabetesFilter, let diabetesScore = score.diabetesScore {
                diabetesDetailRow(diabetesScore)
            }
        }
        .font(.caption)
    }
    
    private func allergenDetailRow(_ allergenScore: RecipeAllergenScore) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.appWarning)
            
            if allergenScore.isSafe {
                Text("No allergens detected")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(allergenScore.detectedAllergens.count) allergen\(allergenScore.detectedAllergens.count == 1 ? "" : "s") detected")
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            Text(allergenScore.scoreLabel)
                .fontWeight(.medium)
                .foregroundStyle(allergenScore.isSafe ? .green : .orange)
        }
    }
    
    private func diabetesDetailRow(_ diabetesScore: DiabetesScore) -> some View {
        HStack {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(Color.appInfo)
            
            Text(diabetesScore.suitability.displayName)
                .foregroundStyle(.primary)
            
            Spacer()
            
            if !diabetesScore.isDiabeticFriendly {
                Text("\(diabetesScore.highSugarIngredients.count + diabetesScore.refinedCarbIngredients.count) concern\(diabetesScore.highSugarIngredients.count + diabetesScore.refinedCarbIngredients.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            }
        }
    }
    
    private var badgeIcon: String {
        if score.isSafe {
            return "checkmark.seal.fill"
        }
        
        switch score.filterMode {
        case .none:
            return "circle"
        case .allergenFODMAP:
            return "exclamationmark.triangle.fill"
        case .diabetes:
            return "heart.text.square.fill"
        case .nutrition:
            return "pencil.and.outline.square"
        case .all:
            return "shield.lefthalf.filled"
        }
    }
    
    private var subtitleText: String {
        switch score.filterMode {
        case .none:
            return "No filters active"
        case .allergenFODMAP:
            return "Allergen & FODMAP Analysis"
        case .diabetes:
            return "Diabetes Analysis"
        case .nutrition:
            return "Nutrition Analysis"
        case .all:
            return "Complete Health Analysis"
        }
    }
    
    private var badgeBackgroundColor: Color {
        switch score.badgeColor {
        case "green":
            return .green
        case "yellow":
            return .yellow
        case "orange":
            return .orange
        case "red":
            return .red
        case "purple":
            return .purple
        case "blue":
            return .blue
        case "mint":
            return .mint
        default:
            return .gray
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Safe allergen score
        CombinedRecipeBadge(
            score: CombinedRecipeScore(
                recipeID: UUID(),
                allergenScore: RecipeAllergenScore(
                    recipeID: UUID(),
                    score: 0,
                    detectedAllergens: [],
                    isSafe: true,
                    severityLevel: nil
                ),
                diabetesScore: nil,
                nutritionalScore: nil,
                filterMode: .allergenFODMAP
            ),
            compact: true
        )
        
        // Unsafe diabetes score
        CombinedRecipeBadge(
            score: CombinedRecipeScore(
                recipeID: UUID(),
                allergenScore: nil,
                diabetesScore: DiabetesScore(
                    recipeID: UUID(),
                    riskScore: 8,
                    suitability: .caution,
                    highSugarIngredients: ["sugar"],
                    refinedCarbIngredients: ["white flour"],
                    beneficialIngredients: [],
                    isDiabeticFriendly: false
                ),
                nutritionalScore: nil,
                filterMode: .diabetes
            ),
            compact: false
        )
    }
    .padding()
}
