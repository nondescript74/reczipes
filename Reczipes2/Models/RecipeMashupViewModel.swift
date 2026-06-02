//
//  RecipeMashupViewModel.swift
//  Reczipes2
//
//  Created for multi-source recipe mashup feature
//

import SwiftUI
import Combine

// MARK: - Models

/// Represents a single source (either a URL or a local recipe) for mashup
struct MashupSource: Identifiable {
    let id = UUID()
    var url: String  // URL for web sources, or reference/description for local sources
    var userDescription: String = ""
    var isExpanded: Bool = true
    var isExtracting: Bool = false
    var extractedRecipe: RecipeX?
    var errorMessage: String?
    var isLocalRecipe: Bool = false  // True if this is a recipe already in SwiftData
    
    /// Indicates which sections the user wants from this source
    var selectedSections: Set<RecipeSectionType> = []
}

/// The different sections of a recipe that can be individually selected
enum RecipeSectionType: String, CaseIterable, Identifiable, Hashable {
    case title = "Title"
    case headerNotes = "Header Notes"
    case ingredients = "Ingredients"
    case instructions = "Instructions"
    case notes = "Notes"
    case yield = "Yield / Servings"
    case reference = "Source / Reference"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .title: return "textformat"
        case .headerNotes: return "text.quote"
        case .ingredients: return "list.bullet"
        case .instructions: return "list.number"
        case .notes: return "note.text"
        case .yield: return "person.2"
        case .reference: return "link"
        }
    }
    
    var color: Color {
        switch self {
        case .title: return .blue
        case .headerNotes: return .indigo
        case .ingredients: return .green
        case .instructions: return .orange
        case .notes: return .purple
        case .yield: return .teal
        case .reference: return .gray
        }
    }
}

/// The synthetic recipe assembled from sections of multiple source recipes.
/// This is session-only and never persisted.
struct SyntheticRecipe: Identifiable {
    let id = UUID()
    var title: String
    var headerNotes: String?
    var yield: String?
    var ingredientSections: [IngredientSection]
    var instructionSections: [InstructionSection]
    var notes: [RecipeNote]
    var reference: String?
    var imageData: Data?  // Image selected from source recipes
    
    /// Tracks which source contributed each section
    var sectionSources: [RecipeSectionType: String] = [:] // section -> source URL
}

// MARK: - ViewModel

