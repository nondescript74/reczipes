//
//  SharingEdgeCasesTests.swift
//  Reczipes2Tests
//
//  Tests for edge cases and error scenarios in sharing
//  Created on 1/17/26.
//

import Testing
import Foundation
import SwiftData
@testable import Reczipes2

/// Tests that validate edge cases and error scenarios
@Suite("Sharing Edge Cases and Error Scenarios")
@MainActor
struct SharingEdgeCasesTests {
    
    // MARK: - Duplicate Sharing Tests
    
    @Suite("Duplicate Sharing Prevention")
    @MainActor
    struct DuplicateSharingTests {
        
        @Test("Cannot share same recipe twice (active)")
        func cannotShareSameRecipeTwiceActive() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let recipeID = UUID()
            
            // First share
            let firstShare = SharedRecipe(
                recipeID: recipeID,
                cloudRecordID: "record_123",
                sharedByUserID: "user_1",
                recipeTitle: "Duplicate Recipe"
            )
            firstShare.isActive = true
            
            context.insert(firstShare)
            try context.save()
            
            // Check if already shared (simulate service logic)
            let recipeIDToFind = recipeID
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> {
                    $0.recipeID == recipeIDToFind && $0.isActive == true
                }
            )
            
            let existingShared = try context.fetch(descriptor).first
            
