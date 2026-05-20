//
//  RecipeValidationResult.swift
//  Reczipes2
//
//  Response model for the Claude-powered recipe validation step.
//

import Foundation

/// Response from recipe validation containing corrections and suggestions
struct RecipeValidationResult: Codable {
    let isValid: Bool
    let corrections: RecipeCorrections?
    let suggestions: [String]
    let confidence: Double // 0.0 to 1.0
    
    struct RecipeCorrections: Codable {
        let title: String?
        let cuisine: String?
        let ingredientSections: [SimplifiedIngredientSection]?
        let instructionSections: [SimplifiedInstructionSection]?
        let headerNotes: String?
        let recipeYield: String?
        let misplacedContent: [MisplacedContent]?
        
        struct MisplacedContent: Codable {
            let content: String
            let currentLocation: String // e.g., "notes", "ingredients"
            let suggestedLocation: String // e.g., "instructions", "headerNotes"
            let reason: String
        }
        
        // Simplified structure for validation responses (no UUIDs needed)
        struct SimplifiedIngredientSection: Codable {
            let title: String?
            let ingredients: [String] // Simple string array like "1 cup flour"
        }
        
        struct SimplifiedInstructionSection: Codable {
            let title: String?
            let steps: [String] // Simple string array
        }
    }
}
