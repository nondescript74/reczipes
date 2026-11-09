//
//  NutritionalGoals.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/2/26.
//  Based on guidelines from American Heart Association, American Diabetes Association, and CDC
//

import Foundation
import SwiftData

// MARK: - Nutritional Goals Model

/// Daily nutritional targets for a user profile
/// Based on medical and nutritional guidelines from:
/// - American Heart Association (AHA)
/// - American Diabetes Association (ADA)
/// - Centers for Disease Control and Prevention (CDC)
/// - Dietary Guidelines for Americans 2020-2025
struct NutritionalGoals: Codable, Sendable {
    
    // MARK: - Core Macronutrients
    
    /// Daily calorie target (kcal)
    /// - ADA: 1,200-2,400 kcal for weight management (varies by activity level)
    /// - CDC: 1,600-2,400 kcal for adult women, 2,000-3,000 for adult men
    var dailyCalories: Double?
    
    /// Daily protein target (grams)
    /// - ADA: 15-20% of total calories (0.8g per kg body weight minimum)
    /// - General: 46g for women, 56g for men
    var dailyProtein: Double?
    
    /// Daily carbohydrate target (grams)
    /// - ADA: 45-60% of total calories, focus on complex carbs
    /// - Diabetes: 45-60g per meal (135-180g daily) for stable blood sugar
    var dailyCarbohydrates: Double?
    
    /// Daily total fat target (grams)
    /// - AHA: 25-35% of total calories
    /// - General: 44-77g for 2,000 calorie diet
    var dailyTotalFat: Double?
    
    // MARK: - Specific Fat Types
    
    /// Daily saturated fat limit (grams)
    /// - AHA: Less than 6% of total calories (13g for 2,000 cal diet)
    /// - CDC: Less than 10% of total calories
    var dailySaturatedFat: Double?
    
    /// Daily trans fat limit (grams)
    /// - AHA: As low as possible, ideally 0g
    /// - FDA: Less than 2g daily
    var dailyTransFat: Double?
    
    // MARK: - Important Minerals
    
    /// Daily sodium limit (mg)
    /// - AHA: Ideal is less than 1,500mg, maximum 2,300mg
    /// - ADA: Less than 2,300mg (1,500mg for hypertension/diabetes)
    /// - CDC: Less than 2,300mg
    var dailySodium: Double?
    
    /// Daily potassium target (mg)
    /// - AHA: 2,600-3,400mg (helps counter sodium effects)
    /// - General: 4,700mg for adults
    var dailyPotassium: Double?
    
    /// Daily calcium target (mg)
    /// - CDC: 1,000-1,200mg for adults
    var dailyCalcium: Double?
    
    // MARK: - Blood Sugar Management
    
    /// Daily sugar limit (grams)
    /// - AHA: Women max 25g (6 tsp), Men max 36g (9 tsp) added sugars
    /// - ADA: Limit added sugars, no specific amount
    var dailySugar: Double?
    
    /// Daily added sugar limit (grams)
    /// - Dietary Guidelines: Less than 10% of calories (50g for 2,000 cal diet)
    /// - AHA: Women 25g, Men 36g
    var dailyAddedSugar: Double?
    
    /// Daily fiber target (grams)
    /// - ADA: 25-30g daily (helps regulate blood sugar)
    /// - General: Women 21-25g, Men 30-38g
    var dailyFiber: Double?
    
    // MARK: - Cholesterol
    
    /// Daily cholesterol limit (mg)
    /// - AHA: Less than 300mg
    /// - ADA: Less than 200mg for those with diabetes
    var dailyCholesterol: Double?
    
    // MARK: - Goal Type & Customization
    
    /// Predefined goal template or custom
    var goalType: GoalType = .custom
    
    /// Date when goals were set
    var dateSet: Date = Date()
    
    /// Date when goals were last updated
    var dateModified: Date = Date()
    
    // MARK: - Initialization
    
