//
//  FODMAPAnalyzer.swift
//  Reczipes2
//
//  FODMAP-specific analysis based on Monash University FODMAP research
//  Created on 12/17/25.
//

import Foundation

// MARK: - FODMAP Categories

/// The four FODMAP categories based on Monash University research
enum FODMAPCategory: String, Codable, CaseIterable, Hashable {
    case oligosaccharides = "Oligosaccharides"  // Fructans & GOS
    case disaccharides = "Disaccharides"        // Lactose
    case monosaccharides = "Monosaccharides"    // Excess Fructose
    case polyols = "Polyols"                    // Sugar Alcohols
    
    var description: String {
        switch self {
        case .oligosaccharides:
            return "Fructans & Galacto-oligosaccharides (GOS)"
        case .disaccharides:
            return "Lactose"
        case .monosaccharides:
            return "Excess Fructose"
        case .polyols:
            return "Sugar Alcohols (Sorbitol, Mannitol, etc.)"
        }
    }
    
    var icon: String {
        switch self {
        case .oligosaccharides: return "🧅" // Onions/garlic
        case .disaccharides: return "🥛"    // Milk
        case .monosaccharides: return "🍯"  // Honey
        case .polyols: return "🍎"          // Apples
        }
    }
    
    var examples: [String] {
        switch self {
        case .oligosaccharides:
            return ["Onions", "Garlic", "Wheat", "Legumes", "Cashews"]
        case .disaccharides:
            return ["Milk", "Yogurt", "Soft Cheese", "Ice Cream"]
        case .monosaccharides:
            return ["Honey", "Apples", "Pears", "Mangoes"]
        case .polyols:
            return ["Mushrooms", "Cauliflower", "Stone Fruits", "Sugar Alcohols"]
        }
    }
}

/// FODMAP level classifications
enum FODMAPLevel: String, Codable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    
    var color: String {
        switch self {
        case .low: return "green"
        case .moderate: return "orange"
        case .high: return "red"
        }
    }
    
    var scoreValue: Double {
        switch self {
        case .low: return 0.0
        case .moderate: return 3.0
        case .high: return 10.0
        }
    }
}

// MARK: - FODMAP Food Data

/// Comprehensive FODMAP food database based on Monash University
struct FODMAPFoodData {
    let name: String
    let categories: [FODMAPCategory]
    let level: FODMAPLevel
    let servingSize: String?
    let notes: String?
    
