//
//  BookRecipeAdminDeleteView.swift
//  Reczipes2
//
//  Created on 10/17/26.
//
//  The ONLY place in the app that can delete a recipe that belongs to a book.
//  Reached from Settings → Sharing → Manage CloudKit Recipes → "Delete a Book
//  Recipe (Admin)…", deliberately kept out of everyday UI.
//
//  Flow: pick a book recipe → see every book that contains it → type the
//  recipe's title exactly → the recipe is removed from those books, its public
//  CloudKit copy (if any) is taken down, and only then is it deleted.
//

import SwiftUI
import SwiftData

struct BookRecipeAdminDeleteView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecipeX.title) private var allRecipes: [RecipeX]
    @Query private var books: [Book]

    @State private var searchText = ""
    @State private var pendingRecipe: RecipeX?
    @State private var resultMessage: String?

    private var bookGuard: BookMembershipGuard { BookMembershipGuard(books: books) }

    /// Recipes that are in at least one book
    private var bookRecipes: [RecipeX] {
        let protectedIDs = bookGuard.protectedRecipeIDs
        return allRecipes.filter { r in
            guard let id = r.id, protectedIDs.contains(id) else { return false }
            return searchText.isEmpty || (r.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Text("Recipes that belong to a book are never deleted anywhere else in the app. Use this only when you are sure. You will have to type the recipe's title to confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Recipes in Books (\(bookRecipes.count))") {
                ForEach(bookRecipes) { recipe in
                    Button {
                        pendingRecipe = recipe
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title ?? "Untitled")
                                .foregroundStyle(.primary)
                            Text(bookGuard.bookNames(for: recipe.id).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search book recipes")
        .navigationTitle("Delete Book Recipe")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingRecipe) { recipe in
            BookRecipeAdminConfirmSheet(
                recipe: recipe,
                bookNames: bookGuard.bookNames(for: recipe.id),
                onConfirm: { typed in
                    Task { await forceDelete(recipe, typed: typed) }
                }
            )
            .macOSSheetFrame()
        }
        .alert("Delete Book Recipe", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK") { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private func forceDelete(_ recipe: RecipeX, typed: String) async {
        let title = recipe.title ?? "Untitled"
        let rid = recipe.id

        // Take down the public CloudKit copy first (best effort)
        if let rid,
           let tracked = try? modelContext.fetch(FetchDescriptor<SharedRecipe>()).first(where: { $0.recipeID == rid && $0.isActive }),
           let cloudRecordID = tracked.cloudRecordID {
            do {
                try await CloudKitSharingService.shared.unshareRecipe(cloudRecordID: cloudRecordID, modelContext: modelContext)
            } catch {
                AppLog.warning("Admin delete: could not take down public copy of '\(title)': \(error)", category: .sharing)
            }
        }

        do {
            if let rid {
                let assignments = (try? modelContext.fetch(FetchDescriptor<RecipeImageAssignment>())) ?? []
                for assignment in assignments where assignment.recipeID == rid {
                    modelContext.delete(assignment)
                }
            }
            let removedFrom = try BookMembershipGuard.forceDeleteBookMember(recipe, typedConfirmation: typed, in: modelContext)
            try modelContext.save()
            pendingRecipe = nil
            resultMessage = "Deleted '\(title)'. It was removed from \(BookMembershipGuard.listPhrase(removedFrom))."
        } catch {
            modelContext.rollback()
            pendingRecipe = nil
            resultMessage = "Not deleted: \(error.localizedDescription)"
        }
    }
}

/// Shows the books that contain the recipe and requires the title to be typed.
private struct BookRecipeAdminConfirmSheet: View {
    let recipe: RecipeX
    let bookNames: [String]
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var expected: String {
        (recipe.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matches: Bool {
        !expected.isEmpty && typed.trimmingCharacters(in: .whitespacesAndNewlines) == expected
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    Text(expected.isEmpty ? "Untitled" : expected)
                        .font(.headline)
                }
                Section("It is in these books") {
                    ForEach(bookNames, id: \.self) { name in
                        Label(name, systemImage: "book.closed")
                    }
                }
                Section {
                    TextField("Type the recipe title", text: $typed)
                        .platformTextInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Confirm")
                } footer: {
                    Text("Type \"\(expected)\" exactly. The recipe will be removed from every book above and permanently deleted from all your devices.")
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
            .navigationTitle("Delete Book Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