    init(
        dailyCalories: Double? = nil,
        dailyProtein: Double? = nil,
        dailyCarbohydrates: Double? = nil,
        dailyTotalFat: Double? = nil,
        dailySaturatedFat: Double? = nil,
        dailyTransFat: Double? = nil,
        dailySodium: Double? = nil,
        dailyPotassium: Double? = nil,
        dailyCalcium: Double? = nil,
        dailySugar: Double? = nil,
        dailyAddedSugar: Double? = nil,
        dailyFiber: Double? = nil,
        dailyCholesterol: Double? = nil,
        goalType: GoalType = .custom,
        dateSet: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.dailyCalories = dailyCalories
        self.dailyProtein = dailyProtein
        self.dailyCarbohydrates = dailyCarbohydrates
        self.dailyTotalFat = dailyTotalFat
        self.dailySaturatedFat = dailySaturatedFat
        self.dailyTransFat = dailyTransFat
        self.dailySodium = dailySodium
        self.dailyPotassium = dailyPotassium
        self.dailyCalcium = dailyCalcium
        self.dailySugar = dailySugar
        self.dailyAddedSugar = dailyAddedSugar
        self.dailyFiber = dailyFiber
        self.dailyCholesterol = dailyCholesterol
        self.goalType = goalType
        self.dateSet = dateSet
        self.dateModified = dateModified
    }
}

// MARK: - Goal Type

enum GoalType: String, Codable, CaseIterable, Sendable {
    case custom = "Custom"
    case weightLoss = "Weight Loss"
    case diabetesManagement = "Diabetes Management"
    case heartHealth = "Heart Health"
    case generalHealth = "General Health"
    case athleticPerformance = "Athletic Performance"
    
    var icon: String {
        switch self {
        case .custom: return "slider.horizontal.3"
        case .weightLoss: return "scalemass"
        case .diabetesManagement: return "cross.case"
        case .heartHealth: return "heart.text.square"
        case .generalHealth: return "heart.circle"
        case .athleticPerformance: return "figure.run"
        }
    }
    
    var description: String {
        switch self {
        case .custom:
            return String(localized: "Personalized goals set by you", bundle: .appLanguage)
        case .weightLoss:
            return String(localized: "Calorie deficit with balanced macros", bundle: .appLanguage)
        case .diabetesManagement:
            return String(localized: "Blood sugar control and carb management", bundle: .appLanguage)
        case .heartHealth:
            return String(localized: "Low sodium, healthy fats, high fiber", bundle: .appLanguage)
        case .generalHealth:
            return String(localized: "Balanced nutrition for overall wellness", bundle: .appLanguage)
        case .athleticPerformance:
            return String(localized: "Higher protein and calories for training", bundle: .appLanguage)
        }
    }
}

// MARK: - Preset Goal Templates

extension NutritionalGoals {
    
