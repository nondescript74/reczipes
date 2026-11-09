//
//  AllergenProfile.swift
//  Reczipes2
//
//  Created on 12/17/25.
//

import Foundation
import SwiftData

// MARK: - Allergen & Sensitivity Types

enum FoodAllergen: String, Codable, CaseIterable, Identifiable, Sendable {
    case milk = "Milk"
    case eggs = "Eggs"
    case peanuts = "Peanuts"
    case treeNuts = "Tree Nuts"
    case wheat = "Wheat"
    case soy = "Soy"
    case fish = "Fish"
    case shellfish = "Shellfish"
    case sesame = "Sesame"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .milk: return "🥛"
        case .eggs: return "🥚"
        case .peanuts: return "🥜"
        case .treeNuts: return "🌰"
        case .wheat: return "🌾"
        case .soy: return "🫘"
        case .fish: return "🐟"
        case .shellfish: return "🦐"
        case .sesame: return "🫘"
        }
    }
    
    var category: String { "Big 9 Allergens" }
    
    // Common ingredient names that contain this allergen
    var ingredientKeywords: [String] {
        switch self {
        case .milk:
            return ["milk", "cream", "butter", "cheese", "yogurt", "whey", "casein", "lactose", "ghee", "buttermilk", "sour cream", "ice cream", "half-and-half", "evaporated milk", "condensed milk", "dairy"]
        case .eggs:
            return ["egg", "eggs", "mayonnaise", "meringue", "albumin", "lysozyme", "ovalbumin"]
        case .peanuts:
            return ["peanut", "peanuts", "peanut butter", "groundnut", "goober"]
        case .treeNuts:
            return ["almond", "almonds", "cashew", "cashews", "walnut", "walnuts", "pecan", "pecans", "pistachio", "pistachios", "hazelnut", "hazelnuts", "macadamia", "pine nut", "pine nuts", "brazil nut"]
        case .wheat:
            return ["wheat", "flour", "bread", "pasta", "bulgur", "couscous", "farina", "semolina", "spelt", "kamut", "durum"]
        case .soy:
            return ["soy", "soya", "tofu", "edamame", "miso", "tempeh", "soy sauce", "tamari", "lecithin"]
        case .fish:
            return ["fish", "salmon", "tuna", "cod", "halibut", "bass", "trout", "anchovy", "anchovies", "sardine", "sardines", "worcestershire"]
        case .shellfish:
            return ["shrimp", "crab", "lobster", "crayfish", "prawn", "prawns", "clam", "clams", "oyster", "oysters", "mussel", "mussels", "scallop", "scallops"]
        case .sesame:
            return ["sesame", "tahini", "sesame oil", "sesame seed"]
        }
    }
}

