//
//  ImageMigrationManager.swift
//  Reczipes2
//
//  Background image recompression manager for optimizing existing images
//

import Foundation
import SwiftData
import SwiftUI
import UIKit
import Combine

/// Manages background recompression of existing images to optimize storage
@MainActor
class ImageMigrationManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ImageMigrationManager()

    // MARK: - Published Properties

    @Published var isRunning = false
    @Published var progress: Double = 0.0
    @Published var currentRecipe: String = ""
    @Published var totalRecipes = 0
    @Published var processedRecipes = 0
    @Published var totalBytesSaved = 0

    // MARK: - UserDefaults Keys

    private let migrationVersionKey = "com.reczipes.imageMigration.version"
    private let currentMigrationVersion = 1 // Increment this to trigger new migrations

    // MARK: - Initialization

    private init() {}

    // MARK: - Migration Check

    /// Check if migration is needed
    func needsMigration() -> Bool {
        let completedVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        return completedVersion < currentMigrationVersion
    }

    /// Mark migration as completed
    private func markMigrationCompleted() {
        UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        AppLog.info("✅ Image migration v\(currentMigrationVersion) marked as completed", category: .image)
    }

    // MARK: - Migration Execution

    /// Start background image recompression
    func startMigration(modelContext: ModelContext) async {
        guard !isRunning else {
            AppLog.warning("Migration already running", category: .image)
            return
        }

        guard needsMigration() else {
            AppLog.info("Image migration not needed - already at version \(currentMigrationVersion)", category: .image)
            return
        }

        isRunning = true
        progress = 0.0
        processedRecipes = 0
        totalBytesSaved = 0

        AppLog.info("🔄 Starting image migration v\(currentMigrationVersion)...", category: .image)

        do {
            // Fetch all recipes
            let recipes = try await fetchAllRecipes(modelContext: modelContext)
            totalRecipes = recipes.count

            AppLog.info("📊 Found \(totalRecipes) recipes to process", category: .image)

            if totalRecipes == 0 {
                AppLog.info("No recipes to migrate", category: .image)
                markMigrationCompleted()
                isRunning = false
                return
            }

            // Process each recipe
            for (index, recipe) in recipes.enumerated() {
                currentRecipe = recipe.title ?? "Unknown Recipe"

                await processRecipe(recipe)

                processedRecipes = index + 1
                progress = Double(processedRecipes) / Double(totalRecipes)

                // Save periodically (every 10 recipes)
                if (index + 1) % 10 == 0 {
                    try modelContext.save()
                    AppLog.info("💾 Progress saved: \(processedRecipes)/\(totalRecipes) recipes processed", category: .image)
                }

                // Yield to avoid blocking UI
                await Task.yield()
            }

            // Final save
            try modelContext.save()

            // Log completion
            let savedMB = Double(totalBytesSaved) / 1_048_576 // Convert to MB
            AppLog.info("✅ Image migration completed successfully!", category: .image)
            AppLog.info("📊 Processed: \(processedRecipes) recipes", category: .image)
            AppLog.info("💾 Storage saved: \(String(format: "%.2f", savedMB)) MB", category: .image)

            markMigrationCompleted()

        } catch {
            AppLog.error("❌ Image migration failed: \(error.localizedDescription)", category: .image)
        }

        isRunning = false
        currentRecipe = ""
    }

    // MARK: - Recipe Processing

    /// Fetch all recipes from the database
    private func fetchAllRecipes(modelContext: ModelContext) async throws -> [RecipeX] {
        let descriptor = FetchDescriptor<RecipeX>()
        return try modelContext.fetch(descriptor)
    }

    /// Process a single recipe's images
    private func processRecipe(_ recipe: RecipeX) async {
        var recipeBytesSaved = 0

        // Process main image
        if let imageData = recipe.imageData {
            let originalSize = imageData.count

            // Only recompress if image is larger than target
            if originalSize > ImageCompressionUtility.targetMaxSize {
                if let image = UIImage(data: imageData),
                   let compressedData = ImageCompressionUtility.compressImage(image) {

                    let newSize = compressedData.count
                    let saved = originalSize - newSize

                    if saved > 0 {
                        recipe.imageData = compressedData
                        recipe.imageHash = RecipeX.calculateImageHash(from: compressedData)
                        recipe.markAsModified()

                        recipeBytesSaved += saved
                        totalBytesSaved += saved

                        AppLog.debug("  Main image: \(originalSize / 1024)KB → \(newSize / 1024)KB (saved \(saved / 1024)KB)", category: .image)
                    }
                }
            }
        }

        // Process additional images
        if let additionalImagesData = recipe.additionalImagesData,
           let decoded = try? JSONDecoder().decode([[String: Data]].self, from: additionalImagesData) {

            var recompressedImages: [[String: Data]] = []
            var hasChanges = false

            for imageDict in decoded {
                if let imageData = imageDict["data"],
                   let nameData = imageDict["name"] {

                    let originalSize = imageData.count

                    // Only recompress if larger than target
                    if originalSize > ImageCompressionUtility.targetMaxSize,
                       let image = UIImage(data: imageData),
                       let compressedData = ImageCompressionUtility.compressImage(image) {

                        let newSize = compressedData.count
                        let saved = originalSize - newSize

                        if saved > 0 {
                            recompressedImages.append(["data": compressedData, "name": nameData])
                            recipeBytesSaved += saved
                            totalBytesSaved += saved
                            hasChanges = true

                            AppLog.debug("  Additional image: \(originalSize / 1024)KB → \(newSize / 1024)KB (saved \(saved / 1024)KB)", category: .image)
                        } else {
                            recompressedImages.append(imageDict)
                        }
                    } else {
                        recompressedImages.append(imageDict)
                    }
                }
            }

            // Update if we made changes
            if hasChanges {
                if let encoded = try? JSONEncoder().encode(recompressedImages) {
                    recipe.additionalImagesData = encoded
                    recipe.markAsModified()
                }
            }
        }

        if recipeBytesSaved > 0 {
            AppLog.debug("✓ \(recipe.title ?? "Unknown"): saved \(recipeBytesSaved / 1024)KB", category: .image)
        }
    }

    // MARK: - Book Processing

    /// Start book image migration
    func startBookMigration(modelContext: ModelContext) async {
        guard !isRunning else {
            AppLog.warning("Migration already running", category: .image)
            return
        }

        AppLog.info("🔄 Starting book cover migration...", category: .image)

        do {
            let books = try await fetchAllBooks(modelContext: modelContext)
            let totalBooks = books.count

            AppLog.info("📊 Found \(totalBooks) books to process", category: .image)

            var booksProcessed = 0
            var totalSaved = 0

            for book in books {
                if let imageData = book.coverImageData {
                    let originalSize = imageData.count

                    // Only recompress if larger than target
                    if originalSize > 150_000, // Book cover target
                       let image = UIImage(data: imageData),
                       let compressedData = ImageCompressionUtility.compressForBookCover(image) {

                        let newSize = compressedData.count
                        let saved = originalSize - newSize

                        if saved > 0 {
                            book.coverImageData = compressedData
                            book.coverImageHash = Book.calculateImageHash(from: compressedData)

                            totalSaved += saved
                            booksProcessed += 1

                            AppLog.debug("✓ Book '\(book.name ?? "Unknown")': \(originalSize / 1024)KB → \(newSize / 1024)KB (saved \(saved / 1024)KB)", category: .image)
                        }
                    }
                }
            }

            try modelContext.save()

            let savedMB = Double(totalSaved) / 1_048_576
            AppLog.info("✅ Book migration completed: \(booksProcessed) books optimized, saved \(String(format: "%.2f", savedMB)) MB", category: .image)

        } catch {
            AppLog.error("❌ Book migration failed: \(error.localizedDescription)", category: .image)
        }
    }

    /// Fetch all books from the database
    private func fetchAllBooks(modelContext: ModelContext) async throws -> [Book] {
        let descriptor = FetchDescriptor<Book>()
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Combined Migration

    /// Run both recipe and book migrations
    func runFullMigration(modelContext: ModelContext) async {
        guard needsMigration() else {
            AppLog.info("No migration needed", category: .image)
            return
        }

        AppLog.info("🚀 Starting full image optimization migration...", category: .image)

        // Migrate recipes
        await startMigration(modelContext: modelContext)

        // Migrate books
        await startBookMigration(modelContext: modelContext)

        AppLog.info("🎉 Full migration completed!", category: .image)
    }

    // MARK: - Manual Trigger

    /// Manually trigger migration (for testing or user-initiated optimization)
    func triggerManualMigration(modelContext: ModelContext) async {
        // Reset migration flag to force re-run
        UserDefaults.standard.set(0, forKey: migrationVersionKey)

        AppLog.info("🔧 Manual migration triggered", category: .image)

        await runFullMigration(modelContext: modelContext)
    }
}
