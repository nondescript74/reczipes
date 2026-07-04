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
    @StateObject private var monitor = CloudKitDuplicateMonitor.shared

    @State private var clusters: [DuplicateCluster] = []
    @State private var isAnalyzing = false
    @State private var showingConfirmation = false
    @State private var selectedRecipe: RecipeX?

    var body: some View {
        List {
            statisticsSection
            actionsSection
            duplicateGroupsSection
        }
        .navigationTitle("Duplicate Detector")
        .platformNavigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete All Duplicates?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(totalDuplicateCount) Duplicates", role: .destructive) {
                deleteAllDuplicates()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete \(totalDuplicateCount) duplicate recipes, keeping the best copy of each. This action cannot be undone.")
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
                Text("Keeps the most complete copy of each recipe (preferring the oldest when tied).")
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
                Image(systemName: "trash")
                Text("Delete All Duplicates")
                Text("(\(totalDuplicateCount))")
                    .foregroundStyle(.secondary)
            }
        }
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
                recipeRow(recipe, isCanonical: recipe.id == cluster.canonical.id)
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
    private func recipeRow(_ recipe: RecipeX, isCanonical: Bool) -> some View {
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
                        Image(systemName: "trash.circle.fill")
                            .foregroundStyle(Color.appCritical)
                        Text("DELETE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appCritical)
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
            Button("Delete", role: .destructive) {
                deleteRecipe(recipe)
            }
            Button("Cancel", role: .cancel) {
                selectedRecipe = nil
            }
        } message: {
            Text("This will permanently delete this copy of '\(recipe.title ?? "Unknown Recipe")'")
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

    static func buildDuplicateClusters(from allRecipes: [RecipeX]) -> [DuplicateCluster] {
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
                  URL(string: ref) != nil else { continue }
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

        // --- Strategy 3: Fuzzy title match ---
        var byNormalizedTitle: [String: [UUID]] = [:]
        for recipe in allRecipes {
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

    private func deleteRecipe(_ recipe: RecipeX) {
        modelContext.delete(recipe)

        do {
            try modelContext.save()
            print("✅ Deleted recipe: \(String(describing: recipe.title)) (ID: \(String(describing: recipe.id)))")
            findDuplicates()
        } catch {
            print("❌ Failed to delete recipe: \(error)")
        }
    }

    private func deleteAllDuplicates() {
        print("🧹 Starting bulk duplicate deletion...")

        var deletedCount = 0

        for cluster in clusters {
            let toDelete = cluster.duplicatesToDelete
            print("   Keeping: \(String(describing: cluster.canonical.title)) (ID: \(String(describing: cluster.canonical.id)))")
            for duplicate in toDelete {
                print("   🗑️ Deleting: \(String(describing: duplicate.title)) (ID: \(String(describing: duplicate.id)))")
                modelContext.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            do {
                try modelContext.save()
                print("✅ Successfully deleted \(deletedCount) duplicate recipes")
                clusters.removeAll()
                monitor.duplicatesDetected = 0
                // Record clean state so auto-scans skip until count changes
                DuplicateScanTracker.recordCleanScan(recipeCount: allRecipes.count - deletedCount)
            } catch {
                print("❌ Failed to save after deletion: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DuplicateRecipeDetectorView()
            .modelContainer(for: RecipeX.self, inMemory: true)
    }
}