    /// Monash University verified high FODMAP foods
    static let highFODMAPFoods: [FODMAPFoodData] = [
        // OLIGOSACCHARIDES - Fructans
        FODMAPFoodData(name: "wheat", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "Contains fructans"),
        FODMAPFoodData(name: "rye", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "Contains fructans"),
        FODMAPFoodData(name: "barley", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "Contains fructans"),
        FODMAPFoodData(name: "onion", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "Very high in fructans"),
        FODMAPFoodData(name: "garlic", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "Very high in fructans"),
        FODMAPFoodData(name: "shallot", categories: [.oligosaccharides], level: .high, servingSize: "any amount", notes: "High in fructans"),
        FODMAPFoodData(name: "leek", categories: [.oligosaccharides], level: .high, servingSize: "bulb", notes: "Leek leaves are low FODMAP"),
        FODMAPFoodData(name: "spring onion", categories: [.oligosaccharides], level: .high, servingSize: "white part", notes: "Green tops are low FODMAP"),
        FODMAPFoodData(name: "artichoke", categories: [.oligosaccharides], level: .high, servingSize: ">1/4 globe", notes: "High in fructans"),
        FODMAPFoodData(name: "asparagus", categories: [.oligosaccharides], level: .high, servingSize: ">1 spear", notes: "Moderate-high in fructans"),
        FODMAPFoodData(name: "beetroot", categories: [.oligosaccharides], level: .high, servingSize: ">2 slices", notes: "Moderate in fructans"),
        FODMAPFoodData(name: "brussels sprout", categories: [.oligosaccharides], level: .high, servingSize: ">2 sprouts", notes: "Moderate in fructans"),
        FODMAPFoodData(name: "cabbage", categories: [.oligosaccharides], level: .high, servingSize: "savoy >1/4 cup", notes: "Savoy cabbage higher than others"),
        
        // OLIGOSACCHARIDES - GOS
        FODMAPFoodData(name: "chickpea", categories: [.oligosaccharides], level: .high, servingSize: ">1/4 cup", notes: "High in GOS"),
        FODMAPFoodData(name: "kidney bean", categories: [.oligosaccharides], level: .high, servingSize: ">1/4 cup", notes: "High in GOS"),
        FODMAPFoodData(name: "black bean", categories: [.oligosaccharides], level: .high, servingSize: ">1/4 cup", notes: "High in GOS"),
        FODMAPFoodData(name: "lentil", categories: [.oligosaccharides], level: .high, servingSize: ">1/2 cup canned", notes: "High in GOS"),
        FODMAPFoodData(name: "soy bean", categories: [.oligosaccharides], level: .high, servingSize: ">1/4 cup", notes: "High in GOS"),
        FODMAPFoodData(name: "cashew", categories: [.oligosaccharides], level: .high, servingSize: ">10 nuts", notes: "High in GOS and fructans"),
        FODMAPFoodData(name: "pistachio", categories: [.oligosaccharides], level: .high, servingSize: ">15 nuts", notes: "High in GOS and fructans"),
        
        // DISACCHARIDES - Lactose
        FODMAPFoodData(name: "milk", categories: [.disaccharides], level: .high, servingSize: ">1/2 cup", notes: "Contains lactose"),
        FODMAPFoodData(name: "yogurt", categories: [.disaccharides], level: .high, servingSize: "regular", notes: "Greek yogurt lower"),
        FODMAPFoodData(name: "ice cream", categories: [.disaccharides], level: .high, servingSize: "any amount", notes: "High in lactose"),
        FODMAPFoodData(name: "soft cheese", categories: [.disaccharides], level: .high, servingSize: "varies", notes: "Cottage cheese, ricotta high"),
        FODMAPFoodData(name: "cream", categories: [.disaccharides], level: .high, servingSize: ">1/4 cup", notes: "Contains lactose"),
        FODMAPFoodData(name: "custard", categories: [.disaccharides], level: .high, servingSize: "any amount", notes: "Made with milk"),
        
        // MONOSACCHARIDES - Excess Fructose
        FODMAPFoodData(name: "honey", categories: [.monosaccharides], level: .high, servingSize: "any amount", notes: "Very high in fructose"),
        FODMAPFoodData(name: "agave", categories: [.monosaccharides], level: .high, servingSize: "any amount", notes: "Very high in fructose"),
        FODMAPFoodData(name: "apple", categories: [.monosaccharides], level: .high, servingSize: ">1/2 medium", notes: "High in fructose"),
        FODMAPFoodData(name: "pear", categories: [.monosaccharides], level: .high, servingSize: ">1/2 medium", notes: "High in fructose"),
        FODMAPFoodData(name: "mango", categories: [.monosaccharides], level: .high, servingSize: ">1/2 cup", notes: "High in fructose"),
        FODMAPFoodData(name: "watermelon", categories: [.monosaccharides], level: .high, servingSize: ">1 cup", notes: "High in fructose"),
        FODMAPFoodData(name: "fig", categories: [.monosaccharides], level: .high, servingSize: ">1 medium", notes: "High in fructose"),
        FODMAPFoodData(name: "asparagus", categories: [.monosaccharides, .oligosaccharides], level: .high, servingSize: ">1 spear", notes: "Contains fructose and fructans"),
        
        // POLYOLS
        FODMAPFoodData(name: "apple", categories: [.polyols, .monosaccharides], level: .high, servingSize: ">1/2 medium", notes: "High in sorbitol"),
        FODMAPFoodData(name: "apricot", categories: [.polyols], level: .high, servingSize: ">1 medium", notes: "High in sorbitol"),
        FODMAPFoodData(name: "avocado", categories: [.polyols], level: .high, servingSize: ">1/4 fruit", notes: "High in sorbitol"),
        FODMAPFoodData(name: "blackberry", categories: [.polyols], level: .high, servingSize: ">10 berries", notes: "Moderate in polyols"),
        FODMAPFoodData(name: "cherry", categories: [.polyols], level: .high, servingSize: ">3 cherries", notes: "High in sorbitol"),
        FODMAPFoodData(name: "nectarine", categories: [.polyols], level: .high, servingSize: ">1/2 medium", notes: "High in sorbitol"),
        FODMAPFoodData(name: "peach", categories: [.polyols], level: .high, servingSize: ">1 medium", notes: "High in sorbitol"),
        FODMAPFoodData(name: "pear", categories: [.polyols, .monosaccharides], level: .high, servingSize: ">1/2 medium", notes: "High in sorbitol and fructose"),
        FODMAPFoodData(name: "plum", categories: [.polyols], level: .high, servingSize: ">1 medium", notes: "High in sorbitol"),
        FODMAPFoodData(name: "prune", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Very high in sorbitol"),
        FODMAPFoodData(name: "mushroom", categories: [.polyols], level: .high, servingSize: ">1/2 cup", notes: "High in mannitol"),
        FODMAPFoodData(name: "cauliflower", categories: [.polyols], level: .high, servingSize: ">1/2 cup", notes: "Moderate-high in mannitol"),
        FODMAPFoodData(name: "snow pea", categories: [.polyols], level: .high, servingSize: ">5 pods", notes: "Moderate in mannitol"),
        FODMAPFoodData(name: "sweet corn", categories: [.polyols], level: .high, servingSize: ">1/2 cob", notes: "Moderate in sorbitol"),
        
        // Sugar alcohols (added to foods)
        FODMAPFoodData(name: "sorbitol", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Artificial sweetener"),
        FODMAPFoodData(name: "mannitol", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Artificial sweetener"),
        FODMAPFoodData(name: "xylitol", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Artificial sweetener"),
        FODMAPFoodData(name: "maltitol", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Artificial sweetener"),
        FODMAPFoodData(name: "isomalt", categories: [.polyols], level: .high, servingSize: "any amount", notes: "Artificial sweetener"),
    ]
    
    /// Get FODMAP data for a specific ingredient
    static func getFODMAPData(for ingredient: String) -> FODMAPFoodData? {
        let lowercased = ingredient.lowercased()
        
        // First, check for exceptions - ingredients that should NOT match
        let exceptions: [String: [String]] = [
            "apple": ["apple cider vinegar", "apple cider", "cider vinegar", "vinegar"],
            "pear": ["pear vinegar"],
            "cherry": ["cherry tomato"],
            "milk": ["coconut milk", "almond milk", "oat milk", "rice milk", "soy milk"]
        ]
        
        return highFODMAPFoods.first { food in
            let foodName = food.name.lowercased()
            
            // Check if this ingredient is in the exception list for this food
            if let foodExceptions = exceptions[foodName] {
                for exception in foodExceptions {
                    if lowercased.contains(exception) {
                        return false // Don't match exceptions
                    }
                }
            }
            
            // Use word boundary matching to avoid partial matches
            // This ensures "apple" matches "apple" or "apples" but not "pineapple"
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: foodName))s?\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lowercased.startIndex..., in: lowercased)
                return regex.firstMatch(in: lowercased, range: range) != nil
            }
            
            // Fallback to contains if regex fails
            return lowercased.contains(foodName)
        }
    }
}

// MARK: - FODMAP Analysis Result

struct FODMAPAnalysisResult: Identifiable {
    let id = UUID()
    let recipeID: UUID
    let overallScore: Double
    let categoryBreakdown: [FODMAPCategory: FODMAPCategoryScore]
    let detectedFoods: [DetectedFODMAPFood]
    let recommendation: FODMAPRecommendation
    let lowFODMAPAlternatives: [String]
    
