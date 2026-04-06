//
//  CloudKitDuplicateMonitor.swift
//  Reczipes2
//
//  Monitor CloudKit sync events and trigger deduplication when needed
//  Created for preventing duplicate recipes during sync token expiry
//

import Foundation
import SwiftData
import Combine

// MARK: - Duplicate Scan Throttle

/// Lightweight tracker that prevents redundant duplicate scans.
/// Persists the recipe count and timestamp of the last *clean* scan
/// (i.e. one that found zero duplicates) so subsequent launches and
/// CloudKit import callbacks can skip the expensive DB walk when
/// nothing has changed.
struct DuplicateScanTracker {
    private static let lastCleanCountKey  = "DedupLastCleanRecipeCount"
    private static let lastCleanDateKey   = "DedupLastCleanDate"
    private static let lastScanDateKey    = "DedupLastScanDate"
    /// Minimum seconds between any two scans (even if count changed)
    static let minimumScanInterval: TimeInterval = 30
    /// After a clean scan, don't re-scan for at least this long
    /// even if triggered by CloudKit import-finished callbacks.
    static let cleanScanCooldown: TimeInterval = 300  // 5 minutes

    /// Record that a scan just ran and found zero duplicates.
    static func recordCleanScan(recipeCount: Int) {
        let now = Date()
        UserDefaults.standard.set(recipeCount, forKey: lastCleanCountKey)
        UserDefaults.standard.set(now.timeIntervalSinceReferenceDate, forKey: lastCleanDateKey)
        UserDefaults.standard.set(now.timeIntervalSinceReferenceDate, forKey: lastScanDateKey)
    }

    /// Record that a scan just ran (regardless of result).
    static func recordScanRan() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: lastScanDateKey)
    }

    /// Whether we should skip the scan entirely.
    /// `currentCount` is the live recipe count from SwiftData.
    /// `force` bypasses the cooldown (used by the manual "Scan" button).
    static func shouldSkipScan(currentCount: Int, force: Bool = false) -> Bool {
        if force { return false }

        let savedCount = UserDefaults.standard.integer(forKey: lastCleanCountKey)
        let cleanDateRaw = UserDefaults.standard.double(forKey: lastCleanDateKey)
        let scanDateRaw  = UserDefaults.standard.double(forKey: lastScanDateKey)

        // Never scanned before → must scan
        guard cleanDateRaw > 0 else { return false }

        let cleanDate = Date(timeIntervalSinceReferenceDate: cleanDateRaw)
        let scanDate  = scanDateRaw > 0 ? Date(timeIntervalSinceReferenceDate: scanDateRaw) : .distantPast

        // If recipe count changed since the last clean scan, we need to scan
        if currentCount != savedCount { return false }

        // Count is the same — skip if still within cooldown
        let sinceClean = Date().timeIntervalSince(cleanDate)
        if sinceClean < cleanScanCooldown { return true }

        // Cooldown expired but count unchanged — also check minimum interval
        let sinceLast = Date().timeIntervalSince(scanDate)
        if sinceLast < minimumScanInterval { return true }

        return false
    }
}

@MainActor
class CloudKitDuplicateMonitor: ObservableObject {
    static let shared = CloudKitDuplicateMonitor()
    
    @Published var isSyncing = false
    @Published var lastSyncReset: Date?
    @Published var duplicatesDetected = 0
    
    private var cancellables = Set<AnyCancellable>()
    private var modelContext: ModelContext?
    
    private init() {
        setupNotifications()
    }
    
