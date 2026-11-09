//
//  RecipeSearchService.swift
//  Reczipes2
//
//  Created for comprehensive recipe searching
//

import Foundation

/// A service that provides comprehensive recipe and book search functionality
class RecipeSearchService {
    
    /// Search criteria for filtering recipes
    struct SearchCriteria {
        var searchText: String = ""
        var dishTypes: Set<DishType> = []
        var maxCookingTime: Int? = nil // in minutes
        var author: String? = nil
        
        var isEmpty: Bool {
            searchText.isEmpty && dishTypes.isEmpty && maxCookingTime == nil && author == nil
        }
    }
    
    /// Search criteria for filtering books
    struct BookSearchCriteria {
        var searchText: String = ""
        var categories: Set<String> = []
        var cuisines: Set<String> = []
        var minRecipeCount: Int? = nil
        var maxRecipeCount: Int? = nil
        var author: String? = nil
        
        var isEmpty: Bool {
            searchText.isEmpty && categories.isEmpty && cuisines.isEmpty && 
            minRecipeCount == nil && maxRecipeCount == nil && author == nil
        }
    }
    
    /// Common dish types that can be detected in recipes
    enum DishType: String, CaseIterable, Identifiable {
        case soup
        case salad
        case appetizer
        case mainCourse = "main course"
        case sideDish = "side dish"
        case dessert
        case breakfast
        case beverage
        case sauce
        case bread
        case pasta
        case pizza
        case sandwich
        case casserole
        case stew
        case curry
        case stirFry = "stir-fry"
        case grill
        case bake
        case roast
        
        var id: String { rawValue }
        
        var displayName: String {
            rawValue.capitalized
        }
        
        /// Keywords that help identify this dish type
        var keywords: [String] {
            switch self {
            case .soup:
                return ["soup", "broth", "chowder", "bisque", "stew", "gazpacho"]
            case .salad:
                return ["salad", "slaw", "greens"]
            case .appetizer:
                return ["appetizer", "starter", "hors d'oeuvre", "finger food", "dip"]
            case .mainCourse:
                return ["main", "entrée", "entree", "dinner"]
            case .sideDish:
                return ["side dish", "side", "accompaniment"]
            case .dessert:
                return ["dessert", "cake", "cookie", "pie", "tart", "pudding", "ice cream", "brownie"]
            case .breakfast:
                return ["breakfast", "pancake", "waffle", "omelet", "omelette", "cereal", "muffin"]
            case .beverage:
                return ["beverage", "drink", "smoothie", "juice", "cocktail", "coffee", "tea"]
            case .sauce:
                return ["sauce", "gravy", "dressing", "marinade", "glaze"]
            case .bread:
                return ["bread", "roll", "biscuit", "scone", "baguette", "loaf"]
            case .pasta:
                return ["pasta", "spaghetti", "lasagna", "ravioli", "penne", "fettuccine", "noodle"]
            case .pizza:
                return ["pizza", "flatbread", "calzone"]
            case .sandwich:
                return ["sandwich", "burger", "wrap", "panini", "sub"]
            case .casserole:
                return ["casserole", "bake", "gratin"]
            case .stew:
                return ["stew", "ragout", "goulash"]
            case .curry:
                return ["curry", "masala", "korma", "vindaloo"]
            case .stirFry:
                return ["stir-fry", "stir fry", "wok"]
            case .grill:
                return ["grilled", "grill", "bbq", "barbecue"]
            case .bake:
                return ["baked", "baking", "oven-baked"]
            case .roast:
                return ["roast", "roasted"]
            }
        }
    }
    
    /// Which part of a recipe matched the search
    enum MatchField: Equatable {
        case title
        case author
        case ingredient(name: String)
        case dishType(DishType)
        case cookingTime
        case headerNotes
        case instructions
    }

    /// Search results with relevance scoring. `Recipe` is RecipeX for the
    /// owned-only callers, or `any RecipeDisplayProtocol` when owned and
    /// community recipes are searched together (the Recipes search button).
    struct SearchResult<Recipe> {
        typealias MatchField = RecipeSearchService.MatchField
        let recipe: Recipe
        let score: Double
        let matchedFields: [MatchField]
    }
    
    // MARK: - Search Methods
    
    /// Search recipes based on the provided criteria
    /// - Parameters:
    ///   - recipes: The recipes to search through
    ///   - criteria: The search criteria to apply
    /// - Returns: An array of search results, sorted by relevance score (highest first)
    func search<R: RecipeDisplayProtocol>(recipes: [R], criteria: SearchCriteria) -> [SearchResult<R>] {
        rank(recipes, criteria: criteria) { $0 }
    }