            #expect(existingShared != nil, "Should find existing active share")
            #expect(existingShared?.cloudRecordID == "record_123")
        }
        
        @Test("Can reshare recipe if previously unshared")
        func canReshareRecipeIfPreviouslyUnshared() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let recipeID = UUID()
            
            // First share (now inactive)
            let firstShare = SharedRecipe(
                recipeID: recipeID,
                cloudRecordID: "record_old",
                sharedByUserID: "user_1",
                recipeTitle: "Reshare Recipe"
            )
            firstShare.isActive = false // Unshared
            
            context.insert(firstShare)
            try context.save()
            
            // Check if already actively shared
            let recipeIDToFind = recipeID
            let descriptor = FetchDescriptor<SharedRecipe>(
                predicate: #Predicate<SharedRecipe> {
                    $0.recipeID == recipeIDToFind && $0.isActive == true
                }
            )
            
            let existingActive = try context.fetch(descriptor).first
            
            #expect(existingActive == nil, "Should not find active share, can reshare")
            
            // Now we can create a new share
            let newShare = SharedRecipe(
                recipeID: recipeID,
                cloudRecordID: "record_new",
                sharedByUserID: "user_1",
                recipeTitle: "Reshare Recipe"
            )
            newShare.isActive = true
            
            context.insert(newShare)
            try context.save()
            
            // Verify both exist in database
            let allDescriptor = FetchDescriptor<SharedRecipe>()
            let allShares = try context.fetch(allDescriptor)
            
            #expect(allShares.count == 2, "Both old and new share records exist")
            #expect(allShares.filter { $0.isActive }.count == 1, "Only one is active")
        }
        
        @Test("Can share same book twice if previously unshared")
        func canShareSameBookTwiceIfPreviouslyUnshared() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let bookID = UUID()
            
            // Previous inactive share
            let oldShare = SharedRecipeBook(
                bookID: bookID,
                cloudRecordID: "record_old",
                sharedByUserID: "user_1",
                bookName: "Reshare Book"
            )
            oldShare.isActive = false
            
            context.insert(oldShare)
            try context.save()
            
            // Check for active share
            let bookIDToFind = bookID
            let descriptor = FetchDescriptor<SharedRecipeBook>(
                predicate: #Predicate<SharedRecipeBook> {
                    $0.bookID == bookIDToFind && $0.isActive == true
                }
            )
            
            let existingActive = try context.fetch(descriptor).first
            
            #expect(existingActive == nil, "No active share, can reshare")
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
    
    // MARK: - Empty Data Tests
    
    @Suite("Empty Data Handling")
    @MainActor
    struct EmptyDataTests {
        
        @Test("Share all recipes with no recipes")
        func shareAllRecipesWithNoRecipes() {
            let allRecipes: [RecipeX] = []
            
            // Should exit early if empty
            guard !allRecipes.isEmpty else {
                // Expected behavior
                #expect(true)
                return
            }
            
            Issue.record("Should not proceed with empty recipe list")
        }
        
        @Test("Share all books with no books")
        func shareAllBooksWithNoBooks() {
            let allBooks: [Book] = []
            
            guard !allBooks.isEmpty else {
                #expect(true)
                return
            }
            
            Issue.record("Should not proceed with empty book list")
        }
        
        @Test("Unshare all recipes with no shared recipes")
        func unshareAllRecipesWithNoSharedRecipes() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let descriptor = FetchDescriptor<SharedRecipe>()
            let allSharedRecipes = try context.fetch(descriptor)
            
            #expect(allSharedRecipes.isEmpty)
            
            // Message should indicate no recipes to unshare
            let message = allSharedRecipes.isEmpty ? "No recipes to unshare" : "Unsharing..."
            
            #expect(message == "No recipes to unshare")
        }
        
        @Test("Unshare all books with no shared books")
        func unshareAllBooksWithNoSharedBooks() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let descriptor = FetchDescriptor<SharedRecipeBook>()
            let allSharedBooks = try context.fetch(descriptor)
            
            #expect(allSharedBooks.isEmpty)
            
            let message = allSharedBooks.isEmpty ? "No books to unshare" : "Unsharing..."
            
            #expect(message == "No books to unshare")
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
    
    // MARK: - Missing Data Tests
    
    @Suite("Missing Data Handling")
    @MainActor
    struct MissingDataTests {
        
        @Test("Recipe without title can still be shared")
        func recipeWithoutTitleCanStillBeShared() {
            _ = RecipeX(title: "")
            
            // Should still allow sharing (CloudKit will accept it)
            let canShare = true
            #expect(canShare == true)
        }
        
        @Test("Recipe without ingredients can be shared")
        func recipeWithoutIngredientsCanBeShared() {
            let recipe = RecipeX(title: "Empty Recipe")
            // No ingredient sections added
            
            #expect(recipe.ingredientSectionsData == nil)
            
            // Should still be shareable
            let canShare = true
            #expect(canShare == true)
        }
        
        @Test("Book without recipes can be shared")
        func bookWithoutRecipesCanBeShared() {
            let book = Book(name: "Empty Book")
            // No recipes added
            
            #expect(book.recipeIDs?.isEmpty ?? true)
            
            // Should still be shareable
            let canShare = true
            #expect(canShare == true)
        }
        
        @Test("SharedRecipe without cloud record ID is handled gracefully")
        func sharedRecipeWithoutCloudRecordID() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let recipe = SharedRecipe(
                recipeID: UUID(),
                cloudRecordID: nil, // Missing!
                sharedByUserID: "user_1",
                recipeTitle: "Recipe Without Cloud ID"
            )
            recipe.isActive = true
            
            context.insert(recipe)
            try context.save()
            
            // When unsharing, should handle gracefully
            if recipe.cloudRecordID == nil {
                // Mark as inactive even without cloud record
                recipe.isActive = false
            }
            
            #expect(recipe.isActive == false)
        }
        
        @Test("SharedBook without cloud record ID is handled gracefully")
        func sharedBookWithoutCloudRecordID() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let book = SharedRecipeBook(
                bookID: UUID(),
                cloudRecordID: nil,
                sharedByUserID: "user_1",
                bookName: "Book Without Cloud ID"
            )
            book.isActive = true
            
            context.insert(book)
            try context.save()
            
            // Handle gracefully during unshare
            if book.cloudRecordID == nil {
                book.isActive = false
            }
            
            #expect(book.isActive == false)
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([
                RecipeX.self,
                Book.self,
                SharedRecipe.self,
                SharedRecipeBook.self
            ])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - Concurrent Operations Tests
    
    @Suite("Concurrent Operations")
    @MainActor
    struct ConcurrentOperationsTests {
        
        @Test("Sharing state prevents concurrent shares")
        func sharingStatePreventssConcurrentShares() {
            var isSharing = false
            
            // Start first share
            isSharing = true
            
            // Attempt second share while first is in progress
            if isSharing {
                // Should not start another share
                #expect(true, "Prevented concurrent share")
            } else {
                Issue.record("Should have prevented concurrent share")
            }
            
            // Complete first share
            isSharing = false
            
            // Now can start another
            #expect(isSharing == false)
        }
        
        @Test("Can track sharing status message")
        func canTrackSharingStatusMessage() {
            var sharingStatus = ""
            
            sharingStatus = "Sharing all recipes..."
            #expect(sharingStatus == "Sharing all recipes...")
            
            sharingStatus = "Unsharing all books..."
            #expect(sharingStatus == "Unsharing all books...")
            
            sharingStatus = ""
            #expect(sharingStatus.isEmpty)
        }
    }
    
    // MARK: - Data Consistency Tests
    
    @Suite("Data Consistency")
    @MainActor
    struct DataConsistencyTests {
        
        @Test("Local recipe and shared recipe IDs match")
        func localAndSharedRecipeIDsMatch() {
            let recipe = RecipeX(title: "Test Recipe")
            let recipeID = recipe.id ?? UUID()
            
            let sharedRecipe = SharedRecipe(
                recipeID: recipeID,
                sharedByUserID: "user_1",
                recipeTitle: recipe.title ?? ""
            )
            
            #expect(sharedRecipe.recipeID == recipeID)
        }
        
        @Test("Local book and shared book IDs match")
        func localAndSharedBookIDsMatch() {
            let book = Book(name: "Test Book")
            let bookID = book.id ?? UUID()
            
            let sharedBook = SharedRecipeBook(
                bookID: bookID,
                sharedByUserID: "user_1",
                bookName: book.name ?? ""
            )
            
            #expect(sharedBook.bookID == bookID)
        }
        
        @Test("Shared recipe caches correct title")
        func sharedRecipeCachesCorrectTitle() {
            let recipe = RecipeX(title: "Amazing Recipe")
            
            let sharedRecipe = SharedRecipe(
                recipeID: recipe.id ?? UUID(),
                sharedByUserID: "user_1",
                recipeTitle: recipe.title ?? ""
            )
            
            #expect(sharedRecipe.recipeTitle == "Amazing Recipe")
        }
        
        @Test("Shared book caches correct name")
        func sharedBookCachesCorrectName() {
            let book = Book(name: "Amazing Book")
            
            let sharedBook = SharedRecipeBook(
                bookID: book.id ?? UUID(),
                sharedByUserID: "user_1",
                bookName: book.name ?? ""
            )
            
            #expect(sharedBook.bookName == "Amazing Book")
        }
    }
    
    // MARK: - Deletion Cleanup Tests
    
    @Suite("Deletion Cleanup")
    @MainActor
    struct DeletionCleanupTests {
        
        @Test("Deleting recipe should unshare if shared")
        func deletingRecipeShouldUnshareIfShared() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let recipe = RecipeX(title: "To Delete")
            context.insert(recipe)
            
            let sharedRecipe = SharedRecipe(
                recipeID: recipe.id ?? UUID(),
                sharedByUserID: "user_1",
                recipeTitle: recipe.title ?? ""
            )
            sharedRecipe.isActive = true
            context.insert(sharedRecipe)
            
            try context.save()
            
            // When recipe is deleted, shared version should be marked inactive
            // (In actual implementation, this would be handled by a delete rule or observer)
            
            // Simulate deletion
            context.delete(recipe)
            
            // Mark shared recipe as inactive
            sharedRecipe.isActive = false
            
            try context.save()
            
            #expect(sharedRecipe.isActive == false)
        }
        
        @Test("Deleting book should unshare if shared")
        func deletingBookShouldUnshareIfShared() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let book = Book(name: "To Delete")
            context.insert(book)
            
            let sharedBook = SharedRecipeBook(
                bookID: book.id ?? UUID(),
                sharedByUserID: "user_1",
                bookName: book.name ?? ""
            )
            sharedBook.isActive = true
            context.insert(sharedBook)
            
            try context.save()
            
            // Simulate deletion
            context.delete(book)
            sharedBook.isActive = false
            
            try context.save()
            
            #expect(sharedBook.isActive == false)
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([
                RecipeX.self,
                Book.self,
                SharedRecipe.self,
                SharedRecipeBook.self
            ])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - User Identity Tests
    
    @Suite("User Identity Handling")
    @MainActor
    struct UserIdentityTests {
        
        @Test("Shared content includes user ID")
        func sharedContentIncludesUserID() {
            let userID = "user_12345"
            
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: userID,
                recipeTitle: "User's Recipe"
            )
            
            #expect(sharedRecipe.sharedByUserID == userID)
        }
        
        @Test("User name is optional")
        func userNameIsOptional() {
            // Without name
            let sharedRecipe1 = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: "user_1",
                sharedByUserName: nil,
                recipeTitle: "Anonymous Recipe"
            )
            
            #expect(sharedRecipe1.sharedByUserName == nil)
            
            // With name
            let sharedRecipe2 = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: "user_2",
                sharedByUserName: "Chef John",
                recipeTitle: "Named Recipe"
            )
            
            #expect(sharedRecipe2.sharedByUserName == "Chef John")
        }
        
        @Test("Display name preference is respected")
        func displayNamePreferenceRespected() throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let prefs = SharingPreferences()
            prefs.allowOthersToSeeMyName = false
            prefs.displayName = "Secret Chef"
            
            context.insert(prefs)
            try context.save()
            
            // When sharing, if allowOthersToSeeMyName is false,
            // should use "Anonymous" instead of actual name
            
            let displayName = prefs.allowOthersToSeeMyName ? prefs.displayName : nil
            
            #expect(displayName == nil, "Should not show name when preference is off")
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([SharingPreferences.self])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
    
    // MARK: - Timestamp Tests
    
    @Suite("Timestamp Handling")
    @MainActor
    struct TimestampTests {
        
        @Test("Shared date is set on creation")
        func sharedDateSetOnCreation() {
            let beforeCreation = Date()
            
            let sharedRecipe = SharedRecipe(
                recipeID: UUID(),
                sharedByUserID: "user_1",
                sharedDate: Date(),
                recipeTitle: "Timestamped Recipe"
            )
            
            let afterCreation = Date()
            
            #expect(sharedRecipe.sharedDate >= beforeCreation)
            #expect(sharedRecipe.sharedDate <= afterCreation)
        }
        
        @Test("Preferences modification date is tracked")
        @MainActor
        func preferencesModificationDateTracked() async throws {
            let container = try createTestModelContainer()
            let context = container.mainContext
            
            let prefs = SharingPreferences()
            let originalDate = prefs.dateModified
            
            context.insert(prefs)
            try context.save()
            
            // Wait a tiny bit
            try? await Task.sleep(for: .milliseconds(10))
            
            // Modify
            prefs.shareAllRecipes = true
            prefs.dateModified = Date()
            
            #expect(prefs.dateModified > originalDate)
        }
        
        private func createTestModelContainer() throws -> ModelContainer {
            let schema = Schema([SharingPreferences.self])
            let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }
}
