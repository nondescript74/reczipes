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
import CloudKit
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
    /// Full detail of that error (domain, code, CloudKit code name, underlying and
    /// per-record errors, retry-after) and when it happened — shown when the banner
    /// is tapped and written to the diagnostic log, so "it could be a timeout" can be
    /// answered from the code instead of a sentence cut off at one line.
    @Published private(set) var privateImportErrorDetail: String?
    @Published private(set) var privateImportErrorDate: Date?
    /// Δ-163 publish pass: items published so far / to publish (0 = not running).
    @Published private(set) var publishDone = 0
    @Published private(set) var publishTotal = 0
    /// Small passes (an edit or two) run quietly.
    private var publishShown: Bool { publishTotal > 3 }

    func publishProgress(done: Int, total: Int) {
        publishDone = done
        publishTotal = total
    }

    func publishFinished() {
        publishDone = 0
        publishTotal = 0
    }

    private static let lastCompleteKey = "LibrarySync.lastCompleteCommunityDownload"
    private static let lastTotalKey = "LibrarySync.lastCommunityRecordTotal"

    /// The community cache was emptied (new cache store): forget the last full download
    /// so the next one runs at launch and shows its progress instead of running quietly.
    static func forgetCompletedCommunityDownload() {
        UserDefaults.standard.removeObject(forKey: lastCompleteKey)
        shared.communityPhase = .notStarted
    }

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
        let errorDetail: String?
    }

    /// Everything an NSError / CKError says about itself, as plain text.
    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var lines: [String] = []
        lines.append("Message: \(ns.localizedDescription)")
        lines.append("Domain: \(ns.domain) · code \(ns.code)")
        if ns.domain == CKError.errorDomain, let code = CKError.Code(rawValue: ns.code) {
            lines.append("CloudKit: \(String(describing: code))")
        }
        if let reason = ns.localizedFailureReason { lines.append("Reason: \(reason)") }
        if let retry = ns.userInfo[CKErrorRetryAfterKey] as? NSNumber {
            lines.append("Retry after: \(retry) s")
        }
        if let partial = ns.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error], !partial.isEmpty {
            lines.append("Per-record errors: \(partial.count)")
            for (_, sub) in partial.prefix(5) {
                let subNS = sub as NSError
                let name = CKError.Code(rawValue: subNS.code).map { String(describing: $0) } ?? "\(subNS.code)"
                lines.append("  • \(name): \(subNS.localizedDescription)")
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            let u = underlying as NSError
            lines.append("Underlying: \(u.domain) · code \(u.code) — \(u.localizedDescription)")
        }
        return lines.joined(separator: "\n")
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
                                       errorText: event.error?.localizedDescription,
                                       errorDetail: event.error.map { LibrarySyncStatus.describe($0) })
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
                privateImportErrorDetail = nil
                privateImportErrorDate = nil
            } else if let text = event.errorText {
                privateImportError = text
                privateImportErrorDetail = event.errorDetail
                privateImportErrorDate = Date()
                AppLog.warning("☁️ iCloud import failed:\n\(event.errorDetail ?? text)", category: .sync)
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
                return String(localized: "Downloading shared recipes… \(min(fetched, expected).formatted()) of about \(expected.formatted())", bundle: .appLanguage)
            }
            return fetched > 0 ? "Downloading shared recipes… \(fetched.formatted())" : "Downloading shared recipes…"
        case .downloadingPhotos(let done, let total):
            return String(localized: "Downloading recipe photos… \(done.formatted()) of \(total.formatted())", bundle: .appLanguage)
        case .incomplete:
            return String(localized: "Library not fully downloaded", bundle: .appLanguage)
        case .notStarted, .complete:
            break
        }
        if publishShown {
            return String(localized: "Sharing your library with everyone… \(publishDone.formatted()) of \(publishTotal.formatted())", bundle: .appLanguage)
        }
        if privateImportActive { return "Syncing your library with iCloud…" }
        if let privateImportError { return "iCloud sync problem: \(privateImportError)" }
        return nil
    }

    /// 0...1 when a fraction is known, else nil (indeterminate spinner).
    var progressFraction: Double? {
        if publishShown, bannerText?.hasPrefix("Sharing your library") == true {
            return Double(publishDone) / Double(publishTotal)
        }
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
        case .downloading, .downloadingPhotos: return !quiet || privateImportActive || publishShown
        default: return privateImportActive || publishShown
        }
    }

    var canRetry: Bool {
        if case .incomplete = communityPhase { return !hasCompleteCommunityDownload }
        return false
    }
}
