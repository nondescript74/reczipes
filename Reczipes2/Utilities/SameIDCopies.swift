//
//  SameIDCopies.swift
//  Reczipes2
//
//  One rule for "the same recipe stored more than once under one id", used by
//  both the Duplicate Recipe Detector ("Remove Extra Stored Copies") and
//  Settings → Maintenance → Remove Duplicate Recipes, so the two cannot drift.
//
//  Keep the most complete row; remove only rows whose content is identical to
//  it; rows that differ are never removed here — the user reviews them.
//

import Foundation
import SwiftData

enum SameIDCopies {
    struct Plan {
        let keep: RecipeX?
        let remove: [RecipeX]
        let differing: [RecipeX]
    }

    /// Rows that share one recipe id. Rows without an id are ignored.
    static func plan(_ rows: [RecipeX]) -> Plan {
        let rows = rows.filter { $0.id != nil }
        guard let keep = rows.max(by: { DuplicateCluster.completenessScore($0) < DuplicateCluster.completenessScore($1) }) else {
            return Plan(keep: nil, remove: [], differing: [])
        }
        var remove: [RecipeX] = []
        var differing: [RecipeX] = []
        for other in rows where other.persistentModelID != keep.persistentModelID {
            if sameContent(keep, other) { remove.append(other) } else { differing.append(other) }
        }
        return Plan(keep: keep, remove: remove, differing: differing)
    }

    struct Result: Equatable {
        var removed = 0
        var differing = 0
    }

    /// The unattended version of "Remove Extra Stored Copies": finds every recipe id
    /// stored as more than one row and deletes only the rows identical to the kept
    /// one. Runs at launch and after each CloudKit import. Safe to run unattended:
    /// the recipe id stays, so books (which list ids) and website copies (keyed by
    /// id) are untouched — nothing is unshared and no book is re-pointed. Rows whose
    /// content differs are left for the Duplicate Detector.
    @MainActor
    @discardableResult
    static func removeIdenticalExtras(in context: ModelContext, operation: String) -> Result {
        guard let rows = try? context.fetch(FetchDescriptor<RecipeX>()) else { return Result() }
        let groups = Dictionary(grouping: rows.filter { $0.id != nil }, by: { $0.id! })
            .values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return Result() }

        var result = Result()
        for group in groups {
            let plan = plan(group)
            plan.remove.forEach(context.delete)
            result.removed += plan.remove.count
            result.differing += plan.differing.count
        }
        if result.removed > 0 {
            do {
                try context.save()
            } catch {
                AppLog.error("\(operation): failed to save after removing same-id copies: \(error)", category: .recipe)
                context.rollback()
                return Result(removed: 0, differing: result.differing)
            }
        }
        AppLog.info("🧹 \(operation): \(groups.count) recipe id(s) stored more than once — removed \(result.removed) identical extra row(s), kept \(result.differing) that differ for review", category: .recipe)
        return result
    }

    /// Same content as the user sees it (decoded, so encoding differences don't matter).
    static func sameContent(_ a: RecipeX, _ b: RecipeX) -> Bool {
        a.title == b.title && a.headerNotes == b.headerNotes && a.recipeYield == b.recipeYield
            && a.reference == b.reference
            && a.ingredientSections == b.ingredientSections
            && a.instructionSections == b.instructionSections
            && a.notes == b.notes
    }
}
