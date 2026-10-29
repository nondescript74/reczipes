//
//  PublicTombstones.swift
//  Reczipes2
//
//  Δ-163: everything is published to everyone, always. Nothing public is ever
//  removed. When an owner deletes a recipe, book or meal, its public record is
//  kept and marked deleted (a "tombstone", inside the JSON payload). The rules
//  for what each device does with that are here, as pure functions, so they
//  can be tested without CloudKit.
//

import Foundation

enum PublicTombstones {

    /// A deleted mark read from the public database.
    struct Mark: Equatable {
        var deletedDate: Date
        var replacedByID: UUID? = nil
    }

    /// Ids that are deleted: a mark exists and no live record for the id was
    /// shared after it (a later live record means the owner published it again).
    static func deletedIDs(newestLive: [UUID: Date], marks: [UUID: Mark]) -> [UUID: Mark] {
        marks.filter { id, mark in
            guard let live = newestLive[id] else { return true }
            return live <= mark.deletedDate
        }
    }

    /// Keeps the newest mark per id while reading pages of records.
    static func merge(_ mark: Mark, into marks: inout [UUID: Mark], id: UUID) {
        if let seen = marks[id], seen.deletedDate >= mark.deletedDate { return }
        marks[id] = mark
    }

    /// What a device does with its own copy of something its owner deleted.
    enum ReceiverAction: Equatable {
        /// This device never had it: don't add it (new devices skip deleted items).
        case skip
        /// Remove the local copy: the owner's own device, or the item was merged
        /// into a copy that is still published.
        case dropCopy
        /// Keep it and show the "User Deleted" badge.
        case keepWithBadge
    }

    static func receiverAction(hadCopyBefore: Bool,
                               isOwnersDevice: Bool,
                               replacementStillPublished: Bool) -> ReceiverAction {
        guard hadCopyBefore else { return .skip }
        if isOwnersDevice { return .dropCopy }
        if replacementStillPublished { return .dropCopy }
        return .keepWithBadge
    }

    /// What the owner's device publishes for one local item.
    enum PublishAction: Equatable {
        case none
        case publishNew
        case refresh(recordName: String)
    }

    /// - live: the newest live public record of this item (name, sharedDate), if any.
    /// - deletedDate: when the item was marked deleted publicly, if it was.
    /// A deleted item still on this device is NOT published again unless it was
    /// edited after the delete (its deletion may simply not have reached this
    /// device yet; publishing it would undo the owner's delete for everyone).
    static func publishAction(localModified: Date,
                              live: (recordName: String, sharedDate: Date)?,
                              deletedDate: Date?,
                              slack: TimeInterval = 1) -> PublishAction {
        if let live {
            return localModified > live.sharedDate.addingTimeInterval(slack)
                ? .refresh(recordName: live.recordName) : .none
        }
        if let deletedDate, localModified <= deletedDate { return .none }
        return .publishNew
    }
}