enum FoodIntolerance: String, Codable, CaseIterable, Identifiable, Sendable {
    case gluten = "Gluten"
    case lactose = "Lactose"
    case caffeine = "Caffeine"
    case histamine = "Histamine"
    case salicylates = "Salicylates"
    case sulfites = "Sulfites"
    case fodmap = "FODMAPs"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .gluten: return "🌾"
        case .lactose: return "🥛"
        case .caffeine: return "☕️"
        case .histamine: return "🍷"
        case .salicylates: return "🫐"
        case .sulfites: return "🍇"
        case .fodmap: return "🧅"
        }
    }
    
    var category: String { "Intolerances" }
    
    var ingredientKeywords: [String] {
        switch self {
        case .gluten:
            return ["wheat", "barley", "rye", "flour", "bread", "pasta", "couscous", "bulgur", "semolina", "spelt", "farina", "kamut", "triticale", "malt", "brewer's yeast"]
        case .lactose:
            return ["milk", "cream", "lactose", "dairy", "buttermilk", "ice cream", "yogurt", "kefir", "sour cream", "evaporated milk", "condensed milk"]
        case .caffeine:
            return ["coffee", "tea", "espresso", "chocolate", "cocoa", "cola", "energy drink", "green tea", "black tea", "matcha", "yerba mate"]
        case .histamine:
            return ["wine", "beer", "champagne", "vinegar", "sauerkraut", "kimchi", "aged cheese", "parmesan", "salami", "pepperoni", "sausage", "smoked", "fermented", "yeast extract", "soy sauce", "miso", "tempeh", "spinach", "eggplant", "tomato", "avocado", "banana"]
        case .salicylates:
            return ["almond", "apple", "apricot", "berry", "berries", "cherry", "cucumber", "grape", "grapes", "orange", "peach", "plum", "raisin", "raisins", "strawberry", "strawberries", "raspberry", "raspberries", "blueberry", "blueberries", "blackberry", "blackberries", "tomato", "pepper", "peppers", "zucchini", "radish", "chicory", "endive"]
        case .sulfites:
            return ["wine", "dried fruit", "molasses", "vinegar", "pickled", "grape", "grapes", "lemon juice", "lime juice", "shrimp", "lobster", "scallop", "scallops", "wine vinegar"]
        case .fodmap:
            // Comprehensive FODMAP keywords based on Monash University research
            // Organized by FODMAP categories: Oligosaccharides, Disaccharides, Monosaccharides, Polyols
            return [
                // OLIGOSACCHARIDES (Fructans & GOS)
                // Fructans - High
                "wheat", "rye", "barley", "onion", "onions", "garlic", "shallot", "shallots", "leek", "leeks",
                "spring onion", "scallion", "scallions", "green onion",
                "artichoke", "asparagus", "beetroot", "beet", "brussels sprout", "brussels sprouts",
                "cabbage", "savoy cabbage", "fennel", "okra",
                "rambutan", "watermelon", "white peach", "nectarine", "persimmon", "tamarillo",
                "pistachio", "pistachios", "cashew", "cashews",
                "chickpea", "chickpeas", "garbanzo", "garbanzos",
                // GOS - High
                "bean", "beans", "kidney bean", "black bean", "pinto bean", "navy bean",
                "lentil", "lentils", "split pea", "split peas",
                "soy bean", "soybeans", "edamame", "soy milk",
                "almond", "almonds",
                
                // DISACCHARIDES (Lactose)
                "milk", "cow's milk", "goat's milk", "sheep's milk",
                "cream", "heavy cream", "whipping cream", "sour cream", "crème fraîche",
                "ice cream", "gelato",
                "yogurt", "yoghurt", "kefir",
                "buttermilk", "evaporated milk", "condensed milk", "sweetened condensed milk",
                "custard", "pudding",
                "cottage cheese", "ricotta", "cream cheese",
                "soft cheese", "fresh cheese",
                // Note: Hard cheeses and butter are usually low FODMAP
                
                // MONOSACCHARIDES (Excess Fructose)
                "honey", "agave", "agave nectar", "agave syrup",
                "high fructose corn syrup", "corn syrup", "hfcs",
                "apple", "apples", "pear", "pears", "mango", "mangoes",
                "watermelon", "cherry", "cherries", "fig", "figs",
                "guava", "longan", "lychee", "papaya", "persimmon",
                "sugar snap pea", "snow pea",
                "asparagus",
                "fruit juice concentrate", "apple juice", "pear juice", "mango juice",
                
                // POLYOLS (Sugar Alcohols)
                "sorbitol", "mannitol", "xylitol", "maltitol", "isomalt", "erythritol",
                "sugar-free", "sugarfree", "diet", "no sugar added",
                "apple", "apples", "apricot", "apricots", "avocado", "avocados",
                "blackberry", "blackberries", "cherry", "cherries",
                "lychee", "longan", "nectarine", "nectarines", "peach", "peaches", "pear", "pears",
                "plum", "plums", "prune", "prunes", "watermelon",
                "cauliflower", "mushroom", "mushrooms", "snow pea", "snow peas",
                "sweet corn", "baby corn",
                "chewing gum", "gum", "breath mint", "mints",
                
                // VEGETABLES - Additional High FODMAP
                "artichoke", "artichoke hearts",
                "baked beans", "refried beans",
                "celery", "chicory", "endive",
                "peas", "green peas", "split peas",
                "sugar snap peas",
                "sun-dried tomato", "sun dried tomato",
                
                // FRUITS - Additional High FODMAP
                "boysenberry", "boysenberries",
                "cranberry", "dried cranberries",
                "date", "dates",
                "dried fruit", "dried apricot", "raisin", "raisins",
                "grapefruit",
                "tamarind", "tamarindo",
                
                // GRAINS & CEREALS - High FODMAP
                "wheat flour", "all-purpose flour", "plain flour", "whole wheat", "wholemeal",
                "bread", "white bread", "wheat bread", "sourdough", "rye bread",
                "pasta", "spaghetti", "noodles", "wheat noodles", "egg noodles",
                "couscous", "bulgur", "farro", "freekeh",
                "bran", "wheat bran", "oat bran",
                "muesli", "granola",
                "rye crackers", "wheat crackers",
                
                // LEGUMES - High FODMAP
                "black-eyed pea", "black eyed pea",
                "broad bean", "fava bean", "lima bean",
                "baked bean", "baked beans",
                "hummus", "houmous",
                "falafel",
                
                // NUTS - High FODMAP
                "cashew butter", "pistachio", "pistachios",
                
                // SWEETENERS - High FODMAP
                "fructose", "fruit sugar",
                "honey", "honeycomb",
                "golden syrup", "molasses", "treacle",
                "inulin", "fos", "fructooligosaccharides",
                
                // CONDIMENTS & SAUCES - High FODMAP
                "garlic powder", "garlic salt", "garlic paste", "garlic oil" /* if has solids */,
                "onion powder", "onion salt", "onion flakes",
                "bbq sauce", "barbecue sauce", "ketchup" /* some brands */,
                "relish", "pickle relish", "chutney",
                "stock", "bouillon", "broth" /* if contains onion/garlic */,
                
                // BEVERAGES - High FODMAP
                "apple juice", "pear juice", "mango juice",
                "coconut water", "coconut milk" /* full fat */,
                "soy milk", "soya milk",
                "chai tea", "chamomile tea", "fennel tea", "oolong tea",
                "rum", "port", "dessert wine",
                
                // DAIRY ALTERNATIVES - High FODMAP
                "soy yogurt", "soy milk", "soya milk",
                "cashew milk", "oat milk" /* some brands */,
                
                // PROCESSED FOODS - Often High FODMAP
                "teriyaki", "hoisin", "plum sauce",
                "gravy" /* if contains wheat/onion */,
                "marinade" /* check ingredients */,
                "instant noodles", "ramen" /* wheat-based */
            ]
        }
    }
}

