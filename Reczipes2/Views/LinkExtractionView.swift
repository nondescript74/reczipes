//
//  LinkExtractionView.swift
//  Reczipes2
//
//  Created for extracting recipes from saved links
//

import SwiftUI
import SwiftData

struct LinkExtractionView: View {
    let link: SavedLink
    let apiKey: String
    let onExtractionComplete: (Bool, String?) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel: RecipeExtractorViewModel
    @State private var showingSaveConfirmation = false
    @State private var selectedWebImageURLs: [String] = []
    @State private var downloadedWebImages: [UIImage] = []
    @State private var isDownloadingImage = false
    @State private var showWebImagePicker = false
    
    private let imageDownloader = WebImageDownloader()
    
    init(link: SavedLink, apiKey: String, onExtractionComplete: @escaping (Bool, String?) -> Void) {
        self.link = link
        self.apiKey = apiKey
        self.onExtractionComplete = onExtractionComplete
        _viewModel = StateObject(wrappedValue: RecipeExtractorViewModel(apiKey: apiKey))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Link info
                    linkInfoSection
                    
                    // Loading Indicator
                    if viewModel.isLoading {
                        loadingSection
                    }
                    
                    // Error Display
                    if let error = viewModel.errorMessage {
                        errorSection(message: error)
                    }
                    
                    // Extracted Recipe
                    if let recipe = viewModel.extractedRecipe {
                        extractedRecipeSection(recipe: recipe)
                    }
                }
                .padding()
            }
            .navigationTitle("Extract Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .onAppear {
                // Automatically start extraction when view appears
                Task {
                    await viewModel.extractRecipe(from: link.url)
                    
                    // Auto-download images after extraction completes
                    if let recipe = viewModel.extractedRecipe {
                        let imageURLs = extractImageURLsFromNotes(recipe)
                        if !imageURLs.isEmpty {
                            AppLog.info("Auto-downloading \(imageURLs.count) images from extracted recipe", category: .image)
                            // Take first 3 images to avoid excessive downloads
                            let urlsToDownload = Array(imageURLs.prefix(3))
                            await downloadImages(imageURLs: urlsToDownload)
                        }
                    }
                }
            }
            .alert("Recipe Saved!", isPresented: $showingSaveConfirmation) {
                Button("Done") {
                    onExtractionComplete(true, nil)
                    dismiss()
                }
            } message: {
                if let recipe = viewModel.extractedRecipe {
                    let imageCount = downloadedWebImages.count
                    if imageCount > 0 {
                        Text("\"\(recipe.safeTitle)\" and \(imageCount) image\(imageCount == 1 ? "" : "s") have been added to your recipe collection.")
                    } else {
                        Text("\"\(recipe.safeTitle)\" has been added to your recipe collection.")
                    }
                }
            }
            .sheet(isPresented: $showWebImagePicker) {
                // Extract image URLs from recipe notes
                if let recipe = viewModel.extractedRecipe {
                    let imageURLs = extractImageURLsFromNotes(recipe)
                    
                    if !imageURLs.isEmpty {
                        MultiWebImagePickerView(
                            imageURLs: imageURLs,
                            selectedURLs: $selectedWebImageURLs
                        ) {
                            // Reset downloaded images when selection changes
                            self.downloadedWebImages = []
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var linkInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Extracting From:", systemImage: "link")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(link.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(link.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
    
    private var loadingSection: some View {
        ExtractionLoadingView(extractionType: .link)
    }
    
    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.headline)
            }
            
            Text(message)
                .font(.body)
            
            Button("Try Again") {
                Task {
                    await viewModel.extractRecipe(from: link.url)
                }
            }
            .buttonStyle(.bordered)
            
            Button("Cancel") {
                onExtractionComplete(false, message)
                dismiss()
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            // Report error but don't dismiss automatically
            AppLog.error("Extraction failed: \(message)", category: .extraction)
        }
    }
    
    private func extractedRecipeSection(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            recipeSuccessHeader
            
            extractionSummary(recipe: recipe)
            
            let imageURLs = extractImageURLsFromNotes(recipe)
            if !imageURLs.isEmpty {
                imageSelectionSection(imageURLs: imageURLs)
            }
            
            saveButton
            
            Divider()
            
            if !recipe.ingredientSections.isEmpty || !recipe.instructionSections.isEmpty {
                recipeQuickPreview(recipe: recipe)
            }
            
            Divider()
            
            recipeNavigationLink(recipe: recipe)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Recipe Section Sub-Views
    
    private var recipeSuccessHeader: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            Text("Recipe Extracted Successfully!")
                .font(.headline)
        }
    }
    
    private func extractionSummary(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extracted:")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("• \(recipe.ingredientSections.count) ingredient section(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("• \(recipe.instructionSections.count) instruction section(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            let imageURLs = extractImageURLsFromNotes(recipe)
            if !imageURLs.isEmpty {
                Text("• \(imageURLs.count) image(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func imageSelectionSection(imageURLs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            imageSelectionHeader(imageCount: imageURLs.count)
            
            if !selectedWebImageURLs.isEmpty {
                selectedImagesScrollView
            } else {
                selectImagesButton(imageCount: imageURLs.count)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func imageSelectionHeader(imageCount: Int) -> some View {
        HStack {
            Text("Recipe Images")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if !selectedWebImageURLs.isEmpty {
                Text("(\(selectedWebImageURLs.count) selected)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(selectedWebImageURLs.isEmpty ? "Select Images" : "Change Selection") {
                showWebImagePicker = true
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
    }
    
    private var selectedImagesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(selectedWebImageURLs.enumerated()), id: \.offset) { index, url in
                    selectedImageThumbnail(url: url, index: index)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func selectedImageThumbnail(url: String, index: Int) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipped()
                        .cornerRadius(8)
                case .failure:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                        )
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .overlay(ProgressView())
                @unknown default:
                    EmptyView()
                }
            }
            
            if index == 0 {
                Text("Main Image")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            } else {
                Text("Image \(index + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func selectImagesButton(imageCount: Int) -> some View {
        Button {
            showWebImagePicker = true
        } label: {
            HStack {
                Image(systemName: "photo.on.rectangle.angled")
                Text("Select Recipe Images (\(imageCount) available)")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var saveButton: some View {
        Button {
            AppLog.info("Save button tapped", category: .ui)
            // If there are selected web image URLs and we haven't downloaded them yet
            if !selectedWebImageURLs.isEmpty && downloadedWebImages.isEmpty {
                Task {
                    await downloadAndSaveRecipe(imageURLs: selectedWebImageURLs)
                }
            } else {
                saveRecipe()
            }
        } label: {
            if isDownloadingImage {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Downloading Images...")
                            .font(.headline)
                        Text("Please wait")
                            .font(.caption)
                            .opacity(0.9)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(12)
            } else {
                Label("Save to Collection", systemImage: "square.and.arrow.down.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .disabled(isDownloadingImage)
        .buttonStyle(.plain)
    }
    
    private func recipeQuickPreview(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Preview")
                .font(.headline)
            
            if !recipe.ingredientSections.isEmpty {
                ingredientsPreview(recipe: recipe)
            }
            
            if !recipe.instructionSections.isEmpty {
                instructionsPreview(recipe: recipe)
            }
            
            Text("Tap recipe title below to view full details →")
                .font(.caption)
                .foregroundColor(.blue)
                .italic()
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func ingredientsPreview(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(recipe.ingredientSections.prefix(1)) { section in
                ForEach(section.ingredients.prefix(3)) { ingredient in
                    HStack {
                        Text("•")
                        if let quantity = ingredient.quantity {
                            Text(quantity)
                        }
                        if let unit = ingredient.unit {
                            Text(unit)
                        }
                        Text(ingredient.name)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                if section.ingredients.count > 3 {
                    Text("... and \(section.ingredients.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func instructionsPreview(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(recipe.instructionSections.prefix(1)) { section in
                ForEach(section.steps.prefix(2)) { step in
                    HStack(alignment: .top) {
                        if step.stepNumber > 0 {
                            Text("\(step.stepNumber).")
                                .fontWeight(.semibold)
                        } else {
                            Text("•")
                        }
                        Text(step.text)
                            .lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                if section.steps.count > 2 {
                    Text("... and \(section.steps.count - 2) more steps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func recipeNavigationLink(recipe: RecipeX) -> some View {
        NavigationLink {
            // Add the first downloaded image if available
            if let firstImage = downloadedWebImages.first {
                recipe.setImage(firstImage, isMainImage: true)
            }
            
            return RecipeDetailView(recipe: recipe)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(recipe.safeTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if let yield = recipe.yield {
                        Text(yield)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Save Recipe
    
    /// Extract image URLs from recipe notes
    /// The RecipeExtractorViewModel stores image URLs in a note with the prefix "Image URLs from source:"
    private func extractImageURLsFromNotes(_ recipe: RecipeX) -> [String] {
        let notes = recipe.notes
        
        // Look for the note containing image URLs
        guard let imageURLNote = notes.first(where: { $0.text.starts(with: "Image URLs from source:") }) else {
            return []
        }
        
        // Extract URLs from the note text
        let lines = imageURLNote.text.components(separatedBy: .newlines)
        
        // Skip the first line (the header) and return the rest as URLs
        return Array(lines.dropFirst()).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    
    private func downloadImages(imageURLs: [String]) async {
        isDownloadingImage = true
        var downloadedImages: [UIImage] = []
        
        for (index, imageURL) in imageURLs.enumerated() {
            do {
                AppLog.info("Downloading image \(index + 1)/\(imageURLs.count) from: \(imageURL)", category: .network)
                let image = try await imageDownloader.downloadImage(from: imageURL)
                downloadedImages.append(image)
            } catch {
                AppLog.error("Failed to download image \(index + 1): \(error)", category: .network)
                // Continue with other images
            }
        }
        
        await MainActor.run {
            self.downloadedWebImages = downloadedImages
            AppLog.info("Auto-downloaded \(downloadedImages.count) images successfully", category: .network)
            self.isDownloadingImage = false
        }
    }
    
    private func downloadAndSaveRecipe(imageURLs: [String]) async {
        await downloadImages(imageURLs: imageURLs)
        
        await MainActor.run {
            self.saveRecipe()
        }
    }
    
    private func saveRecipe() {
        AppLog.info("Saving recipe from link", category: .recipe)
        
        guard let recipe = viewModel.extractedRecipe else {
            AppLog.error("No recipe to save", category: .recipe)
            return
        }
        
        AppLog.info("Saving recipe: \(recipe.safeTitle)", category: .recipe)
        
        // Add tips from the SavedLink as recipe notes (type: .tip)
        if let tips = link.tips, !tips.isEmpty {
            AppLog.info("Adding \(tips.count) tip(s) from saved link to recipe notes", category: .recipe)
            
            // Convert tips to RecipeNote objects
            let tipNotes = tips.map { tipText in
                RecipeNote(type: .tip, text: tipText)
            }
            
            // Get existing notes and append tips
            var existingNotes = recipe.notes
            existingNotes.append(contentsOf: tipNotes)
            
            // Encode and store back in recipe
            if let encodedNotes = try? JSONEncoder().encode(existingNotes) {
                recipe.notesData = encodedNotes
            }
            
            AppLog.info("Total notes including tips: \(existingNotes.count)", category: .recipe)
        }
        
        // EXTRACT AND MOVE: Move image URLs from notes to the reference field
        var notes = recipe.notes
        var imageURLs: [String] = []
        
        // Find and extract image URLs from notes
        if let imageURLNote = notes.first(where: { $0.text.hasPrefix("Image URLs from source:") }) {
            let lines = imageURLNote.text.components(separatedBy: .newlines)
            imageURLs = Array(lines.dropFirst()).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        
        // Remove the temporary image URL note
        notes.removeAll { note in
            note.text.hasPrefix("Image URLs from source:")
        }
        
        // Update the recipe with cleaned notes
        if let encodedNotes = try? JSONEncoder().encode(notes) {
            recipe.notesData = encodedNotes.isEmpty ? nil : encodedNotes
            AppLog.info("Moved image URLs from notes to reference field", category: .recipe)
        }
        
        // Append image URLs to the reference field as clickable links
        if !imageURLs.isEmpty {
            var referenceText = recipe.reference ?? ""
            
            // Add a separator if there's already content in reference
            if !referenceText.isEmpty {
                referenceText += "\n\n"
            }
            
            // Add image URLs section
            referenceText += "Source Images:\n"
            for url in imageURLs {
                referenceText += url + "\n"
            }
            
            recipe.reference = referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
            AppLog.info("Added \(imageURLs.count) image URL(s) to reference field", category: .recipe)
        }
        
        // Determine which images we'll save
        let imagesToSave = downloadedWebImages.isEmpty ? [] : downloadedWebImages
        
        // Set extraction source
        recipe.extractionSource = "web"
        
        // Set reference to the original link URL (if not already set)
        if recipe.reference == nil || recipe.reference?.isEmpty == true {
            recipe.reference = link.url
        }
        
        // Initialize CloudKit sync properties
        recipe.needsCloudSync = true
        recipe.syncRetryCount = 0
        recipe.lastSyncError = nil
        
        // Set timestamps
        let now = Date()
        recipe.dateAdded = now
        recipe.dateCreated = now
        recipe.lastModified = now
        
        // Set initial version
        recipe.version = 1
        
        // Insert into SwiftData context
        modelContext.insert(recipe)
        
        // Save all images using the setImage() method
        for (index, image) in imagesToSave.enumerated() {
            if index == 0 {
                // First image is the main thumbnail
                recipe.setImage(image, isMainImage: true)
                AppLog.info("✅ Saved main image using setImage() (CloudKit-synced)", category: .recipe)
            } else {
                // Additional images
                recipe.setImage(image, isMainImage: false)
                AppLog.info("✅ Saved additional image \(index) using setImage() (CloudKit-synced)", category: .recipe)
            }
        }
        
        AppLog.info("Saved \(imagesToSave.count) image(s) to RecipeX for CloudKit sync", category: .recipe)
        
        // Update the link to mark it as processed
        link.isProcessed = true
        link.extractedRecipeID = recipe.safeID
        link.processingError = nil
        
        // Save the context
        do {
            try modelContext.save()
            AppLog.info("Recipe saved successfully to SwiftData as RecipeX with imageData", category: .storage)
            
            // Small delay to ensure SwiftData propagates the change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingSaveConfirmation = true
            }
        } catch {
            AppLog.error("Failed to save recipe: \(error)", category: .storage)
            onExtractionComplete(false, error.localizedDescription)
        }
    }
    
    // MARK: - Image Management (Deprecated - kept for reference)
    // Note: saveImageToDisk() is no longer used - images are saved via recipe.setImage() in RecipeX
    
    @available(*, deprecated, message: "Use recipe.setImage() instead - images are now stored in RecipeX.imageData")
    private func saveImageToDisk(_ image: UIImage, filename: String) {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            AppLog.error("Failed to convert image to JPEG data", category: .storage)
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            AppLog.info("Saved recipe image to: \(fileURL.path)", category: .storage)
        } catch {
            AppLog.error("Error saving recipe image: \(error)", category: .storage)
        }
    }
}

// MARK: - Preview

#Preview {
    let link = SavedLink(
        title: "Chocolate Chip Cookies",
        url: "https://www.example.com/recipe/chocolate-chip-cookies"
    )
    
    return LinkExtractionView(
        link: link,
        apiKey: "test-api-key",
        onExtractionComplete: { _, _ in }
    )
    .modelContainer(for: [SavedLink.self, RecipeX.self], inMemory: true)
}
