//
//  RecipeRepairService.swift
//  Reczipes2
//
//  Service for re-extracting missing recipe data (ingredients/instructions)
//  from the original source URL or image.
//

import Foundation
import SwiftData
import Combine

/// Handles re-extraction of missing recipe data by going back to the original source
@MainActor
class RecipeRepairService: ObservableObject {

    @Published var isRepairing = false
    @Published var repairPhase: RepairPhase = .idle
    @Published var errorMessage: String?

    enum RepairPhase: Equatable {
        case idle
        case fetchingSource
        case extracting
        case saving
        case completed
        case failed
    }

    private let apiClient: ClaudeAPIClient
    private let webExtractor = WebRecipeExtractor()

    init(apiKey: String) {
        self.apiClient = ClaudeAPIClient(apiKey: apiKey)
    }

    /// Attempt to repair a recipe by re-extracting from its original source.
    /// Returns `true` on success.
    @discardableResult
    func repair(_ recipe: RecipeX, in context: ModelContext) async -> Bool {
        isRepairing = true
        repairPhase = .fetchingSource
        errorMessage = nil

        do {
            let freshRecipe: RecipeX

            // Strategy 1: Re-extract from source URL
            if let ref = recipe.reference, !ref.isEmpty, URL(string: ref) != nil {
                AppLog.info("🔧 Repairing '\(recipe.safeTitle)' from URL: \(ref)", category: .storage)
                repairPhase = .fetchingSource
                let html = try await webExtractor.fetchWebContent(from: ref)

                repairPhase = .extracting
                freshRecipe = try await apiClient.extractRecipe(from: html)

            // Strategy 2: Re-extract from stored image data
            } else if let imgData = recipe.imageData {
                AppLog.info("🔧 Repairing '\(recipe.safeTitle)' from stored image", category: .storage)
                repairPhase = .extracting
                freshRecipe = try await apiClient.extractRecipe(from: imgData)

            } else {
                throw RepairError.noSource
            }

            // Patch the existing recipe with any missing data
            repairPhase = .saving
            patchRecipe(recipe, from: freshRecipe)

            try context.save()
            AppLog.info("✅ Successfully repaired '\(recipe.safeTitle)'", category: .storage)

            repairPhase = .completed
            isRepairing = false
            return true

        } catch {
            AppLog.error("❌ Repair failed for '\(recipe.safeTitle)': \(error)", category: .storage)
            errorMessage = error.localizedDescription
            repairPhase = .failed
            isRepairing = false
            return false
        }
    }

    // MARK: - Private

    /// Copies missing sections from freshRecipe into the existing recipe
    private func patchRecipe(_ existing: RecipeX, from fresh: RecipeX) {
        // Patch ingredients if missing
        if existing.ingredientSectionsData == nil || existing.ingredientSections.isEmpty {
            if fresh.ingredientSectionsData != nil && !fresh.ingredientSections.isEmpty {
                existing.ingredientSectionsData = fresh.ingredientSectionsData
                AppLog.info("  → Patched ingredients (\(fresh.ingredientSections.flatMap { $0.ingredients }.count) items)", category: .storage)
            }
        }

        // Patch instructions if missing
        if existing.instructionSectionsData == nil || existing.instructionSections.isEmpty {
            if fresh.instructionSectionsData != nil && !fresh.instructionSections.isEmpty {
                existing.instructionSectionsData = fresh.instructionSectionsData
                AppLog.info("  → Patched instructions (\(fresh.instructionSections.flatMap { $0.steps }.count) steps)", category: .storage)
            }
        }

        // Patch notes if missing and fresh has them
        if (existing.notesData == nil || existing.notes.isEmpty),
           let freshNotes = fresh.notesData, !fresh.notes.isEmpty {
            existing.notesData = freshNotes
            AppLog.info("  → Patched notes (\(fresh.notes.count) notes)", category: .storage)
        }

        // Update metadata
        existing.lastModified = Date()
        existing.version = (existing.version ?? 0) + 1
    }

    enum RepairError: LocalizedError {
        case noSource

        var errorDescription: String? {
            switch self {
            case .noSource:
                return "No source URL or image available to re-extract from"
            }
        }
    }
}
