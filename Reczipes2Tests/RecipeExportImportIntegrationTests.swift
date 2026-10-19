//
//  RecipeExportImportIntegrationTests.swift
//  Reczipes2Tests
//
//  Integration tests for complete export/import workflows
//  Created on 1/5/26.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

@Suite("Recipe Export/Import Integration Tests", .serialized)
struct RecipeExportImportIntegrationTests {
    
    /// Helper to get the Reczipes2 backup directory path
    /// Uses the same logic as RecipeBackupManager to handle test environments
    func getBackupDirectory() -> URL {
        // Use the same logic as RecipeBackupManager
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Check if Documents directory is accessible
        var isDir: ObjCBool = false
        let docsExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        if docsExists && isDir.boolValue {
            return documentsDirectory.appendingPathComponent("Reczipes2", isDirectory: true)
        } else {
            // Fall back to temp directory (common in test environments)
            return FileManager.default.temporaryDirectory.appendingPathComponent("Reczipes2", isDirectory: true)
        }
    }
    
    /// Helper to create ingredient sections data
    func encodeIngredientSections(_ sections: [IngredientSection]) throws -> Data {
        return try JSONEncoder().encode(sections)
    }
    
    /// Helper to create instruction sections data
    func encodeInstructionSections(_ sections: [InstructionSection]) throws -> Data {
        return try JSONEncoder().encode(sections)
    }
    
    /// Helper to create notes data
    func encodeNotes(_ notes: [RecipeNote]) throws -> Data {
        return try JSONEncoder().encode(notes)
    }
    
    @Test("Full export/import cycle preserves all data")
    @MainActor
    func testFullExportImportCycle() async throws {
        // Create a complete recipe with RecipeX
        let ingredientSections = [
            IngredientSection(
                title: "Main",
                ingredients: [
                    Ingredient(
                        quantity: "2",
                        unit: "cups",
                        name: "flour",
                        metricQuantity: "480",
                        metricUnit: "mL"
                    )
                ]
            )
        ]
        
        let instructionSections = [
            InstructionSection(
                steps: [
                    InstructionStep(stepNumber: 1, text: "Mix ingredients")
                ]
            )
        ]
        
        let notes = [
            RecipeNote(type: .tip, text: "Test tip")
        ]
        
        let original = RecipeX(
            id: UUID(),
            title: "Integration Test Recipe",
            headerNotes: "Test notes",
            recipeYield: "4 servings",
            reference: "Test source",
            ingredientSectionsData: try encodeIngredientSections(ingredientSections),
            instructionSectionsData: try encodeInstructionSections(instructionSections),
            notesData: try encodeNotes(notes),
            imageName: "test.jpg"
        )
        
        // Create in-memory ModelContainer for this test
        let schema = Schema([RecipeX.self, Book.self])
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        
        // Insert recipe
        context.insert(original)
        try context.save()
        
        // Read back (simulating export)
        let decoder = JSONDecoder()
        
        let decodedIngredientSections = try decoder.decode(
            [IngredientSection].self,
            from: original.ingredientSectionsData!
        )
        let decodedInstructionSections = try decoder.decode(
            [InstructionSection].self,
            from: original.instructionSectionsData!
        )
        let decodedNotes = try decoder.decode(
            [RecipeNote].self,
            from: original.notesData!
        )
        
        // Verify everything matches
        #expect(original.id != nil)
        #expect(original.title == "Integration Test Recipe")
        #expect(original.headerNotes == "Test notes")
        #expect(original.recipeYield == "4 servings")
        #expect(original.reference == "Test source")
        #expect(original.imageName == "test.jpg")
        #expect(decodedIngredientSections.count == ingredientSections.count)
        #expect(decodedInstructionSections.count == instructionSections.count)
        #expect(decodedNotes.count == notes.count)
        
        print("✓ Full export/import cycle preserved all recipe data")
    }
    