// MARK: - Severity Levels

enum SensitivitySeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case mild = "Mild"
    case moderate = "Moderate"
    case severe = "Severe"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .mild: return "⚠️"
        case .moderate: return "⚠️⚠️"
        case .severe: return "🚫"
        }
    }
    
    var scoreMultiplier: Double {
        switch self {
        case .mild: return 1.0
        case .moderate: return 2.0
        case .severe: return 5.0
        }
    }
    
    var color: String {
        switch self {
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }
}

// MARK: - User Sensitivity Entry

struct UserSensitivity: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let allergen: FoodAllergen?
    let intolerance: FoodIntolerance?
    let severity: SensitivitySeverity
    let notes: String?
    
    init(id: UUID = UUID(),
         allergen: FoodAllergen? = nil,
         intolerance: FoodIntolerance? = nil,
         severity: SensitivitySeverity,
         notes: String? = nil) {
        self.id = id
        self.allergen = allergen
        self.intolerance = intolerance
        self.severity = severity
        self.notes = notes
    }
    
    var name: String {
        allergen?.rawValue ?? intolerance?.rawValue ?? "Unknown"
    }
    
    var icon: String {
        allergen?.icon ?? intolerance?.icon ?? "❓"
    }
    
    var category: String {
        allergen?.category ?? intolerance?.category ?? "Other"
    }
    
    var keywords: [String] {
        allergen?.ingredientKeywords ?? intolerance?.ingredientKeywords ?? []
    }
}