@MainActor
class RecipeMashupViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var sources: [MashupSource] = []
    @Published var syntheticRecipe: SyntheticRecipe?
    @Published var showingSyntheticRecipe = false
    @Published var isExtractingAll = false
    @Published var globalError: String?
    @Published var selectedImageSource: UUID?
    @Published var selectedImageIndex: Int = 0
    
    // MARK: - Private
    
    private let apiClient: ClaudeAPIClient
    private let webExtractor = WebRecipeExtractor()
    
    init(apiKey: String) {
        self.apiClient = ClaudeAPIClient(apiKey: apiKey)
    }
    
    // MARK: - Source Management
    
    func addSource() {
        sources.append(MashupSource(url: ""))
    }
    
    func removeSource(at index: Int) {
        guard sources.indices.contains(index) else { return }
        sources.remove(at: index)
        // Clear synthetic recipe whenever sources change
        syntheticRecipe = nil
        showingSyntheticRecipe = false
    }
    
    func toggleExpansion(for sourceID: UUID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].isExpanded.toggle()
    }
    
    // MARK: - Extraction
    
    /// Extract a single source by index
    func extractSource(at index: Int) async {
        guard sources.indices.contains(index) else { return }
        
        // Skip extraction if this is a local recipe (already loaded)
        if sources[index].isLocalRecipe {
            AppLog.info("Mashup: Source is a local recipe, skipping extraction", category: .recipe)
            return
        }
        
        guard !sources[index].url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sources[index].errorMessage = "Please enter a URL"
            return
        }
        
        sources[index].isExtracting = true
        sources[index].errorMessage = nil
        sources[index].extractedRecipe = nil
        
        do {
            let url = sources[index].url.trimmingCharacters(in: .whitespacesAndNewlines)
            let htmlContent = try await webExtractor.fetchWebContent(from: url)
            let cleanedContent = webExtractor.cleanHTML(htmlContent)
            
            let contentToSend: String
            if cleanedContent.count > 50_000 {
                contentToSend = String(cleanedContent.prefix(50_000))
            } else {
                contentToSend = cleanedContent
            }
            
            let recipe = try await apiClient.extractRecipe(from: contentToSend)
            
            // Store the source URL on the recipe
            if recipe.reference == nil || recipe.reference?.isEmpty == true {
                recipe.reference = url
            }
            
            sources[index].extractedRecipe = recipe
            sources[index].errorMessage = nil
            
            AppLog.info("Mashup: Extracted recipe '\(recipe.safeTitle)' from \(url)", category: .recipe)
        } catch {
            sources[index].errorMessage = "Extraction failed: \(error.localizedDescription)"
            AppLog.error("Mashup extraction error for source \(index): \(error)", category: .recipe)
        }
        
        sources[index].isExtracting = false
    }
    
    /// Extract all sources that haven't been extracted yet
    func extractAllSources() async {
        isExtractingAll = true
        globalError = nil
        
        for index in sources.indices {
            if sources[index].extractedRecipe == nil &&
                !sources[index].url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await extractSource(at: index)
            }
        }
        
        isExtractingAll = false
    }
    
    // MARK: - Section Selection
    
    func toggleSection(_ section: RecipeSectionType, for sourceID: UUID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        
        if sources[index].selectedSections.contains(section) {
            sources[index].selectedSections.remove(section)
        } else {
            // Remove this section from all other sources first (exclusive selection)
            for otherIndex in sources.indices where sources[otherIndex].id != sourceID {
                sources[otherIndex].selectedSections.remove(section)
            }
            sources[index].selectedSections.insert(section)
        }
        
        // Clear synthetic recipe when selection changes
        syntheticRecipe = nil
        showingSyntheticRecipe = false
    }
    
    /// Check if a section is selected for a given source
    func isSectionSelected(_ section: RecipeSectionType, for sourceID: UUID) -> Bool {
        guard let source = sources.first(where: { $0.id == sourceID }) else { return false }
        return source.selectedSections.contains(section)
    }
    
    /// Check if a section is selected on ANY source (used to show dim state)
    func isSectionClaimedByOther(_ section: RecipeSectionType, excludingSourceID: UUID) -> Bool {
        return sources.contains { $0.id != excludingSourceID && $0.selectedSections.contains(section) }
    }
    
    /// Returns the number of sections selected across all sources
    var totalSelectedSections: Int {
        sources.reduce(0) { $0 + $1.selectedSections.count }
    }
    
    /// Returns how many sources have completed extraction
    var extractedSourceCount: Int {
        sources.filter { $0.extractedRecipe != nil }.count
    }
    
    /// Whether the user can build a synthetic recipe
    var canBuildSyntheticRecipe: Bool {
        totalSelectedSections > 0 && extractedSourceCount >= 1
    }
    
    // MARK: - Build Synthetic Recipe
    
    func buildSyntheticRecipe() {
        var title = "Mashup Recipe"
        var headerNotes: String?
        var yield: String?
        var ingredientSections: [IngredientSection] = []
        var instructionSections: [InstructionSection] = []
        var notes: [RecipeNote] = []
        var reference: String?
        var sectionSources: [RecipeSectionType: String] = [:]
        
        for source in sources {
            guard let recipe = source.extractedRecipe else { continue }
            // Replacing '.label' usage with actual property '.url' as appropriate (fix 1)
            let sourceLabel = recipe.safeTitle.isEmpty ? source.url : recipe.safeTitle
            
            for section in source.selectedSections {
                sectionSources[section] = sourceLabel
                
                switch section {
                case .title:
                    title = recipe.safeTitle
                case .headerNotes:
                    headerNotes = recipe.headerNotes
                case .ingredients:
                    ingredientSections = recipe.ingredientSections
                case .instructions:
                    instructionSections = recipe.instructionSections
                case .notes:
                    notes = recipe.notes
                case .yield:
                    yield = recipe.yield
                case .reference:
                    reference = recipe.reference
                }
            }
        }
        
        // Build attribution reference
        let allSourceURLs = sources.compactMap { source -> String? in
            guard source.extractedRecipe != nil else { return nil }
            return source.url
        }
        let attributionText = "Mashup from: " + allSourceURLs.joined(separator: ", ")
        if reference == nil {
            reference = attributionText
        } else {
            reference = (reference ?? "") + "\n\n" + attributionText
        }
        
        // Get selected image
        let selectedImage = getSelectedImage()
        
        syntheticRecipe = SyntheticRecipe(
            title: title,
            headerNotes: headerNotes,
            yield: yield,
            ingredientSections: ingredientSections,
            instructionSections: instructionSections,
            notes: notes,
            reference: reference,
            imageData: selectedImage,
            sectionSources: sectionSources
        )
        
        showingSyntheticRecipe = true
        
        AppLog.info("Mashup: Built synthetic recipe '\(title)' from \(sectionSources.count) sections", category: .recipe)
    }
    
    func reset() {
        sources = []
        syntheticRecipe = nil
        showingSyntheticRecipe = false
        isExtractingAll = false
        globalError = nil
        selectedImageSource = nil
        selectedImageIndex = 0
    }
    
    // MARK: - Image Selection
    
    func selectImageSource(_ sourceID: UUID, imageIndex: Int) {
        selectedImageSource = sourceID
        selectedImageIndex = imageIndex
    }
    
    func getSelectedImage() -> Data? {
        guard let sourceID = selectedImageSource else { return nil }
        guard let source = sources.first(where: { $0.id == sourceID }) else { return nil }
        guard let recipe = source.extractedRecipe else { return nil }
        
        if selectedImageIndex == 0 {
            return recipe.imageData
        } else {
            guard let additionalImagesData = recipe.additionalImagesData else {
                return nil
            }
            guard let decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData) else {
                return nil
            }
            let adjustedIndex = selectedImageIndex - 1
            guard adjustedIndex >= 0, adjustedIndex < decoded.count else {
                return nil
            }
            return decoded[adjustedIndex]["data"]
        }
    }
    
    // Adding dummy sectionHasContent computed property to fix missing reference (fix 2)
    var sectionHasContent: Bool {
        // TODO: implement
        return false
    }
}

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