    /// Preset goals for different health objectives
    /// Based on a 2,000 calorie baseline, adjust for individual needs
    static func preset(for type: GoalType) -> NutritionalGoals {
        switch type {
        case .custom:
            return NutritionalGoals(goalType: .custom)
            
        case .weightLoss:
            // Moderate calorie deficit with balanced macros
            // Based on ADA/CDC guidelines
            return NutritionalGoals(
                dailyCalories: 1500,           // 500 cal deficit for ~1lb/week loss
                dailyProtein: 75,              // 20% of calories (helps preserve muscle)
                dailyCarbohydrates: 169,       // 45% of calories
                dailyTotalFat: 58,             // 35% of calories
                dailySaturatedFat: 10,         // <7% of calories (AHA)
                dailyTransFat: 0,              // Minimize (AHA)
                dailySodium: 1500,             // AHA ideal limit
                dailyPotassium: 3400,          // AHA recommendation
                dailyCalcium: 1000,            // CDC recommendation
                dailySugar: 25,                // AHA limit for women
                dailyAddedSugar: 25,           // AHA limit for women
                dailyFiber: 28,                // 14g per 1000 cal (ADA)
                dailyCholesterol: 200,         // ADA limit
                goalType: .weightLoss
            )
            
        case .diabetesManagement:
            // Carb-controlled, high fiber, moderate calories
            // Based on ADA guidelines
            return NutritionalGoals(
                dailyCalories: 1800,           // Moderate for stable blood sugar
                dailyProtein: 90,              // 20% of calories
                dailyCarbohydrates: 180,       // 40% of calories (60g per meal)
                dailyTotalFat: 70,             // 35% of calories
                dailySaturatedFat: 12,         // <7% of calories (ADA)
                dailyTransFat: 0,              // Eliminate (ADA)
                dailySodium: 1500,             // ADA limit for diabetes
                dailyPotassium: 3400,          // AHA recommendation
                dailyCalcium: 1000,            // CDC recommendation
                dailySugar: 30,                // Limit added sugars (ADA)
                dailyAddedSugar: 18,           // <10% of calories
                dailyFiber: 30,                // ADA recommendation (25-30g)
                dailyCholesterol: 200,         // ADA limit for diabetes
                goalType: .diabetesManagement
            )
            
        case .heartHealth:
            // Low sodium, healthy fats, high fiber
            // Based on AHA DASH diet guidelines
            return NutritionalGoals(
                dailyCalories: 2000,           // Standard baseline
                dailyProtein: 100,             // 20% of calories
                dailyCarbohydrates: 250,       // 50% of calories
                dailyTotalFat: 67,             // 30% of calories
                dailySaturatedFat: 13,         // <6% of calories (AHA ideal)
                dailyTransFat: 0,              // Minimize (AHA)
                dailySodium: 1500,             // AHA ideal for heart health
                dailyPotassium: 4700,          // High potassium (DASH)
                dailyCalcium: 1200,            // DASH recommendation
                dailySugar: 25,                // AHA limit
                dailyAddedSugar: 25,           // AHA limit
                dailyFiber: 30,                // High fiber (AHA)
                dailyCholesterol: 200,         // AHA limit
                goalType: .heartHealth
            )
            
        case .generalHealth:
            // Balanced nutrition following Dietary Guidelines
            // Based on Dietary Guidelines for Americans
            return NutritionalGoals(
                dailyCalories: 2000,           // Standard baseline
                dailyProtein: 100,             // 20% of calories (0.8g/kg)
                dailyCarbohydrates: 275,       // 55% of calories
                dailyTotalFat: 56,             // 25% of calories
                dailySaturatedFat: 22,         // <10% of calories (CDC)
                dailyTransFat: 2,              // <1% of calories (CDC)
                dailySodium: 2300,             // CDC limit
                dailyPotassium: 3400,          // Adequate intake
                dailyCalcium: 1000,            // CDC recommendation
                dailySugar: 50,                // <10% of calories
                dailyAddedSugar: 50,           // <10% of calories
                dailyFiber: 28,                // 14g per 1000 cal
                dailyCholesterol: 300,         // General limit
                goalType: .generalHealth
            )
            
        case .athleticPerformance:
            // Higher calories and protein for training
            // Based on sports nutrition guidelines
            return NutritionalGoals(
                dailyCalories: 2800,           // Higher for energy needs
                dailyProtein: 140,             // 20% of calories (1.2-2.0g/kg)
                dailyCarbohydrates: 385,       // 55% of calories (fuel for activity)
                dailyTotalFat: 78,             // 25% of calories
                dailySaturatedFat: 31,         // <10% of calories
                dailyTransFat: 2,              // Minimize
                dailySodium: 3000,             // Higher for sweat losses
                dailyPotassium: 4700,          // Replace losses
                dailyCalcium: 1200,            // Bone health
                dailySugar: 70,                // Some for quick energy
                dailyAddedSugar: 56,           // <10% of calories
                dailyFiber: 35,                // Higher intake
                dailyCholesterol: 300,         // General limit
                goalType: .athleticPerformance
            )
        }
    }
    
    /// Check if all goals are set (no nil values for critical fields)
    var isComplete: Bool {
        return dailyCalories != nil &&
               dailySodium != nil &&
               dailyTotalFat != nil &&
               dailyCarbohydrates != nil
    }
    