// MARK: - Recipe Allergen Score

struct RecipeAllergenScore: Identifiable, Sendable {
    let id = UUID()
    let recipeID: UUID
    let score: Double // 0 = safe, higher = more problematic
    let detectedAllergens: [DetectedAllergen]
    let isSafe: Bool // true if score is 0
    let severityLevel: SensitivitySeverity?
    
    var summary: String {
        if isSafe {
            return String(localized: "No detected allergens", bundle: .appLanguage)
        }
        let count = detectedAllergens.count
        return "\(count) allergen\(count == 1 ? "" : "s") detected"
    }
    
    var scoreLabel: String {
        if isSafe { return "Safe" }
        if score < 5 { return "Low Risk" }
        if score < 10 { return "Medium Risk" }
        return String(localized: "High Risk", bundle: .appLanguage)
    }
}

struct DetectedAllergen: Identifiable, Sendable {
    let id = UUID()
    let sensitivity: UserSensitivity
    let matchedIngredients: [String] // Ingredient names that matched
    let matchedKeywords: [String] // Keywords that caused the match
}

// MARK: - User Sensitivity Model

struct UserFoodSensitivity: Codable, Identifiable, Hashable {
    let id: UUID
    let intolerance: FoodIntoleranceType
    let severity: AllergenSeverity
    let notes: String?
    let fodmapCategories: Set<FODMAPCategory>?  // Only used when intolerance == .fodmap
    
    init(id: UUID = UUID(),
         intolerance: FoodIntoleranceType,
         severity: AllergenSeverity = .moderate,
         notes: String? = nil,
         fodmapCategories: Set<FODMAPCategory>? = nil) {
        self.id = id
        self.intolerance = intolerance
        self.severity = severity
        self.notes = notes
        self.fodmapCategories = fodmapCategories
    }
    
    var name: String {
        intolerance.name
    }
    
    var keywords: [String] {
        intolerance.keywords
    }
    
    var isFODMAP: Bool {
        intolerance == .fodmap
    }
    
    /// Returns the specific FODMAP categories the user is sensitive to
    /// Returns all categories if none specifically selected
    var selectedFODMAPCategories: Set<FODMAPCategory> {
        if isFODMAP {
            return fodmapCategories ?? Set(FODMAPCategory.allCases)
        }
        return []
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: UserFoodSensitivity, rhs: UserFoodSensitivity) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Food Intolerance Types

enum FoodIntoleranceType: String, Codable, CaseIterable {
    case gluten
    case dairy
    case lactose
    case eggs
    case soy
    case peanuts
    case treeNuts
    case fish
    case shellfish
    case wheat
    case sesame
    case sulfites
    case fodmap  // Special case - has sub-categories
    case nightshades
    case corn
    case yeast
    
    var name: String {
        switch self {
        case .gluten: return "Gluten"
        case .dairy: return "Dairy"
        case .lactose: return "Lactose"
        case .eggs: return "Eggs"
        case .soy: return "Soy"
        case .peanuts: return "Peanuts"
        case .treeNuts: return "Tree Nuts"
        case .fish: return "Fish"
        case .shellfish: return "Shellfish"
        case .wheat: return "Wheat"
        case .sesame: return "Sesame"
        case .sulfites: return "Sulfites"
        case .fodmap: return "FODMAP"
        case .nightshades: return "Nightshades"
        case .corn: return "Corn"
        case .yeast: return "Yeast"
        }
    }
    
    var icon: String {
        switch self {
        case .gluten, .wheat: return "🌾"
        case .dairy, .lactose: return "🥛"
        case .eggs: return "🥚"
        case .soy: return "🫘"
        case .peanuts: return "🥜"
        case .treeNuts: return "🌰"
        case .fish: return "🐟"
        case .shellfish: return "🦞"
        case .sesame: return "🫘"
        case .sulfites: return "🍷"
        case .fodmap: return "🌱"
        case .nightshades: return "🍅"
        case .corn: return "🌽"
        case .yeast: return "🍞"
        }
    }
    
