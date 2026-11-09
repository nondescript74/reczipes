//
//  UserAllergenProfile.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/18/25.
//  Schema Version: 3.0.0 - Added nutritional goals support
//  Previous: 2.0.0 - Added diabetes status support
//
//  CloudKit Compatibility Notes:
//  - All properties are optional (CloudKit requirement)
//  - No unique constraints (CloudKit doesn't support them)
//  - Default values provided in init() method
//

import Foundation
import SwiftData

// MARK: - Diabetes Status

enum DiabetesStatus: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case prediabetic = "Prediabetic"
    case diabetic = "Diabetic"
    
    var icon: String {
        switch self {
        case .none: return ""
        case .prediabetic: return "⚠️"
        case .diabetic: return "🩸"
        }
    }
    
    var description: String {
        switch self {
        case .none: return String(localized: "No diabetes concerns", bundle: .appLanguage)
        case .prediabetic: return String(localized: "Monitor blood sugar levels", bundle: .appLanguage)
        case .diabetic: return String(localized: "Requires blood sugar management", bundle: .appLanguage)
        }
    }
}

// MARK: - User Profile (SwiftData Model)
// Schema Version: 3.0.0

@Model
final class UserAllergenProfile {
    // CloudKit doesn't support unique constraints - removed @Attribute(.unique)
    // CloudKit requires all properties to be optional OR have default values
    var id: UUID?
    var name: String?
    var isActive: Bool?
    var sensitivitiesData: Data?
    
    // Added in Schema V2.0.0
    // Default value ensures automatic migration works without deleting the app
    var diabetesStatusRaw: String?
    
    // Added in Schema V3.0.0
    // Nutritional goals (calories, sodium, fat, etc.)
    // Stored as encoded Data for CloudKit compatibility
    var nutritionalGoalsData: Data?
    
    var dateCreated: Date?
    var dateModified: Date?
    
    init(
        id: UUID = UUID(),
        name: String = "",
        isActive: Bool = false,
        sensitivitiesData: Data? = nil,
        diabetesStatus: DiabetesStatus = .none,
        nutritionalGoals: NutritionalGoals? = nil,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.sensitivitiesData = sensitivitiesData
        self.diabetesStatusRaw = diabetesStatus.rawValue
        // Encode nutritional goals data using MainActor.assumeIsolated
        if let goals = nutritionalGoals {
            self.nutritionalGoalsData = MainActor.assumeIsolated {
                try? JSONEncoder().encode(goals)
            }
        } else {
            self.nutritionalGoalsData = nil
        }
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
    
    // Computed property for diabetes status
    nonisolated var diabetesStatus: DiabetesStatus {
        get {
            guard let raw = diabetesStatusRaw else { return .none }
            return DiabetesStatus(rawValue: raw) ?? .none
        }
        set {
            diabetesStatusRaw = newValue.rawValue
            dateModified = Date()
        }
    }
    
    // Computed property for nutritional goals
    var nutritionalGoals: NutritionalGoals? {
        get {
            guard let data = nutritionalGoalsData else { return nil }
            return MainActor.assumeIsolated {
                try? JSONDecoder().decode(NutritionalGoals.self, from: data)
            }
        }
        set {
            if let goals = newValue {
                nutritionalGoalsData = MainActor.assumeIsolated {
                    try? JSONEncoder().encode(goals)
                }
            } else {
                nutritionalGoalsData = nil
            }
            dateModified = Date()
        }
    }
    
    // Convenience property to check if diabetes filtering is needed
    nonisolated var hasDiabetesConcern: Bool {
        diabetesStatus != .none
    }
    
    // Convenience property to check if nutritional goals are set
    var hasNutritionalGoals: Bool {
        nutritionalGoalsData != nil
    }
    
    // Computed property to get sensitivities
    nonisolated var sensitivities: [UserSensitivity] {
        get {
            guard let data = sensitivitiesData else { return [] }
            return (try? JSONDecoder().decode([UserSensitivity].self, from: data)) ?? []
        }
        set {
            sensitivitiesData = try? JSONEncoder().encode(newValue)
            dateModified = Date()
        }
    }
    
    // Add a sensitivity
    nonisolated func addSensitivity(_ sensitivity: UserSensitivity) {
        var current = sensitivities
        current.append(sensitivity)
        sensitivities = current
    }
    
    // Remove a sensitivity
    nonisolated func removeSensitivity(id: UUID) {
        var current = sensitivities
        current.removeAll { $0.id == id }
        sensitivities = current
    }
    
    // Update a sensitivity
    nonisolated func updateSensitivity(_ sensitivity: UserSensitivity) {
        var current = sensitivities
        if let index = current.firstIndex(where: { $0.id == sensitivity.id }) {
            current[index] = sensitivity
            sensitivities = current
        }
    }
}
