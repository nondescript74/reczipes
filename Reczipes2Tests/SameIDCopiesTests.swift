//
//  SameIDCopiesTests.swift
//  Reczipes2Tests
//
//  The one rule shared by the Duplicate Detector and Maintenance → Remove
//  Duplicate Recipes: same id, keep the most complete row, remove only
//  identical extras, never a row whose content differs.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Same-ID copies")
@MainActor
struct SameIDCopiesTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([RecipeX.self])
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func sections(_ names: [String]) throws -> Data {
        let section = IngredientSection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                        ingredients: names.enumerated().map { i, n in
                                            Ingredient(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", i + 10))!, name: n)
                                        })
        return try JSONEncoder().encode([section])
    }

    @Test("Identical extras are removed and the most complete row is kept")
    func identicalExtrasRemoved() throws {
        let context = try makeContext()
        let id = UUID()
        let data = try sections(["flour", "sugar"])
        let rows = (0..<3).map { _ in RecipeX(id: id, title: "Scones", ingredientSectionsData: data) }
        rows.forEach(context.insert)
        try context.save()

        let plan = SameIDCopies.plan(rows)
        #expect(plan.keep != nil)
        #expect(plan.remove.count == 2)
        #expect(plan.differing.isEmpty)
    }

    @Test("A row whose content differs is never removed")
    func differingRowKept() throws {
        let context = try makeContext()
        let id = UUID()
        let fuller = RecipeX(id: id, title: "Burtha", ingredientSectionsData: try sections(["eggplant", "oil", "onion"]))
        let older = RecipeX(id: id, title: "Burtha", ingredientSectionsData: try sections(["eggplant", "onion"]))
        context.insert(fuller); context.insert(older)
        try context.save()

        let plan = SameIDCopies.plan([older, fuller])
        #expect(plan.keep?.persistentModelID == fuller.persistentModelID)
        #expect(plan.remove.isEmpty)
        #expect(plan.differing.count == 1)
        #expect(plan.differing.first?.persistentModelID == older.persistentModelID)
    }

    @Test("Rows without an id are ignored")
    func nilIDIgnored() throws {
        let context = try makeContext()
        let row = RecipeX(id: nil, title: "No id")
        context.insert(row)
        try context.save()

        let plan = SameIDCopies.plan([row])
        #expect(plan.keep == nil)
        #expect(plan.remove.isEmpty && plan.differing.isEmpty)
    }
}

@Suite("Ingredients editor preview")
@MainActor
struct IngredientsEditorPreviewTests {
    @Test("Section row lists its ingredients, capped with a count")
    func previewLines() {
        let few = EditableIngredientSection(ingredients: [
            EditableIngredient(quantity: "2", unit: "cups", name: "flour"),
            EditableIngredient(name: "salt"),
            EditableIngredient(),
        ])
        #expect(IngredientsEditorView.previewLines(for: few) == ["• 2 cups flour", "• salt", "• New Ingredient"])

        let many = EditableIngredientSection(ingredients: (1...10).map { EditableIngredient(name: "i\($0)") })
        let lines = IngredientsEditorView.previewLines(for: many)
        #expect(lines.count == 9)
        #expect(lines.last == "+2 more")
    }
}
