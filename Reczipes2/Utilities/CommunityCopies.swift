//
//  CommunityCopies.swift
//  Reczipes2
//
//  The shared library can hold one recipe under two ids (a library merge left
//  two copies, both shared). The web version shows one of them; this is the
//  same read-side rule for the app's Shared recipe list: copies whose title AND
//  ingredient names match show once. Same title with different ingredients
//  stays apart (a title match is not identity). Nothing is deleted — books
//  still find every copy by its own id.
//

import Foundation

enum CommunityCopies {
    /// Lower-case, accents folded, anything not a letter or digit → one space.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        var out = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return out
    }

    /// Title plus the sorted ingredient names (matches the web's copySignature).
    static func signature(title: String, ingredientNames: [String]) -> String {
        normalized(title) + "|" + ingredientNames.map(normalized).sorted().joined(separator: ",")
    }

    /// One row per signature (and per id): the copy with a photo, then the newest share.
    @MainActor
    static func collapse(_ rows: [CachedSharedRecipe]) -> [CachedSharedRecipe] {
        var best: [String: CachedSharedRecipe] = [:]
        var order: [String] = []
        var seenIDs = Set<UUID>()
        for row in rows {
            guard seenIDs.insert(row.id).inserted else { continue }
            let key = signature(title: row.title,
                                ingredientNames: row.ingredientSections.flatMap { $0.ingredients.map(\.name) })
            guard let current = best[key] else {
                best[key] = row
                order.append(key)
                continue
            }
            if prefer(row, over: current) { best[key] = row }
        }
        return order.compactMap { best[$0] }
    }

    @MainActor
    private static func prefer(_ a: CachedSharedRecipe, over b: CachedSharedRecipe) -> Bool {
        if (a.imageData != nil) != (b.imageData != nil) { return a.imageData != nil }
        return a.sharedDate > b.sharedDate
    }
}
