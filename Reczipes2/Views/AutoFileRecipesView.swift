//
//  AutoFileRecipesView.swift
//  Reczipes2
//
//  Files recipes that are in no book. A recipe whose source URL belongs to a site with
//  its own book goes there; everything else is filed by meal / food type from its title
//  (soups -> Soups, breakfast -> Breakfast, ...). Missing type books are created on Apply.
//  Nothing changes until the user reviews the preview and taps Apply; every proposal can
//  be unticked. Recipes are only ever added to books — nothing is removed or deleted.
//
//  Lane 37, 2026-10-15. Rules were tuned against the live public catalogue (131 unfiled
//  recipes: 130 classified, 1 left unfiled).
//

import SwiftUI
import SwiftData

/// Pure classification rules, kept free of SwiftUI so they can be reasoned about and tested.
enum RecipeAutoFiler {

    /// Source-URL rules: a site with a book of its own.
    static let urlRules: [(pattern: String, book: String)] = [
        ("seriouseats\\.com", "Kenji and SeriousEats"),
        ("indianhealthyrecipes\\.com", "Swasthi and others"),
    ]

    /// Title rules by meal / food type. Order matters: the first match wins
    /// (e.g. "Satay with Peanut Sauce" is an appetizer, "Tomato Pie" is dinner).
    static let titleRules: [(book: String, pattern: String)] = [
        ("Dinner", #"\b(tomato pie|pot ?pie)\b"#),
        ("Soups", #"\b(soup|stew|pho|chowder|bisque|chili|bowl of red|dumplings)\b"#),
        ("Appetizers", #"\b(satay|samosas?|pakoras?|kachori|hummus|nuggets|chips|tortilla stack|pinwheel|cutlets?|hondwo|snacks?|appetizers?)\b"#),
        ("Sauces, Chutneys & Spices", #"\b(chutney|pickle|aioli|sauce|salsa|raita|dip|seasoning|garam masala|spice mix|dressing|relish|kraut|horseradish)\b"#),
        ("Breakfast", #"\b(pancakes?|waffles?|muffins?|scones?|granola|parfaits?|french toast|frittata|omelet+e?|eggs and|bacon|breakfast|danish|yogh?urt)\b"#),
        ("Desserts & Sweets", #"\b(cakes?|cookies?|fudge|brownies?|bars|pudding|ice cream|popsicles?|crisp|cheesecake|toffee|macaroons?|snickerdoodles?|ginger ?snaps|nankhatai|shahi tukda|paskha|pies?|tarts?|candy|walnuts|mandazi|snickets|don'?t buts|icebox)\b"#),
        ("Breads", #"\b(bread|paratha|puri|naan|roti|biscuits?|rolls|corn ?bread|sourdough|hardtack|flatbread|mani|wrappers?)\b"#),
        ("Dinner", #"\b(chicken|beef|steak|lamb|pork|fish|cod|shrimp|curry|biryani|meat ?loaf|meatballs|manicotti|lasagna|pasta|massaman|mishkaki|short ribs|tofu|feta|paneer)\b"#),
        ("Sides & Salads", #"\b(salad|potatoes|gratin|beans|beanery|rice|kachumber|cauliflower steaks?|saak|aloo|palak|dal)\b"#),
    ]

    /// Colors for books this tool creates (hex, as BookEditorView stores them).
    static let newBookColors: [String: String] = [
        "Breakfast": "#F5A623", "Dinner": "#D0021B", "Desserts & Sweets": "#BD10E0",
        "Breads": "#8B572A", "Sides & Salads": "#7ED321", "Sauces, Chutneys & Spices": "#F8E71C",
        "Soups": "#4A90E2", "Appetizers": "#50E3C2",
    ]

    static func bookName(title: String?, reference: String?) -> String? {
        if let ref = reference {
            for rule in urlRules where ref.range(of: rule.pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return rule.book
            }
        }
        guard let title = title?.lowercased(), !title.isEmpty else { return nil }
        for rule in titleRules where title.range(of: rule.pattern, options: .regularExpression) != nil {
            return rule.book
        }
        return nil
    }
}

struct AutoFileRecipesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecipes: [RecipeX]
    @Query private var allBooks: [Book]

    /// Recipe ids the user unticked in the preview.
    @State private var excluded: Set<UUID> = []
    @State private var resultMessage: String?

    private var ownBooks: [Book] { allBooks.filter { $0.isImported != true } }

    /// Recipes in no book, one per exact-copy group (same contentFingerprint), and not an
    /// exact copy of a recipe that is already filed.
    private var unfiledRecipes: [RecipeX] {
        let filedIDs = Set(allBooks.flatMap { $0.recipeIDs ?? [] })
        let filedPrints = Set(allRecipes.filter { filedIDs.contains($0.id ?? UUID()) }.compactMap { $0.contentFingerprint })
        var seenPrints = Set<String>()
        return allRecipes
            .filter { recipe in
                guard let id = recipe.id, !filedIDs.contains(id) else { return false }
                if let fp = recipe.contentFingerprint {
                    if filedPrints.contains(fp) { return false }
                    return seenPrints.insert(fp).inserted
                }
                return true
            }
            .sorted { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
    }

    private struct Plan {
        var groups: [(book: String, recipes: [RecipeX])]
        var unmatched: [RecipeX]
    }

    private var plan: Plan {
        var byBook: [String: [RecipeX]] = [:]
        var unmatched: [RecipeX] = []
        for recipe in unfiledRecipes {
            if let name = RecipeAutoFiler.bookName(title: recipe.title, reference: recipe.reference) {
                byBook[name, default: []].append(recipe)
            } else {
                unmatched.append(recipe)
            }
        }
        let groups = byBook.keys.sorted().map { ($0, byBook[$0]!) }
        return Plan(groups: groups, unmatched: unmatched)
    }

    private func existingBook(named name: String) -> Book? {
        // Two books can share a name (e.g. two "Soups"); file into the fuller one.
        ownBooks
            .filter { ($0.name ?? "").caseInsensitiveCompare(name) == .orderedSame }
            .max { ($0.recipeIDs?.count ?? 0) < ($1.recipeIDs?.count ?? 0) }
    }

    private var selectedCount: Int {
        plan.groups.reduce(0) { $0 + $1.recipes.filter { !excluded.contains($0.id ?? UUID()) }.count }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(unfiledRecipes.count) recipes aren't in any book. Untick anything you don't want filed, then tap Apply. Recipes are only added to books — nothing is removed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(plan.groups, id: \.book) { group in
                    Section {
                        ForEach(group.recipes) { recipe in
                            Toggle(isOn: Binding(
                                get: { !excluded.contains(recipe.id ?? UUID()) },
                                set: { on in
                                    guard let id = recipe.id else { return }
                                    if on { excluded.remove(id) } else { excluded.insert(id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title ?? "Untitled")
                                    if let ref = recipe.reference, ref.hasPrefix("http") {
                                        Text(ref).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(group.book) (\(group.recipes.count))\(existingBook(named: group.book) == nil ? " — new book" : "")")
                    }
                }

                if !plan.unmatched.isEmpty {
                    Section {
                        ForEach(plan.unmatched) { recipe in
                            Text(recipe.title ?? "Untitled").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Can't tell — left unfiled (\(plan.unmatched.count))")
                    } footer: {
                        Text("Add these by hand from a book's Manage Recipes.")
                    }
                }
            }
            .navigationTitle("Auto-File Recipes")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply (\(selectedCount))") { apply() }
                        .disabled(selectedCount == 0)
                }
            }
            .alert("Auto-File", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )) {
                Button("OK") { resultMessage = nil; dismiss() }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func apply() {
        var filed = 0
        var created: [String] = []
        for group in plan.groups {
            let recipes = group.recipes.filter { !excluded.contains($0.id ?? UUID()) }
            guard !recipes.isEmpty else { continue }
            let book: Book
            if let existing = existingBook(named: group.book) {
                book = existing
            } else {
                book = Book(
                    name: group.book,
                    bookDescription: "Filed automatically by meal and food type",
                    color: RecipeAutoFiler.newBookColors[group.book],
                    recipeIDs: [],
                    dateCreated: Date(),
                    dateModified: Date(),
                    version: 1,
                    needsCloudSync: false,
                    isShared: false
                )
                book.recipeIDsHash = Book.calculateRecipeIDsHash(from: [])
                modelContext.insert(book)
                created.append(group.book)
            }
            for recipe in recipes {
                if let id = recipe.id {
                    book.addRecipe(id)
                    filed += 1
                }
            }
        }
        do {
            try modelContext.save()
            AppLog.info("Auto-filed \(filed) recipes; created books: \(created.joined(separator: ", "))", category: .recipe)
            resultMessage = "Filed \(filed) recipes." + (created.isEmpty ? "" : " New books: \(created.joined(separator: ", ")).")
        } catch {
            AppLog.error("Auto-file failed to save: \(error)", category: .recipe)
            resultMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
