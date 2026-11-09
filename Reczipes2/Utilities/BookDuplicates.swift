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
//  2026-11-09: a copy also merges without asking when it is the SAME BOOK — same name
//  AND the same non-empty description — and the merge loses nothing: every recipe is
//  kept (the kept book gets the union), pictures move over (identical ones are not
//  doubled), and a contents page or glossary of its own is only dropped when all its
//  recipes are already in the kept book (the kept book's is then the fuller one).
//  Same name with a different description still waits for the owner; with no
//  description on either, the copy merges only when all its recipes are already in the
//  kept one. Copies are matched within their description (unattendedMerges).
//

import Foundation

struct BookCopy: Equatable, Identifiable {
    let id: UUID
    let name: String
    let recipeIDs: [UUID]
    let dateCreated: Date?
    /// Pictures, glossary or table of contents of its own
    let hasOwnContent: Bool
    var bookDescription: String? = nil
    var glossaryData: Data? = nil
    var contentsData: Data? = nil
}

struct BookDuplicateGroup: Identifiable {
    let key: String
    let keep: BookCopy
    let extras: [BookCopy]
    var id: String { key }

    /// Extras that add nothing to the kept book: merge without asking
    var exactExtras: [BookCopy] { extras.filter { BookDuplicates.isExactCopy($0, of: keep) } }

    /// Extras merged unattended: exact copies, plus copies of the same book (same name
    /// and description) whose merge loses nothing.
    var autoMergeExtras: [BookCopy] { extras.filter { BookDuplicates.mergesUnattended($0, into: keep) } }

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

    /// Description key: same folding as the name; empty when there is none.
    static func descriptionKey(_ text: String?) -> String { key(text ?? "") }

    /// Same book: same name (grouping already ensures it) and the same non-empty description.
    static func isSameBook(_ a: BookCopy, _ b: BookCopy) -> Bool {
        let da = descriptionKey(a.bookDescription)
        return !da.isEmpty && da == descriptionKey(b.bookDescription)
    }

    /// Whether `extra` can be merged into `keep` without asking.
    static func mergesUnattended(_ extra: BookCopy, into keep: BookCopy) -> Bool {
        if isExactCopy(extra, of: keep) { return true }
        let covered = Set(extra.recipeIDs).isSubset(of: Set(keep.recipeIDs))
        // No description on either: the same book only when every recipe of the extra
        // is already in the kept one (a name alone never merges; a name plus a recipe
        // list that is wholly contained does). Then nothing at all is added or lost.
        if descriptionKey(extra.bookDescription).isEmpty && descriptionKey(keep.bookDescription).isEmpty {
            return covered && !extra.recipeIDs.isEmpty
        }
        guard isSameBook(extra, keep) else { return false }
        // The merge keeps the kept book's contents page and glossary; the extra's is
        // only copied over when the kept book has none. Dropping a different one is
        // fine only when the kept book already holds every recipe the extra has.
        func conflicts(_ e: Data?, _ k: Data?) -> Bool { e != nil && k != nil && e != k }
        if !covered && (conflicts(extra.contentsData, keep.contentsData) || conflicts(extra.glossaryData, keep.glossaryData)) {
            return false
        }
        return true
    }

    /// Unattended merges for one name group: (kept id, extra ids) pairs. Copies are
    /// first matched to the book that shares their description (two "Soups — Any kind
    /// of soup" copies merge with each other, not into a different "Soups"), then exact
    /// copies of the group's kept book.
    static func unattendedMerges(_ group: BookDuplicateGroup) -> [(keep: UUID, extras: [UUID])] {
        let all = [group.keep] + group.extras
        var merged = Set<UUID>()
        var plan: [(keep: UUID, extras: [UUID])] = []
        let byDescription = Dictionary(grouping: all) { descriptionKey($0.bookDescription) }
        for (_, copies) in byDescription where copies.count > 1 {
            guard let keep = preferredKeep(copies) else { continue }
            let extras = copies.filter { $0.id != keep.id && mergesUnattended($0, into: keep) }.map(\.id)
            if !extras.isEmpty { plan.append((keep.id, extras)); merged.formUnion(extras) }
        }
        let exact = group.extras.filter { !merged.contains($0.id) && isExactCopy($0, of: group.keep) }.map(\.id)
        if !exact.isEmpty {
            if let i = plan.firstIndex(where: { $0.keep == group.keep.id }) { plan[i].extras += exact }
            else { plan.append((group.keep.id, exact)) }
        }
        // A kept book that is itself merged away elsewhere would be lost: drop such entries.
        let mergedAway = Set(plan.flatMap(\.extras))
        return plan.filter { !mergedAway.contains($0.keep) }
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
