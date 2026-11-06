//
//  BookDuplicates.swift
//  Reczipes2
//
//  Pure rules for books that share a name (Lane 37, 2026-11-06). A name alone never
//  merges two books: a copy merges without asking only when it adds nothing — the same
//  recipes as the kept book, or none — and has no pictures, glossary or contents of its
//  own. Everything else is shown for the owner to decide (Database Maintenance →
//  Duplicate Books).
//

import Foundation

struct BookCopy: Equatable, Identifiable {
    let id: UUID
    let name: String
    let recipeIDs: [UUID]
    let dateCreated: Date?
    /// Pictures, glossary or table of contents of its own
    let hasOwnContent: Bool
}

struct BookDuplicateGroup: Identifiable {
    let key: String
    let keep: BookCopy
    let extras: [BookCopy]
    var id: String { key }

    /// Extras that add nothing to the kept book: merge without asking
    var exactExtras: [BookCopy] { extras.filter { BookDuplicates.isExactCopy($0, of: keep) } }

    /// Recipes in this group that are not in the kept book
    var recipesOnlyInExtras: Int {
        let kept = Set(keep.recipeIDs)
        return Set(extras.flatMap(\.recipeIDs)).subtracting(kept).count
    }
}

enum BookDuplicates {
    /// Name key: letters and digits only, case-folded ("The Low-Carb Cookbook" ==
    /// "The Low Carb Cookbook").
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// The copy to keep: most recipes, then oldest, then smallest id (stable).
    static func preferredKeep(_ copies: [BookCopy]) -> BookCopy? {
        copies.min { a, b in
            if a.recipeIDs.count != b.recipeIDs.count { return a.recipeIDs.count > b.recipeIDs.count }
            let da = a.dateCreated ?? .distantFuture, db = b.dateCreated ?? .distantFuture
            if da != db { return da < db }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func isExactCopy(_ extra: BookCopy, of keep: BookCopy) -> Bool {
        guard !extra.hasOwnContent else { return false }
        return extra.recipeIDs.isEmpty || Set(extra.recipeIDs) == Set(keep.recipeIDs)
    }

    /// Groups of two or more books with the same name key, largest group first.
    static func groups(_ books: [BookCopy]) -> [BookDuplicateGroup] {
        let byKey = Dictionary(grouping: books.filter { !key($0.name).isEmpty }) { key($0.name) }
        return byKey.compactMap { key, copies -> BookDuplicateGroup? in
            guard copies.count > 1, let keep = preferredKeep(copies) else { return nil }
            let extras = copies.filter { $0.id != keep.id }
                .sorted { $0.recipeIDs.count > $1.recipeIDs.count }
            return BookDuplicateGroup(key: key, keep: keep, extras: extras)
        }
        .sorted { ($0.extras.count, $0.keep.name) > ($1.extras.count, $1.keep.name) }
    }

    /// Recipe order after a merge: the kept book's order, then each extra's new recipes.
    static func mergedRecipeIDs(keep: [UUID], extras: [[UUID]]) -> [UUID] {
        var seen = Set(keep)
        var result = keep
        for list in extras {
            for id in list where seen.insert(id).inserted { result.append(id) }
        }
        return result
    }
}
