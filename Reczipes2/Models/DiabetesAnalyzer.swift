//
//  DiabetesAnalyzer.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import Foundation

/// Analyzes recipes for diabetes-friendly characteristics
class DiabetesAnalyzer {
    
    static let shared = DiabetesAnalyzer()
    
    private init() {}
    
    // MARK: - High-Risk Ingredients for Diabetes
    
    private let highSugarKeywords = [
        // Direct Sugars
        "sugar", "brown sugar", "white sugar", "granulated sugar", "powdered sugar",
        "confectioner's sugar", "caster sugar", "turbinado sugar", "raw sugar",
        
        // Syrups & Sweeteners
        "honey", "maple syrup", "corn syrup", "high-fructose corn syrup", "agave syrup",
        "agave nectar", "golden syrup", "molasses", "treacle",
        
        // Refined Carbs
        "white flour", "all-purpose flour", "refined flour", "white bread", "white rice",
        
        // Sweet Additions
        "chocolate chips", "candy", "frosting", "icing", "glaze",
        "sweetened condensed milk", "condensed milk",
        
        // Dried Fruits (concentrated sugars)
        "raisins", "dried cranberries", "dried apricots", "dried figs", "dates",
        "dried fruit", "candied fruit",
        
        // Juices (high glycemic)
        "fruit juice", "orange juice", "apple juice", "grape juice", "cranberry juice"
    ]
    
    private let refinedCarbKeywords = [
        "white bread", "white rice", "white pasta", "refined flour",
        "all-purpose flour", "white flour", "enriched flour",
        "instant rice", "rice noodles", "rice vermicelli",
        "cornflakes", "corn flakes", "rice cereal",
        "crackers", "pretzels", "potato chips"
    ]
    
    private let beneficialKeywords = [
        // Whole Grains
        "whole wheat", "whole grain", "brown rice", "quinoa", "barley",
        "oats", "oatmeal", "bulgur", "farro", "wild rice",
        
        // Legumes (low GI, high fiber)
        "lentils", "chickpeas", "black beans", "kidney beans", "pinto beans",
        "navy beans", "white beans", "split peas",
        
        // Non-Starchy Vegetables
        "broccoli", "cauliflower", "spinach", "kale", "lettuce", "cucumber",
        "zucchini", "bell pepper", "tomato", "asparagus", "green beans",
        "cabbage", "brussels sprouts", "celery", "mushrooms",
        
        // Lean Proteins
        "chicken breast", "turkey breast", "fish", "salmon", "tuna",
        "egg whites", "tofu", "tempeh",
        
        // Healthy Fats
        "olive oil", "avocado", "nuts", "almonds", "walnuts",
        "chia seeds", "flax seeds", "flaxseed"
    ]
    
    // MARK: - Analysis Methods
    
    /// Analyze a recipe for diabetes-friendliness
    func analyzeRecipe(_ recipe: RecipeX) -> DiabetesScore {
        let ingredients = extractIngredientNames(from: recipe)
        
        let highSugarMatches = findMatches(in: ingredients, keywords: highSugarKeywords)
        let refinedCarbMatches = findMatches(in: ingredients, keywords: refinedCarbKeywords)
        let beneficialMatches = findMatches(in: ingredients, keywords: beneficialKeywords)
        
        // Calculate risk score (higher = worse for diabetes)
        let riskScore = calculateRiskScore(
            highSugarCount: highSugarMatches.count,
            refinedCarbCount: refinedCarbMatches.count,
            beneficialCount: beneficialMatches.count
        )
        
        let suitability = determineSuitability(score: riskScore)
        
        return DiabetesScore(
            recipeID: recipe.safeID,
            riskScore: riskScore,
            suitability: suitability,
            highSugarIngredients: highSugarMatches,
            refinedCarbIngredients: refinedCarbMatches,
            beneficialIngredients: beneficialMatches,
            isDiabeticFriendly: suitability == .excellent || suitability == .good
        )
    }
    
    /// Analyze multiple recipes
    func analyzeRecipes(_ recipes: [RecipeX]) -> [UUID: DiabetesScore] {
        var scores: [UUID: DiabetesScore] = [:]
        for recipe in recipes {
            scores[recipe.safeID] = analyzeRecipe(recipe)
        }
        return scores
    }
    
