//
//  OwnerDeletedStore.swift
//  Reczipes2
//
//  Δ-163. Two small per-device lists, kept in UserDefaults (no SwiftData /
//  CloudKit schema change):
//
//  - which community recipes, books and meals on this device were deleted by
//    their owner (they stay here with a "User Deleted" badge until this
//    person removes them);
//  - the owner's own deletions still waiting to be marked in the public
//    database (retried by every publish pass, so a delete made offline still
//    reaches everyone).
//

import Foundation
import Combine

enum PublicItemKind: String, Codable, CaseIterable {
    case recipe, book, meal
}

@MainActor
final class OwnerDeletedStore: ObservableObject {
    static let shared = OwnerDeletedStore()

    private static let deletedKey = "OwnerDeleted.items.v1"
    private static let pendingKey = "OwnerDeleted.pendingTombstones.v1"

    /// "kind:UUID" -> date the owner deleted it.
    @Published private(set) var deleted: [String: Date] = [:]

    struct Pending: Codable, Hashable {
        var kind: PublicItemKind
        var id: UUID
        var replacedByID: UUID?
        var requested: Date
    }
    @Published private(set) var pending: [Pending] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.deletedKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            deleted = decoded
        }
        if let data = defaults.data(forKey: Self.pendingKey),
           let decoded = try? JSONDecoder().decode([Pending].self, from: data) {
            pending = decoded
        }
    }

    private static func key(_ kind: PublicItemKind, _ id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }

    // MARK: Received deletions (badge)

    func isDeleted(_ kind: PublicItemKind, _ id: UUID?) -> Bool {
        guard let id else { return false }
        return deleted[Self.key(kind, id)] != nil
    }

    func deletedDate(_ kind: PublicItemKind, _ id: UUID?) -> Date? {
        guard let id else { return nil }
        return deleted[Self.key(kind, id)]
    }

    func markDeleted(_ kind: PublicItemKind, _ id: UUID, on date: Date) {
        let key = Self.key(kind, id)
        guard deleted[key] == nil else { return }
        deleted[key] = date
        saveDeleted()
    }

    /// The owner published it again, or this person removed it from the device.
    func clear(_ kind: PublicItemKind, _ id: UUID) {
        if deleted.removeValue(forKey: Self.key(kind, id)) != nil { saveDeleted() }
    }

    func count(_ kind: PublicItemKind) -> Int {
        deleted.keys.filter { $0.hasPrefix(kind.rawValue + ":") }.count
    }

    // MARK: Own deletions waiting to be marked publicly

    func enqueueTombstone(_ kind: PublicItemKind, _ id: UUID, replacedByID: UUID? = nil) {
        guard !pending.contains(where: { $0.kind == kind && $0.id == id }) else { return }
        pending.append(Pending(kind: kind, id: id, replacedByID: replacedByID, requested: Date()))
        savePending()
    }

    func isPendingTombstone(_ kind: PublicItemKind, _ id: UUID?) -> Bool {
        guard let id else { return false }
        return pending.contains { $0.kind == kind && $0.id == id }
    }

    func completeTombstone(_ kind: PublicItemKind, _ id: UUID) {
        pending.removeAll { $0.kind == kind && $0.id == id }
        savePending()
    }

    // MARK: Persistence

    private func saveDeleted() {
        if let data = try? JSONEncoder().encode(deleted) { defaults.set(data, forKey: Self.deletedKey) }
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) { defaults.set(data, forKey: Self.pendingKey) }
    }
}
