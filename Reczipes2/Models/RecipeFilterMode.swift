//
//  RecipeFilterMode.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/28/25.
//

import Foundation

/// Defines the four filtering modes for recipes
enum RecipeFilterMode: String, CaseIterable, Identifiable {
    case none = "None"
    case allergenFODMAP = "Allergen + FODMAP"
    case diabetes = "Diabetes"
    case all = "Allergen + FODMAP + Diabetes + Nutrition"
    case nutrition = "Nutrition"
    
    var id: String { rawValue }
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .none:
            return "line.3.horizontal.decrease.circle"
        case .nutrition:
            return "leaf.fill"
        case .allergenFODMAP:
            return "exclamationmark.triangle.fill"
        case .diabetes:
            return "heart.text.square.fill"
        case .all:
            return "shield.lefthalf.filled"
        }
    }
    
    var description: String {
        switch self {
        case .none:
            return String(localized: "Show all recipes without filtering", bundle: .appLanguage)
        case .nutrition:
            return String(localized: "Filter based on nutritional information", bundle: .appLanguage)
        case .allergenFODMAP:
            return String(localized: "Filter based on allergens and FODMAP sensitivities", bundle: .appLanguage)
        case .diabetes:
            return String(localized: "Filter for diabetes-friendly recipes (low sugar, complex carbs)", bundle: .appLanguage)
        case .all:
            return String(localized: "Apply all filters: allergens, FODMAP, and diabetes", bundle: .appLanguage)
        }
    }
    
    /// Whether this mode includes allergen/FODMAP filtering
    var includesAllergenFilter: Bool {
        switch self {
        case .none, .diabetes, .nutrition:
            return false
        case .allergenFODMAP, .all:
            return true
        }
    }
    var includesNutritionalFilter: Bool {
        self == .nutrition || self == .all
    }
    
    /// Whether this mode includes diabetes filtering
    var includesDiabetesFilter: Bool {
        switch self {
        case .none, .allergenFODMAP, .nutrition:
            return false
        case .diabetes, .all:
            return true
        }
    }
}
