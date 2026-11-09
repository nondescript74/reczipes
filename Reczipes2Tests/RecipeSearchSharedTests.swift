//
//  RecipeSearchSharedTests.swift
//  Reczipes2Tests
//
//  The Recipes search button searches owned and community recipes together.
//

import Testing
import Foundation
@testable import Reczipes2

/// Stand-in for a community recipe (CachedSharedRecipe needs a CloudKit record).
private struct CommunityStub: RecipeDisplayProtocol {
    var displayID = UUID()
    var displayTitle: String
    var headerNotes: String? = nil
    var yield: String? = nil
    var ingredientSections: [IngredientSection] = []
    var instructionSections: [InstructionSection] = []
    var notes: [RecipeNote] = []
    var reference: String? = nil
    var imageName: String? = nil
    var additionalImageNames: [String]? = nil
    var displayDate = Date()
    var isSharedRecipe = true
    var sharedByUserName: String? = "Z"
}

@Suite("Recipe Search — owned and community together")
@MainActor
struct RecipeSearchSharedTests {
    let service = RecipeSearchService()

    @Test("A community recipe is found by title")
    func communityTitle() {
        let biscuits = CommunityStub(displayTitle: "BUTTERMILK BISCUITS")
        let other = CommunityStub(displayTitle: "Meat Cutlets")
        let found = service.searchRecipes(recipes: [biscuits, other] as [any RecipeDisplayProtocol],
                                          criteria: .init(searchText: "biscuit"))
        #expect(found.map(\.displayTitle) == ["BUTTERMILK BISCUITS"])
    }

    @Test("A community recipe is found by ingredient")
    func communityIngredient() {
        let r = CommunityStub(displayTitle: "Thumbprint Cookies",
                              ingredientSections: [IngredientSection(ingredients: [
                                  Ingredient(quantity: "1", unit: "cup", name: "butter")])])
        let found = service.searchRecipes(recipes: [r] as [any RecipeDisplayProtocol],
                                          criteria: .init(searchText: "butter"))
        #expect(found.count == 1)
    }

    @Test("Author filter matches who shared it")
    func sharerAsAuthor() {
        let r = CommunityStub(displayTitle: "Meat Cutlets", sharedByUserName: "Carol")
        let found = service.searchRecipes(recipes: [r] as [any RecipeDisplayProtocol],
                                          criteria: .init(author: "carol"))
        #expect(found.count == 1)
    }

    @Test("Owned and community recipes come back together")
    func mixed() {
        let owned = RecipeX(title: "Biscuit Pudding", headerNotes: nil, recipeYield: nil, reference: nil)
        let shared = CommunityStub(displayTitle: "Buttermilk Biscuits")
        let found = service.searchRecipes(recipes: [owned, shared] as [any RecipeDisplayProtocol],
                                          criteria: .init(searchText: "biscuit"))
        #expect(found.count == 2)
        #expect(found.contains { !$0.isSharedRecipe })
        #expect(found.contains { $0.isSharedRecipe })
    }
}
