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

    /// Same content as the user sees it (decoded, so encoding differences don't matter).
    static func sameContent(_ a: RecipeX, _ b: RecipeX) -> Bool {
        a.title == b.title && a.headerNotes == b.headerNotes && a.recipeYield == b.recipeYield
            && a.reference == b.reference
            && a.ingredientSections == b.ingredientSections
            && a.instructionSections == b.instructionSections
            && a.notes == b.notes
    }
}
