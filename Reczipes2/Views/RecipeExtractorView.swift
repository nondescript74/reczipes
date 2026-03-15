//
//  RecipeExtractorView.swift
//  Reczipes2
//
//  Created for Claude-powered recipe extraction
//

import SwiftUI
import PhotosUI
import SwiftData

struct RecipeExtractorView: View {
    @StateObject private var viewModel: RecipeExtractorViewModel
    @State private var keepAwakeManager = KeepAwakeManager.shared
    @EnvironmentObject private var appState: AppStateManager
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showImageCrop = false
    @State private var imageToCrop: UIImage?
    @State private var showImageComparison = false
    @State private var showingSaveConfirmation = false
    @State private var showURLInput = false
    @State private var showWebImagePicker = false
    @State private var selectedWebImageURLs: [String] = []
    @State private var downloadedWebImages: [UIImage] = []
    @State private var isDownloadingImage = false
    @State private var extractionSource: ExtractionSource = .none
    @State private var extractionProgress: Double = 0.0
    @State private var showPendingExtractionAlert = false
    @State private var showBatchExtraction = false
    @State private var showBatchImageExtraction = false
    @State private var showImportLinks = false
    @State private var showManageLinks = false
    // mashup moved to RecipeDetailView
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    private let imageDownloader = WebImageDownloader()
    private let apiKey: String
    
    enum ExtractionSource {
        case none
        case camera
        case library
        case url
        case batch
        case batchImages
    }
    
