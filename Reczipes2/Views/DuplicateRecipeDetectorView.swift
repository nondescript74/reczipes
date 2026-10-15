//
//  DuplicateRecipeDetectorView.swift
//  Reczipes2
//
//  Tool for finding and cleaning up duplicate recipes
//  Created by Zahirudeen Premji on 1/19/26.
//

import SwiftUI
import SwiftData

// MARK: - Union-Find (value type, no closure capture issues)

/// Simple Union-Find data structure for grouping recipe UUIDs
struct RecipeUnionFind {
    private var parent: [UUID: UUID] = [:]

    mutating func makeSet(_ id: UUID) {
        if parent[id] == nil { parent[id] = id }
    }

    mutating func find(_ id: UUID) -> UUID {
        var current = id
        while let p = parent[current], p != current {
            parent[current] = parent[p] ?? p  // path compression
            current = p
        }
        return current
    }

    mutating func union(_ a: UUID, _ b: UUID) {
        let ra = find(a)
        let rb = find(b)
        if ra != rb { parent[ra] = rb }
    }

    /// All unique IDs that have been registered
    var allIDs: [UUID] { Array(parent.keys) }
}

// MARK: - Duplicate Cluster Model

/// Represents a group of recipes detected as duplicates, with the reason(s) they matched
struct DuplicateCluster: Identifiable {
    let id = UUID()
    let recipes: [RecipeX]
    let matchReasons: Set<MatchReason>

    enum MatchReason: Hashable {
        case fingerprint         // Exact content fingerprint match
        case sameSourceURL       // Same reference URL
        case similarTitle        // Normalized title match
    }

    var title: String {
        recipes.first?.title ?? "Untitled"
    }

    var copyCount: Int { recipes.count }
    var extraCount: Int { recipes.count - 1 }

    /// The recipe to keep (oldest by dateAdded, preferring the one with more data)
    var canonical: RecipeX {
        recipes.sorted { r1, r2 in
            // Prefer recipe with more complete data
            let score1 = dataCompletenessScore(r1)
            let score2 = dataCompletenessScore(r2)
            if score1 != score2 { return score1 > score2 }
            // Then prefer oldest
            return (r1.dateAdded ?? .distantFuture) < (r2.dateAdded ?? .distantFuture)
        }.first!
    }

    var duplicatesToDelete: [RecipeX] {
        let keep = canonical
        return recipes.filter { $0.id != keep.id }
    }

    var reasonLabels: [String] {
        matchReasons.sorted(by: { $0.sortOrder < $1.sortOrder }).map(\.label)
    }

    private func dataCompletenessScore(_ recipe: RecipeX) -> Int {
        var score = 0
        if recipe.ingredientSectionsData != nil && !recipe.ingredientSections.isEmpty { score += 1 }
        if recipe.instructionSectionsData != nil && !recipe.instructionSections.isEmpty { score += 1 }
        if recipe.imageData != nil { score += 1 }
        if recipe.notesData != nil && !recipe.notes.isEmpty { score += 1 }
        return score
    }
}

extension DuplicateCluster.MatchReason {
    var label: String {
        switch self {
        case .fingerprint:    return "Exact Match"
        case .sameSourceURL:  return "Same URL"
        case .similarTitle:   return "Similar Title"
        }
    }

    var icon: String {
        switch self {
        case .fingerprint:    return "equal.circle.fill"
        case .sameSourceURL:  return "link.circle.fill"
        case .similarTitle:   return "textformat.abc"
        }
    }

    var color: Color {
        switch self {
        case .fingerprint:    return .red
        case .sameSourceURL:  return .orange
        case .similarTitle:   return .yellow
        }
    }

    var sortOrder: Int {
        switch self {
        case .fingerprint:    return 0
        case .sameSourceURL:  return 1
        case .similarTitle:   return 2
        }
    }
}

// MARK: - View

struct DuplicateRecipeDetectorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeX.title) private var allRecipes: [RecipeX]
    @Query private var recipeXEntities: [RecipeX]
    @Query private var allBooks: [Book]
    @Query private var sharedRecipes: [SharedRecipe]
    @StateObject private var monitor = CloudKitDuplicateMonitor.shared

    @State private var clusters: [DuplicateCluster] = []
    @State private var isAnalyzing = false
    @State private var showingConfirmation = false
    @State private var selectedRecipe: RecipeX?
    @State private var isMerging = false
    @State private var mergeMessage: String?

    var body: some View {
        List {
            statisticsSection
            actionsSection
            duplicateGroupsSection
        }
        .navigationTitle("Duplicate Detector")
        .platformNavigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Merge Exact Copies?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Merge \(exactExtraCount) Copies", role: .destructive) {
                Task { await mergeAllExactCopies() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes \(exactExtraCount) extra copies that match exactly (same content or same source link), keeping the most complete copy of each. Books that held a removed copy get the kept copy instead, and the removed copy's public (website) copy is taken down. Same-title groups are NOT touched — review those one by one.")
        }
        .alert("Duplicates", isPresented: Binding(
            get: { mergeMessage != nil },
            set: { if !$0 { mergeMessage = nil } }
        )) {
            Button("OK") { mergeMessage = nil }
        } message: {
            Text(mergeMessage ?? "")
        }
        .onAppear {
            monitor.configure(with: modelContext)
            findDuplicates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowDuplicateDetector"))) { _ in
            findDuplicates()
        }
    }

    // MARK: - Section Views

    private var statisticsSection: some View {
        Section {
            HStack {
                statisticView(title: "Total Recipes", value: "\(allRecipes.count)", color: nil)
                Spacer()
                statisticView(title: "Duplicate Groups", value: "\(clusters.count)", color: clusters.isEmpty ? .green : .red)
                Spacer()
                statisticView(title: "Extra Copies", value: "\(totalDuplicateCount)", color: totalDuplicateCount == 0 ? .green : .orange)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Statistics")
        }
    }

    private func statisticView(title: String, value: String, color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color ?? Color.primary)
        }
    }

    private var actionsSection: some View {
        Section {
            scanButton
            if !clusters.isEmpty {
                deleteAllButton
            }
        } header: {
            Text("Actions")
        } footer: {
            if !clusters.isEmpty {
                Text("Merging keeps the most complete copy and moves its book memberships across. Groups marked only \"Similar Title\" may be different recipes (e.g. two fudges) — open them and remove a copy only if it really is the same recipe.")
                    .font(.caption)
            }
        }
    }

    private var scanButton: some View {
        Button {
            findDuplicates()
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Scan for Duplicates")
                if isAnalyzing {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
        }
        .disabled(isAnalyzing)
    }

    private var deleteAllButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                Text(isMerging ? "Merging…" : "Merge Exact Copies")
                Text("(\(exactExtraCount))")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(exactExtraCount == 0 || isMerging)
        .foregroundStyle(Color.appCritical)
    }

    @ViewBuilder
    private var duplicateGroupsSection: some View {
        if !clusters.isEmpty {
            Section {
                ForEach(clusters) { cluster in
                    duplicateClusterRow(cluster)
                }
            } header: {
                Text("Duplicate Groups (\(clusters.count))")
            }
        } else if isAnalyzing {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Analyzing recipes...")
                    Spacer()
                }
                .padding()
            }
        } else {
            Section {
                ContentUnavailableView(
                    "No Duplicates Found",
                    systemImage: "checkmark.circle.fill",
                    description: Text("Tap 'Scan for Duplicates' to check for duplicate recipes")
                )
            }
        }
    }

    private func duplicateClusterRow(_ cluster: DuplicateCluster) -> some View {
        DisclosureGroup {
            ForEach(cluster.recipes.sorted(by: { r1, r2 in
                (r1.dateAdded ?? Date.distantPast) < (r2.dateAdded ?? Date.distantPast)
            })) { recipe in
                recipeRow(recipe, isCanonical: recipe.id == cluster.canonical.id,
                          keep: cluster.canonical, titleOnly: cluster.matchReasons == [.similarTitle])
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cluster.title)
                        .font(.headline)
                    Text("\(cluster.copyCount) copies found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Match reason badges
                    HStack(spacing: 4) {
                        ForEach(cluster.reasonLabels, id: \.self) { label in
                            let reason = cluster.matchReasons.first(where: { $0.label == label })
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background((reason?.color ?? .gray).opacity(0.2))
                                .foregroundStyle(reason?.color ?? .gray)
                                .clipShape(Capsule())
                        }
                    }
                }

                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.appWarning)
            }
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeX, isCanonical: Bool, keep: RecipeX, titleOnly: Bool) -> some View {
        let recipeIDPreview: String = {
            if let id = recipe.id {
                return String(id.uuidString.prefix(8))
            } else {
                return "unknown"
            }
        }()

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isCanonical {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("KEEP")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appSuccess)
                    } else {
                        Image(systemName: titleOnly ? "questionmark.circle.fill" : "trash.circle.fill")
                            .foregroundStyle(titleOnly ? Color.appWarning : Color.appCritical)
                        Text(titleOnly ? "SAME TITLE — CHECK" : "EXTRA COPY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(titleOnly ? Color.appWarning : Color.appCritical)
                    }
                }

                Text(recipe.title ?? "Untitled")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("ID: \(recipeIDPreview)...")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Label {
                    Text(recipe.dateAdded ?? Date(), style: .date)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let ref = recipe.reference, !ref.isEmpty {
                    Label {
                        Text(ref)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !isCanonical {
                Button {
                    selectedRecipe = recipe
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.appCritical)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .alert("Delete This Recipe?", isPresented: .init(
            get: { selectedRecipe == recipe },
            set: { if !$0 { selectedRecipe = nil } }
        )) {
            Button("Remove Copy", role: .destructive) {
                Task { await mergeCopy(recipe, into: keep); findDuplicates() }
            }
            Button("Cancel", role: .cancel) {
                selectedRecipe = nil
            }
        } message: {
            Text("Removes this copy of '\(recipe.title ?? "Unknown Recipe")'. Its books get the kept copy instead; its website copy is taken down. Can't be undone.")
        }
    }

    // MARK: - Computed Properties

    private var totalDuplicateCount: Int {
        clusters.reduce(0) { $0 + $1.extraCount }
    }

    // MARK: - Multi-Strategy Duplicate Detection

    private func findDuplicates() {
        isAnalyzing = true

        let recipes = allRecipes
        let resultClusters = Self.buildDuplicateClusters(from: recipes)

        clusters = resultClusters
        isAnalyzing = false

        // Record scan result so auto-scans elsewhere can skip when clean
        if resultClusters.isEmpty {
            DuplicateScanTracker.recordCleanScan(recipeCount: recipes.count)
        } else {
            DuplicateScanTracker.recordScanRan()
        }

        print("📊 Duplicate scan complete:")
        print("   Total recipes: \(recipes.count)")
        print("   Duplicate groups: \(resultClusters.count)")
        print("   Extra copies: \(totalDuplicateCount)")
        for cluster in resultClusters {
            print("   → \(cluster.title): \(cluster.copyCount) copies [\(cluster.reasonLabels.joined(separator: ", "))]")
        }
    }

    /// Creates a stable string key from two UUIDs for the reasons dictionary
    private static func pairKey(_ a: UUID, _ b: UUID) -> String {
        let sa = a.uuidString; let sb = b.uuidString
        return sa < sb ? "\(sa)|\(sb)" : "\(sb)|\(sa)"
    }

    /// - Parameter includeTitleMatches: when false, only exact copies (same content
    ///   fingerprint or same source URL) are clustered. Automatic, unattended cleanup
    ///   must pass false: different recipes often share a title ("Scones", "Fudge"),
    ///   and re-extractions of the same page can differ in content, so title matches
    ///   need a human to decide which copy to keep.
    static func buildDuplicateClusters(from allRecipes: [RecipeX], includeTitleMatches: Bool = true) -> [DuplicateCluster] {
        var uf = RecipeUnionFind()
        var reasons: [String: Set<DuplicateCluster.MatchReason>] = [:]

        let recipeMap: [UUID: RecipeX] = Dictionary(
            allRecipes.compactMap { r in r.id.map { ($0, r) } },
            uniquingKeysWith: { first, _ in first }
        )

        // Initialize
        for recipe in allRecipes {
            guard let rid = recipe.id else { continue }
            uf.makeSet(rid)
        }

        // --- Strategy 1: Exact content fingerprint ---
        var byFingerprint: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id else { continue }
            let fp = recipe.contentFingerprint ?? rid.uuidString
            byFingerprint[fp, default: []].append(rid)
        }
        for (_, ids) in byFingerprint where ids.count > 1 {
            for i in 1..<ids.count {
                uf.union(ids[0], ids[i])
                let key = pairKey(ids[0], ids[i])
                reasons[key, default: []].insert(.fingerprint)
            }
        }

        // --- Strategy 2: Same source URL ---
        var byURL: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id,
                  let ref = recipe.reference,
                  !ref.isEmpty,
                  // Only real web links: URL(string:) also accepts "75" or "Page 26", which
                  // made recipes on the same book page "exact copies" for the launch auto-clean.
                  let url = URL(string: ref.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  url.host != nil else { continue }
            let normalizedURL = ref.lowercased()
                .replacingOccurrences(of: "http://", with: "https://")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            byURL[normalizedURL, default: []].append(rid)
        }
        for (_, ids) in byURL where ids.count > 1 {
            for i in 1..<ids.count {
                uf.union(ids[0], ids[i])
                let key = pairKey(ids[0], ids[i])
                reasons[key, default: []].insert(.sameSourceURL)
            }
        }

        // --- Strategy 3: Fuzzy title match (manual review only) ---
        var byNormalizedTitle: [String: [UUID]] = [:]
        for recipe in allRecipes where includeTitleMatches {
            guard let rid = recipe.id else { continue }
            let normalized = normalizeTitle(recipe.title ?? "")
            guard !normalized.isEmpty else { continue }
            byNormalizedTitle[normalized, default: []].append(rid)
        }
        for (_, ids) in byNormalizedTitle where ids.count > 1 {
            for i in 1..<ids.count {
                uf.union(ids[0], ids[i])
                let key = pairKey(ids[0], ids[i])
                reasons[key, default: []].insert(.similarTitle)
            }
        }

        // --- Build clusters from Union-Find ---
        // find() is mutating (path compression), so we work with the mutable uf
        var groupsByRoot: [UUID: [UUID]] = [:]
        for rid in uf.allIDs {
            let root = uf.find(rid)
            groupsByRoot[root, default: []].append(rid)
        }

        var resultClusters: [DuplicateCluster] = []
        for (_, memberIDs) in groupsByRoot where memberIDs.count > 1 {
            let recipes = memberIDs.compactMap { recipeMap[$0] }
            guard recipes.count > 1 else { continue }

            // Collect all match reasons for this cluster
            var clusterReasons: Set<DuplicateCluster.MatchReason> = []
            for i in 0..<memberIDs.count {
                for j in (i+1)..<memberIDs.count {
                    let key = pairKey(memberIDs[i], memberIDs[j])
                    if let pairReasons = reasons[key] {
                        clusterReasons.formUnion(pairReasons)
                    }
                }
            }

            resultClusters.append(DuplicateCluster(
                recipes: recipes,
                matchReasons: clusterReasons
            ))
        }

        resultClusters.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return resultClusters
    }

    /// Normalize a recipe title for fuzzy comparison:
    /// lowercase, strip punctuation, collapse whitespace, remove common filler words
    static func normalizeTitle(_ title: String) -> String {
        var t = title.lowercased()
        // Remove common suffixes added by extraction
        let stripSuffixes = [" recipe", " - recipe"]
        for suffix in stripSuffixes {
            if t.hasSuffix(suffix) {
                t = String(t.dropLast(suffix.count))
            }
        }
        // Strip punctuation except spaces
        t = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map { String($0) }.joined()
        // Collapse whitespace
        t = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Actions

    /// Every book that lists `dupID` lists `keepID` instead (once). Used before a duplicate is
    /// deleted, by the detector and by the launch auto-clean, so books never lose a recipe.
    static func repointBooks(from dupID: UUID, to keepID: UUID, in books: [Book]) {
        for book in books {
            guard var ids = book.recipeIDs, let index = ids.firstIndex(of: dupID) else { continue }
            if ids.contains(keepID) {
                ids.remove(at: index)
            } else {
                ids[index] = keepID
            }
            book.recipeIDs = ids
            book.recipeIDsHash = Book.calculateRecipeIDsHash(from: ids)
            book.dateModified = Date()
        }
    }

    /// Clusters joined by exact content or same source URL only (never by title alone).
    private var exactClusters: [DuplicateCluster] {
        Self.buildDuplicateClusters(from: allRecipes, includeTitleMatches: false)
    }

    private var exactExtraCount: Int {
        exactClusters.reduce(0) { $0 + $1.extraCount }
    }

    /// Removes `duplicate` after moving its book memberships to `keep` and taking down its
    /// public copy. Nothing in a book is lost: each book that listed the duplicate lists the
    /// kept copy instead (once).
    private func mergeCopy(_ duplicate: RecipeX, into keep: RecipeX) async {
        guard let dupID = duplicate.id, let keepID = keep.id, dupID != keepID else { return }

        Self.repointBooks(from: dupID, to: keepID, in: allBooks)

        if let tracked = sharedRecipes.first(where: { $0.recipeID == dupID && $0.isActive }),
           let cloudRecordID = tracked.cloudRecordID {
            do {
                try await CloudKitSharingService.shared.unshareRecipe(cloudRecordID: cloudRecordID, modelContext: modelContext)
            } catch {
                AppLog.warning("Could not take down public copy of duplicate '\(duplicate.title ?? "")': \(error)", category: .sharing)
            }
        }

        modelContext.delete(duplicate)
        do {
            try modelContext.save()
            AppLog.info("Merged duplicate '\(duplicate.title ?? "")' (\(dupID)) into \(keepID)", category: .recipe)
        } catch {
            AppLog.error("Failed to save after merging duplicate: \(error)", category: .recipe)
        }
    }

    /// Merges every exact-copy group (content fingerprint or same source URL). Same-title-only
    /// groups are left for manual review.
    private func mergeAllExactCopies() async {
        isMerging = true
        defer { isMerging = false }
        var merged = 0
        for cluster in exactClusters {
            let keep = cluster.canonical
            for duplicate in cluster.duplicatesToDelete {
                await mergeCopy(duplicate, into: keep)
                merged += 1
            }
        }
        findDuplicates()
        DuplicateScanTracker.recordCleanScan(recipeCount: allRecipes.count)
        mergeMessage = "Merged \(merged) extra copies. Books now point at the kept copies. Use Update Public Copy on any book you want refreshed on the website."
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DuplicateRecipeDetectorView()
            .modelContainer(for: RecipeX.self, inMemory: true)
    }
}
