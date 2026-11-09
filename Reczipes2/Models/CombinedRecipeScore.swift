//
//  CombinedRecipeScore.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import Foundation

/// Combined score that includes allergen, FODMAP, diabetes, and nutritional analysis
struct CombinedRecipeScore: Identifiable, Sendable {
    let id = UUID()
    let recipeID: UUID
    let allergenScore: RecipeAllergenScore?
    let diabetesScore: DiabetesScore?
    let nutritionalScore: NutritionalScore?
    let filterMode: RecipeFilterMode
    
    /// Overall safety score considering active filters
    var overallScore: Double {
        var total: Double = 0
        var components = 0
        
        // Add allergen score if relevant
        if filterMode.includesAllergenFilter, let allergen = allergenScore {
            total += allergen.score
            components += 1
        }
        
        // Add diabetes score if relevant
        if filterMode.includesDiabetesFilter, let diabetes = diabetesScore {
            total += diabetes.riskScore
            components += 1
        }
        
        // Add nutritional score if relevant
        if filterMode.includesNutritionalFilter, let nutrition = nutritionalScore {
            // Convert compatibility score (0-100) to risk score (0-15) by inverting
            // Higher compatibility = lower risk
            let nutritionalRisk = 15.0 - (nutrition.compatibilityScore / 100.0 * 15.0)
            total += nutritionalRisk
            components += 1
        }
        
        // Return average if we have components, otherwise 0
        return components > 0 ? total / Double(components) : 0
    }
    
    /// Whether this recipe is safe given the active filter mode
    var isSafe: Bool {
        switch filterMode {
        case .none:
            return true
        case .allergenFODMAP:
            return allergenScore?.isSafe ?? true
        case .diabetes:
            return diabetesScore?.isDiabeticFriendly ?? true
        case .nutrition:
            return nutritionalScore?.isCompatible ?? true
        case .all:
            let allergenSafe = allergenScore?.isSafe ?? true
            let diabetesSafe = diabetesScore?.isDiabeticFriendly ?? true
            let nutritionSafe = nutritionalScore?.isCompatible ?? true
            return allergenSafe && diabetesSafe && nutritionSafe
        }
    }
    
    /// Display text for the badge
    var displayText: String {
        if isSafe {
            return "✓"
        }
        
        switch filterMode {
        case .none:
            return ""
        case .allergenFODMAP:
            return allergenScore?.scoreLabel ?? ""
        case .diabetes:
            return diabetesScore?.suitability.displayName ?? ""
        case .nutrition:
            if let nutrition = nutritionalScore {
                return nutrition.overallSeverity == .high ? "High Risk" : "Moderate"
            }
            return ""
        case .all:
            if let allergen = allergenScore, !allergen.isSafe {
                return allergen.scoreLabel
            }
            if let diabetes = diabetesScore, !diabetes.isDiabeticFriendly {
                return diabetes.suitability.displayName
            }
            if let nutrition = nutritionalScore, !nutrition.isCompatible {
                return nutrition.overallSeverity == .high ? "High Risk" : "Moderate"
            }
            return String(localized: "Safe", bundle: .appLanguage)
        }
    }
    
    /// Color for the badge
    var badgeColor: String {
        if isSafe {
            return "green"
        }
        
        switch filterMode {
        case .none:
            return "gray"
        case .allergenFODMAP:
            if let allergen = allergenScore {
                return allergen.score < 5 ? "yellow" : (allergen.score < 10 ? "orange" : "red")
            }
            return "gray"
        case .diabetes:
            return diabetesScore?.suitability.color ?? "gray"
        case .nutrition:
            if let nutrition = nutritionalScore {
                return nutrition.overallSeverity.color
            }
            return "gray"
        case .all:
            // Use the worse of the three
            let allergenRisk = allergenScore?.score ?? 0
            let diabetesRisk = diabetesScore?.riskScore ?? 0
            
            // Convert nutritional compatibility to risk (inverted scale)
            let nutritionRisk = nutritionalScore.map { 15.0 - ($0.compatibilityScore / 100.0 * 15.0) } ?? 0
            
            let maxRisk = max(allergenRisk, diabetesRisk, nutritionRisk)
            
            if maxRisk < 5 {
                return "yellow"
            } else if maxRisk < 10 {
                return "orange"
            } else {
                return "red"
            }
        }
    }
}