    var isSafe: Bool {
        recommendation == .safe
    }
    
    var summary: String {
        if isSafe {
            return "Low FODMAP - Generally suitable"
        }
        let count = detectedFoods.count
        return "\(count) high FODMAP ingredient\(count == 1 ? "" : "s") detected"
    }
}

struct FODMAPCategoryScore {
    let category: FODMAPCategory
    let score: Double
    let level: FODMAPLevel
    let detectedIngredients: [String]
}

struct DetectedFODMAPFood: Identifiable {
    let id = UUID()
    let foodData: FODMAPFoodData
    let matchedIngredient: String
    let portionConcern: Bool // True if portion size matters
}

enum FODMAPRecommendation: String {
    case safe = "Safe - Low FODMAP"
    case caution = "Caution - Moderate FODMAP"
    case modify = "Modify - Reduce portions or substitute"
    case avoid = "Avoid - High FODMAP"
    
    var color: String {
        switch self {
        case .safe: return "green"
        case .caution: return "yellow"
        case .modify: return "orange"
        case .avoid: return "red"
        }
    }
}

// MARK: - FODMAP Analyzer

class FODMAPAnalyzer {
    static let shared = FODMAPAnalyzer()
    
    private init() {}
    
    /// Analyze a recipe for FODMAP content
    func analyzeRecipe(_ recipe: RecipeX) -> FODMAPAnalysisResult {
        var detectedFoods: [DetectedFODMAPFood] = []
        var categoryScores: [FODMAPCategory: Double] = [:]
        var categoryIngredients: [FODMAPCategory: [String]] = [:]
        
        // Initialize category tracking
        for category in FODMAPCategory.allCases {
            categoryScores[category] = 0.0
            categoryIngredients[category] = []
        }
        
        // Analyze each ingredient
        let ingredients = extractAllIngredients(from: recipe)
        for ingredient in ingredients {
            if let foodData = FODMAPFoodData.getFODMAPData(for: ingredient) {
                // Add to detected foods
                let detected = DetectedFODMAPFood(
                    foodData: foodData,
                    matchedIngredient: ingredient,
                    portionConcern: foodData.servingSize != nil && foodData.servingSize != "any amount"
                )
                detectedFoods.append(detected)
                
                // Update category scores
                for category in foodData.categories {
                    categoryScores[category, default: 0.0] += foodData.level.scoreValue
                    categoryIngredients[category, default: []].append(ingredient)
                }
            }
        }
        
        // Calculate overall score
        let totalScore = categoryScores.values.reduce(0, +)
        
        // Create category breakdown
        var categoryBreakdown: [FODMAPCategory: FODMAPCategoryScore] = [:]
        for category in FODMAPCategory.allCases {
            let score = categoryScores[category] ?? 0.0
            let level: FODMAPLevel
            if score == 0 { level = .low }
            else if score < 10 { level = .moderate }
            else { level = .high }
            
            categoryBreakdown[category] = FODMAPCategoryScore(
                category: category,
                score: score,
                level: level,
                detectedIngredients: categoryIngredients[category] ?? []
            )
        }
        
        // Determine recommendation
        let recommendation: FODMAPRecommendation
        if totalScore == 0 {
            recommendation = .safe
        } else if totalScore < 10 {
            recommendation = .caution
        } else if totalScore < 30 {
            recommendation = .modify
        } else {
            recommendation = .avoid
        }
        
        // Get alternatives
        let alternatives = getLowFODMAPAlternatives(for: detectedFoods)
        
        return FODMAPAnalysisResult(
            recipeID: recipe.safeID,
            overallScore: totalScore,
            categoryBreakdown: categoryBreakdown,
            detectedFoods: detectedFoods,
            recommendation: recommendation,
            lowFODMAPAlternatives: alternatives
        )
    }
    