    // MARK: - Filtering & Sorting
    
    /// Filter recipes to show only diabetes-friendly ones
    func filterDiabeticFriendlyRecipes(_ recipes: [RecipeX]) -> [RecipeX] {
        recipes.filter { recipe in
            let score = analyzeRecipe(recipe)
            return score.isDiabeticFriendly
        }
    }
    
    /// Sort recipes by diabetes-friendliness (best first)
    func sortRecipesByDiabeticFriendliness(_ recipes: [RecipeX]) -> [RecipeX] {
        let scores = analyzeRecipes(recipes)
        return recipes.sorted { recipe1, recipe2 in
            let score1 = scores[recipe1.safeID]?.riskScore ?? Double.infinity
            let score2 = scores[recipe2.safeID]?.riskScore ?? Double.infinity
            return score1 < score2
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractIngredientNames(from recipe: RecipeX) -> [String] {
        var names: [String] = []
        
        // Decode ingredient sections from JSON data
        guard let sectionsData = recipe.ingredientSectionsData,
              let sections = try? JSONDecoder().decode([IngredientSection].self, from: sectionsData) else {
            return []
        }
        
        for section in sections {
            for ingredient in section.ingredients {
                names.append(ingredient.name)
                
                if let prep = ingredient.preparation {
                    names.append(prep)
                }
                
                if let unit = ingredient.unit {
                    names.append(unit)
                }
            }
        }
        
        return names
    }
    
    private func findMatches(in ingredients: [String], keywords: [String]) -> [String] {
        var matches: [String] = []
        
        for ingredient in ingredients {
            let lowercased = ingredient.lowercased()
            
            for keyword in keywords {
                if lowercased.contains(keyword.lowercased()) {
                    if !matches.contains(ingredient) {
                        matches.append(ingredient)
                    }
                    break
                }
            }
        }
        
        return matches
    }
    
    private func calculateRiskScore(highSugarCount: Int, refinedCarbCount: Int, beneficialCount: Int) -> Double {
        // High sugar items are worst (weight: 3.0)
        let sugarScore = Double(highSugarCount) * 3.0
        
        // Refined carbs are bad (weight: 2.0)
        let carbScore = Double(refinedCarbCount) * 2.0
        
        // Beneficial ingredients reduce score (weight: -1.0)
        let benefitScore = Double(beneficialCount) * -1.0
        
        let rawScore = sugarScore + carbScore + benefitScore
        
        // Ensure minimum score is 0
        return max(0, rawScore)
    }
    
    private func determineSuitability(score: Double) -> DiabetesSuitability {
        if score == 0 {
            return .excellent
        } else if score <= 3 {
            return .good
        } else if score <= 6 {
            return .moderate
        } else if score <= 10 {
            return .caution
        } else {
            return .avoid
        }
    }
}

// MARK: - Diabetes Score Model

struct DiabetesScore: Identifiable, Sendable {
    let id = UUID()
    let recipeID: UUID
    let riskScore: Double
    let suitability: DiabetesSuitability
    let highSugarIngredients: [String]
    let refinedCarbIngredients: [String]
    let beneficialIngredients: [String]
    let isDiabeticFriendly: Bool
    
    var summary: String {
        if isDiabeticFriendly {
            return String(localized: "Diabetes-friendly", bundle: .appLanguage)
        }
        return suitability.displayName
    }
}

// MARK: - Diabetes Suitability Levels

enum DiabetesSuitability: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case moderate = "Moderate"
    case caution = "Caution"
    case avoid = "Avoid"
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .excellent:
            return "checkmark.seal.fill"
        case .good:
            return "checkmark.circle.fill"
        case .moderate:
            return "exclamationmark.circle.fill"
        case .caution:
            return "exclamationmark.triangle.fill"
        case .avoid:
            return "xmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .excellent:
            return "green"
        case .good:
            return "mint"
        case .moderate:
            return "yellow"
        case .caution:
            return "orange"
        case .avoid:
            return "red"
        }
    }
}
