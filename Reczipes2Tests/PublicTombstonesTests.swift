//
//  PublicTombstonesTests.swift
//  Reczipes2Tests
//
//  Δ-163: everything is public, nothing is removed; owner deletes are marks.
//

import Testing
import Foundation
@testable import Reczipes2

@Suite("Public tombstones")
@MainActor
struct PublicTombstonesTests {
    let a = UUID(), b = UUID(), c = UUID()
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test("A mark with no later live record means deleted; published again means live")
    func deletedIDs() {
        let marks: [UUID: PublicTombstones.Mark] = [
            a: .init(deletedDate: t0),
            b: .init(deletedDate: t0)
        ]
        let live: [UUID: Date] = [b: t0.addingTimeInterval(60), c: t0]
        let deleted = PublicTombstones.deletedIDs(newestLive: live, marks: marks)
        #expect(Set(deleted.keys) == [a])
    }

    @Test("Newest mark wins while merging pages")
    func mergeKeepsNewest() {
        var marks: [UUID: PublicTombstones.Mark] = [:]
        PublicTombstones.merge(.init(deletedDate: t0.addingTimeInterval(10)), into: &marks, id: a)
        PublicTombstones.merge(.init(deletedDate: t0), into: &marks, id: a)
        #expect(marks[a]?.deletedDate == t0.addingTimeInterval(10))
    }

    @Test("Receivers: new devices skip, owner and merged copies drop, everyone else keeps with badge")
    func receiverActions() {
        #expect(PublicTombstones.receiverAction(hadCopyBefore: false, isOwnersDevice: false, replacementStillPublished: false) == .skip)
        #expect(PublicTombstones.receiverAction(hadCopyBefore: true, isOwnersDevice: true, replacementStillPublished: false) == .dropCopy)
        #expect(PublicTombstones.receiverAction(hadCopyBefore: true, isOwnersDevice: false, replacementStillPublished: true) == .dropCopy)
        #expect(PublicTombstones.receiverAction(hadCopyBefore: true, isOwnersDevice: false, replacementStillPublished: false) == .keepWithBadge)
    }

    @Test("Publishing: new, refresh only when edited, never resurrect an unedited delete")
    func publishActions() {
        // Not public at all
        #expect(PublicTombstones.publishAction(localModified: t0, live: nil, deletedDate: nil) == .publishNew)
        // Public and unchanged (within the 1 s slack)
        #expect(PublicTombstones.publishAction(localModified: t0, live: ("R", t0), deletedDate: nil) == .none)
        // Edited after publishing
        #expect(PublicTombstones.publishAction(localModified: t0.addingTimeInterval(5), live: ("R", t0), deletedDate: nil)
                == .refresh(recordName: "R"))
        // Deleted publicly, still on this device, not edited since (delete not synced here yet)
        #expect(PublicTombstones.publishAction(localModified: t0, live: nil, deletedDate: t0.addingTimeInterval(1)) == .none)
        // Deleted publicly, then edited here afterwards: a deliberate restore
        #expect(PublicTombstones.publishAction(localModified: t0.addingTimeInterval(10), live: nil, deletedDate: t0) == .publishNew)
    }

    @Test("Older payloads without the new fields still decode; the mark round-trips")
    func payloadCompatibility() throws {
        let old = #"{"id":"\#(a.uuidString)","title":"Dal","ingredientSections":[],"instructionSections":[],"notes":[],"sharedDate":1000}"#
        let decoded = try JSONDecoder().decode(CloudKitRecipe.self, from: Data(old.utf8))
        #expect(decoded.deletedByOwner == nil)

        // The publisher edits the JSON generically; the app must read that back.
        var object = try #require(try JSONSerialization.jsonObject(with: Data(old.utf8)) as? [String: Any])
        object["deletedByOwner"] = true
        object["deletedDate"] = 2000.0
        object["replacedByID"] = b.uuidString
        let marked = try JSONDecoder().decode(CloudKitRecipe.self,
                                              from: JSONSerialization.data(withJSONObject: object))
        #expect(marked.deletedByOwner == true)
        #expect(marked.deletedDate == Date(timeIntervalSinceReferenceDate: 2000))
        #expect(marked.replacedByID == b)
    }

    @Test("Badge list and pending deletions persist per device")
    func storePersists() throws {
        let suite = "PublicTombstonesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = OwnerDeletedStore(defaults: defaults)
        store.markDeleted(.recipe, a, on: t0)
        store.enqueueTombstone(.book, b)
        store.enqueueTombstone(.book, b) // once only
        let reloaded = OwnerDeletedStore(defaults: defaults)
        #expect(reloaded.isDeleted(.recipe, a))
        #expect(!reloaded.isDeleted(.book, a))
        #expect(reloaded.pending.count == 1)
        reloaded.clear(.recipe, a)
        reloaded.completeTombstone(.book, b)
        #expect(OwnerDeletedStore(defaults: defaults).deleted.isEmpty)
        #expect(OwnerDeletedStore(defaults: defaults).pending.isEmpty)
    }
}
