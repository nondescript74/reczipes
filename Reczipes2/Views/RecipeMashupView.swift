//
//  RecipeMashupView.swift
//  Reczipes2
//
//  Launched from RecipeDetailView's toolbar.
//  The user's saved recipe is pre-loaded as the first source.
//  Additional URLs can be added, extracted, and then sections
//  cherry-picked from each source to form a synthetic combined
//  recipe (display-only, never saved).
//
//  Closing and re-opening this view from the same recipe
//  restores the previous mashup state for the current session.
//

import SwiftUI
import SwiftData

struct RecipeMashupView: View {
    @ObservedObject private var viewModel: RecipeMashupViewModel
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \RecipeX.dateAdded, order: .reverse) private var allRecipes: [RecipeX]
    
    @State private var showAddSourcePanel = false
    @State private var addSourceURL: String = ""
    @State private var addSourceError: String? = nil
    
    /// Initialise with the recipe the user tapped on and the API key.
    /// The actual view-model comes from MashupSessionManager so that
    /// state survives dismissal.
    init(baseRecipe: RecipeX, apiKey: String) {
        // Pre-load the base recipe as the first source
        let vm = RecipeMashupViewModel(apiKey: apiKey)
        var baseSource = MashupSource(url: baseRecipe.reference ?? "", userDescription: baseRecipe.title ?? "(Untitled)")
        baseSource.extractedRecipe = baseRecipe  // Pre-load the recipe
        baseSource.isLocalRecipe = true  // It's a local recipe, no extraction needed
        vm.sources = [baseSource]
        self.viewModel = vm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    introSection

                    sourcesSection

                    addSourceButton

                    // Inline panel for adding a mashup source
                    if showAddSourcePanel {
                        VStack(spacing: 16) {
                            // Web URL section
                            VStack(spacing: 12) {
                                Text("Add by Web URL").font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                TextField("https://example.com/recipe", text: $addSourceURL)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .textContentType(.URL)
                                Button("Add by URL") {
                                    let url = addSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !url.isEmpty, url.hasPrefix("http") else {
                                        addSourceError = "Enter a valid URL starting with http"
                                        return
                                    }
                                    if viewModel.sources.contains(where: { $0.url == url }) {
                                        addSourceError = "This URL is already added."
                                        return
                                    }
                                    viewModel.sources.append(MashupSource(url: url))
                                    addSourceURL = ""
                                    addSourceError = nil
                                    showAddSourcePanel = false
                                }
                                .buttonStyle(.borderedProminent)
                                if let error = addSourceError {
                                    Text(error).foregroundColor(.red).font(.caption)
                                }
                            }
                            
                            Divider().padding(.vertical, 4)
                            
                            // My Recipes section
                            VStack(spacing: 12) {
                                Text("Pick from My Recipes").font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                let availableRecipes = allRecipes.filter { r in
                                    r.reference != nil && !viewModel.sources.contains(where: { $0.url == r.reference })
                                }
                                
                                if availableRecipes.isEmpty {
                                    Text("No recipes available or all added").foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(12)
                                        .background(Color.gray.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    VStack(spacing: 8) {
                                        ForEach(availableRecipes) { recipe in
                                            Button {
                                                // For local recipes, pre-load the recipe directly
                                                var source = MashupSource(url: recipe.reference ?? "", userDescription: recipe.title ?? "(Untitled)")
                                                source.extractedRecipe = recipe
                                                source.isLocalRecipe = true
                                                viewModel.sources.append(source)
                                                showAddSourcePanel = false
                                                addSourceError = nil
                                                addSourceURL = ""
                                            } label: {
                                                HStack(spacing: 12) {
                                                    // Thumbnail or icon
                                                    if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 48, height: 48)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    } else {
                                                        Image(systemName: "book.fill")
                                                            .font(.title3)
                                                            .foregroundStyle(.blue)
                                                            .frame(width: 48, height: 48)
                                                            .background(Color.blue.opacity(0.1))
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    }
                                                    
                                                    // Recipe info
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(recipe.title ?? "(Untitled)")
                                                            .font(.subheadline)
                                                            .fontWeight(.semibold)
                                                            .foregroundStyle(.primary)
                                                        
                                                        if let yield = recipe.recipeYield, !yield.isEmpty {
                                                            Text(yield)
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    Image(systemName: "plus.circle.fill")
                                                        .foregroundStyle(.blue)
                                                }
                                                .padding(12)
                                                .background(Color.blue.opacity(0.06))
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(radius: 3)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if viewModel.extractedSourceCount >= 2 {
                        sectionSelectionGuidance
                    }

                    if viewModel.canBuildSyntheticRecipe {
                        buildButton
                    }

                    if let error = viewModel.globalError {
                        errorBanner(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Recipe Mashup")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                if viewModel.sources.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await viewModel.extractAllSources() }
                        } label: {
                            if viewModel.isExtractingAll {
                                ProgressView()
                            } else {
                                Label("Extract All", systemImage: "arrow.down.circle.fill")
                            }
                        }
                        .disabled(viewModel.isExtractingAll)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSyntheticRecipe) {
                if let synthetic = viewModel.syntheticRecipe {
                    SyntheticRecipeView(recipe: synthetic)
                }
            }
        }
    }

    // MARK: - Intro

    private var introSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 44))
                .foregroundStyle(.purple)

            Text("Combine the Best Parts")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.purple.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(spacing: 16) {
            ForEach(Array(viewModel.sources.enumerated()), id: \.element.id) { index, source in
                MashupSourceCard(
                    source: source,
                    index: index,
                    viewModel: viewModel
                )
            }
        }
    }

    // MARK: - Add Source

    private var addSourceButton: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                showAddSourcePanel.toggle()
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Another Recipe URL")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple.opacity(0.12))
            .foregroundColor(.purple)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Guidance

    private var sectionSelectionGuidance: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.orange)
                Text("Select Sections")
                    .font(.headline)
            }

            Text("Tap the section buttons on each card to choose which parts you want. Each section can only come from one source.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if viewModel.totalSelectedSections > 0 {
                Text("\(viewModel.totalSelectedSections) section\(viewModel.totalSelectedSections == 1 ? "" : "s") selected")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Build

    private var buildButton: some View {
        Button {
            viewModel.buildSyntheticRecipe()
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("View Combined Recipe")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Mashup Source Card

struct MashupSourceCard: View {
    let source: MashupSource
    let index: Int
    @ObservedObject var viewModel: RecipeMashupViewModel

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if source.isExpanded {
                Divider()
                expandedContent
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            // Number badge
            Text(index == 0 ? "★" : "\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(statusColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.userDescription.isEmpty ? source.url : source.userDescription)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if index == 0 {
                    Text("Your recipe")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }

                if !source.selectedSections.isEmpty {
                    Text("\(source.selectedSections.count) section\(source.selectedSections.count == 1 ? "" : "s") selected")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
            }

            Spacer()

            // Status
            if source.isExtracting {
                ProgressView().scaleEffect(0.8)
            } else if source.extractedRecipe != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if source.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }

            // Expand / Collapse
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.toggleExpansion(for: source.id)
                }
            } label: {
                Image(systemName: source.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Delete (not for base)
            if index != 0 {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.3)) {
                        viewModel.removeSource(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        if index == 0               { return .blue }
        if source.extractedRecipe != nil { return .green }
        if source.errorMessage != nil    { return .red }
        if source.isExtracting           { return .blue }
        return .gray
    }

    // MARK: Expanded Content

    private var expandedContent: some View {
        VStack(spacing: 14) {
            // URL field (not for the base recipe)
            if index != 0 {
                HStack {
                    TextField("https://example.com/recipe", text: Binding<String>(
                        get: { viewModel.sources[index].url },
                        set: { viewModel.sources[index].url = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .disabled(source.isExtracting)

                    Button {
                        Task { await viewModel.extractSource(at: index) }
                    } label: {
                        if source.isExtracting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.down.circle.fill").font(.title3)
                        }
                    }
                    .disabled(source.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || source.isExtracting)
                    .buttonStyle(.plain)
                }
            }

            // Error
            if let error = source.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Preview
            if let recipe = source.extractedRecipe {
                extractedRecipePreview(recipe)
                sectionPicker
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: Preview

    private func extractedRecipePreview(_ recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if index != 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                    Text("Extracted Successfully")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            Text(recipe.safeTitle)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                Label("\(recipe.ingredientSections.flatMap(\.ingredients).count) ingredients",
                      systemImage: "list.bullet")
                .font(.caption2).foregroundStyle(.secondary)
                Label("\(recipe.instructionSections.flatMap(\.steps).count) steps",
                      systemImage: "list.number")
                .font(.caption2).foregroundStyle(.secondary)
                if !recipe.notes.isEmpty {
                    Label("\(recipe.notes.count) notes", systemImage: "note.text")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((index == 0 ? Color.blue : Color.green).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Section Picker

    private var sectionPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick sections to use:")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            FlowLayoutSRV(spacing: 8) {
                ForEach(RecipeSectionType.allCases) { section in
                    let isSelected      = viewModel.isSectionSelected(section, for: source.id)
                    let claimedByOther  = viewModel.isSectionClaimedByOther(section, excludingSourceID: source.id)
                    let hasContent      = sectionHasContent(section)

                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            viewModel.toggleSection(section, for: source.id)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: section.icon).font(.caption2)
                            Text(section.rawValue)
                                .font(.caption2)
                                .fontWeight(isSelected ? .semibold : .regular)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected     ? section.color.opacity(0.25) :
                            claimedByOther ? Color.gray.opacity(0.08) :
                                             Color.gray.opacity(0.12)
                        )
                        .foregroundStyle(
                            isSelected     ? section.color :
                            claimedByOther ? .gray.opacity(0.4) :
                            hasContent     ? .primary : .secondary
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? section.color : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasContent)
                    .opacity(hasContent ? 1.0 : 0.4)
                }
            }
            
            // Image selection
            imagePicker
        }
    }
    
    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipe image:")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            
            if let recipe = source.extractedRecipe {
                let hasMainImage = recipe.imageData != nil
                let additionalImages = recipe.additionalImagesData?.isEmpty == false
                
                if !hasMainImage && !additionalImages {
                    Text("No images available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        // Main image
                        if hasMainImage {
                            Button {
                                viewModel.selectImageSource(source.id, imageIndex: 0)
                            } label: {
                                HStack(spacing: 10) {
                                    if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "photo.fill")
                                            .font(.title3)
                                            .frame(width: 60, height: 60)
                                            .background(Color.gray.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Main Image")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                        Text("From \(recipe.safeTitle)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if viewModel.selectedImageSource == source.id && viewModel.selectedImageIndex == 0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .padding(10)
                                .background(viewModel.selectedImageSource == source.id && viewModel.selectedImageIndex == 0 ? Color.green.opacity(0.08) : Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Additional images
                        if additionalImages, let additionalData = recipe.additionalImagesData,
                           let decodedImages = try? JSONDecoder().decode([[String: Data]].self, from: additionalData) {
                            ForEach(Array(decodedImages.enumerated()), id: \.offset) { idx, imageDict in
                                if let imageData = imageDict["data"], let uiImage = UIImage(data: imageData) {
                                    Button {
                                        viewModel.selectImageSource(source.id, imageIndex: idx + 1)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 60, height: 60)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Image \(idx + 2)")
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                Text("From \(recipe.safeTitle)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if viewModel.selectedImageSource == source.id && viewModel.selectedImageIndex == idx + 1 {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        .padding(10)
                                        .background(viewModel.selectedImageSource == source.id && viewModel.selectedImageIndex == idx + 1 ? Color.green.opacity(0.08) : Color.gray.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHasContent(_ section: RecipeSectionType) -> Bool {
        guard let recipe = source.extractedRecipe else { return false }
        switch section {
        case .title:
            return !(recipe.safeTitle.isEmpty)
        case .headerNotes:
            return (recipe.headerNotes?.isEmpty == false)
        case .ingredients:
            return !recipe.ingredientSections.flatMap { $0.ingredients }.isEmpty
        case .instructions:
            return !recipe.instructionSections.flatMap { $0.steps }.isEmpty
        case .notes:
            return !recipe.notes.isEmpty
        case .yield:
            return (recipe.yield?.isEmpty == false)
        case .reference:
            return (recipe.reference?.isEmpty == false)
        }
    }
}

// MARK: - Synthetic Recipe View

struct SyntheticRecipeView: View {
    let recipe: SyntheticRecipe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sessionBanner
                    
                    // Display selected image if available
                    if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 4)
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text(recipe.title)
                            .font(.title).fontWeight(.bold)
                        if let src = recipe.sectionSources[.title] { sourceAttribution(src) }
                    }

                    // Header Notes
                    if let hn = recipe.headerNotes, !hn.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("Description", icon: "text.quote", color: .indigo)
                            Text(hn).font(.body).foregroundStyle(.secondary)
                            if let src = recipe.sectionSources[.headerNotes] { sourceAttribution(src) }
                        }
                    }

                    // Yield
                    if let y = recipe.yield, !y.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("Yield / Servings", icon: "person.2", color: .teal)
                            Text(y).font(.body)
                            if let src = recipe.sectionSources[.yield] { sourceAttribution(src) }
                        }
                    }

                    // Ingredients
                    if !recipe.ingredientSections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Ingredients", icon: "list.bullet", color: .green)

                            ForEach(recipe.ingredientSections) { section in
                                if let t = section.title, !t.isEmpty {
                                    Text(t).font(.subheadline).fontWeight(.semibold).padding(.top, 4)
                                }
                                ForEach(section.ingredients) { ing in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•").foregroundStyle(.green)
                                        HStack(spacing: 4) {
                                            if let q = ing.quantity { Text(q).fontWeight(.medium) }
                                            if let u = ing.unit    { Text(u) }
                                            Text(ing.name)
                                            if let p = ing.preparation { Text("(\(p))").foregroundStyle(.secondary) }
                                        }.font(.body)
                                    }
                                }
                                if let tn = section.transitionNote {
                                    Text(tn).font(.caption).italic().foregroundStyle(.secondary)
                                }
                            }
                            if let src = recipe.sectionSources[.ingredients] { sourceAttribution(src) }
                        }
                    }

                    // Instructions
                    if !recipe.instructionSections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Instructions", icon: "list.number", color: .orange)

                            ForEach(recipe.instructionSections) { section in
                                if let t = section.title, !t.isEmpty {
                                    Text(t).font(.subheadline).fontWeight(.semibold).padding(.top, 4)
                                }
                                ForEach(section.steps) { step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(step.stepNumber)")
                                            .font(.caption).fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .frame(width: 24, height: 24)
                                            .background(Circle().fill(.orange))
                                        Text(step.text).font(.body)
                                    }.padding(.vertical, 2)
                                }
                            }
                            if let src = recipe.sectionSources[.instructions] { sourceAttribution(src) }
                        }
                    }

                    // Notes
                    if !recipe.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("Notes", icon: "note.text", color: .purple)

                            ForEach(recipe.notes) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: note.type.icon)
                                        .foregroundStyle(note.type.color)
                                        .font(.caption).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(note.type.displayName)
                                            .font(.caption2).fontWeight(.semibold)
                                            .foregroundStyle(note.type.color)
                                        Text(note.text).font(.body)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(note.type.color.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            if let src = recipe.sectionSources[.notes] { sourceAttribution(src) }
                        }
                    }

                    // Reference
                    if let ref = recipe.reference, !ref.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionHeader("Source / Reference", icon: "link", color: .gray)
                            referenceContent(ref)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Combined Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Components

    private var sessionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            Text("This combined recipe is temporary and will not be saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.headline)
        }
    }

    private func sourceAttribution(_ source: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.turn.down.right").font(.caption2)
            Text("from \(source)").font(.caption2).italic()
        }
        .foregroundStyle(.tertiary)
    }
    
    /// Extracts URLs from reference text and displays them as clickable links
    private func referenceContent(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let urls = extractURLs(from: text)
            
            if urls.isEmpty {
                // No URLs found, display as plain text
                Text(text).font(.caption).foregroundStyle(.secondary)
            } else {
                // Display extracted URLs as clickable links
                ForEach(Array(urls.enumerated()), id: \.offset) { _, urlString in
                    if let url = URL(string: urlString) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Link(destination: url) {
                                    Text(urlString)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                }
                                
                                Text("Tap to open in Safari")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                // Display non-URL text if any
                let nonURLText = removeURLs(from: text)
                if !nonURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(nonURLText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    /// Extracts all URLs from a text string
    private func extractURLs(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, range: range) ?? []
        
        return matches.compactMap { match in
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
            return nil
        }
    }
    
    /// Removes all URLs from a text string
    private func removeURLs(from text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, range: range) ?? []
        
        var result = text
        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                result.removeSubrange(range)
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Flow Layout

struct FlowLayoutSRV: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (i, pos) in result.positions.enumerated() {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxW = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0

        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 {
                x = 0; y += lineH + spacing; lineH = 0
            }
            positions.append(CGPoint(x: x, y: y))
            lineH = max(lineH, s.height)
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + lineH), positions)
    }
}

// MARK: - Preview

#Preview {
    let preview = RecipeX(
        id: UUID(),
        title: "Preview Recipe",
        headerNotes: "A test recipe",
        recipeYield: "Serves 4",
        reference: nil,
        ingredientSectionsData: try? JSONEncoder().encode([
            IngredientSection(ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "flour")
            ])
        ]),
        instructionSectionsData: try? JSONEncoder().encode([
            InstructionSection(steps: [
                InstructionStep(stepNumber: 1, text: "Mix together.")
            ])
        ]),
        notesData: nil,
        imageData: nil,
        additionalImagesData: nil,
        imageName: nil,
        additionalImageNames: nil,
        dateAdded: Date(),
        dateCreated: Date(),
        lastModified: Date(),
        version: 1
    )
    RecipeMashupView(baseRecipe: preview, apiKey: "test-key")
}

