//
//  CachedDiabeticAnalysis.swift
//  Reczipes2
//
//  Persistent cache for diabetic analysis results
//  Created by Zahirudeen Premji on 12/24/25.
//

import Foundation
import SwiftData

@Model
final class CachedDiabeticAnalysis {
    // Removed @Attribute(.unique) - CloudKit doesn't support unique constraints
    var recipeId: UUID = UUID()
    var analysisData: Data = Data() // Encoded DiabeticInfo
    var cachedAt: Date = Date()
    
    // Ingredient change tracking
    var recipeVersion: Int = 1 // Recipe version when analyzed
    var ingredientsHash: String = "" // Hash of ingredients when analyzed
    var recipeLastModified: Date = Date() // Recipe's lastModified when analyzed
    
    init(recipeId: UUID, 
         analysisData: Data, 
         cachedAt: Date = Date(),
         recipeVersion: Int,
         ingredientsHash: String,
         recipeLastModified: Date) {
        self.recipeId = recipeId
        self.analysisData = analysisData
        self.cachedAt = cachedAt
        self.recipeVersion = recipeVersion
        self.ingredientsHash = ingredientsHash
        self.recipeLastModified = recipeLastModified
    }
    
    /// Check if this cached analysis is still valid (30 days per guidelines)
    var isStale: Bool {
        let expirationInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days in seconds
        return Date().timeIntervalSince(cachedAt) > expirationInterval
    }
    
    /// Check if ingredients have changed since this analysis
    func isIngredientsOutdated(recipe: RecipeX) -> Bool {
        // Check version mismatch
        if recipe.currentVersion != recipeVersion {
            return true
        }
        
        // Check hash mismatch
        if let currentHash = recipe.ingredientsHash,
           currentHash != ingredientsHash {
            return true
        }
        
        // Check if recipe was modified after analysis
        if recipe.modificationDate > recipeLastModified {
            return true
        }
        
        return false
    }
    
    /// Prefix of `ingredientsHash` on a batch claim (DiabeticBackfill).
    static let batchClaimPrefix = "batch:"

    /// A marker that this recipe is in a DiabeticBackfill batch on some device, so another
    /// device does not pay for it again. It holds no analysis and is never published: its
    /// hash never matches a recipe's, so it always reads as outdated.
    var isBatchClaim: Bool { ingredientsHash.hasPrefix(Self.batchClaimPrefix) }

    /// The batch a claim belongs to (nil for a real analysis).
    var claimBatchID: String? {
        isBatchClaim ? String(ingredientsHash.dropFirst(Self.batchClaimPrefix.count)) : nil
    }

    static func batchClaim(recipeId: UUID, batchID: String, at date: Date = Date()) -> CachedDiabeticAnalysis {
        CachedDiabeticAnalysis(recipeId: recipeId, analysisData: Data(), cachedAt: date,
                               recipeVersion: -1, ingredientsHash: batchClaimPrefix + batchID,
                               recipeLastModified: date)
    }

    /// Check if cache is still valid (not stale and ingredients haven't changed)
    func isValid(for recipe: RecipeX) -> Bool {
        return !isStale && !isIngredientsOutdated(recipe: recipe)
    }
    
    /// Decode the stored analysis
    @MainActor func decodedAnalysis() throws -> DiabeticInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DiabeticInfo.self, from: analysisData)
    }
    
    /// Create a cached analysis from DiabeticInfo
    @MainActor static func create(from info: DiabeticInfo, recipe: RecipeX) throws -> CachedDiabeticAnalysis {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(info)
        
        return CachedDiabeticAnalysis(
            recipeId: recipe.id!,
            analysisData: data,
            cachedAt: Date(),
            recipeVersion: recipe.currentVersion,
            ingredientsHash: recipe.ingredientsHash ?? "",
            recipeLastModified: recipe.modificationDate
        )
    }
}