    /// Owned and community recipes together (RecipeX and CachedSharedRecipe)
    func search(recipes: [any RecipeDisplayProtocol], criteria: SearchCriteria) -> [SearchResult<any RecipeDisplayProtocol>] {
        rank(recipes, criteria: criteria) { $0 }
    }

    private func rank<R>(_ items: [R], criteria: SearchCriteria, as view: (R) -> any RecipeDisplayProtocol) -> [SearchResult<R>] {
        guard !criteria.isEmpty else {
            // Return all recipes with default score when no criteria
            return items.map { SearchResult(recipe: $0, score: 1.0, matchedFields: []) }
        }
        
        var results: [SearchResult<R>] = []
        
        for item in items {
            let recipe = view(item)
            var score: Double = 0
            var matchedFields: [MatchField] = []
            
            // Dish type matching - this acts as a FILTER when specified
            if !criteria.dishTypes.isEmpty {
                let dishTypeMatches = matchDishTypes(in: recipe, types: criteria.dishTypes)
                if dishTypeMatches.isEmpty {
                    // Recipe doesn't match required dish type - skip it
                    continue
                }
                score += 10.0 * Double(dishTypeMatches.count)
                matchedFields.append(contentsOf: dishTypeMatches.map { .dishType($0) })
            }
            
            // Cooking time matching - also acts as a FILTER when specified
            if let maxTime = criteria.maxCookingTime {
                guard let recipeTime = extractCookingTime(from: recipe), recipeTime <= maxTime else {
                    // Recipe doesn't meet cooking time requirement - skip it
                    continue
                }
                score += 5.0
                matchedFields.append(.cookingTime)
            }
            
            // Author matching - acts as a FILTER when specified
            if let authorQuery = criteria.author, !authorQuery.isEmpty {
                let byReference = recipe.reference?.localizedCaseInsensitiveContains(authorQuery) == true
                let bySharer = recipe.sharedByUserName?.localizedCaseInsensitiveContains(authorQuery) == true
                guard byReference || bySharer else {
                    // Recipe doesn't match author requirement - skip it
                    continue
                }
                score += 8.0
                matchedFields.append(.author)
            }
            
            // Search text matching (title, ingredients, instructions, notes)
            // This is optional - if specified, adds to score, but if not specified, doesn't filter
            if !criteria.searchText.isEmpty {
                let textMatches = searchText(in: recipe, searchText: criteria.searchText)
                if textMatches.score > 0 {
                    score += textMatches.score
                    matchedFields.append(contentsOf: textMatches.fields)
                } else if !criteria.dishTypes.isEmpty || criteria.maxCookingTime != nil || criteria.author != nil {
                    // If there are other criteria (dish type, time, author) and text search is specified,
                    // the recipe must match the text search too
                    continue
                }
            }
            
            // Only include recipes with matches
            if score > 0 {
                results.append(SearchResult(recipe: item, score: score, matchedFields: matchedFields))
            }
        }
        
        // Sort by score (highest first)
        return results.sorted { $0.score > $1.score }
    }
    
    /// Convenience method to get just the recipes without search metadata
    func searchRecipes<R: RecipeDisplayProtocol>(recipes: [R], criteria: SearchCriteria) -> [R] {
        search(recipes: recipes, criteria: criteria).map { $0.recipe }
    }

    func searchRecipes(recipes: [any RecipeDisplayProtocol], criteria: SearchCriteria) -> [any RecipeDisplayProtocol] {
        search(recipes: recipes, criteria: criteria).map { $0.recipe }
    }
    
    // MARK: - Private Helper Methods
    
    private func searchText(in recipe: any RecipeDisplayProtocol, searchText: String) -> (score: Double, fields: [MatchField]) {
        var score: Double = 0
        var fields: [MatchField] = []
        let query = searchText.lowercased()
        
        // Title matching (highest weight)
        if recipe.displayTitle.localizedCaseInsensitiveContains(query) {
            score += 10.0
            fields.append(.title)
        }
        
        // Header notes matching
        if let headerNotes = recipe.headerNotes, headerNotes.localizedCaseInsensitiveContains(query) {
            score += 6.0
            fields.append(.headerNotes)
        }
        
        // Ingredient matching
        for section in recipe.ingredientSections {
            for ingredient in section.ingredients {
                if ingredient.name.localizedCaseInsensitiveContains(query) {
                    score += 5.0
                    if !fields.contains(where: { 
                        if case .ingredient(let name) = $0, name == ingredient.name {
                            return true
                        }
                        return false
                    }) {
                        fields.append(.ingredient(name: ingredient.name))
                    }
                }
                
                // Also check preparation notes
                if let prep = ingredient.preparation, prep.localizedCaseInsensitiveContains(query) {
                    score += 2.0
                    if !fields.contains(where: { 
                        if case .ingredient(let name) = $0, name == ingredient.name {
                            return true
                        }
                        return false
                    }) {
                        fields.append(.ingredient(name: ingredient.name))
                    }
                }
            }
        }
        
        // Instruction matching
        for section in recipe.instructionSections {
            for step in section.steps {
                if step.text.localizedCaseInsensitiveContains(query) {
                    score += 3.0
                    if !fields.contains(.instructions) {
                        fields.append(.instructions)
                    }
                }
            }
        }
        
        // Reference/author matching
        if let reference = recipe.reference, reference.localizedCaseInsensitiveContains(query) {
            score += 4.0
            fields.append(.author)
        } else if let sharer = recipe.sharedByUserName, sharer.localizedCaseInsensitiveContains(query) {
            // Community recipe: who shared it
            score += 4.0
            fields.append(.author)
        }
        
        return (score, fields)
    }
    
