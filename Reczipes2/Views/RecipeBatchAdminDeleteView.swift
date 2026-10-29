//
//  RecipeBatchAdminDeleteView.swift
//  Reczipes2
//
//  Created on 10/18/26.
//
//  Admin tool to discard a failed batch extraction: every recipe added on one
//  day, before a chosen time, is listed; the user unticks any to keep, then types
//  "DELETE <count>". Book members are removed from their books first (the only
//  other path that can do that is BookRecipeAdminDeleteView, one recipe at a time).
//  Reached from Settings → Sharing → Manage CloudKit Recipes.
//

import SwiftUI
import SwiftData

struct RecipeBatchAdminDeleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeX.dateAdded) private var allRecipes: [RecipeX]
    @Query private var books: [Book]

    @State private var day = Date()
    @State private var before = Date()
    @State private var useBefore = false
    @State private var excluded: Set<UUID> = []
    @State private var showingConfirm = false
    @State private var resultMessage: String?

    private var bookGuard: BookMembershipGuard { BookMembershipGuard(books: books) }

    private var candidates: [RecipeX] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        var cutoff = dayEnd
        if useBefore {
            let c = cal.dateComponents([.hour, .minute], from: before)
            cutoff = cal.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: dayStart) ?? dayEnd
        }
        return allRecipes.filter { r in
            guard let added = r.dateAdded else { return false }
            return added >= dayStart && added < cutoff
        }
    }

    private var selected: [RecipeX] {
        candidates.filter { r in
            guard let id = r.id else { return false }
            return !excluded.contains(id)
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        List {
            Section {
                Text("Lists every recipe added on one day (optionally before a time). Untick any you want to keep. Recipes in books are removed from their books first, then everything ticked is permanently deleted. Use this only to discard a bad batch extraction.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Added on") {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                Toggle("Only recipes added before a time", isOn: $useBefore)
                if useBefore {
                    DatePicker("Before", selection: $before, displayedComponents: .hourAndMinute)
                }
            }
            Section {
                ForEach(candidates) { recipe in
                    let id = recipe.id ?? UUID()
                    Toggle(isOn: Binding(
                        get: { !excluded.contains(id) },
                        set: { on in if on { excluded.remove(id) } else { excluded.insert(id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title ?? "Untitled")
                            HStack(spacing: 6) {
                                if let d = recipe.dateAdded { Text(Self.time.string(from: d)) }
                                let names = bookGuard.bookNames(for: recipe.id)
                                if !names.isEmpty { Text("· " + names.joined(separator: ", ")) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Recipes (\(selected.count) of \(candidates.count) ticked)")
                    Spacer()
                    Button("All") { excluded.removeAll() }.font(.caption)
                    Button("None") { excluded = Set(candidates.compactMap(\.id)) }.font(.caption)
                }
            }
            Section {
                Button(role: .destructive) {
                    showingConfirm = true
                } label: {
                    Label("Delete \(selected.count) Recipe\(selected.count == 1 ? "" : "s")…", systemImage: "trash")
                }
                .disabled(selected.isEmpty)
            }
        }
        .navigationTitle("Delete Recipes Added on a Day")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfirm) {
            RecipeBatchAdminConfirmSheet(
                count: selected.count,
                bookNames: Array(Set(selected.flatMap { bookGuard.bookNames(for: $0.id) })).sorted(),
                onConfirm: { typed in Task { await forceDelete(selected, typed: typed) } }
            )
            .macOSSheetFrame()
        }
        .alert("Delete Recipes", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func forceDelete(_ recipes: [RecipeX], typed: String) async {
        let count = recipes.count
        // Δ-163: public copies are marked deleted (never removed), after the delete succeeds.
        let deletedIDs = recipes.compactMap(\.id)
        do {
            let ids = Set(recipes.compactMap(\.id))
            let assignments = (try? modelContext.fetch(FetchDescriptor<RecipeImageAssignment>())) ?? []
            for assignment in assignments where ids.contains(assignment.recipeID) {
                modelContext.delete(assignment)
            }
            let removedFrom = try BookMembershipGuard.forceDeleteBatch(recipes, typedConfirmation: typed, in: modelContext)
            try modelContext.save()
            for id in deletedIDs {
                CloudKitSharingService.shared.ownerDeleted(.recipe, id: id, modelContext: modelContext)
            }
            excluded.removeAll()
            resultMessage = removedFrom.isEmpty
                ? "Deleted \(count) recipes."
                : "Deleted \(count) recipes. Removed from \(BookMembershipGuard.listPhrase(removedFrom)) first."
        } catch {
            modelContext.rollback()
            resultMessage = "Not deleted: \(error.localizedDescription)"
        }
    }
}

private struct RecipeBatchAdminConfirmSheet: View {
    let count: Int
    let bookNames: [String]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var expected: String { "DELETE \(count)" }
    private var matches: Bool { typed.trimmingCharacters(in: .whitespacesAndNewlines) == expected }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipes") {
                    Text("\(count) recipe\(count == 1 ? "" : "s") will be permanently deleted from all your devices.")
                }
                if !bookNames.isEmpty {
                    Section("They will first be removed from") {
                        ForEach(bookNames, id: \.self) { Label($0, systemImage: "book.closed") }
                    }
                }
                Section {
                    TextField("Type \(expected)", text: $typed)
                        .platformTextInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Confirm")
                } footer: {
                    Text("Type \"\(expected)\" exactly.")
                }
                Section {
                    Button(role: .destructive) {
                        onConfirm(typed)
                        dismiss()
                    } label: {
                        Label("Remove from Books and Delete", systemImage: "trash")
                    }
                    .disabled(!matches)
                }
            }
            .navigationTitle("Delete Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
