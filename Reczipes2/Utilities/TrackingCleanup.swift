//
//  TrackingCleanup.swift
//  Reczipes2
//
//  Decides what happens to a local SharedRecipe tracking row whose public
//  record was not in this listing. Pure logic, so it can be tested.
//
//  The old rule deleted every such row on every load of the sharing manager.
//  Rows for records that failed to download or decode, and rows that pointed at
//  a record replaced by a newer one for the same recipe, were deleted too — and
//  the next load then listed those public records as "orphaned".
//

import Foundation

enum TrackingCleanup {
    typealias Row = (recipeID: UUID?, cloudRecordID: String?, isMine: Bool)

    struct Plan: Equatable {
        /// Row index → the record id it should now point at.
        var repoint: [Int: String] = [:]
        /// Row indexes that may be deleted.
        var drop: [Int] = []
    }

    /// - Parameters:
    ///   - foundRecordIDs: every one of my record ids seen in the listing, readable or not.
    ///   - newestRecordIDByRecipeID: for each recipe with a readable record, its newest record id.
    ///   - listingComplete: false when any record could not be read or decoded.
    static func plan(rows: [Row],
                     foundRecordIDs: Set<String>,
                     newestRecordIDByRecipeID: [UUID: String],
                     listingComplete: Bool) -> Plan {
        var plan = Plan()
        for (index, row) in rows.enumerated() {
            guard row.isMine, let recordID = row.cloudRecordID, !foundRecordIDs.contains(recordID) else { continue }
            if let recipeID = row.recipeID, let current = newestRecordIDByRecipeID[recipeID] {
                plan.repoint[index] = current           // the recipe was re-shared under a new record
            } else if listingComplete {
                plan.drop.append(index)                 // no public record for this recipe at all
            }                                           // incomplete listing: leave the row alone
        }
        return plan
    }

    /// Orphans (public records with no tracking row) that "Delete All Orphaned" may
    /// remove: only those whose recipe is neither in this library nor in any book.
    /// The rest are re-linked, never deleted in bulk.
    static func mayBulkDeleteOrphan(inLocalLibrary: Bool, inBook: Bool) -> Bool {
        !inLocalLibrary && !inBook
    }
}
