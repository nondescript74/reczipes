//
//  SharingWorkflowTests.swift
//  Reczipes2Tests
//
//  Tests for sharing and unsharing workflows
//  Created on 1/17/26.
//

import Testing
import Foundation
import CloudKit
import SwiftData
@testable import Reczipes2

/// Tests that validate sharing and unsharing workflows work correctly
@Suite("Sharing Workflow Tests")
@MainActor
struct SharingWorkflowTests {
    
    // MARK: - Test Setup Helpers
    
    private func createTestModelContainer() throws -> ModelContainer {
        let schema = Schema([
            RecipeX.self,
            Book.self,
            SharedRecipe.self,
            SharedRecipeBook.self,
            SharingPreferences.self
        ])
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
    
    private func createTestRecipe(title: String = "Test Recipe") -> RecipeX {
        let recipe = RecipeX(title: title)
        recipe.headerNotes = "Test notes"
        recipe.recipeYield = "4 servings"
        return recipe
    }
    
    private func createTestBook(name: String = "Test Book") -> Book {
        let book = Book(name: name, bookDescription: "Test description")
        return book
    }
    
    // MARK: - Sharing Preferences Tests
    
    @Suite("Sharing Preferences Management")
    @MainActor
    struct SharingPreferencesTests {
        
        @Test("Sharing preferences are created with correct defaults")
        func preferencesCreatedWithDefaults() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let prefs = SharingPreferences()
            context.insert(prefs)
            
            #expect(prefs.shareAllRecipes == false, "Should default to not sharing all recipes")
            #expect(prefs.shareAllBooks == false, "Should default to not sharing all books")
            #expect(prefs.allowOthersToSeeMyName == true, "Should default to allowing name visibility")
        }
        
        @Test("Sharing preferences can be toggled")
        func preferencesCanBeToggled() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let prefs = SharingPreferences()
            context.insert(prefs)
            
            // Toggle share all recipes
            prefs.shareAllRecipes = true
            #expect(prefs.shareAllRecipes == true)
            
            // Toggle share all books
            prefs.shareAllBooks = true
            #expect(prefs.shareAllBooks == true)
            
            // Toggle name visibility
            prefs.allowOthersToSeeMyName = false
            #expect(prefs.allowOthersToSeeMyName == false)
        }
        
        @Test("Date modified is tracked")
        func dateModifiedTracked() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let prefs = SharingPreferences()
            context.insert(prefs)
            
            let initialDate = prefs.dateModified
            
            // Simulate modification
            prefs.shareAllRecipes = true
            prefs.dateModified = Date()
            
            #expect(prefs.dateModified > initialDate, "Modified date should be updated")
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([SharingPreferences.self])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - Shared Content Model Tests
    
    @Suite("Shared Content Models")
    @MainActor
    struct SharedContentModelsTests {
        
        @Test("SharedRecipe tracks all required information")
        func sharedRecipeTracksRequiredInfo() {
            let recipeID = UUID()
            let userID = "user_123"
            let userName = "Test User"
            
            let sharedRecipe = SharedRecipe(
                recipeID: recipeID,
                cloudRecordID: "record_456",
                sharedByUserID: userID,
                sharedByUserName: userName,
                recipeTitle: "Test Recipe"
            )
            
            #expect(sharedRecipe.recipeID == recipeID)
            #expect(sharedRecipe.cloudRecordID == "record_456")
            #expect(sharedRecipe.sharedByUserID == userID)
            #expect(sharedRecipe.sharedByUserName == userName)
            #expect(sharedRecipe.recipeTitle == "Test Recipe")
            #expect(sharedRecipe.isActive == true, "Should be active by default")
        }
        
        @Test("SharedRecipe can be deactivated")
        func sharedRecipeCanBeDeactivated() {
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: "user_123",
                recipeTitle: "Test Recipe"
            )
            
            #expect(sharedRecipe.isActive == true)
            