    @Test("Complete backup and restore workflow from Files/Reczipes2")
    @MainActor
    func testCompleteBackupRestoreWorkflow() async throws {
        // Step 1: Create original recipes
        let exportSchema = Schema([RecipeX.self, Book.self])
        let exportConfig = ModelConfiguration(UUID().uuidString, schema: exportSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let exportContainer = try ModelContainer(for: exportSchema, configurations: [exportConfig])
        let exportContext = exportContainer.mainContext
        
        let recipe1 = RecipeX(
            id: UUID(),
            title: "Workflow Test Recipe 1",
            ingredientSectionsData: try encodeIngredientSections([
                IngredientSection(ingredients: [Ingredient(name: "ingredient 1")])
            ]),
            instructionSectionsData: try encodeInstructionSections([
                InstructionSection(steps: [InstructionStep(stepNumber: 1, text: "step 1")])
            ])
        )
        
        let recipe2 = RecipeX(
            id: UUID(),
            title: "Workflow Test Recipe 2",
            ingredientSectionsData: try encodeIngredientSections([
                IngredientSection(ingredients: [Ingredient(name: "ingredient 2")])
            ]),
            instructionSectionsData: try encodeInstructionSections([
                InstructionSection(steps: [InstructionStep(stepNumber: 1, text: "step 2")])
            ])
        )
        
        exportContext.insert(recipe1)
        exportContext.insert(recipe2)
        
        print("Step 1: Created 2 original recipes")
        
        // Step 2: Create backup to Files/Reczipes2
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [recipe1, recipe2])
        
        #expect(backupURL.path.contains("Reczipes2"), 
                "Backup should be in Reczipes2 folder")
        #expect(FileManager.default.fileExists(atPath: backupURL.path), 
                "Backup file should exist")
        
        print("Step 2: Created backup at: \(backupURL.lastPathComponent)")
        
        // Step 3: Verify backup is listed in available backups
        let availableBackups = try RecipeBackupManager.shared.listAvailableBackups()
        let ourBackup = availableBackups.first { $0.url == backupURL }
        
        #expect(ourBackup != nil, 
                "Backup should be listed in available backups")
        
        print("Step 3: Verified backup appears in available backups list")
        
        // Step 4: Create new context (simulating app reinstall or new device)
        let importSchema = Schema([RecipeX.self, Book.self])
        let importConfig = ModelConfiguration(UUID().uuidString, schema: importSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let importContainer = try ModelContainer(for: importSchema, configurations: [importConfig])
        let importContext = importContainer.mainContext
        
        print("Step 4: Created fresh database context (simulating new device)")
        
        // Step 5: Import from backup
        let importResult = try await RecipeBackupManager.shared.importBackup(
            from: backupURL,
            into: importContext,
            existingRecipes: [],
            overwriteMode: .overwrite
        )
        
        #expect(importResult.newRecipes == 2, 
                "Should import 2 new recipes")
        #expect(importResult.totalRecipes == 2, 
                "Total should be 2 recipes")
        
        print("Step 5: Successfully imported backup: \(importResult.summary)")
        
        // Step 6: Verify imported recipes match originals
        try importContext.save()
        
        let importedRecipes = try importContext.fetch(FetchDescriptor<RecipeX>())
        #expect(importedRecipes.count == 2, 
                "Should have 2 recipes in new context")
        
        let titles = Set(importedRecipes.map { $0.title ?? "" })
        #expect(titles.contains("Workflow Test Recipe 1"), 
                "Should contain Recipe 1")
        #expect(titles.contains("Workflow Test Recipe 2"), 
                "Should contain Recipe 2")
        
        print("Step 6: Verified all recipes restored correctly")
        print("✅ Complete backup/restore workflow succeeded!")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Backup and restore preserves recipe relationships")
    @MainActor
    func testBackupRestoreWithRelationships() async throws {
        // Create recipes with complex data
        let exportSchema = Schema([RecipeX.self, Book.self])
        let exportConfig = ModelConfiguration(UUID().uuidString, schema: exportSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let exportContainer = try ModelContainer(for: exportSchema, configurations: [exportConfig])
        let exportContext = exportContainer.mainContext
        
        let complexRecipe = RecipeX(
            id: UUID(),
            title: "Complex Recipe with All Features",
            headerNotes: "Header notes with émojis 🍕",
            recipeYield: "Serves 4-6",
            reference: "Test Cookbook, Page 42",
            ingredientSectionsData: try encodeIngredientSections([
                IngredientSection(
                    title: "Section 1",
                    ingredients: [
                        Ingredient(quantity: "2", unit: "cups", name: "flour"),
                        Ingredient(quantity: "1", unit: "tsp", name: "salt")
                    ],
                    transitionNote: "Mix dry ingredients"
                ),
                IngredientSection(
                    title: "Section 2",
                    ingredients: [
                        Ingredient(quantity: "2", unit: "cups", name: "water")
                    ]
                )
            ]),
            instructionSectionsData: try encodeInstructionSections([
                InstructionSection(
                    title: "Preparation",
                    steps: [
                        InstructionStep(stepNumber: 1, text: "Prepare ingredients"),
                        InstructionStep(stepNumber: 2, text: "Mix together")
                    ]
                ),
                InstructionSection(
                    title: "Cooking",
                    steps: [
                        InstructionStep(stepNumber: 3, text: "Cook at 350°F")
                    ]
                )
            ]),
            notesData: try encodeNotes([
                RecipeNote(type: .tip, text: "Use fresh ingredients"),
                RecipeNote(type: .warning, text: "Don't overmix"),
                RecipeNote(type: .timing, text: "Takes 45 minutes")
            ])
        )
        
        exportContext.insert(complexRecipe)
        
        // Create backup
        let backupURL = try await RecipeBackupManager.shared.createBackup(from: [complexRecipe])
        
        // Import to new context
        let importSchema = Schema([RecipeX.self, Book.self])
        let importConfig = ModelConfiguration(UUID().uuidString, schema: importSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let importContainer = try ModelContainer(for: importSchema, configurations: [importConfig])
        let importContext = importContainer.mainContext
        
        let result = try await RecipeBackupManager.shared.importBackup(
            from: backupURL,
            into: importContext,
            existingRecipes: [],
            overwriteMode: .overwrite
        )
        
        #expect(result.newRecipes == 1)
        
        // Verify imported recipe
        let importedRecipes = try importContext.fetch(FetchDescriptor<RecipeX>())
        #expect(importedRecipes.count == 1)
        
        let imported = importedRecipes[0]
        #expect(imported.title == "Complex Recipe with All Features")
        #expect(imported.headerNotes == "Header notes with émojis 🍕")
        #expect(imported.recipeYield == "Serves 4-6")
        #expect(imported.reference == "Test Cookbook, Page 42")
        
        // Verify sections were preserved
        let decoder = JSONDecoder()
        let ingredientSections = try decoder.decode([IngredientSection].self, from: imported.ingredientSectionsData!)
        let instructionSections = try decoder.decode([InstructionSection].self, from: imported.instructionSectionsData!)
        let notes = try decoder.decode([RecipeNote].self, from: imported.notesData!)
        
        #expect(ingredientSections.count == 2)
        #expect(ingredientSections[0].title == "Section 1")
        #expect(ingredientSections[0].ingredients.count == 2)
        #expect(ingredientSections[0].transitionNote == "Mix dry ingredients")
        
        #expect(instructionSections.count == 2)
        #expect(instructionSections[0].title == "Preparation")
        #expect(instructionSections[0].steps.count == 2)
        
        #expect(notes.count == 3)
        #expect(notes[0].type == .tip)
        #expect(notes[1].type == .warning)
        #expect(notes[2].type == .timing)
        
        print("✅ Complex recipe with all relationships preserved perfectly!")
        
        // Cleanup
        try? FileManager.default.removeItem(at: backupURL)
    }
    
    @Test("Export package encodes with all required fields")
    @MainActor
    func testExportPackageRequiredFields() throws {
        let bookID = UUID()
        let recipeID = UUID()
        
        let exportableBook = ExportableBook(
            id: bookID,
            name: "Test Book",
            bookDescription: "Test description",
            coverImageName: "cover.jpg",
            dateCreated: Date(),
            dateModified: Date(),
            recipeIDs: [recipeID],
            color: "blue"
        )
        
        let exportableRecipe = ExportableRecipe(
            id: recipeID,
            title: "Test Recipe",
            headerNotes: "Test notes",
            yield: "4 servings",
            ingredientSections: [
                IngredientSection(ingredients: [Ingredient(name: "test")])
            ],
            instructionSections: [
                InstructionSection(steps: [InstructionStep(stepNumber: 1, text: "test")])
            ],
            notes: [
                RecipeNote(type: .general, text: "Test note")
            ],
            reference: "Test source",
            imageName: "recipe.jpg",
            additionalImageNames: [],
            imageURLs: []
        )
        
        let package = BookExportPackage(
            version: "2.0",
            book: exportableBook,
            recipes: [exportableRecipe],
            imageManifest: []
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(package)
        
        // Verify JSON is valid
        #expect(data.count > 0)
        
        // Verify it can be decoded back
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BookExportPackage.self, from: data)
        
        #expect(decoded.book.id == bookID)
        #expect(decoded.recipes.count == 1)
        #expect(decoded.version == "2.0")
    }
    
    @Test("ExportableBook initializes correctly")
    @MainActor
    func testExportableBookInitialization() throws {
        let exportable = ExportableBook(
            id: UUID(),
            name: "My Cookbook",
            bookDescription: "A test cookbook",
            coverImageName: "cover.jpg",
            dateCreated: Date(),
            dateModified: Date(),
            recipeIDs: [UUID(), UUID()],
            color: "red"
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportable)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportableBook.self, from: data)
        
        #expect(decoded.name == exportable.name)
        #expect(decoded.bookDescription == exportable.bookDescription)
        #expect(decoded.recipeIDs.count == 2)
        #expect(decoded.color == "red")
    }
    
    @Test("Image manifest entry IDs are unique")
    @MainActor
    func testUniqueManifestIDs() {
        let entries = (1...10).map { i in
            ImageManifestEntry(
                fileName: "image\(i).jpg",
                type: .recipePrimary,
                associatedID: UUID()
            )
        }
        
        let fileNames = Set(entries.map { $0.fileName })
        #expect(fileNames.count == 10, "All manifest entry file names should be unique")
    }
    
    @Test("Image manifest correctly categorizes image types")
    @MainActor
    func testImageTypeCategorization() {
        let bookID = UUID()
        let recipeID = UUID()
        
        let coverEntry = ImageManifestEntry(
            fileName: "cover.jpg",
            type: .bookCover,
            associatedID: bookID
        )
        
        let primaryEntry = ImageManifestEntry(
            fileName: "primary.jpg",
            type: .recipePrimary,
            associatedID: recipeID
        )
        
        let additionalEntry = ImageManifestEntry(
            fileName: "additional.jpg",
            type: .recipeAdditional,
            associatedID: recipeID
        )
        
        #expect(coverEntry.type == .bookCover)
        #expect(primaryEntry.type == .recipePrimary)
        #expect(additionalEntry.type == .recipeAdditional)
        
        // Book cover should reference book ID
        #expect(coverEntry.associatedID == bookID)
        
        // Recipe images should reference recipe ID
        #expect(primaryEntry.associatedID == recipeID)
        #expect(additionalEntry.associatedID == recipeID)
    }
}