    private func extractAllIngredients(from recipe: RecipeX) -> [String] {
        var ingredients: [String] = []
        for section in recipe.ingredientSections {
            for ingredient in section.ingredients {
                ingredients.append(ingredient.name)
                if let prep = ingredient.preparation {
                    ingredients.append(prep)
                }
            }
        }
        return ingredients
    }
    
    private func getLowFODMAPAlternatives(for detectedFoods: [DetectedFODMAPFood]) -> [String] {
        var alternatives: [String] = []
        
        for detected in detectedFoods {
            let food = detected.foodData.name
            
            // Common FODMAP substitutions based on Monash University
            switch food {
            case "onion", "onions":
                alternatives.append("Use green tops of spring onions only")
                alternatives.append("Use garlic-infused oil (no solids)")
                alternatives.append("Use asafoetida powder (hing)")
            case "garlic":
                alternatives.append("Use garlic-infused oil (strain out solids)")
                alternatives.append("Use asafoetida powder (hing)")
            case "wheat", "wheat flour":
                alternatives.append("Use gluten-free flour blend")
                alternatives.append("Use rice flour")
                alternatives.append("Use sourdough spelt bread (fermented >4 hours)")
            case "milk":
                alternatives.append("Use lactose-free milk")
                alternatives.append("Use almond milk (small amounts)")
                alternatives.append("Use rice milk")
            case "apple", "apples":
                alternatives.append("Use banana (1 medium)")
                alternatives.append("Use blueberries (1/4 cup)")
                alternatives.append("Use strawberries (10 medium)")
            case "honey":
                alternatives.append("Use maple syrup")
                alternatives.append("Use glucose syrup")
                alternatives.append("Use table sugar (sucrose)")
            case "beans", "kidney bean", "black bean":
                alternatives.append("Use canned lentils, rinsed (1/2 cup)")
                alternatives.append("Use firm tofu")
                alternatives.append("Use tempeh (small amounts)")
            case "mushroom", "mushrooms":
                alternatives.append("Use eggplant")
                alternatives.append("Use zucchini")
                alternatives.append("Use oyster mushrooms (small amounts)")
            case "yogurt":
                alternatives.append("Use lactose-free yogurt")
                alternatives.append("Use coconut yogurt (check ingredients)")
            case "cashew", "cashews":
                alternatives.append("Use macadamias (up to 20 nuts)")
                alternatives.append("Use peanuts (32 nuts)")
                alternatives.append("Use pecans (10 nuts)")
            default:
                break
            }
        }
        
        return Array(Set(alternatives)) // Remove duplicates
    }
    