    var keywords: [String] {
        switch self {
        case .gluten:
            return ["wheat", "barley", "rye", "malt", "flour", "bread", "pasta", "noodles", "cereal",
                    "couscous", "semolina", "durum", "spelt", "farro", "kamut", "seitan", "bulgur",
                    "wheat germ", "bran", "graham", "triticale"]
            
        case .dairy:
            return ["milk", "cream", "butter", "cheese", "yogurt", "whey", "casein", "lactose",
                    "ghee", "buttermilk", "sour cream", "curd", "paneer", "cottage cheese",
                    "ricotta", "mozzarella", "parmesan", "cheddar", "dairy"]
            
        case .lactose:
            return ["milk", "cream", "lactose", "whey", "buttermilk", "sour cream",
                    "ice cream", "yogurt", "soft cheese", "ricotta", "cottage cheese"]
            
        case .eggs:
            return ["egg", "eggs", "mayonnaise", "meringue", "albumin", "egg white",
                    "egg yolk", "egg wash", "eggnog"]
            
        case .soy:
            return ["soy", "soya", "tofu", "tempeh", "miso", "edamame", "soy sauce",
                    "tamari", "soybean", "lecithin", "soy protein", "soy milk"]
            
        case .peanuts:
            return ["peanut", "peanuts", "peanut butter", "peanut oil", "groundnut", "arachis"]
            
        case .treeNuts:
            return ["almond", "cashew", "walnut", "pecan", "pistachio", "macadamia",
                    "hazelnut", "brazil nut", "pine nut", "chestnut", "nut", "nuts"]
            
        case .fish:
            return ["fish", "salmon", "tuna", "cod", "halibut", "trout", "bass",
                    "anchovy", "sardine", "herring", "mackerel", "fish sauce"]
            
        case .shellfish:
            return ["shrimp", "crab", "lobster", "crayfish", "prawn", "clam", "mussel",
                    "oyster", "scallop", "squid", "octopus", "shellfish"]
            
        case .wheat:
            return ["wheat", "wheat flour", "whole wheat", "enriched flour",
                    "all-purpose flour", "bread flour", "wheat bran", "wheat germ"]
            
        case .sesame:
            return ["sesame", "tahini", "sesame oil", "sesame seeds"]
            
        case .sulfites:
            return ["sulfite", "sulfur dioxide", "sodium sulfite", "sodium bisulfite",
                    "dried fruit", "wine", "vinegar"]
            
        case .fodmap:
            return [
                // Oligosaccharides (Fructans & GOS)
                "wheat", "rye", "barley", "onion", "onions", "garlic", "shallot", "leek",
                "artichoke", "asparagus", "beetroot", "brussels sprout", "cabbage",
                "chickpea", "kidney bean", "black bean", "lentil", "soy bean",
                "cashew", "pistachio",
                
                // Disaccharides (Lactose)
                "milk", "yogurt", "ice cream", "soft cheese", "cream", "custard",
                "cottage cheese", "ricotta",
                
                // Monosaccharides (Excess Fructose)
                "honey", "agave", "apple", "pear", "mango", "watermelon", "fig",
                "high-fructose corn syrup",
                
                // Polyols (Sugar Alcohols)
                "sorbitol", "mannitol", "xylitol", "maltitol", "isomalt",
                "apricot", "avocado", "blackberry", "cherry", "nectarine", "peach",
                "plum", "prune", "mushroom", "cauliflower", "snow pea", "sweet corn"
            ]
            
        case .nightshades:
            return ["tomato", "potato", "eggplant", "pepper", "bell pepper", "chili",
                    "cayenne", "paprika", "goji berry", "nightshade"]
            
        case .corn:
            return ["corn", "maize", "cornstarch", "corn syrup", "corn oil",
                    "popcorn", "corn flour", "cornmeal", "hominy", "polenta"]
            
        case .yeast:
            return ["yeast", "nutritional yeast", "brewer's yeast", "yeast extract"]
        }
    }
    
