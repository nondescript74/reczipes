//
//  TrackingCleanupTests.swift
//  Reczipes2Tests
//
//  The sharing manager must not delete tracking rows on an incomplete listing,
//  and re-points a row whose recipe was re-shared under a new record.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Tracking cleanup")
@MainActor
struct TrackingCleanupTests {
    private let r1 = UUID(), r2 = UUID(), r3 = UUID()

    @Test("A row whose recipe has a newer record is re-pointed, not dropped")
    func repointed() {
        let plan = TrackingCleanup.plan(
            rows: [(recipeID: r1, cloudRecordID: "old", isMine: true)],
            foundRecordIDs: ["new"],
            newestRecordIDByRecipeID: [r1: "new"],
            listingComplete: true)
        #expect(plan.repoint == [0: "new"])
        #expect(plan.drop.isEmpty)
    }

    @Test("Nothing is dropped when the listing was incomplete")
    func incompleteListing() {
        let plan = TrackingCleanup.plan(
            rows: [(recipeID: r2, cloudRecordID: "gone", isMine: true)],
            foundRecordIDs: [],
            newestRecordIDByRecipeID: [:],
            listingComplete: false)
        #expect(plan == TrackingCleanup.Plan())
    }

    @Test("Dropped only when the listing was complete and the recipe has no record")
    func dropped() {
        let plan = TrackingCleanup.plan(
            rows: [(recipeID: r3, cloudRecordID: "gone", isMine: true),
                   (recipeID: r1, cloudRecordID: "seen", isMine: true),
                   (recipeID: r2, cloudRecordID: "theirs", isMine: false),
                   (recipeID: r2, cloudRecordID: nil, isMine: true)],
            foundRecordIDs: ["seen"],
            newestRecordIDByRecipeID: [r1: "seen"],
            listingComplete: true)
        #expect(plan.drop == [0])
        #expect(plan.repoint.isEmpty)
    }

    @Test("Bulk delete never takes a record whose recipe is here or in a book")
    func bulkDeleteGuard() {
        #expect(TrackingCleanup.mayBulkDeleteOrphan(inLocalLibrary: false, inBook: false))
        #expect(!TrackingCleanup.mayBulkDeleteOrphan(inLocalLibrary: true, inBook: false))
        #expect(!TrackingCleanup.mayBulkDeleteOrphan(inLocalLibrary: false, inBook: true))
    }
}