    /// Generate enhanced Claude prompt for FODMAP analysis
    func generateClaudeFODMAPPrompt(recipe: RecipeX) -> String {
        let ingredients = extractAllIngredients(from: recipe).joined(separator: ", ")
        
        return """
        Perform a comprehensive FODMAP analysis of this recipe based on Monash University FODMAP research.
        
        Recipe: \(recipe.safeTitle)
        Ingredients: \(ingredients)
        
        Please analyze this recipe according to the four FODMAP categories:
        
        1. **Oligosaccharides** (Fructans & GOS)
           - Check for: wheat, rye, barley, onions, garlic, beans, lentils, chickpeas
           
        2. **Disaccharides** (Lactose)
           - Check for: milk, cream, yogurt, soft cheeses, ice cream
           
        3. **Monosaccharides** (Excess Fructose)
           - Check for: honey, agave, apples, pears, mangoes, high-fructose foods
           
        4. **Polyols** (Sugar Alcohols)
           - Check for: sorbitol, mannitol, xylitol, apples, pears, stone fruits, mushrooms, cauliflower
        
        For each detected HIGH FODMAP ingredient:
        - Identify which FODMAP category/categories it belongs to
        - Note if portion size affects FODMAP level (some foods are low in small amounts)
        - Suggest LOW FODMAP alternatives from Monash University data
        - Consider hidden FODMAPs (e.g., garlic powder in seasonings, wheat in soy sauce)
        
        Important considerations:
        - Green onion/scallion tops are LOW FODMAP (white parts are HIGH)
        - Garlic-infused oil is LOW FODMAP if solids are strained out
        - Firm tofu is LOW FODMAP but silken tofu is MODERATE
        - Hard cheeses (cheddar, parmesan) are LOW FODMAP
        - Lactose-free dairy is LOW FODMAP
        - Sourdough spelt bread (properly fermented) can be LOW FODMAP
        
        Response format (JSON):
        {
            "overallScore": 0-100,
            "recommendation": "safe|caution|modify|avoid",
            "categoryBreakdown": {
                "oligosaccharides": {"level": "low|moderate|high", "detectedIngredients": []},
                "disaccharides": {"level": "low|moderate|high", "detectedIngredients": []},
                "monosaccharides": {"level": "low|moderate|high", "detectedIngredients": []},
                "polyols": {"level": "low|moderate|high", "detectedIngredients": []}
            },
            "detectedFODMAPs": [
                {
                    "ingredient": "ingredient name",
                    "fodmapType": ["oligosaccharides"],
                    "level": "high",
                    "portionMatters": true/false,
                    "servingGuidance": "safe portion if applicable",
                    "alternatives": ["alternative 1", "alternative 2"]
                }
            ],
            "modificationSuggestions": [
                "Specific suggestion to make recipe low FODMAP"
            ],
            "monashNotes": "Additional guidance from Monash University FODMAP data",
            "overallGuidance": "Summary recommendation for someone following low FODMAP diet"
        }
        
        Base your analysis on current Monash University FODMAP research and guidelines.
        """
    }
}

// MARK: - Claude FODMAP Response Models

struct ClaudeFODMAPAnalysis: Codable {
    let overallScore: Double
    let recommendation: String
    let categoryBreakdown: [String: ClaudeFODMAPCategory]
    let detectedFODMAPs: [ClaudeDetectedFODMAP]
    let modificationSuggestions: [String]
    let monashNotes: String?
    let overallGuidance: String
}

struct ClaudeFODMAPCategory: Codable {
    let level: String  // "low", "moderate", "high"
    let detectedIngredients: [String]
}

struct ClaudeDetectedFODMAP: Codable {
    let ingredient: String
    let fodmapType: [String]
    let level: String
    let portionMatters: Bool
    let servingGuidance: String?
    let alternatives: [String]
}

// MARK: - Enhanced FODMAP Score with Claude

struct EnhancedFODMAPScore: Identifiable {
    let id = UUID()
    let basicAnalysis: FODMAPAnalysisResult
    let claudeAnalysis: ClaudeFODMAPAnalysis?
    let recipe: RecipeX
    