    init(apiKey: String) {
        self.apiKey = apiKey
        _viewModel = StateObject(wrappedValue: RecipeExtractorViewModel(apiKey: apiKey))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Source Selection Section (hide when loading)
                    if !viewModel.isLoading && imageToCrop == nil {
                        sourceSelectionSection
                    }
                    
                    // Preparing image indicator (between picker and crop)
                    if imageToCrop != nil && !showImageCrop {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Preparing image...")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                    
                    // URL Input (if URL source selected and not loading)
                    if extractionSource == .url && !viewModel.isLoading {
                        urlInputSection
                    }
                    
                    // Preprocessing Toggle (only for images and not loading)
                    if viewModel.selectedImage != nil && extractionSource != .url && !viewModel.isLoading {
                        preprocessingToggle
                    }
                    
                    // Image Preview (hide during loading to keep focus on spinner)
                    if let image = viewModel.selectedImage, extractionSource != .url && !viewModel.isLoading {
                        imagePreviewSection(image: image)
                    }
                    
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
            .navigationTitle("Recipe Extractor")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        keepAwakeManager.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: keepAwakeManager.isKeepAwakeEnabled ? "moon.zzz.fill" : "moon.zzz")
                                .foregroundColor(keepAwakeManager.isKeepAwakeEnabled ? .blue : .secondary)
                            
                            if keepAwakeManager.isKeepAwakeEnabled {
                                Text("Stay Awake")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .help(keepAwakeManager.isKeepAwakeEnabled ? "Device will stay awake" : "Tap to prevent sleep")
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.extractedRecipe != nil {
                        // nothing for now

                    } else {
                        Text("No recipe")
                            .onAppear {
                                logWarning("No recipe available to save", category: "ui")
                            }
                    }
                }
            }
            .alert("Recipe Saved!", isPresented: $showingSaveConfirmation) {
                Button("View in Collection") {
                    // Verify the recipe was saved with image before dismissing
                    if let recipe = viewModel.extractedRecipe {
                        // Capture the UUID value to avoid Sendable issues
                        let recipeID = recipe.id
                        
                        // Query to check if recipe exists in context
                        let descriptor = FetchDescriptor<RecipeX>(
                            predicate: #Predicate { $0.id == recipeID }
                        )
                        if let savedRecipe = try? modelContext.fetch(descriptor).first {
                            logInfo("Verified recipe in DB: '\(savedRecipe.safeTitle)'", category: "storage")
                            logInfo("Recipe imageName in DB: '\(savedRecipe.imageName ?? "nil")'", category: "storage")
                        } else {
                            logWarning("Could not find recipe in DB after save", category: "storage")
                        }
                    }
                    // Dismiss and let the ContentView refresh
                    dismiss()
                }
                Button("Extract Another") {
                    viewModel.reset()
                    extractionSource = .none
                    selectedWebImageURLs = []
                    downloadedWebImages = []
                }
            } message: {
                if let recipe = viewModel.extractedRecipe {
                    let imageCount = downloadedWebImages.count + (viewModel.selectedImage != nil ? 1 : 0)
                    if imageCount > 0 {
                        Text("\"\(String(describing: recipe.title))\" and \(imageCount) image\(imageCount == 1 ? "" : "s") have been added to your recipe collection.")
                    } else {
                        Text("\"\(String(describing: recipe.title))\" has been added to your recipe collection.")
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(
                    sourceType: .photoLibrary,
                    onImageSelected: { image in
                        logInfo("Image selected from library, size: \(image.size)", category: "ui")
                        // Store the image and wait for sheet to dismiss before showing crop
                        imageToCrop = image
                        // Delay to ensure sheet dismisses before fullScreenCover presents
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            logInfo("Presenting crop view", category: "ui")
                            showImageCrop = true
                        }
                    },
                    onCancel: {
                        logInfo("Image picker cancelled", category: "ui")
                        // User cancelled, do nothing
                    }
                )
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(
                    sourceType: .camera,
                    onImageSelected: { image in
                        // Store the image and wait for sheet to dismiss before showing crop
                        imageToCrop = image
                        // Delay to ensure sheet dismisses before fullScreenCover presents
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            showImageCrop = true
                        }
                    },
                    onCancel: {
                        // User cancelled, do nothing
                    }
                )
            }
            .fullScreenCover(isPresented: $showImageCrop) {
                if let image = imageToCrop {
                    ImageCropView(
                        image: image,
                        onCrop: { croppedImage in
                            // After cropping, proceed with extraction
                            viewModel.selectedImage = croppedImage
                            
                            // Save input data for task restoration
                            if let imageData = croppedImage.jpegData(compressionQuality: 0.8) {
                                let inputData = ExtractionInputData(
                                    imageData: imageData,
                                    textInput: nil,
                                    timestamp: Date()
                                )
                                if let encoded = try? JSONEncoder().encode(inputData) {
                                    appState.startTask(type: .extraction, inputData: encoded)
                                }
                            }
                            
                            showImageCrop = false
                            imageToCrop = nil
                            
                            Task {
                                await viewModel.extractRecipe(from: croppedImage)
                            }
                        },
                        onCancel: {
                            // User cancelled cropping
                            showImageCrop = false
                            imageToCrop = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showImageComparison) {
                if let original = viewModel.selectedImage,
                   let processed = viewModel.processedImage {
                    ImageComparisonView(original: original, processed: processed)
                }
            }
            .onAppear {
                checkForPendingExtraction()
            }
            .trackTask(
                type: .extraction,
                progress: extractionProgress,
                isActive: viewModel.isLoading
            )
            .alert("Resume Extraction?", isPresented: $showPendingExtractionAlert) {
                Button("Resume") {
                    resumeExtraction()
                }
                Button("Cancel", role: .cancel) {
                    appState.completeTask()
                }
            } message: {
                Text("You have an extraction in progress. Would you like to resume where you left off?")
            }
            .sheet(isPresented: $showBatchExtraction) {
                BatchRecipeExtractorView(apiKey: apiKey, modelContext: modelContext)
            }
            .sheet(isPresented: $showBatchImageExtraction) {
                BatchImageExtractorView(apiKey: apiKey, modelContext: modelContext)
            }
            .sheet(isPresented: $viewModel.showingValidation) {
                if let recipe = viewModel.extractedRecipe,
                   let validationResult = viewModel.validationResult {
                    RecipeValidationView(
                        recipe: recipe,
                        validationResult: validationResult,
                        onApplyCorrections: { result in
                            viewModel.applyValidationCorrections(result)
                        },
                        onSkipValidation: {
                            viewModel.showingValidation = false
                        },
                        onFindSimilarRecipes: {
                            viewModel.showingValidation = false
                            Task {
                                await viewModel.findSimilarRecipes(modelContext: modelContext)
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $viewModel.showingSimilarRecipes) {
                if let recipe = viewModel.extractedRecipe {
                    SimilarRecipesView(
                        originalRecipe: recipe,
                        similarRecipes: viewModel.similarRecipes,
                        onDismiss: {
                            viewModel.showingSimilarRecipes = false
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var sourceSelectionSection: some View {
        VStack(spacing: 16) {
            Text("Choose how to extract your recipe")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                // Row 1: Camera and Library
                HStack(spacing: 20) {
                    Button {
                        extractionSource = .camera
                        showCamera = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                            Text("Camera")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(extractionSource == .camera ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(extractionSource == .camera ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        extractionSource = .library
                        showImagePicker = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 40))
                            Text("Library")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(extractionSource == .library ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(extractionSource == .library ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Row 2: Web URL (full width)
                Button {
                    extractionSource = .url
                    showURLInput = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 40))
                        Text("Web URL")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Extract from a recipe website")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(extractionSource == .url ? Color.blue.opacity(0.2) : Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(extractionSource == .url ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                
                // Row 3: Batch Extract URLs and Manage Links (side by side)
                HStack(spacing: 12) {
                    Button {
                        extractionSource = .batch
                        showBatchExtraction = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 36))
                            Text("Batch Extract URLs")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Extract from saved links")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(extractionSource == .batch ? Color.purple.opacity(0.2) : Color.purple.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(extractionSource == .batch ? Color.purple : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showManageLinks = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 36))
                            Text("Manage Links")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("View & delete links")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.teal.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Row 4: Batch Extract from Images (full width)
                Button {
                    extractionSource = .batchImages
                    showBatchImageExtraction = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 40))
                        Text("Batch Extract Images")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Extract multiple recipes from Photos library")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(extractionSource == .batchImages ? Color.orange.opacity(0.2) : Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(extractionSource == .batchImages ? Color.orange : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                
                // Row 5: Import Links (full width) — feeds the Batch Extract URLs flow
                Button {
                    showImportLinks = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 40))
                        Text("Import Recipe Links")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Import links from JSON to batch extract later")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                

            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
        .sheet(isPresented: $showManageLinks) {
            SavedLinksView()
        }
        .sheet(isPresented: $showImportLinks) {
            ImportLinksSheet(
                onImportComplete: { count in
                    importResultMessage = "Successfully imported \(count) new link(s)"
                    showingImportResult = true
                }
            )
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK") { }
        } message: {
            if let message = importResultMessage {
                Text(message)
            }
        }
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Recipe URL")
                .font(.headline)
            
            TextField("https://example.com/recipe", text: $viewModel.recipeURL)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.URL)
                .textContentType(.URL)
            
            Button {
                // Save input data for task restoration
                let inputData = ExtractionInputData(
                    imageData: nil,
                    textInput: viewModel.recipeURL,
                    timestamp: Date()
                )
                if let encoded = try? JSONEncoder().encode(inputData) {
                    appState.startTask(type: .extraction, inputData: encoded)
                }
                
                Task {
                    await viewModel.extractRecipe(from: viewModel.recipeURL)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Extract Recipe from URL")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.recipeURL.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.recipeURL.isEmpty || viewModel.isLoading)
            .buttonStyle(.plain)
            
            Text("Enter the full URL of a recipe webpage. The app will fetch and analyze the page to extract the recipe.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private var preprocessingToggle: some View {
        VStack(spacing: 8) {
            Toggle("Enhance Image for OCR", isOn: $viewModel.usePreprocessing)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
            
            Text("Applies contrast enhancement and sharpening for better text recognition")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if viewModel.processedImage != nil {
                Button("Compare Original vs Processed") {
                    showImageComparison = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
        .onChange(of: viewModel.usePreprocessing) { _, _ in
            Task {
                await viewModel.togglePreprocessing()
            }
        }
    }
    
    private func imagePreviewSection(image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Image")
                .font(.headline)
            
            ImagePreviewWithExpand(image: image)
        }
    }
    
    private var loadingSection: some View {
        ExtractionLoadingView(
            extractionType: extractionSource == .url ? .url : .image
        )
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
                if extractionSource == .url, !viewModel.recipeURL.isEmpty {
                    // Save input data for task restoration
                    let inputData = ExtractionInputData(
                        imageData: nil,
                        textInput: viewModel.recipeURL,
                        timestamp: Date()
                    )
                    if let encoded = try? JSONEncoder().encode(inputData) {
                        appState.startTask(type: .extraction, inputData: encoded)
                    }
                    
                    Task {
                        await viewModel.extractRecipe(from: viewModel.recipeURL)
                    }
                } else if let image = viewModel.selectedImage {
                    // Save input data for task restoration
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        let inputData = ExtractionInputData(
                            imageData: imageData,
                            textInput: nil,
                            timestamp: Date()
                        )
                        if let encoded = try? JSONEncoder().encode(inputData) {
                            appState.startTask(type: .extraction, inputData: encoded)
                        }
                    }
                    
                    Task {
                        await viewModel.extractRecipe(from: image)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func extractedRecipeSection(recipe: RecipeX) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            recipeSuccessHeader
            
            recipeDebugInfo(recipe: recipe)
            
            extractionSummary(recipe: recipe)
            
            if !viewModel.extractedImageURLs.isEmpty {
                imageSelectionSection(imageURLs: viewModel.extractedImageURLs)
            }
            
            // Enhancement buttons (for image-based extractions)
            if extractionSource == .camera || extractionSource == .library {
                enhancementButtonsSection
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
        .sheet(isPresented: $showWebImagePicker) {
            if !viewModel.extractedImageURLs.isEmpty {
                MultiWebImagePickerView(
                    imageURLs: viewModel.extractedImageURLs,
                    selectedURLs: $selectedWebImageURLs
                ) {
                    // Reset downloaded images when selection changes
                    self.downloadedWebImages = []
                }
            }
        }
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
    
    private func recipeDebugInfo(recipe: RecipeX) -> some View {
        Group {
            if recipe.ingredientSections.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No ingredients found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if recipe.instructionSections.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("No instructions found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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
            if !viewModel.extractedImageURLs.isEmpty {
                Text("• \(viewModel.extractedImageURLs.count) image(s) found")
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
    
    private var enhancementButtonsSection: some View {
        VStack(spacing: 12) {
            Text("Enhance Your Recipe")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Auto-save status indicator
            if viewModel.isRecipeSaved {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Recipe auto-saved before enhancement")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
            
            Text("Get AI-powered suggestions to improve content placement and discover similar recipes from top recipe websites.")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                // Validate & Enhance button
                Button {
                    Task {
                        await viewModel.validateRecipe(modelContext: modelContext)
                    }
                } label: {
                    HStack {
                        if viewModel.isValidating {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                        Text(viewModel.isValidating ? "Validating..." : "Validate Content")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isValidating || viewModel.isFindingSimilar)
                .buttonStyle(.plain)
                
                // Find Similar Recipes button
                Button {
                    Task {
                        await viewModel.findSimilarRecipes(modelContext: modelContext)
                    }
                } label: {
                    HStack {
                        if viewModel.isFindingSimilar {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(viewModel.isFindingSimilar ? "Searching..." : "Find Similar")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isValidating || viewModel.isFindingSimilar)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var saveButton: some View {
        Button {
            logInfo("INLINE Save button tapped", category: "ui")
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
                ingredientsPreview(ingredientSections: recipe.ingredientSections)
            }
            
            if !recipe.instructionSections.isEmpty {
                instructionsPreview(instructionSections: recipe.instructionSections)
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
    
    private func ingredientsPreview(ingredientSections: [IngredientSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingredients:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(ingredientSections.prefix(1)) { section in
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
    
    private func instructionsPreview(instructionSections: [InstructionSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(instructionSections.prefix(1)) { section in
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
            // Convert RecipeModel to RecipeX for the detail view
            RecipeDetailView(recipe: recipe)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(recipe.title ?? "Unknown")
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

    
    private func downloadAndSaveRecipe(imageURLs: [String]) async {
        isDownloadingImage = true
        var downloadedImages: [UIImage] = []
        
        for (index, imageURL) in imageURLs.enumerated() {
            do {
                logInfo("Downloading image \(index + 1)/\(imageURLs.count) from: \(imageURL)", category: "network")
                let image = try await imageDownloader.downloadImage(from: imageURL)
                downloadedImages.append(image)
            } catch {
                logError("Failed to download image \(index + 1): \(error)", category: "network")
                // Continue with other images
            }
        }
        
        await MainActor.run {
            self.downloadedWebImages = downloadedImages
            logInfo("Downloaded \(downloadedImages.count) images successfully", category: "network")
            self.saveRecipe()
            self.isDownloadingImage = false
        }
    }
    
    @MainActor
    private func saveRecipe() {
        logInfo("Save button tapped", category: "recipe")
        
        guard let recipe = viewModel.extractedRecipe else {
            logError("No recipe to save", category: "recipe")
            return
        }
        
        logInfo("Saving recipe: \(recipe.title ?? "Unknown")", category: "recipe")
        
        // Determine which images we'll save
        let imagesToSave: [UIImage]
        if !downloadedWebImages.isEmpty {
            imagesToSave = downloadedWebImages
        } else if let selectedImage = viewModel.selectedImage {
            imagesToSave = [selectedImage]
        } else {
            imagesToSave = []
        }
        
        // Save all images using RecipeX's setImage method
        for (index, image) in imagesToSave.enumerated() {
            if index == 0 {
                // First image is the main thumbnail
                recipe.setImage(image, isMainImage: true)
                logInfo("Set main image for recipe: \(recipe.safeTitle)", category: "recipe")
            } else {
                // Additional images
                recipe.setImage(image, isMainImage: false)
                logInfo("Added additional image \(index) for recipe: \(recipe.safeTitle)", category: "recipe")
            }
        }
        
        // Insert into SwiftData context
        modelContext.insert(recipe)
        logDebug("RecipeX inserted into context", category: "storage")
        logDebug("Recipe ID: \(recipe.safeID)", category: "storage")
        logDebug("Recipe imageName: \(recipe.imageName ?? "nil")", category: "storage")
        logDebug("Recipe imageData size: \(recipe.imageData?.count ?? 0) bytes", category: "storage")
        
        // Save the context
        do {
            try modelContext.save()
            logInfo("RecipeX saved successfully to SwiftData", category: "storage")
            logDebug("Recipe ID: \(recipe.safeID)", category: "storage")
            logDebug("Recipe Title: \(recipe.safeTitle)", category: "storage")
            logDebug("Recipe imageName (after context save): \(recipe.imageName ?? "nil")", category: "storage")
            logDebug("Recipe imageData size (after save): \(recipe.imageData?.count ?? 0) bytes", category: "storage")
            logDebug("Recipe has \(recipe.imageCount) image(s)", category: "storage")
            
            // Small delay to ensure SwiftData propagates the change
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showingSaveConfirmation = true
            }
        } catch {
            logError("Failed to save recipe: \(error)", category: "storage")
            logError("Error details: \(error.localizedDescription)", category: "storage")
            // Optionally show an error alert here
        }
    }
    
    // MARK: - Task Restoration
    
    private func checkForPendingExtraction() {
        // Check if there's a pending extraction task
        if let task = appState.activeTask,
           task.taskType == .extraction {
            logInfo("Found pending extraction task with progress: \(task.progress)", category: "state")
            showPendingExtractionAlert = true
        }
    }
    
    private func resumeExtraction() {
        // Resume from saved progress
        guard let task = appState.activeTask else { return }
        
        logInfo("Resuming extraction from progress: \(task.progress)", category: "state")
        extractionProgress = task.progress
        
        // If we have saved input data, try to restore it
        if let inputData = task.inputData,
           let extractionInput = try? JSONDecoder().decode(ExtractionInputData.self, from: inputData) {
            
            // Restore image if available
            if let imageData = extractionInput.imageData,
               let image = UIImage(data: imageData) {
                viewModel.selectedImage = image
                extractionSource = .library
                
                // Resume extraction
                Task {
                    await viewModel.extractRecipe(from: image)
                }
            }
            
            // Restore URL if available
            if let textInput = extractionInput.textInput, !textInput.isEmpty {
                viewModel.recipeURL = textInput
                extractionSource = .url
                
                // Resume extraction
                Task {
                    await viewModel.extractRecipe(from: textInput)
                }
            }
        } else {
            // No input data saved - just show the UI state
            logWarning("No input data available to resume extraction", category: "state")
            appState.completeTask()
        }
    }
}

// MARK: - Image Preview with Expand

struct ImagePreviewWithExpand: View {
    let image: UIImage
    @State private var showingImageViewer = false
    
    var body: some View {
        Button {
            showingImageViewer = true
        } label: {
            VStack(spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
                    .shadow(radius: 3)
                
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                    Text("Tap to expand and zoom")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingImageViewer) {
            ExpandableImageViewer(image: image)
        }
    }
}
