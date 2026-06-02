//
//  SharedRecipeViewService.swift
//  Reczipes2
//
//  Created on 1/25/26.
//

import Foundation
import SwiftData
import CloudKit
import Combine

/// Service for viewing shared recipes on-demand
/// Downloads full recipe data only when user wants to view it
@MainActor
class SharedRecipeViewService: ObservableObject {
    static let shared = SharedRecipeViewService()
    
    @Published var isLoading = false
    @Published var currentRecipe: CloudKitRecipe?
    @Published var error: Error?
    
    private let sharingService = CloudKitSharingService.shared
    private var recipeCache: [UUID: CloudKitRecipe] = [:]
    
    private init() {}
    
    /// Fetch full recipe data from CloudKit for viewing
    /// Downloads on-demand when user taps a recipe preview
    func fetchRecipeForViewing(preview: CloudKitRecipePreview) async throws -> CloudKitRecipe {
        AppLog.info("📖 Fetching full recipe for viewing: '\(preview.title)'", category: .sharing)
        
        // Check cache first
        if let cached = recipeCache[preview.id] {
            AppLog.info("📖 Using cached recipe data", category: .sharing)
            return cached
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Option 1: Fetch by cloudRecordID if available
        if let cloudRecordID = preview.cloudRecordID {
            let recipe = try await fetchRecipeByCloudRecordID(cloudRecordID)
            recipeCache[preview.id] = recipe
            AppLog.info("✅ Recipe fetched successfully", category: .sharing)
            return recipe
        }
        
        // Option 2: Search by recipe ID (slower)
        AppLog.info("⚠️ No cloudRecordID, searching by recipe ID...", category: .sharing)
        let recipe = try await searchRecipeByID(preview.id)
        recipeCache[preview.id] = recipe
        return recipe
    }
    
    /// Fetch recipe by CloudKit record ID (fast)
    private func fetchRecipeByCloudRecordID(_ recordID: String) async throws -> CloudKitRecipe {
        let publicDatabase = sharingService.container.publicCloudDatabase
        let ckRecordID = CKRecord.ID(recordName: recordID)
        
        let record = try await publicDatabase.record(for: ckRecordID)
        
        guard let recipeData = record["recipeData"] as? String,
              let jsonData = recipeData.data(using: .utf8),
              let recipe = try? JSONDecoder().decode(CloudKitRecipe.self, from: jsonData) else {
            throw SharingError.invalidData
        }
        
        return recipe
    }
    
    /// Search for recipe by ID (fallback, slower)
    private func searchRecipeByID(_ recipeID: UUID) async throws -> CloudKitRecipe {
        let recipes = try await sharingService.fetchSharedRecipes(limit: 400, excludeCurrentUser: true)
        
        guard let recipe = recipes.first(where: { $0.id == recipeID }) else {
            throw SharingError.recipeNotFound
        }
        
        return recipe
    }
    
    /// Clear cache to free memory
    func clearCache() {
        recipeCache.removeAll()
        AppLog.info("🧹 Recipe view cache cleared", category: .sharing)
    }
    
    /// Pre-fetch recipes for a book (optional optimization)
    func prefetchRecipesForBook(previews: [CloudKitRecipePreview]) async {
        AppLog.info("🔄 Pre-fetching \(previews.count) recipes in background...", category: .sharing)
        
        for preview in previews {
            do {
                let recipe = try await fetchRecipeForViewing(preview: preview)
                recipeCache[preview.id] = recipe
            } catch {
                AppLog.warning("Failed to prefetch '\(preview.title)': \(error)", category: .sharing)
            }
        }
        
        AppLog.info("✅ Pre-fetch complete: \(recipeCache.count) recipes cached", category: .sharing)
    }
}