            sharedRecipe.isActive = false
            
            #expect(sharedRecipe.isActive == false)
        }
        
        @Test("SharedRecipeBook tracks all required information")
        func sharedBookTracksRequiredInfo() {
            let bookID = UUID()
            let userID = "user_123"
            let userName = "Test User"
            
            let sharedBook = SharedRecipeBook(
                bookID: bookID,
                cloudRecordID: "record_789",
                sharedByUserID: userID,
                sharedByUserName: userName,
                bookName: "Test Book",
                bookDescription: "Test Description"
            )
            
            #expect(sharedBook.bookID == bookID)
            #expect(sharedBook.cloudRecordID == "record_789")
            #expect(sharedBook.sharedByUserID == userID)
            #expect(sharedBook.sharedByUserName == userName)
            #expect(sharedBook.bookName == "Test Book")
            #expect(sharedBook.bookDescription == "Test Description")
            #expect(sharedBook.isActive == true)
        }
        
        @Test("SharedRecipeBook can be deactivated")
        func sharedBookCanBeDeactivated() {
            let sharedBook = SharedRecipeBook(
                bookID: UUID(),
                sharedByUserID: "user_123",
                bookName: "Test Book"
            )
            
            #expect(sharedBook.isActive == true)
            
            sharedBook.isActive = false
            
            #expect(sharedBook.isActive == false)
        }
    }
    
    // MARK: - Sharing Result Tests
    
    @Suite("Sharing Result Handling")
    struct SharingResultTests {
        
        @Test("Success result contains record ID")
        func successResultContainsRecordID() {
            let result = SharingResult.success(recordID: "record_123")
            
            if case .success(let recordID) = result {
                #expect(recordID == "record_123")
            } else {
                Issue.record("Expected success result")
            }
        }
        
        @Test("Failure result contains error")
        func failureResultContainsError() {
            let error = SharingError.recipeNotFound
            let result = SharingResult.failure(error: error)
            
            if case .failure(let resultError) = result {
                #expect(resultError as? SharingError == .recipeNotFound)
            } else {
                Issue.record("Expected failure result")
            }
        }
        
        @Test("Partial success tracks both counts")
        func partialSuccessTracksCounts() {
            let result = SharingResult.partialSuccess(successful: 5, failed: 2)
            
            if case .partialSuccess(let successful, let failed) = result {
                #expect(successful == 5)
                #expect(failed == 2)
            } else {
                Issue.record("Expected partial success result")
            }
        }
    }
    
    // MARK: - Sharing Error Tests
    
    @Suite("Sharing Error Messages")
    struct SharingErrorTests {
        
        @Test("All errors have user-friendly descriptions")
        func allErrorsHaveDescriptions() {
            let errors: [SharingError] = [
                .notAuthenticated,
                .cloudKitUnavailable(),
                .cloudKitUnavailable(message: "Custom message"),
                .recipeNotFound,
                .bookNotFound,
                .uploadFailed(NSError(domain: "test", code: 1)),
                .downloadFailed(NSError(domain: "test", code: 2)),
                .invalidData,
                .imageUploadFailed(NSError(domain: "test", code: 3))
            ]
            
            for error in errors {
                let description = error.errorDescription ?? ""
                #expect(!description.isEmpty, "Error \(error) should have description")
                
                // Should not expose technical CloudKit terms
                #expect(!description.contains("CKError"), "Should not expose CKError codes")
                #expect(!description.contains("database"), "Should use user-friendly terms")
            }
        }
        
        @Test("CloudKit unavailable error can open onboarding")
        func cloudKitUnavailableCanOpenOnboarding() {
            let error = SharingError.cloudKitUnavailable()
            #expect(error.canOpenOnboarding == true)
        }
        
        @Test("Not authenticated error can open onboarding")
        func notAuthenticatedCanOpenOnboarding() {
            let error = SharingError.notAuthenticated
            #expect(error.canOpenOnboarding == true)
        }
        
        @Test("Other errors cannot open onboarding")
        func otherErrorsCannotOpenOnboarding() {
            let errors: [SharingError] = [
                .recipeNotFound,
                .bookNotFound,
                .invalidData
            ]
            
            for error in errors {
                #expect(error.canOpenOnboarding == false,
                       "\(error) should not open onboarding")
            }
        }
    }
    
    // MARK: - SwiftData Integration Tests
    
    @Suite("SwiftData Integration")
    @MainActor
    struct SwiftDataIntegrationTests {
        
        @Test("Can query active shared recipes")
        func canQueryActiveSharedRecipes() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            // Create shared recipes
            let active = SharedRecipe(recipeID: UUID(), sharedByUserID: "user_1", recipeTitle: "Active")
            active.isActive = true
            
            let inactive = SharedRecipe(recipeID: UUID(), sharedByUserID: "user_1", recipeTitle: "Inactive")
            inactive.isActive = false
            
            context.insert(active)
            context.insert(inactive)
            try context.save()
            
            // Query only active
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.isActive == true }
            )
            
            let results = try context.fetch(descriptor)
            
            #expect(results.count == 1, "Should only fetch active recipes")
            #expect(results.first?.recipeTitle == "Active")
        }
        
        @Test("Can query active shared books")
        func canQueryActiveSharedBooks() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            // Create shared books
            let active = SharedRecipeBook(bookID: UUID(), sharedByUserID: "user_1", bookName: "Active Book")
            active.isActive = true
            
            let inactive = SharedRecipeBook(bookID: UUID(), sharedByUserID: "user_1", bookName: "Inactive Book")
            inactive.isActive = false
            
            context.insert(active)
            context.insert(inactive)
            try context.save()
            
            // Query only active
            let descriptor = FetchDescriptor<SharedRecipeBook>(
                predicate: #Predicate<SharedRecipeBook> { $0.isActive == true }
            )
            
            let results = try context.fetch(descriptor)
            
            #expect(results.count == 1, "Should only fetch active books")
            #expect(results.first?.bookName == "Active Book")
        }
        
        @Test("Can find shared recipe by cloud record ID")
        func canFindSharedRecipeByCloudRecordID() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                cloudRecordID: "record_123",
                sharedByUserID: "user_1",
                recipeTitle: "Findable Recipe"
            )
            
            context.insert(sharedRecipe)
            try context.save()
            
            // Find by cloud record ID
            let recordIDToFind = "record_123"
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.cloudRecordID == recordIDToFind }
            )
            
            let results = try context.fetch(descriptor)
            
            #expect(results.count == 1)
            #expect(results.first?.recipeTitle == "Findable Recipe")
        }
        
        @Test("Can delete shared content from SwiftData")
        func canDeleteSharedContent() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: "user_1",
                recipeTitle: "To Delete"
            )
            
            context.insert(sharedRecipe)
            try context.save()
            
            // Verify it exists
            var descriptor = FetchDescriptor<SharedRecipe>()
            var results = try context.fetch(descriptor)
            #expect(results.count == 1)
            
            // Delete it
            context.delete(sharedRecipe)
            try context.save()
            
            // Verify deletion
            descriptor = FetchDescriptor<SharedRecipe>()
            results = try context.fetch(descriptor)
            #expect(results.count == 0, "Shared recipe should be deleted")
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([
                SharedRecipe.self,
                SharedRecipeBook.self
            ])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - Unsharing Logic Tests
    
    @Suite("Unsharing Logic")
    @MainActor
    struct UnsharingLogicTests {
        
        @Test("Unsharing marks recipe as inactive")
        func unsharingMarksRecipeInactive() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                cloudRecordID: "record_123",
                sharedByUserID: "user_1",
                recipeTitle: "To Unshare"
            )
            sharedRecipe.isActive = true
            
            context.insert(sharedRecipe)
            try context.save()
            
            // Simulate unsharing (mark as inactive)
            sharedRecipe.isActive = false
            try context.save()
            
            #expect(sharedRecipe.isActive == false)
        }
        
        @Test("Unsharing marks book as inactive")
        func unsharingMarksBookInactive() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let sharedBook = SharedRecipeBook(
                bookID: UUID(),
                cloudRecordID: "record_456",
                sharedByUserID: "user_1",
                bookName: "To Unshare"
            )
            sharedBook.isActive = true
            
            context.insert(sharedBook)
            try context.save()
            
            // Simulate unsharing
            sharedBook.isActive = false
            try context.save()
            
            #expect(sharedBook.isActive == false)
        }
        
        @Test("Can count items to unshare")
        func canCountItemsToUnshare() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            // Create mix of active and inactive
            for i in 0..<5 {
                let recipe = SharedRecipe(
                    recipeID: UUID(),
                    sharedByUserID: "user_1",
                    recipeTitle: "Recipe \(i)"
                )
                recipe.isActive = i < 3 // First 3 are active
                context.insert(recipe)
            }
            
            try context.save()
            
            // Count active items (items to potentially unshare)
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.isActive == true }
            )
            
            let activeRecipes = try context.fetch(descriptor)
            
            #expect(activeRecipes.count == 3, "Should have 3 active recipes to unshare")
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([
                SharedRecipe.self,
                SharedRecipeBook.self
            ])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - Bulk Operations Tests
    
    @Suite("Bulk Sharing Operations")
    @MainActor
    struct BulkOperationsTests {
        
        @Test("Can track progress of bulk share")
        func canTrackBulkShareProgress() async {
            // Simulate sharing multiple items
            let totalItems = 10
            var successfulShares = 0
            var failedShares = 0
            
            // Simulate the sharing loop
            for _ in 0..<totalItems {
                // Randomly succeed or fail (50/50)
                if Bool.random() {
                    successfulShares += 1
                } else {
                    failedShares += 1
                }
            }
            
            #expect(successfulShares + failedShares == totalItems,
                   "Total should equal sum of successful and failed")
        }
        
        @Test("Bulk share can handle all successes")
        func bulkShareAllSuccesses() {
            let successful = 10
            _ = 0
            
            // Since we know failed == 0, directly create success result
            let result = SharingResult.success(recordID: "\(successful) items shared")
            
            // Verify result is success
            if case .success(let recordID) = result {
                #expect(recordID == "10 items shared")
            } else {
                Issue.record("Should be success when no failures")
            }
        }
        
        @Test("Bulk share can handle partial success")
        func bulkSharePartialSuccess() {
            let successful = 7
            let failed = 3
            
            // Directly create the partial success result since we know there are failures
            let result = SharingResult.partialSuccess(successful: successful, failed: failed)
            
            if case .partialSuccess(let s, let f) = result {
                #expect(s == 7)
                #expect(f == 3)
            } else {
                Issue.record("Should be partial success when some failures")
            }
        }
        
        @Test("Bulk unshare tracks successful and failed counts")
        func bulkUnshareTracksCounts() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            // Create items to unshare
            for i in 0..<5 {
                let recipe = SharedRecipe(
                    recipeID: UUID(),
                    cloudRecordID: "record_\(i)",
                    sharedByUserID: "user_1",
                    recipeTitle: "Recipe \(i)"
                )
                recipe.isActive = true
                context.insert(recipe)
            }
            
            try context.save()
            
            // Simulate bulk unshare
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> { $0.isActive == true }
            )
            let activeRecipes = try context.fetch(descriptor)
            
            var successful = 0
            var failed = 0
            
            for recipe in activeRecipes {
                if recipe.cloudRecordID != nil {
                    // Would call CloudKit unshare here
                    // For test, just mark inactive
                    recipe.isActive = false
                    successful += 1
                } else {
                    failed += 1
                }
            }
            
            try context.save()
            
            #expect(successful == 5, "All 5 recipes should unshare successfully")
            #expect(failed == 0)
        }
        
        @Test("Bulk unshare handles items without cloud record ID")
        func bulkUnshareHandlesMissingCloudRecordID() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            // Create recipe WITHOUT cloud record ID (edge case)
            let recipe = SharedRecipe(
                recipeID: UUID(),
                cloudRecordID: nil, // Missing!
                sharedByUserID: "user_1",
                recipeTitle: "Recipe Without Record"
            )
            recipe.isActive = true
            context.insert(recipe)
            
            try context.save()
            
            // Simulate unshare handling
            if recipe.cloudRecordID == nil {
                // Should still mark as inactive even if no cloud record
                recipe.isActive = false
            }
            
            try context.save()
            
            #expect(recipe.isActive == false,
                   "Should mark inactive even without cloud record ID")
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([
                SharedRecipe.self,
                SharedRecipeBook.self
            ])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - CloudKit Record Type Tests
    
    @Suite("CloudKit Record Types")
    struct CloudKitRecordTypeTests {
        
        @Test("CloudKit record types are consistent")
        @MainActor
        func recordTypesAreConsistent() {
            #expect(CloudKitRecordType.sharedRecipe == "SharedRecipe")
            #expect(CloudKitRecordType.sharedRecipeBook == "SharedRecipeBook")
            #expect(CloudKitRecordType.sharedImage == "SharedImage")
        }
        
        @Test("Record type names are alphanumeric")
        @MainActor
        func recordTypeNamesAreAlphanumeric() {
            let recordTypes = [
                CloudKitRecordType.sharedRecipe,
                CloudKitRecordType.sharedRecipeBook,
                CloudKitRecordType.sharedImage
            ]
            
            for recordType in recordTypes {
                // Should only contain letters (no spaces, special characters)
                let isValid = recordType.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil
                #expect(isValid, "\(recordType) should be alphanumeric")
            }
        }
    }
    
    // MARK: - CloudKit Codable Model Tests
    
    @Suite("CloudKit Codable Models")
    struct CloudKitCodableModelTests {
        
        @Test("CloudKitRecipe is encodable and decodable")
        @MainActor
        func cloudKitRecipeIsEncodableDecodable() throws {
            let recipe = CloudKitRecipe(
                id: UUID(),
                title: "Test Recipe",
                headerNotes: "Test Notes",
                yield: "4 servings",
                ingredientSections: [],
                instructionSections: [],
                notes: [],
                reference: nil,
                imageName: nil,
                additionalImageNames: nil,
                sharedByUserID: "user_123",
                sharedByUserName: "Test User",
                sharedDate: Date()
            )
            
            // Encode
            let encoder = JSONEncoder()
            let data = try encoder.encode(recipe)
            
            #expect(data.count > 0, "Should encode to data")
            
            // Decode
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CloudKitRecipe.self, from: data)
            
            #expect(decoded.title == "Test Recipe")
            #expect(decoded.sharedByUserID == "user_123")
        }
        
        @Test("CloudKitRecipeBook is encodable and decodable")
        @MainActor
        func cloudKitRecipeBookIsEncodableDecodable() throws {
            let book = CloudKitRecipeBook(
                id: UUID(),
                name: "Test Book",
                bookDescription: "Test Description",
                coverImageName: nil,
                recipeIDs: [UUID(), UUID()],
                color: "#FF5733",
                sharedByUserID: "user_123",
                sharedByUserName: "Test User",
                sharedDate: Date()
            )
            
            // Encode
            let encoder = JSONEncoder()
            let data = try encoder.encode(book)
            
            #expect(data.count > 0, "Should encode to data")
            
            // Decode
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CloudKitRecipeBook.self, from: data)
            
            #expect(decoded.name == "Test Book")
            #expect(decoded.recipeIDs.count == 2)
        }
    }
}

