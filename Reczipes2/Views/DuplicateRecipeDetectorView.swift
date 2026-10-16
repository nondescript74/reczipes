//
//  DuplicateRecipeDetectorView.swift
//  Reczipes2
//
//  Tool for finding and cleaning up duplicate recipes
//  Created by Zahirudeen Premji on 1/19/26.
//
//  Rule set (revised Oct 2026 after the Shahsultan book dedupe):
//  • A matching title alone is never a duplicate. Same-title recipes are only
//    grouped when their ingredient lists match (by ingredient name — quantities
//    are ignored because OCR re-extractions often misread them).
//  • The "source URL" rule only applies to real http(s) links. Page numbers
//    stored in the reference field ("12", "Page 9") are ignored.
//  • Each group carries a confidence level. Only exact copies (same content
//    fingerprint or same web link) may be bulk-merged; everything else is
//    review-only, one copy at a time.
//  • The suggested keeper is the most complete copy (ingredients + steps),
//    preferring one that is already in a book, then the oldest. The user can
//    override it with "Keep This".
//  • Removing a copy is a merge: every book that listed it lists the kept copy
//    instead, and its public (website) copy is taken down.
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
    /// How sure we are that every recipe in the group is the same recipe
    var confidence: Confidence = .exactCopy
    /// Lowest pairwise ingredient similarity inside the group (nil for exact copies)
    var ingredientSimilarity: Double? = nil
    /// IDs of recipes that belong to at least one book (used to pick the keeper)
    var bookRecipeIDs: Set<UUID> = []

    enum MatchReason: Hashable {
        case fingerprint         // Exact content fingerprint match
        case sameSourceURL       // Same http(s) reference link
        case sameIngredients     // Same title + matching ingredient list
        case similarTitle        // Same title + partially matching ingredients (review)
    }

    enum Confidence: Int, Comparable {
        case possible = 0    // same title, ingredients only partly match — review
        case likely = 1      // same title, ingredient lists match — review
        case exactCopy = 2   // identical content or same web link — safe to bulk merge

        static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .exactCopy: return "Exact Copy"
            case .likely:    return "Likely Same Recipe"
            case .possible:  return "Possible — Review"
            }
        }

        var color: Color {
            switch self {
            case .exactCopy: return .red
            case .likely:    return .orange
            case .possible:  return .yellow
            }
        }
    }

    var title: String {
        recipes.first?.title ?? "Untitled"
    }

    var copyCount: Int { recipes.count }
    var extraCount: Int { recipes.count - 1 }

    /// Only exact copies are merged by "Merge Exact Copies" and by the launch auto-clean.
    var isSafeToBulkDelete: Bool { confidence == .exactCopy }

    /// Stable key for this group (survives re-scans), used for keeper overrides.
    var stableKey: String {
        recipes.compactMap { $0.id?.uuidString }.sorted().joined(separator: "|")
    }

    /// The suggested recipe to keep: most complete, then in a book, then oldest.
    var canonical: RecipeX {
        recipes.sorted { r1, r2 in
            let s1 = Self.completenessScore(r1)
            let s2 = Self.completenessScore(r2)
            if s1 != s2 { return s1 > s2 }
            let b1 = r1.id.map { bookRecipeIDs.contains($0) } ?? false
            let b2 = r2.id.map { bookRecipeIDs.contains($0) } ?? false
            if b1 != b2 { return b1 }
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

    /// Ingredients + instruction steps, plus a point each for image, notes and yield.
    static func completenessScore(_ recipe: RecipeX) -> Int {
        let ingredientCount = recipe.ingredientSections.reduce(0) { $0 + $1.ingredients.count }
        let stepCount = recipe.instructionSections.reduce(0) { $0 + $1.steps.count }
        var score = ingredientCount + stepCount
        if recipe.imageData != nil { score += 1 }
        if recipe.notesData != nil && !recipe.notes.isEmpty { score += 1 }
        if let y = recipe.recipeYield, !y.isEmpty { score += 1 }
        return score
    }
}

extension DuplicateCluster.MatchReason {
    var label: String {
        switch self {
        case .fingerprint:     return "Exact Match"
        case .sameSourceURL:   return "Same URL"
        case .sameIngredients: return "Same Ingredients"
        case .similarTitle:    return "Same Title"
        }
    }

    var icon: String {
        switch self {
        case .fingerprint:     return "equal.circle.fill"
        case .sameSourceURL:   return "link.circle.fill"
        case .sameIngredients: return "list.bullet.circle.fill"
        case .similarTitle:    return "textformat.abc"
        }
    }

    var color: Color {
        switch self {
        case .fingerprint:     return .red
        case .sameSourceURL:   return .orange
        case .sameIngredients: return .orange
        case .similarTitle:    return .yellow
        }
    }

    var sortOrder: Int {
        switch self {
        case .fingerprint:     return 0
        case .sameSourceURL:   return 1
        case .sameIngredients: return 2
        case .similarTitle:    return 3
        }
    }

    /// Strength of a single pairwise match, as a confidence level
    var confidence: DuplicateCluster.Confidence {
        switch self {
        case .fingerprint, .sameSourceURL: return .exactCopy
        case .sameIngredients:             return .likely
        case .similarTitle:                return .possible
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
    /// User-chosen keeper per group (keyed by DuplicateCluster.stableKey)
    @State private var keeperOverrides: [String: UUID] = [:]
    @State private var keepConfirmation: (cluster: DuplicateCluster, recipe: RecipeX)?

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
            Button("Merge \(exactCopyCount) Copies", role: .destructive) {
                Task { await mergeAllExactCopies() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Removes \(exactCopyCount) extra copies that match exactly (same content or same web link), keeping one of each. Books that held a removed copy get the kept copy instead, and the removed copy's website copy is taken down. Groups matched by title or ingredients are NOT touched — review those one at a time. This cannot be undone.")
        }
        .alert("Keep This Copy?", isPresented: .init(
            get: { keepConfirmation != nil },
            set: { if !$0 { keepConfirmation = nil } }
        )) {
            Button("Remove the Others", role: .destructive) {
                if let pending = keepConfirmation {
                    Task { await keepOnly(pending.recipe, in: pending.cluster) }
                }
                keepConfirmation = nil
            }
            Button("Cancel", role: .cancel) { keepConfirmation = nil }
        } message: {
            if let pending = keepConfirmation {
                Text("Keeps '\(pending.recipe.title ?? "this recipe")' and removes the other \(pending.cluster.copyCount - 1) cop\(pending.cluster.copyCount - 1 == 1 ? "y" : "ies") in this group. Their books get this copy instead; their website copies are taken down.")
            }
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
                statisticView(title: "Groups to Review", value: "\(clusters.count)", color: clusters.isEmpty ? .green : .orange)
                Spacer()
                statisticView(title: "Exact Copies", value: "\(exactCopyCount)", color: exactCopyCount == 0 ? .green : .red)
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
            if exactCopyCount > 0 {
                mergeAllButton
            }
        } header: {
            Text("Actions")
        } footer: {
            Text("A shared title alone never counts as a duplicate. \"Likely\" and \"Possible\" groups are for review only: compare the ingredients, then remove one copy or use \"Keep This\". Removing a copy moves its book memberships to the kept copy.")
                .font(.caption)
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

    private var mergeAllButton: some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                Text(isMerging ? "Merging…" : "Merge Exact Copies")
                Text("(\(exactCopyCount))")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(exactCopyCount == 0 || isMerging)
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

    private func keeper(for cluster: DuplicateCluster) -> RecipeX {
        if let overrideID = keeperOverrides[cluster.stableKey],
           let chosen = cluster.recipes.first(where: { $0.id == overrideID }) {
            return chosen
        }
        return cluster.canonical
    }

    private func duplicateClusterRow(_ cluster: DuplicateCluster) -> some View {
        let keep = keeper(for: cluster)
        return DisclosureGroup {
            ForEach(cluster.recipes.sorted(by: { r1, r2 in
                (r1.dateAdded ?? Date.distantPast) < (r2.dateAdded ?? Date.distantPast)
            })) { recipe in
                recipeRow(recipe, in: cluster, keep: keep)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cluster.title)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text("\(cluster.copyCount) copies")
                        if let sim = cluster.ingredientSimilarity {
                            Text("· ingredients \(Int((sim * 100).rounded()))% alike")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        badge(cluster.confidence.label, color: cluster.confidence.color)
                        ForEach(cluster.reasonLabels, id: \.self) { label in
                            let reason = cluster.matchReasons.first(where: { $0.label == label })
                            badge(label, color: reason?.color ?? .gray)
                        }
                    }
                }

                Spacer()

                Image(systemName: cluster.isSafeToBulkDelete ? "exclamationmark.triangle.fill" : "eye.circle.fill")
                    .foregroundStyle(cluster.isSafeToBulkDelete ? Color.appWarning : Color.secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Row Views

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeX, in cluster: DuplicateCluster, keep: RecipeX) -> some View {
        let isKeeper = recipe.id == keep.id
        let reviewOnly = !cluster.isSafeToBulkDelete
        let recipeIDPreview: String = recipe.id.map { String($0.uuidString.prefix(8)) } ?? "unknown"
        let ingredientNames = recipe.ingredientSections.flatMap { $0.ingredients }.map(\.name)
        let stepCount = recipe.instructionSections.reduce(0) { $0 + $1.steps.count }
        let inBook = recipe.id.map { cluster.bookRecipeIDs.contains($0) } ?? false

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if isKeeper {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("KEEP")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appSuccess)
                    } else {
                        Image(systemName: reviewOnly ? "questionmark.circle.fill" : "trash.circle.fill")
                            .foregroundStyle(reviewOnly ? Color.appWarning : Color.appCritical)
                        Text(reviewOnly ? "CHECK — SAME RECIPE?" : "EXTRA COPY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(reviewOnly ? Color.appWarning : Color.appCritical)
                    }
                }

                Text(recipe.title ?? "Untitled")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(ingredientNames.count) ingredients · \(stepCount) steps\(inBook ? " · in a book" : "")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !ingredientNames.isEmpty {
                    Text(ingredientNames.prefix(4).joined(separator: ", ") + (ingredientNames.count > 4 ? "…" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

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

            if !isKeeper {
                VStack(spacing: 8) {
                    Button {
                        if let rid = recipe.id {
                            keeperOverrides[cluster.stableKey] = rid
                        }
                        keepConfirmation = (cluster, recipe)
                    } label: {
                        Text("Keep This")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        selectedRecipe = recipe
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.appCritical)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Remove This Copy?", isPresented: .init(
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

    /// Extra copies that "Merge Exact Copies" would remove
    private var exactCopyCount: Int {
        clusters.filter(\.isSafeToBulkDelete).reduce(0) { $0 + $1.extraCount }
    }

    private var bookRecipeIDs: Set<UUID> {
        Set(allBooks.flatMap { $0.recipeIDs ?? [] })
    }

    // MARK: - Multi-Strategy Duplicate Detection

    private func findDuplicates() {
        isAnalyzing = true

        let recipes = allRecipes
        let resultClusters = Self.buildDuplicateClusters(from: recipes, bookRecipeIDs: bookRecipeIDs)

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
        print("   Groups: \(resultClusters.count) (exact-copy extras: \(exactCopyCount))")
        for cluster in resultClusters {
            print("   → \(cluster.title): \(cluster.copyCount) copies [\(cluster.confidence.label); \(cluster.reasonLabels.joined(separator: ", "))]")
        }
    }

    /// Creates a stable string key from two UUIDs for the reasons dictionary
    private static func pairKey(_ a: UUID, _ b: UUID) -> String {
        let sa = a.uuidString; let sb = b.uuidString
        return sa < sb ? "\(sa)|\(sb)" : "\(sb)|\(sa)"
    }

    // MARK: Thresholds (calibrated on the Oct 2026 Shahsultan book dedupe:
    // all 12 true duplicate pairs scored ≥ 0.60; same-name different recipes
    // scored ≤ 0.67, and ≥ 0.75 only for a genuine re-extraction)

    /// Same title + at least this ingredient match → "Likely Same Recipe"
    static let likelyIngredientMatch = 0.75
    /// Same title + at least this ingredient match → "Possible — Review"
    static let possibleIngredientMatch = 0.60
    /// Fewer ingredients than this can't be compared meaningfully (e.g. "1 lb butter")
    static let minimumIngredientsToCompare = 3

    /// Builds duplicate clusters from multiple strategies (fingerprint, URL, ingredient-checked title).
    /// - Parameters:
    ///   - includeTitleMatches: when false, only exact copies (same content
    ///     fingerprint or same http(s) link) are clustered. Automatic, unattended cleanup
    ///     must pass false: different recipes often share a title ("Dhokra", "Nan"),
    ///     so title-based groups need a human to decide.
    ///   - bookRecipeIDs: recipes that are in a book, preferred as the keeper.
    static func buildDuplicateClusters(
        from allRecipes: [RecipeX],
        includeTitleMatches: Bool = true,
        bookRecipeIDs: Set<UUID> = []
    ) -> [DuplicateCluster] {
        var uf = RecipeUnionFind()
        var reasons: [String: Set<DuplicateCluster.MatchReason>] = [:]
        var pairSimilarity: [String: Double] = [:]

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
                reasons[pairKey(ids[0], ids[i]), default: []].insert(.fingerprint)
            }
        }

        // --- Strategy 2: Same source URL (real http/https links only) ---
        // Extracted book pages store page numbers ("12", "Page 9") in `reference`;
        // URL(string: "12") is non-nil, so a scheme check is required.
        var byURL: [String: [UUID]] = [:]
        for recipe in allRecipes {
            guard let rid = recipe.id,
                  let ref = recipe.reference?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !ref.isEmpty,
                  let url = URL(string: ref),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else { continue }
            let normalizedURL = ref.lowercased()
                .replacingOccurrences(of: "http://", with: "https://")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            byURL[normalizedURL, default: []].append(rid)
        }
        for (_, ids) in byURL where ids.count > 1 {
            for i in 1..<ids.count {
                uf.union(ids[0], ids[i])
                reasons[pairKey(ids[0], ids[i]), default: []].insert(.sameSourceURL)
            }
        }

        // --- Strategy 3: Same title AND matching ingredients (manual review only) ---
        if includeTitleMatches {
            var byNormalizedTitle: [String: [RecipeX]] = [:]
            for recipe in allRecipes where recipe.id != nil {
                let normalized = normalizeTitle(recipe.title ?? "")
                guard !normalized.isEmpty else { continue }
                byNormalizedTitle[normalized, default: []].append(recipe)
            }
            for (_, group) in byNormalizedTitle where group.count > 1 {
                let lines = group.map { ingredientLines($0) }
                for i in 0..<group.count {
                    for j in (i + 1)..<group.count {
                        guard let a = group[i].id, let b = group[j].id else { continue }
                        let key = pairKey(a, b)
                        if reasons[key]?.isEmpty == false { continue } // already an exact copy
                        guard lines[i].count >= minimumIngredientsToCompare,
                              lines[j].count >= minimumIngredientsToCompare else { continue }
                        let sim = ingredientSimilarity(lines[i], lines[j])
                        let countGap = abs(lines[i].count - lines[j].count)
                        if sim >= likelyIngredientMatch && countGap <= 1 {
                            uf.union(a, b)
                            reasons[key, default: []].insert(.sameIngredients)
                            pairSimilarity[key] = sim
                        } else if sim >= possibleIngredientMatch {
                            uf.union(a, b)
                            reasons[key, default: []].insert(.similarTitle)
                            pairSimilarity[key] = sim
                        }
                        // Below the threshold: same name, different recipe — not a duplicate.
                    }
                }
            }
        }

        // --- Build clusters from Union-Find ---
        var groupsByRoot: [UUID: [UUID]] = [:]
        for rid in uf.allIDs {
            let root = uf.find(rid)
            groupsByRoot[root, default: []].append(rid)
        }

        var resultClusters: [DuplicateCluster] = []
        for (_, memberIDs) in groupsByRoot where memberIDs.count > 1 {
            let recipes = memberIDs.compactMap { recipeMap[$0] }
            guard recipes.count > 1 else { continue }

            var clusterReasons: Set<DuplicateCluster.MatchReason> = []
            var weakest: DuplicateCluster.Confidence = .exactCopy
            var lowestSimilarity: Double?
            for i in 0..<memberIDs.count {
                for j in (i + 1)..<memberIDs.count {
                    let key = pairKey(memberIDs[i], memberIDs[j])
                    guard let pairReasons = reasons[key], !pairReasons.isEmpty else { continue }
                    clusterReasons.formUnion(pairReasons)
                    let strongest = pairReasons.map(\.confidence).max() ?? .possible
                    weakest = min(weakest, strongest)
                    if let s = pairSimilarity[key] {
                        lowestSimilarity = min(lowestSimilarity ?? s, s)
                    }
                }
            }

            resultClusters.append(DuplicateCluster(
                recipes: recipes,
                matchReasons: clusterReasons,
                confidence: weakest,
                ingredientSimilarity: weakest == .exactCopy ? nil : lowestSimilarity,
                bookRecipeIDs: bookRecipeIDs
            ))
        }

        // Exact copies first, then likely, then possible; alphabetical within each
        resultClusters.sort {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return resultClusters
    }

    // MARK: Ingredient comparison

    private static let ingredientStopWords: Set<String> = [
        "cup", "cups", "tsp", "tbsp", "tablespoon", "tablespoons", "teaspoon", "teaspoons",
        "lb", "lbs", "oz", "ozs", "grams", "gram", "kg", "ml", "large", "small", "medium",
        "chopped", "ground", "fresh", "crushed", "pkt", "can", "little", "and", "the", "for",
        "mug", "mugs", "pinch", "dash", "level", "heaped"
    ]

    /// Each ingredient reduced to a set of name words (quantities ignored — OCR misreads them).
    static func ingredientLines(_ recipe: RecipeX) -> [Set<String>] {
        recipe.ingredientSections.flatMap { $0.ingredients }.map { ingredient in
            let letters = ingredient.name.lowercased().unicodeScalars.map {
                CharacterSet.letters.contains($0) ? Character($0) : " "
            }
            let words = String(letters).split(separator: " ").map(String.init)
            return Set(words.compactMap { word -> String? in
                guard word.count > 2, !ingredientStopWords.contains(word) else { return nil }
                return word.hasSuffix("s") ? String(word.dropLast()) : word
            })
        }.filter { !$0.isEmpty }
    }

    /// Fraction of ingredient lines that have a counterpart in the other recipe
    /// (name words at least half shared), relative to the longer list.
    static func ingredientSimilarity(_ a: [Set<String>], _ b: [Set<String>]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var used = Set<Int>()
        var matched = 0
        for lineA in a {
            for (j, lineB) in b.enumerated() where !used.contains(j) {
                let union = lineA.union(lineB).count
                guard union > 0 else { continue }
                if Double(lineA.intersection(lineB).count) / Double(union) >= 0.5 {
                    used.insert(j)
                    matched += 1
                    break
                }
            }
        }
        return Double(matched) / Double(max(a.count, b.count))
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

    /// Keeps the chosen copy and merges every other copy in its group into it
    private func keepOnly(_ keep: RecipeX, in cluster: DuplicateCluster) async {
        for other in cluster.recipes where other.id != keep.id {
            await mergeCopy(other, into: keep)
        }
        keeperOverrides[cluster.stableKey] = nil
        findDuplicates()
    }

    /// Merges every exact-copy group (content fingerprint or same http(s) link).
    /// Title- and ingredient-matched groups are left for manual review.
    private func mergeAllExactCopies() async {
        isMerging = true
        defer { isMerging = false }
        var merged = 0
        for cluster in clusters where cluster.isSafeToBulkDelete {
            let keep = keeper(for: cluster)
            for duplicate in cluster.recipes where duplicate.id != keep.id {
                await mergeCopy(duplicate, into: keep)
                merged += 1
            }
        }
        monitor.duplicatesDetected = 0
        findDuplicates()
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