    /// Get a summary of unset goals
    var missingGoals: [String] {
        var missing: [String] = []
        
        if dailyCalories == nil { missing.append("Calories") }
        if dailyProtein == nil { missing.append("Protein") }
        if dailyCarbohydrates == nil { missing.append("Carbohydrates") }
        if dailyTotalFat == nil { missing.append("Total Fat") }
        if dailySaturatedFat == nil { missing.append("Saturated Fat") }
        if dailySodium == nil { missing.append("Sodium") }
        if dailyFiber == nil { missing.append("Fiber") }
        if dailySugar == nil { missing.append("Sugar") }
        
        return missing
    }
}

// MARK: - Display Helpers

extension NutritionalGoals {
    
    /// Format a nutrient value with appropriate units
    func formatNutrient(_ value: Double?, unit: String) -> String {
        guard let value = value else { return "Not set" }
        return String(format: "%.0f%@", value, unit)
    }
    
    /// Get all goals as displayable key-value pairs
    var displayableGoals: [(name: String, value: String, unit: String, icon: String)] {
        var goals: [(name: String, value: String, unit: String, icon: String)] = []
        
        if let calories = dailyCalories {
            goals.append(("Calories", String(format: "%.0f", calories), "kcal", "flame.fill"))
        }
        
        if let protein = dailyProtein {
            goals.append(("Protein", String(format: "%.0f", protein), "g", "p.circle.fill"))
        }
        
        if let carbs = dailyCarbohydrates {
            goals.append(("Carbohydrates", String(format: "%.0f", carbs), "g", "c.circle.fill"))
        }
        
        if let fat = dailyTotalFat {
            goals.append(("Total Fat", String(format: "%.0f", fat), "g", "f.circle.fill"))
        }
        
        if let satFat = dailySaturatedFat {
            goals.append(("Saturated Fat", String(format: "%.0f", satFat), "g", "exclamationmark.triangle.fill"))
        }
        
        if let sodium = dailySodium {
            goals.append(("Sodium", String(format: "%.0f", sodium), "mg", "drop.fill"))
        }
        
        if let fiber = dailyFiber {
            goals.append(("Fiber", String(format: "%.0f", fiber), "g", "leaf.fill"))
        }
        
        if let sugar = dailySugar {
            goals.append(("Sugar", String(format: "%.0f", sugar), "g", "cube.fill"))
        }
        
        return goals
    }
}

// MARK: - Documentation

/*
 MEDICAL SOURCES AND GUIDELINES
 ================================
 
 This implementation is based on guidelines from:
 
 1. AMERICAN HEART ASSOCIATION (AHA)
    - Sodium: Ideal <1,500mg, Max 2,300mg
    - Saturated Fat: <6% of total calories
    - Trans Fat: As low as possible
    - Added Sugar: Women 25g, Men 36g
    - Source: heart.org/en/healthy-living/healthy-eating
 
 2. AMERICAN DIABETES ASSOCIATION (ADA)
    - Carbohydrates: 45-60g per meal (135-180g daily)
    - Fiber: 25-30g daily
    - Saturated Fat: <7% of calories
    - Cholesterol: <200mg for diabetes
    - Source: diabetes.org/food-and-nutrition
 
 3. CENTERS FOR DISEASE CONTROL (CDC)
    - Sodium: <2,300mg
    - Saturated Fat: <10% of calories
    - Added Sugars: <10% of calories
    - Source: cdc.gov/nutrition
 
 4. DIETARY GUIDELINES FOR AMERICANS 2020-2025
    - Published by USDA and HHS
    - Comprehensive nutrition recommendations
    - Source: dietaryguidelines.gov
 
 USAGE NOTES
 ===========
 
 - All values are DAILY targets
 - Values should be adjusted based on:
   * Individual health conditions
   * Activity level
   * Age and gender
   * Weight management goals
   * Medical advice from healthcare provider
 
 - These are GENERAL GUIDELINES
 - Users should consult healthcare professionals for personalized advice
 - This is for informational purposes, not medical advice
 
 CUSTOMIZATION
 =============
 
 Users can:
 - Start with a preset template
 - Modify any individual goal
 - Leave some goals unset if not tracking
 - Update goals over time as needs change
 
 */
