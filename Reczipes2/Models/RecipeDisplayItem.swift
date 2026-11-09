//
//  RecipeDisplayItem.swift
//  Reczipes2
//
//  Created on 1/23/26.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Supporting Types

/// Represents a section of ingredients with optional title and transition note
struct IngredientSection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String?
    var ingredients: [Ingredient] = []
    var transitionNote: String?
    
    init(id: UUID = UUID(), title: String? = nil, ingredients: [Ingredient] = [], transitionNote: String? = nil) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
        self.transitionNote = transitionNote
    }
}

/// Represents an individual ingredient
struct Ingredient: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var quantity: String?
    var unit: String?
    var name: String
    var preparation: String?
    var metricQuantity: String?
    var metricUnit: String?
    
    init(id: UUID = UUID(), quantity: String? = nil, unit: String? = nil, name: String, preparation: String? = nil, metricQuantity: String? = nil, metricUnit: String? = nil) {
        self.id = id
        self.quantity = quantity
        self.unit = unit
        self.name = name
        self.preparation = preparation
        self.metricQuantity = metricQuantity
        self.metricUnit = metricUnit
    }
}

/// Represents a section of instructions with optional title
struct InstructionSection: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String?
    var steps: [InstructionStep] = []
    
    init(id: UUID = UUID(), title: String? = nil, steps: [InstructionStep] = []) {
        self.id = id
        self.title = title
        self.steps = steps
    }
}

/// Represents an individual instruction step
struct InstructionStep: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var stepNumber: Int
    var text: String
    
    init(id: UUID = UUID(), stepNumber: Int, text: String) {
        self.id = id
        self.stepNumber = stepNumber
        self.text = text
    }
}

/// Represents a recipe note with categorized type
struct RecipeNote: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var type: RecipeNoteType
    var text: String
    
    init(id: UUID = UUID(), type: RecipeNoteType, text: String) {
        self.id = id
        self.type = type
        self.text = text
    }
}

/// Categories of recipe notes
enum RecipeNoteType: String, Codable, CaseIterable {
    case tip = "tip"
    case substitution = "substitution"
    case warning = "warning"
    case timing = "timing"
    case general = "general"
    
    var displayName: String {
        switch self {
        case .tip: return String(localized: "Tip", bundle: .appLanguage)
        case .substitution: return String(localized: "Substitution", bundle: .appLanguage)
        case .warning: return String(localized: "Warning", bundle: .appLanguage)
        case .timing: return String(localized: "Timing", bundle: .appLanguage)
        case .general: return String(localized: "General", bundle: .appLanguage)
        }
    }
}

// MARK: - RecipeNote.NoteType Extension

extension RecipeNoteType {

    var icon: String {
        switch self {
        case .general: return "note.text"
        case .tip: return "lightbulb.fill"
        case .substitution: return "arrow.left.arrow.right"
        case .warning: return "exclamationmark.triangle.fill"
        case .timing: return "clock.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .general: return .blue
        case .tip: return .yellow
        case .substitution: return .green
        case .warning: return .red
        case .timing: return .orange
        }
    }
    
    var helpText: String {
        switch self {
        case .general: return String(localized: "General information or notes about the recipe", bundle: .appLanguage)
        case .tip: return String(localized: "Helpful tips to improve the recipe or technique", bundle: .appLanguage)
        case .substitution: return String(localized: "Alternative ingredients or methods", bundle: .appLanguage)
        case .warning: return String(localized: "Important warnings or things to watch out for", bundle: .appLanguage)
        case .timing: return String(localized: "Timing-related notes and guidance", bundle: .appLanguage)
        }
    }
    
    static var allCases: [RecipeNoteType] {
        [.general, .tip, .substitution, .warning, .timing]
    }
}

/// Unified type for displaying both owned recipes and cached community recipes
enum RecipeDisplayItem: Identifiable {
    case owned(RecipeX)
    case cached(CachedSharedRecipe)
    
    var id: UUID {
        switch self {
        case .owned(let recipe): return recipe.id ?? UUID()
        case .cached(let cached): return cached.id
        }
    }
    
    var title: String {
        switch self {
        case .owned(let recipe): return recipe.title ?? ""
        case .cached(let cached): return cached.title
        }
    }
    
    var headerNotes: String? {
        switch self {
        case .owned(let recipe): return recipe.headerNotes
        case .cached(let cached): return cached.headerNotes
        }
    }
    
    var yield: String? {
        switch self {
        case .owned(let recipe): return recipe.recipeYield
        case .cached(let cached): return cached.yield
        }
    }
    
    var ingredientSections: [IngredientSection] {
        switch self {
        case .owned(let recipe): return recipe.ingredientSections
        case .cached(let cached): return cached.ingredientSections
        }
    }
    
    var instructionSections: [InstructionSection] {
        switch self {
        case .owned(let recipe): return recipe.instructionSections
        case .cached(let cached): return cached.instructionSections
        }
    }
    
    var notes: [RecipeNote] {
        switch self {
        case .owned(let recipe): return recipe.notes
        case .cached(let cached): return cached.notes
        }
    }
    
    var reference: String? {
        switch self {
        case .owned(let recipe): return recipe.reference
        case .cached(let cached): return cached.reference
        }
    }
    
    var imageName: String? {
        switch self {
        case .owned(let recipe): return recipe.imageName
        case .cached(let cached): return cached.imageName
        }
    }
    
    var additionalImageNames: [String]? {
        switch self {
        case .owned(let recipe): return recipe.additionalImageNames
        case .cached(let cached): return cached.additionalImageNames
        }
    }
    
    var isCached: Bool {
        if case .cached = self { return true }
        return false
    }
    
    var sharedByUserName: String? {
        switch self {
        case .owned: return nil
        case .cached(let cached): return cached.sharedByUserName
        }
    }
    
    /// Convert to RecipeModel for compatibility with existing code
//    func toRecipeModel() -> RecipeModel {
//        switch self {
//        case .owned(let recipe):
//            return recipe
//        case .cached(let cached):
//            return RecipeModel(
//                id: cached.id,
//                title: cached.title,
//                headerNotes: cached.headerNotes,
//                yield: cached.yield,
//                ingredientSections: cached.ingredientSections,
//                instructionSections: cached.instructionSections,
//                notes: cached.notes,
//                reference: cached.reference,
//                imageName: cached.imageName,
//                additionalImageNames: cached.additionalImageNames
//            )
//        }
//    }
}