    var combinedRecommendation: FODMAPRecommendation {
        guard let claude = claudeAnalysis else {
            return basicAnalysis.recommendation
        }
        
        // Use Claude's recommendation if available
        switch claude.recommendation.lowercased() {
        case "safe": return .safe
        case "caution": return .caution
        case "modify": return .modify
        case "avoid": return .avoid
        default: return basicAnalysis.recommendation
        }
    }
    
    var allAlternatives: [String] {
        var alternatives = basicAnalysis.lowFODMAPAlternatives
        if let claude = claudeAnalysis {
            for detected in claude.detectedFODMAPs {
                alternatives.append(contentsOf: detected.alternatives)
            }
        }
        return Array(Set(alternatives)).sorted()
    }
    
    var modificationTips: [String] {
        claudeAnalysis?.modificationSuggestions ?? []
    }
}

// MARK: - Extension to AllergenAnalyzer for FODMAP

extension AllergenAnalyzer {
    
    /// Analyze recipe for FODMAPs using both local and Claude analysis
    func analyzeFODMAP(
        _ recipe: RecipeX,
        apiKey: String
    ) async throws -> EnhancedFODMAPScore {
        // 1. Get basic FODMAP analysis
        let basicAnalysis = FODMAPAnalyzer.shared.analyzeRecipe(recipe)
        
        // 2. Generate Claude prompt
        let prompt = FODMAPAnalyzer.shared.generateClaudeFODMAPPrompt(recipe: recipe)
        
        // 3. Call Claude API
        do {
            let claudeResponse = try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
            
            // 4. Parse Claude's response
            if let data = claudeResponse.data(using: .utf8),
               let analysis = try? JSONDecoder().decode(ClaudeFODMAPAnalysis.self, from: data) {
                return EnhancedFODMAPScore(
                    basicAnalysis: basicAnalysis,
                    claudeAnalysis: analysis,
                    recipe: recipe
                )
            }
        } catch {
            AppLog.error("Claude FODMAP analysis failed: \(error)", category: .fodmap)
        }
        
        // Return basic analysis if Claude fails
        return EnhancedFODMAPScore(
            basicAnalysis: basicAnalysis,
            claudeAnalysis: nil,
            recipe: recipe
        )
    }
}