    var description: String {
        switch self {
        case .gluten:
            return String(localized: "Protein found in wheat, barley, and rye", bundle: .appLanguage)
        case .dairy:
            return String(localized: "All milk products and derivatives", bundle: .appLanguage)
        case .lactose:
            return String(localized: "Milk sugar found in dairy products", bundle: .appLanguage)
        case .eggs:
            return String(localized: "Chicken eggs and egg products", bundle: .appLanguage)
        case .soy:
            return String(localized: "Soybeans and soy-derived products", bundle: .appLanguage)
        case .peanuts:
            return String(localized: "Legume commonly causing allergic reactions", bundle: .appLanguage)
        case .treeNuts:
            return String(localized: "Nuts from trees (almonds, cashews, etc.)", bundle: .appLanguage)
        case .fish:
            return String(localized: "Finned fish species", bundle: .appLanguage)
        case .shellfish:
            return String(localized: "Crustaceans and mollusks", bundle: .appLanguage)
        case .wheat:
            return String(localized: "Wheat grain and wheat-based products", bundle: .appLanguage)
        case .sesame:
            return String(localized: "Sesame seeds and sesame oil", bundle: .appLanguage)
        case .sulfites:
            return String(localized: "Preservatives in wine, dried fruit, etc.", bundle: .appLanguage)
        case .fodmap:
            return String(localized: "Fermentable carbohydrates (6 categories)", bundle: .appLanguage)
        case .nightshades:
            return String(localized: "Tomatoes, potatoes, peppers, eggplant", bundle: .appLanguage)
        case .corn:
            return String(localized: "Corn and corn-derived products", bundle: .appLanguage)
        case .yeast:
            return String(localized: "Baker's and brewer's yeast", bundle: .appLanguage)
        }
    }
    
    /// Returns true if this intolerance has sub-categories (like FODMAP)
    var hasSubCategories: Bool {
        return self == .fodmap
    }
}

// MARK: - Sensitivity Severity

enum AllergenSeverity: String, Codable, CaseIterable {
    case mild
    case moderate
    case severe
    case lifeThreatening
    
    var displayName: String {
        switch self {
        case .mild: return String(localized: "Mild", bundle: .appLanguage)
        case .moderate: return String(localized: "Moderate", bundle: .appLanguage)
        case .severe: return String(localized: "Severe", bundle: .appLanguage)
        case .lifeThreatening: return String(localized: "Life-Threatening", bundle: .appLanguage)
        }
    }
    
    var color: String {
        switch self {
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        case .lifeThreatening: return "purple"
        }
    }
    
    var scoreMultiplier: Double {
        switch self {
        case .mild: return 1.0
        case .moderate: return 2.0
        case .severe: return 3.0
        case .lifeThreatening: return 5.0
        }
    }
}

// MARK: - Detected Allergen Result

struct DetectedAllergenMatch: Identifiable {
    let id = UUID()
    let sensitivity: UserFoodSensitivity
    let matchedIngredients: [String]
    let matchedKeywords: [String]
    
    var score: Double {
        Double(matchedIngredients.count) * sensitivity.severity.scoreMultiplier
    }
}

// MARK: - Recipe Allergen Score

struct RecipeAllergenAnalysis: Identifiable {
    let id = UUID()
    let recipeID: UUID
    let score: Double
    let detectedAllergens: [DetectedAllergenMatch]
    let isSafe: Bool
    let severityLevel: AllergenSeverity?
    
    var displayScore: String {
        if isSafe {
            return "✓ Safe"
        }
        return String(format: "%.0f", score)
    }
    
    var badgeColor: String {
        if isSafe { return "green" }
        if score < 5 { return "yellow" }
        if score < 10 { return "orange" }
        return "red"
    }
    
    var riskLevel: String {
        if isSafe { return "Safe" }
        if score < 5 { return "Low Risk" }
        if score < 10 { return "Moderate Risk" }
        return String(localized: "High Risk", bundle: .appLanguage)
    }
}