    func configure(with context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - CloudKit Notifications
    
    private func setupNotifications() {
        // Notification when CloudKit sync will reset (token expired)
        NotificationCenter.default.publisher(for: NSNotification.Name("NSCloudKitMirroringDelegateWillResetSyncNotificationName"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSyncWillReset(notification)
            }
            .store(in: &cancellables)
        
        // Notification when CloudKit sync did reset
        NotificationCenter.default.publisher(for: NSNotification.Name("NSCloudKitMirroringDelegateDidResetSyncNotificationName"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleSyncDidReset(notification)
            }
            .store(in: &cancellables)
        
        // Import started
        NotificationCenter.default.publisher(for: NSNotification.Name("NSCloudKitMirroringDelegateImportDidStart"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isSyncing = true
                logInfo("☁️ CloudKit import started", category: "cloudkit")
            }
            .store(in: &cancellables)
        
        // Import finished
        NotificationCenter.default.publisher(for: NSNotification.Name("NSCloudKitMirroringDelegateImportDidFinish"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleImportFinished(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleSyncWillReset(_ notification: Notification) {
        logWarning("⚠️ CloudKit sync will reset - change token expired", category: "cloudkit")
        logWarning("⚠️ This may cause duplicate recipes to be synced", category: "cloudkit")
        
        // Log the reason if available
        if let userInfo = notification.userInfo,
           let reason = userInfo["reason"] as? String {
            logWarning("⚠️ Reason: \(reason)", category: "cloudkit")
        }
        
        isSyncing = true
    }
    
    private func handleSyncDidReset(_ notification: Notification) {
        logInfo("✅ CloudKit sync reset complete", category: "cloudkit")
        lastSyncReset = Date()
        
        // Schedule duplicate detection after a delay to let sync finish
        Task {
            try? await Task.sleep(for: .seconds(5))
            await checkForDuplicates()
        }
    }
    
    private func handleImportFinished(_ notification: Notification) {
        logInfo("✅ CloudKit import finished", category: "cloudkit")
        isSyncing = false
        
        // Check if there was an error
        if let userInfo = notification.userInfo,
           let error = userInfo[NSUnderlyingErrorKey] as? Error {
            logError("❌ Import finished with error: \(error.localizedDescription)", category: "cloudkit")
        }
        
        // Run duplicate check after import
        Task {
            await checkForDuplicates()
        }
    }
    
    // MARK: - Multi-Strategy Duplicate Detection

    /// Finds duplicate clusters using fingerprint, URL, and title matching
    /// Returns array of (canonical recipe to keep, duplicates to delete)
    private func findDuplicateClusters(_ allRecipes: [RecipeX]) -> [(keep: RecipeX, delete: [RecipeX])] {
        var uf = RecipeUnionFind()

        let recipeMap: [UUID: RecipeX] = Dictionary(
            allRecipes.compactMap { r in r.id.map { ($0, r) } },
            uniquingKeysWith: { first, _ in first }
        )

        for recipe in allRecipes {
            guard let rid = recipe.id else { continue }
            uf.makeSet(rid)
        }

        // Strategy 1: Exact content fingerprint
        var byFingerprint: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id else { continue }
            let fp = recipe.contentFingerprint ?? rid.uuidString
            byFingerprint[fp, default: []].append(rid)
        }
        for (_, ids) in byFingerprint where ids.count > 1 {
            for i in 1..<ids.count { uf.union(ids[0], ids[i]) }
        }

        // Strategy 2: Same source URL
        var byURL: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id,
                  let ref = recipe.reference, !ref.isEmpty else { continue }
            let normalized = ref.lowercased()
                .replacingOccurrences(of: "http://", with: "https://")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            byURL[normalized, default: []].append(rid)
        }
        for (_, ids) in byURL where ids.count > 1 {
            for i in 1..<ids.count { uf.union(ids[0], ids[i]) }
        }

        // Strategy 3: Normalized title match
        var byTitle: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id else { continue }
            let normalized = DuplicateRecipeDetectorView.normalizeTitle(recipe.title ?? "")
            guard !normalized.isEmpty else { continue }
            byTitle[normalized, default: []].append(rid)
        }
        for (_, ids) in byTitle where ids.count > 1 {
            for i in 1..<ids.count { uf.union(ids[0], ids[i]) }
        }

        // Build groups
        var groups: [UUID: [UUID]] = [:]
        for rid in uf.allIDs {
            let root = uf.find(rid)
            groups[root, default: []].append(rid)
        }

        var results: [(keep: RecipeX, delete: [RecipeX])] = []
        for (_, memberIDs) in groups where memberIDs.count > 1 {
            let recipes = memberIDs.compactMap { recipeMap[$0] }
            guard recipes.count > 1 else { continue }

            // Keep most complete, then oldest
            let sorted = recipes.sorted { r1, r2 in
                let s1 = dataScore(r1); let s2 = dataScore(r2)
                if s1 != s2 { return s1 > s2 }
                return (r1.dateAdded ?? .distantFuture) < (r2.dateAdded ?? .distantFuture)
            }
            let canonical = sorted[0]
            let dupes = Array(sorted.dropFirst())
            results.append((keep: canonical, delete: dupes))
        }
        return results
    }

    private func dataScore(_ recipe: RecipeX) -> Int {
        var score = 0
        if recipe.ingredientSectionsData != nil && !recipe.ingredientSections.isEmpty { score += 1 }
        if recipe.instructionSectionsData != nil && !recipe.instructionSections.isEmpty { score += 1 }
        if recipe.imageData != nil { score += 1 }
        if recipe.notesData != nil && !recipe.notes.isEmpty { score += 1 }
        return score
    }

    func checkForDuplicates(force: Bool = false) async {
        guard let context = modelContext else {
            logWarning("⚠️ ModelContext not configured for duplicate detection", category: "cloudkit")
            return
        }

        do {
            // Quick count check to see if a scan is even needed
            let countDescriptor = FetchDescriptor<RecipeX>()
            let recipeCount = try context.fetchCount(countDescriptor)

            if DuplicateScanTracker.shouldSkipScan(currentCount: recipeCount, force: force) {
                logInfo("⏭️ Skipping duplicate scan — recipe count unchanged (\(recipeCount)) and cooldown active", category: "cloudkit")
                return
            }

            logInfo("🔍 Checking for duplicates after sync (multi-strategy)...", category: "cloudkit")
            DuplicateScanTracker.recordScanRan()

            let descriptor = FetchDescriptor<RecipeX>(sortBy: [SortDescriptor(\.title)])
            let allRecipes = try context.fetch(descriptor)

            logInfo("📊 Total recipes: \(allRecipes.count)", category: "cloudkit")

            let clusters = findDuplicateClusters(allRecipes)
            let totalDuplicates = clusters.reduce(0) { $0 + $1.delete.count }

            duplicatesDetected = totalDuplicates

            if totalDuplicates > 0 {
                logWarning("⚠️ Found \(clusters.count) duplicate groups containing \(totalDuplicates) extra recipes", category: "cloudkit")

                logInfo("🧹 Auto-cleaning \(totalDuplicates) duplicate(s) from CloudKit sync...", category: "cloudkit")
                var deletedCount = 0
                for cluster in clusters {
                    logInfo("   Keeping: '\(cluster.keep.safeTitle)' (ID: \(String(describing: cluster.keep.id)))", category: "cloudkit")
                    for duplicate in cluster.delete {
                        logInfo("   🗑️ Deleting duplicate: \(String(describing: duplicate.id))", category: "cloudkit")
                        context.delete(duplicate)
                        deletedCount += 1
                    }
                }

                if deletedCount > 0 {
                    try context.save()
                    logInfo("✅ Auto-cleaned \(deletedCount) CloudKit sync duplicates", category: "cloudkit")
                    duplicatesDetected = 0
                }

                // After cleanup, re-count and record clean state
                let newCount = try context.fetchCount(countDescriptor)
                DuplicateScanTracker.recordCleanScan(recipeCount: newCount)
                logInfo("🧹 Silently resolved \(deletedCount) duplicate(s) — next scan skipped until count changes", category: "cloudkit")
            } else {
                logInfo("✅ No duplicates detected — recording clean state", category: "cloudkit")
                DuplicateScanTracker.recordCleanScan(recipeCount: recipeCount)
            }

        } catch {
            logError("❌ Error checking for duplicates: \(error)", category: "cloudkit")
        }
    }

    // MARK: - Auto Cleanup (Manual trigger)

    /// Manually trigger duplicate cleanup with multi-strategy detection
    func autoCleanupDuplicates() async {
        await checkForDuplicates()
    }
}

// MARK: - SwiftUI Integration

import SwiftUI

/// View modifier to show duplicate detection alert (only for edge cases not caught by auto-cleanup)
struct DuplicateDetectionModifier: ViewModifier {
    @StateObject private var monitor = CloudKitDuplicateMonitor.shared
    @State private var showingAlert = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDuplicatesDetected"))) { notification in
                if let count = notification.userInfo?["count"] as? Int, count > 0 {
                    showingAlert = true
                }
            }
            .alert("Duplicates Detected", isPresented: $showingAlert) {
                Button("View & Clean Up", role: .none) {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowDuplicateDetector"), object: nil)
                }
                Button("Dismiss", role: .cancel) { }
            } message: {
                Text("Found \(monitor.duplicatesDetected) duplicate recipes. Would you like to clean them up?")
            }
    }
}

extension View {
    func monitorDuplicates() -> some View {
        modifier(DuplicateDetectionModifier())
    }
}