    private func matchDishTypes(in recipe: any RecipeDisplayProtocol, types: Set<DishType>) -> [DishType] {
        var matches: [DishType] = []
        
        for dishType in types {
            if detectDishType(recipe, type: dishType) {
                matches.append(dishType)
            }
        }
        
        return matches
    }
    
    /// Detect if a recipe matches a specific dish type
    private func detectDishType(_ recipe: any RecipeDisplayProtocol, type: DishType) -> Bool {
        let searchableText = [
            recipe.displayTitle,
            recipe.headerNotes ?? "",
            recipe.notes.map { $0.text }.joined(separator: " ")
        ].joined(separator: " ").lowercased()
        
        // Check if any of the dish type's keywords appear in the recipe
        return type.keywords.contains { keyword in
            searchableText.contains(keyword.lowercased())
        }
    }
    
    /// Extract cooking time from recipe (in minutes)
    private func extractCookingTime(from recipe: any RecipeDisplayProtocol) -> Int? {
        // First check if cookTimeMinutes is set (owned recipes only)
        if let cookTime = (recipe as? RecipeX)?.cookTimeMinutes, cookTime > 0 {
            return cookTime
        }
        
        // Fall back to parsing text
        // Look for time mentions in header notes, instructions, and notes
        let searchableText = [
            recipe.headerNotes ?? "",
            recipe.instructionSections.flatMap { $0.steps.map { $0.text } }.joined(separator: " "),
            recipe.notes.map { $0.text }.joined(separator: " ")
        ].joined(separator: " ")
        
        return parseTimeFromText(searchableText)
    }
    
