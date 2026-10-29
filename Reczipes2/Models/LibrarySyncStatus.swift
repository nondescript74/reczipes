//
//  LibrarySyncStatus.swift
//  Reczipes2
//
//  One place that knows whether this device's copy of the library is still
//  catching up, so the app can say so instead of looking finished.
//
//  Two sources:
//  - the shared (community) library download from the public CloudKit database,
//    which is how a device on someone else's Apple ID gets the recipes and books;
//  - SwiftData's own iCloud mirroring of the private library (import / setup
//    events from NSPersistentCloudKitContainer), for the owner's devices.
//

import Foundation
import CoreData
import Combine

@MainActor
final class LibrarySyncStatus: ObservableObject {
    static let shared = LibrarySyncStatus()

    enum CommunityPhase: Equatable {
        /// No full download has been tried on this device yet.
        case notStarted
        /// A full download is running: records read so far, total if known.
        case downloading(fetched: Int, expected: Int?)
        /// Recipe text is in; photos are still being fetched.
        case downloadingPhotos(done: Int, total: Int)
        /// The last full download stopped before the end.
        case incomplete(message: String)
        /// The last full download read every record.
        case complete(Date)
    }

    @Published private(set) var communityPhase: CommunityPhase = .notStarted
    /// True while a private-library iCloud import has been running for a moment.
    @Published private(set) var privateImportActive = false
    /// The last private-library import error, cleared by the next good import.
    @Published private(set) var privateImportError: String?

    private static let lastCompleteKey = "LibrarySync.lastCompleteCommunityDownload"
    private static let lastTotalKey = "LibrarySync.lastCommunityRecordTotal"

    private var inFlightImports = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()
    private var showImportTask: Task<Void, Never>?

    private init() {
        let raw = UserDefaults.standard.double(forKey: Self.lastCompleteKey)
        if raw > 0 {
            communityPhase = .complete(Date(timeIntervalSinceReferenceDate: raw))
        }
        observePrivateMirroring()
    }

    // MARK: - Community library

    /// Records the last full download counted, used as the "of N" estimate.
    var lastKnownCommunityTotal: Int? {
        let n = UserDefaults.standard.integer(forKey: Self.lastTotalKey)
        return n > 0 ? n : nil
    }

    var lastCompleteCommunityDownload: Date? {
        if case .complete(let date) = communityPhase { return date }
        let raw = UserDefaults.standard.double(forKey: Self.lastCompleteKey)
        return raw > 0 ? Date(timeIntervalSinceReferenceDate: raw) : nil
    }

    /// True once a full download has finished on this device (now or earlier).
    var hasCompleteCommunityDownload: Bool { lastCompleteCommunityDownload != nil }

    func communityDownloadStarted() {
        communityPhase = .downloading(fetched: 0, expected: lastKnownCommunityTotal)
    }

    func communityDownloadProgress(fetched: Int) {
        communityPhase = .downloading(fetched: fetched, expected: lastKnownCommunityTotal)
    }

    func communityPhotosProgress(done: Int, total: Int) {
        communityPhase = .downloadingPhotos(done: done, total: total)
    }

    func communityDownloadFinished(totalRecords: Int) {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSinceReferenceDate, forKey: Self.lastCompleteKey)
        UserDefaults.standard.set(totalRecords, forKey: Self.lastTotalKey)
        communityPhase = .complete(now)
    }

    func communityDownloadFailed(_ message: String) {
        communityPhase = .incomplete(message: message)
    }

    // MARK: - Private library (SwiftData iCloud mirroring)

    /// The parts of a mirroring event the banner needs (plain values, so they
    /// can cross from the notification to the main actor).
    nonisolated private struct ImportEvent: Sendable {
        let id: UUID
        let ended: Bool
        let succeeded: Bool
        let errorText: String?
    }

    private func observePrivateMirroring() {
        // Hop to main first: CloudKit posts this on its own queue.
        NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }
                // Exports follow every save and finish quickly; only imports (and
                // the first setup) mean "this device is still receiving data".
                guard event.type == .import || event.type == .setup else { return }
                let info = ImportEvent(id: event.identifier,
                                       ended: event.endDate != nil,
                                       succeeded: event.succeeded,
                                       errorText: event.error?.localizedDescription)
                Task { @MainActor in self?.handle(info) }
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: ImportEvent) {
        if !event.ended {
            inFlightImports.insert(event.id)
            // Only show the banner for an import that lasts a moment, so routine
            // quick imports don't flicker it.
            if showImportTask == nil {
                showImportTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    guard let self, !Task.isCancelled else { return }
                    if !self.inFlightImports.isEmpty { self.privateImportActive = true }
                    self.showImportTask = nil
                }
            }
        } else {
            inFlightImports.remove(event.id)
            if event.succeeded {
                privateImportError = nil
            } else if let text = event.errorText {
                privateImportError = text
            }
            if inFlightImports.isEmpty {
                showImportTask?.cancel()
                showImportTask = nil
                privateImportActive = false
            }
        }
    }

    // MARK: - What the banner shows

    /// Nil when everything is caught up (the banner hides).
    var bannerText: String? {
        // Once a full download has finished on this device, later refreshes run
        // quietly: the library is complete, they only pick up changes.
        let quiet = UserDefaults.standard.double(forKey: Self.lastCompleteKey) > 0
        switch quiet ? .notStarted : communityPhase {
        case .downloading(let fetched, let expected):
            if let expected, expected > 0 {
                return "Downloading shared recipes… \(min(fetched, expected).formatted()) of about \(expected.formatted())"
            }
            return fetched > 0 ? "Downloading shared recipes… \(fetched.formatted())" : "Downloading shared recipes…"
        case .downloadingPhotos(let done, let total):
            return "Downloading recipe photos… \(done.formatted()) of \(total.formatted())"
        case .incomplete:
            return "Library not fully downloaded"
        case .notStarted, .complete:
            break
        }
        if privateImportActive { return "Syncing your library with iCloud…" }
        if let privateImportError { return "iCloud sync problem: \(privateImportError)" }
        return nil
    }

    /// 0...1 when a fraction is known, else nil (indeterminate spinner).
    var progressFraction: Double? {
        guard bannerText != nil, !hasCompleteCommunityDownload else { return nil }
        switch communityPhase {
        case .downloading(let fetched, let expected):
            guard let expected, expected > 0 else { return nil }
            return min(1, Double(fetched) / Double(expected))
        case .downloadingPhotos(let done, let total):
            return total > 0 ? Double(done) / Double(total) : nil
        default:
            return nil
        }
    }

    var isWorking: Bool {
        let quiet = UserDefaults.standard.double(forKey: Self.lastCompleteKey) > 0
        switch communityPhase {
        case .downloading, .downloadingPhotos: return !quiet || privateImportActive
        default: return privateImportActive
        }
    }

    var canRetry: Bool {
        if case .incomplete = communityPhase { return !hasCompleteCommunityDownload }
        return false
    }
}
