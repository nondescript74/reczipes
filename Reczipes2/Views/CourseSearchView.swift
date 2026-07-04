//
//  CourseSearchView.swift
//  Reczipes2
//
//  Sheet shown when the user taps the magnifying glass on an
//  unlinked meal course. First scans the user's recipe library for
//  matches by title; if any exist they're offered first, so the
//  user can link a known recipe without leaving the app. A "Search
//  the Web" action then falls through to Google for cases where no
//  match exists or the user wants additional ideas.
//

import SwiftUI

struct CourseSearchView: View {
    @Environment(\.dismiss) private var dismiss

    /// Course name driving the search (matched against recipe titles
    /// and used as the Google query).
    let courseName: String

    /// Library to search.
    let recipes: [RecipeX]

    /// Called when the user picks a recipe from the suggestion list.
    /// Parent handles linking / navigation.
    let onRecipeSelected: (RecipeX) -> Void

    @State private var searchURL: URL?
    @State private var showSafari = false
    @State private var pasteURL: String = ""

    private var trimmedQuery: String {
        courseName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Recipes whose titles overlap the course name (case-insensitive,
    /// either direction so short queries like "Pizza" match "Pizza
    /// Margherita" and vice versa).
    private var matchingRecipes: [RecipeX] {
        let query = trimmedQuery.lowercased()
        guard !query.isEmpty else { return [] }
        return recipes.filter { recipe in
            guard let title = recipe.title?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  !title.isEmpty else {
                return false
            }
            return title.contains(query) || query.contains(title)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !matchingRecipes.isEmpty {
                    matchingRecipesSection
                } else {
                    emptyMatchSection
                }
                webSearchSection
                sendToExtractSection
            }
            .navigationTitle(trimmedQuery.isEmpty ? "Find a Recipe" : "Find: \(trimmedQuery)")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showSafari) {
                if let url = searchURL {
                    SafariView(url: url, entersReaderIfAvailable: false)
                        .ignoresSafeArea()
                }
            }
        }
    }

    // MARK: - Sections

    private var matchingRecipesSection: some View {
        Section {
            ForEach(matchingRecipes) { recipe in
                Button {
                    onRecipeSelected(recipe)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(Color.appSuccess)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title ?? "Untitled Recipe")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text("Tap to link this recipe to the course")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("From your library (\(matchingRecipes.count))")
        } footer: {
            Text("These recipes match \"\(trimmedQuery)\". Tap one to link it, or search the web below for more ideas.")
        }
    }

    private var emptyMatchSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No matching recipes")
                        .font(.body)
                    Text("Nothing in your library matches \"\(trimmedQuery)\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var webSearchSection: some View {
        Section {
            Button {
                openWebSearch()
            } label: {
                Label(
                    matchingRecipes.isEmpty ? "Search the Web" : "Search the Web Instead",
                    systemImage: "magnifyingglass"
                )
            }
            .disabled(trimmedQuery.isEmpty)
        } footer: {
            Text("Opens a Google search for \"\(trimmedQuery) recipe\". Long-press a link in Safari to copy the URL, then come back here and paste it below to extract the recipe.")
        }
    }

    private var sendToExtractSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("https://example.com/recipe", text: $pasteURL)
                    .textFieldStyle(.plain)
                    .platformTextInputAutocapitalization(.never)
                    .platformKeyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.go)
                    .onSubmit { sendToExtract() }
                if !pasteURL.isEmpty {
                    Button {
                        pasteURL = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if let pasted = PlatformPasteboard.string {
                        pasteURL = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                sendToExtract()
            } label: {
                Label("Send to Extract Tab", systemImage: "arrow.up.right.square")
            }
            .disabled(!isValidExtractURL(pasteURL))
        } header: {
            Text("Send a URL to Extract")
        } footer: {
            Text("Paste a recipe URL above, then tap Send to open it in the Extract tab. The Extract tab will pre-fill the URL ready for one-tap extraction.")
        }
    }

    // MARK: - Actions

    private func openWebSearch() {
        guard !trimmedQuery.isEmpty,
              let encoded = "\(trimmedQuery) recipe".addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return
        }
        searchURL = url
        showSafari = true
    }

    private func sendToExtract() {
        let trimmed = pasteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidExtractURL(trimmed) else { return }
        AppStateManager.shared.pendingExtractURL = trimmed
        AppStateManager.shared.currentTab = .extract
        dismiss()
    }

    private func isValidExtractURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }
}

#Preview {
    CourseSearchView(
        courseName: "Kung Pao Chicken",
        recipes: []
    ) { _ in }
}