    /// Parse time mentions from text (e.g., "30 minutes", "1 hour", "2 hrs")
    private func parseTimeFromText(_ text: String) -> Int? {
        let lowercased = text.lowercased()
        var totalMinutes: Int? = nil
        
        // Patterns to match time expressions
        let patterns = [
            // "30 minutes", "30 mins", "30 min"
            (regex: #"(\d+)\s*(minute|minutes|min|mins)"#, multiplier: 1),
            // "2 hours", "2 hrs", "2 hr"
            (regex: #"(\d+)\s*(hour|hours|hr|hrs)"#, multiplier: 60),
            // "1.5 hours"
            (regex: #"(\d+\.?\d*)\s*(hour|hours|hr|hrs)"#, multiplier: 60)
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern.regex, options: .caseInsensitive) {
                let nsRange = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
                if let match = regex.firstMatch(in: lowercased, options: [], range: nsRange) {
                    if let numberRange = Range(match.range(at: 1), in: lowercased) {
                        let numberString = String(lowercased[numberRange])
                        if let number = Double(numberString) {
                            let minutes = Int(number * Double(pattern.multiplier))
                            if let existing = totalMinutes {
                                totalMinutes = min(existing, minutes)
                            } else {
                                totalMinutes = minutes
                            }
                        }
                    }
                }
            }
        }
        
        return totalMinutes
    }
    
    // MARK: - Helper Methods for UI
    
    /// Get all detected dish types for a recipe
    func detectAllDishTypes(for recipe: any RecipeDisplayProtocol) -> [DishType] {
        DishType.allCases.filter { detectDishType(recipe, type: $0) }
    }
    
    /// Get cooking time display string for a recipe
    func getCookingTimeString(for recipe: any RecipeDisplayProtocol) -> String? {
        guard let minutes = extractCookingTime(from: recipe) else { return nil }
        
        if minutes < 60 {
            return String(localized: "\(minutes) min", bundle: .appLanguage)
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return String(localized: "\(hours) hr", bundle: .appLanguage)
            } else {
                return String(localized: "\(hours) hr \(remainingMinutes) min", bundle: .appLanguage)
            }
        }
    }
    
    // MARK: - Book Search
    
    /// Search results for books with relevance scoring
    struct BookSearchResult {
        let book: Book
        let score: Double
        let matchedFields: [BookMatchField]
        
        enum BookMatchField: Equatable {
            case name
            case description
            case author
            case category
            case cuisine
            case recipeCount
        }
    }
    
    /// Search books based on the provided criteria
    /// - Parameters:
    ///   - books: The books to search through
    ///   - criteria: The search criteria to apply
    /// - Returns: An array of search results, sorted by relevance score (highest first)
    func searchBooks(books: [Book], criteria: BookSearchCriteria) -> [BookSearchResult] {
        guard !criteria.isEmpty else {
            // Return all books with default score when no criteria
            return books.map { BookSearchResult(book: $0, score: 1.0, matchedFields: []) }
        }
        
        var results: [BookSearchResult] = []
        
        for book in books {
            var score: Double = 0
            var matchedFields: [BookSearchResult.BookMatchField] = []
            
            // Category filtering
            if !criteria.categories.isEmpty {
                if let category = book.category, criteria.categories.contains(category) {
                    score += 8.0
                    matchedFields.append(.category)
                } else {
                    // Book doesn't match required category - skip it
                    continue
                }
            }
            
            // Cuisine filtering
            if !criteria.cuisines.isEmpty {
                if let cuisine = book.cuisine, criteria.cuisines.contains(cuisine) {
                    score += 8.0
                    matchedFields.append(.cuisine)
                } else {
                    // Book doesn't match required cuisine - skip it
                    continue
                }
            }
            
            // Recipe count filtering
            let recipeCount = book.recipeIDs?.count ?? 0
            if let minCount = criteria.minRecipeCount, recipeCount < minCount {
                continue
            }
            if let maxCount = criteria.maxRecipeCount, recipeCount > maxCount {
                continue
            }
            if criteria.minRecipeCount != nil || criteria.maxRecipeCount != nil {
                score += 5.0
                matchedFields.append(.recipeCount)
            }
            
            // Author filtering
            if let authorQuery = criteria.author, !authorQuery.isEmpty {
                guard let ownerName = book.ownerDisplayName, 
                      ownerName.localizedCaseInsensitiveContains(authorQuery) else {
                    continue
                }
                score += 10.0
                matchedFields.append(.author)
            }
            
            // Text search
            if !criteria.searchText.isEmpty {
                let textMatches = searchTextInBook(book, searchText: criteria.searchText)
                if textMatches.score > 0 {
                    score += textMatches.score
                    matchedFields.append(contentsOf: textMatches.fields)
                } else if !criteria.categories.isEmpty || !criteria.cuisines.isEmpty || 
                          criteria.minRecipeCount != nil || criteria.maxRecipeCount != nil || 
                          criteria.author != nil {
                    // If there are other criteria and text search is specified,
                    // the book must match the text search too
                    continue
                }
            }
            
            // Only include books with matches
            if score > 0 {
                results.append(BookSearchResult(book: book, score: score, matchedFields: matchedFields))
            }
        }
        
        // Sort by score (highest first)
        return results.sorted { $0.score > $1.score }
    }
    
    /// Search text within a book
    private func searchTextInBook(_ book: Book, searchText: String) -> (score: Double, fields: [BookSearchResult.BookMatchField]) {
        var score: Double = 0
        var fields: [BookSearchResult.BookMatchField] = []
        let query = searchText.lowercased()
        
        // Name matching (highest weight)
        if let name = book.name, name.localizedCaseInsensitiveContains(query) {
            score += 10.0
            fields.append(.name)
        }
        
        // Description matching
        if let description = book.bookDescription, description.localizedCaseInsensitiveContains(query) {
            score += 8.0
            fields.append(.description)
        }
        
        // Category matching
        if let category = book.category, category.localizedCaseInsensitiveContains(query) {
            score += 5.0
            fields.append(.category)
        }
        
        // Cuisine matching
        if let cuisine = book.cuisine, cuisine.localizedCaseInsensitiveContains(query) {
            score += 5.0
            fields.append(.cuisine)
        }
        
        // Author matching
        if let author = book.ownerDisplayName, author.localizedCaseInsensitiveContains(query) {
            score += 7.0
            fields.append(.author)
        }
        
        return (score, fields)
    }
    
    /// Get all unique categories from books
    func extractCategories(from books: [Book]) -> [String] {
        let categories = books.compactMap { $0.category }
        return Array(Set(categories)).sorted()
    }
    
    /// Get all unique cuisines from books
    func extractCuisines(from books: [Book]) -> [String] {
        let cuisines = books.compactMap { $0.cuisine }
        return Array(Set(cuisines)).sorted()
    }
}


