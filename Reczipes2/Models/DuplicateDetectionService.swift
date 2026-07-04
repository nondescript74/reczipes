//
//  DuplicateDetectionService.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/20/26.
//


import SwiftUI
import SwiftData

@MainActor
class DuplicateDetectionService {
    
    private let imageHashService = ImageHashService()
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Image-Based Detection
    
    /// Find recipes with similar images
    func findSimilarByImage(_ image: PlatformImage, threshold: Double = 0.95) async -> [RecipeX] {
        guard let imageHash = imageHashService.generateHash(for: image) else {
            return []
        }
        
        let descriptor = FetchDescriptor<RecipeX>(
            predicate: #Predicate { recipe in
                recipe.imageHash != nil
            }
        )
        
        guard let allRecipes = try? modelContext.fetch(descriptor) else {
            return []
        }
        
        let similar = allRecipes.filter { recipe in
            guard let existingHash = recipe.imageHash else { return false }
            let similarity = imageHashService.similarity(hash1: imageHash, hash2: existingHash)
            return similarity >= threshold
        }
        
        return similar
    }
    
    // MARK: - Content-Based Detection
    
    /// Find recipes with similar content
    func findSimilarByContent(_ recipe: RecipeX, threshold: Double = 0.8) async -> [DuplicateMatch] {
        let descriptor = FetchDescriptor<RecipeX>()
        
        guard let allRecipes = try? modelContext.fetch(descriptor) else {
            return []
        }
        
        var matches: [DuplicateMatch] = []
        
        for existingRecipe in allRecipes {
            let score = calculateSimilarity(newRecipe: recipe, existingRecipe: existingRecipe)
            
            if score.overall >= threshold {
                let match = DuplicateMatch(
                    existingRecipe: existingRecipe,
                    confidence: score.overall,
                    matchType: determineMatchType(score: score),
                    reasons: generateReasons(score: score)
                )
                matches.append(match)
            }
        }
        
        return matches.sorted { $0.confidence > $1.confidence }
    }
    
    // MARK: - Similarity Calculation
    
    func calculateSimilarity(newRecipe: RecipeX, existingRecipe: RecipeX) -> DuplicateMatchScore {
        let titleSim = titleSimilarity(newRecipe.safeTitle, existingRecipe.safeTitle)
        let ingredientSim = ingredientSimilarity(newRecipe: newRecipe, existingRecipe: existingRecipe)
        
        // Weighted average: title 40%, ingredients 60%
        let overall = (titleSim * 0.4) + (ingredientSim * 0.6)
        
        return DuplicateMatchScore(
            titleSimilarity: titleSim,
            ingredientSimilarity: ingredientSim,
            imageSimilarity: 0.0, // Set separately if needed
            overall: overall
        )
    }
    
    private func titleSimilarity(_ title1: String, _ title2: String) -> Double {
        let normalized1 = title1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized2 = title2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalized1 == normalized2 {
            return 1.0
        }
        
        // Simple Levenshtein-based similarity
        let distance = levenshteinDistance(normalized1, normalized2)
        let maxLength = max(normalized1.count, normalized2.count)
        guard maxLength > 0 else { return 0.0 }
        
        return 1.0 - (Double(distance) / Double(maxLength))
    }
    
    private func ingredientSimilarity(newRecipe: RecipeX, existingRecipe: RecipeX) -> Double {
        let newIngredients = extractIngredients(from: newRecipe)
        let existingIngredients = extractIngredients(from: existingRecipe)
        
        let set1 = Set(newIngredients.map { normalizeIngredient($0) })
        let set2 = Set(existingIngredients.map { normalizeIngredient($0) })
        
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        guard union > 0 else { return 0.0 }
        
        return Double(intersection) / Double(union)
    }
    
    private func extractIngredients(from recipe: RecipeX) -> [String] {
        // Decode the ingredientSections from stored Data
        guard let sectionsData = recipe.ingredientSectionsData,
              let sections = try? JSONDecoder().decode([IngredientSection].self, from: sectionsData) else {
            return []
        }
        
        return sections.flatMap { section in
            section.ingredients.map { formatIngredientText($0) }
        }
    }
    
    /// Formats an Ingredient into a readable string for comparison
    /// Combines quantity, unit, and name with proper spacing
    private func formatIngredientText(_ ingredient: Ingredient) -> String {
        var parts: [String] = []
        
        // Add quantity if present
        if let quantity = ingredient.quantity, !quantity.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(quantity)
        }
        
        // Add unit if present
        if let unit = ingredient.unit, !unit.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(unit)
        }
        
        // Always add name (required)
        parts.append(ingredient.name)
        
        // Add preparation if present
        if let preparation = ingredient.preparation, !preparation.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(preparation)
        }
        
        // Join with spaces
        return parts.joined(separator: " ")
    }
    
    private func normalizeIngredient(_ ingredient: String) -> String {
        ingredient
            .lowercased()
            .replacingOccurrences(of: #"\d+\.?\d*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(cup|cups|tbsp|tsp|oz|lb|g|kg|ml|l)\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: s2.count + 1), count: s1.count + 1)
        
        for i in 0...s1.count {
            dist[i][0] = i
        }
        
        for j in 0...s2.count {
            dist[0][j] = j
        }
        
        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i-1] == s2[j-1] ? 0 : 1
                dist[i][j] = min(
                    dist[i-1][j] + 1,
                    dist[i][j-1] + 1,
                    dist[i-1][j-1] + cost
                )
            }
        }
        
        return dist[s1.count][s2.count]
    }
    
    private func determineMatchType(score: DuplicateMatchScore) -> MatchType {
        if score.titleSimilarity > 0.9 && score.ingredientSimilarity > 0.7 {
            return .combined
        } else if score.titleSimilarity > 0.9 {
            return .titleMatch
        } else if score.ingredientSimilarity > 0.8 {
            return .ingredientMatch
        } else {
            return .combined
        }
    }
    
    private func generateReasons(score: DuplicateMatchScore) -> [String] {
        var reasons: [String] = []
        
        if score.titleSimilarity > 0.9 {
            reasons.append("Title is very similar (\(Int(score.titleSimilarity * 100))%)")
        }
        
        if score.ingredientSimilarity > 0.7 {
            reasons.append("Ingredients match (\(Int(score.ingredientSimilarity * 100))%)")
        }
        
        if score.imageSimilarity > 0.9 {
            reasons.append("Image looks identical (\(Int(score.imageSimilarity * 100))%)")
        }
        
        return reasons
    }
}

// MARK: - Supporting Types

struct DuplicateMatch {
    let existingRecipe: RecipeX
    let confidence: Double
    let matchType: MatchType
    let reasons: [String]
}

enum MatchType {
    case imageHash
    case titleMatch
    case ingredientMatch
    case combined
}

struct DuplicateMatchScore {
    let titleSimilarity: Double
    let ingredientSimilarity: Double
    let imageSimilarity: Double
    let overall: Double
}
