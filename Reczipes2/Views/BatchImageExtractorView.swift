//
//  BatchImageExtractorView.swift
//  Reczipes2
//
//  Created for batch recipe extraction from Photos library
//

import SwiftUI
import SwiftData
import Photos
import OSLog
import UniformTypeIdentifiers

/// UI for batch extracting recipes from tagged Photos library images
struct BatchImageExtractorView: View {
    @StateObject private var viewModel: BatchImageExtractorViewModel
    @StateObject private var photoManager = PhotoLibraryManager()
    @State private var keepAwakeManager = KeepAwakeManager.shared
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingImagePicker = false
    @State private var showingDocumentPicker = false
    @State private var selectedAssets: [PHAsset] = []
    @State private var selectedImages: [UIImage] = [] // For iCloud Drive images
    @State private var showingCropOptions = false
    @State private var showingCompletionAlert = false
    @State private var shouldCropImages = false
    @State private var showingHelp = false
    @State private var showingSourcePicker = false
    @State private var isLoadingImages = false
    @State private var loadingProgress = LoadingProgress(current: 0, total: 0)
    @State private var showingBackgroundExtractionAlert = false
    
    init(apiKey: String, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: BatchImageExtractorViewModel(
            apiKey: apiKey,
            modelContext: modelContext
        ))
        AppLog.info("BatchImageExtractorView initialized", category: .ui)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if selectedAssets.isEmpty && selectedImages.isEmpty {
                    emptyStateView
                } else if viewModel.isExtracting {
                    extractionProgressView
                } else {
                    imageSelectionView
                }
                
                // Loading overlay for file picker
                if isLoadingImages {
                    loadingOverlay
                }
            }
            .navigationTitle("Batch Image Extract")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        handleCloseButton()
                    }
                }
                
                
                // ADD THIS NEW ITEM:
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        AppLog.debug("User tapped help button for batch extraction", category: .ui)
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                
                if !selectedAssets.isEmpty && !viewModel.isExtracting {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                AppLog.info("User tapped 'Add More from Photos' to add additional images", category: .ui)
                                showingImagePicker = true
                            } label: {
                                Label("From Photos", systemImage: "photo.on.rectangle")
                            }
                            
                            Button {
                                AppLog.info("User tapped 'Add More from Files' to add additional images", category: .ui)
                                showingDocumentPicker = true
                            } label: {
                                Label("From Files (iCloud Drive)", systemImage: "folder")
                            }
                        } label: {
                            Label("Add More", systemImage: "plus")
                        }
                    }
                }
                
                if !selectedImages.isEmpty && !viewModel.isExtracting {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                AppLog.info("User tapped 'Add More from Photos' to add additional images", category: .ui)
                                showingImagePicker = true
                            } label: {
                                Label("From Photos", systemImage: "photo.on.rectangle")
                            }
                            
                            Button {
                                AppLog.info("User tapped 'Add More from Files' to add additional images", category: .ui)
                                showingDocumentPicker = true
                            } label: {
                                Label("From Files (iCloud Drive)", systemImage: "folder")
                            }
                        } label: {
                            Label("Add More", systemImage: "plus")
                        }
                    }
                }
                
            }
            .sheet(isPresented: $showingImagePicker) {
                PhotosPickerSheet(
                    selectedAssets: $selectedAssets,
                    photoManager: photoManager
                )
            }
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPickerView(
                    selectedImages: $selectedImages,
                    isLoadingImages: $isLoadingImages,
                    loadingProgress: $loadingProgress
                )
            }
            .sheet(isPresented: $showingSourcePicker) {
                sourceSelectionSheet
            }
            .sheet(isPresented: $showingCropOptions) {
                cropOptionsSheet
            }
            
            .sheet(isPresented: $showingHelp) {
                HelpDetailView(topic: AppHelp.batchImageExtraction_image)
            }
            .alert("Batch Extraction Complete", isPresented: $showingCompletionAlert) {
                Button("View Recipes") {
                    AppLog.info("User chose to view recipes after batch extraction", category: .ui)
                    dismiss()
                }
                Button("OK", role: .cancel) {
                    AppLog.info("User dismissed completion alert and reset batch extractor", category: .ui)
                    viewModel.reset()
                    selectedAssets = []
                    selectedImages = []
                }
            } message: {
                Text("Extracted \(viewModel.successCount) recipe\(viewModel.successCount == 1 ? "" : "s") successfully\(viewModel.failureCount > 0 ? " with \(viewModel.failureCount) failure\(viewModel.failureCount == 1 ? "" : "s")" : "").")
            }
            .onAppear {
                AppLog.debug("BatchImageExtractorView appeared", category: .ui)
                Task {
                    await photoManager.requestPermission()
                    AppLog.info("Photo library permission requested", category: .image)
                }
            }
            .onChange(of: viewModel.isExtracting) { _, isExtracting in
                if !isExtracting && viewModel.currentProgress > 0 {
                    AppLog.info("Batch extraction completed. Success: \(viewModel.successCount), Failures: \(viewModel.failureCount)", category: .extraction)
                    showingCompletionAlert = true
                }
            }
            .onChange(of: selectedImages) { _, newImages in
                if !newImages.isEmpty {
                    AppLog.info("Loaded \(newImages.count) images from iCloud Drive/Files", category: .ui)
                }
            }
            .onChange(of: isLoadingImages) { oldValue, newValue in
                // When loading finishes, provide haptic feedback
                if oldValue && !newValue && loadingProgress.total > 0 {
                    let successCount = selectedImages.count
                    _ = loadingProgress.total
                    
                    if successCount > 0 {
                        // Success haptic
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        
                        AppLog.info("Finished loading images: \(successCount) loaded successfully", category: .ui)
                    }
                    
                    // Reset progress
                    loadingProgress = LoadingProgress(current: 0, total: 0)
                }
            }
            .fullScreenCover(isPresented: $viewModel.showingCropForBatch) {
                if let image = viewModel.imageToCropInBatch {
                    ImageCropView(
                        image: image,
                        onCrop: { croppedImage in
                            AppLog.debug("User completed cropping image in batch workflow", category: .image)
                            viewModel.handleCroppedImage(croppedImage)
                        },
                        onCancel: {
                            AppLog.debug("User cancelled crop view in batch workflow", category: .image)
                            viewModel.handleCroppedImage(nil)
                        }
                    )
                }
            }
            .alert("Extraction in Progress", isPresented: $showingBackgroundExtractionAlert) {
                Button("Continue in Background", role: .none) {
                    AppLog.info("User chose to continue extraction in background", category: .batch)
                    viewModel.prepareForBackgroundDismissal()
                    dismiss()
                }
                Button("Stop and Close", role: .destructive) {
                    AppLog.info("User stopped extraction and closed view", category: .batch)
                    viewModel.stop()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    AppLog.info("User cancelled close action", category: .batch)
                }
            } message: {
                Text("Batch extraction is still running. You can let it continue in the background, or stop it now.")
            }
            .onChange(of: viewModel.isExtracting) { oldValue, newValue in
                // Automatically enable keep awake during batch extraction
                if newValue {
                    AppLog.info("Batch extraction started - enabling keep awake", category: .batch)
                    keepAwakeManager.enable()
                } else if oldValue {
                    AppLog.info("Batch extraction ended - disabling keep awake", category: .batch)
                    keepAwakeManager.disable()
                }
            }
            .onDisappear {
                // Disable keep awake when view disappears if extraction is not running
                if !viewModel.isExtracting {
                    keepAwakeManager.disable()
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleCloseButton() {
        if viewModel.isExtracting && !shouldCropImages {
            // If extraction is running without cropping, offer background option
            AppLog.info("User tapped close during background-capable extraction", category: .ui)
            showingBackgroundExtractionAlert = true
        } else if viewModel.isExtracting {
            // If cropping is enabled, must stop
            AppLog.info("User stopped extraction with cropping and closed view", category: .extraction)
            viewModel.stop()
            dismiss()
        } else {
            // Not extracting, just close
            AppLog.info("User closed BatchImageExtractorView", category: .ui)
            dismiss()
        }
    }
    
    // MARK: - Empty State
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                VStack(spacing: 8) {
                    Text("Loading Images from Files")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if loadingProgress.total > 0 {
                        Text(loadingProgress.progressText)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        ProgressView(value: loadingProgress.percentage)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(width: 200)
                    }
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.8))
            )
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: isLoadingImages)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("Select Images to Extract")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose multiple recipe images from Photos or Files to extract recipes in batch")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Button {
                    AppLog.info("User tapped 'Select from Photos' in empty state", category: .ui)
                    showingImagePicker = true
                } label: {
                    Label("Select from Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    AppLog.info("User tapped 'Select from Files' in empty state", category: .ui)
                    showingDocumentPicker = true
                } label: {
                    Label("Select from Files (iCloud Drive)", systemImage: "folder.fill")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    // MARK: - Image Selection View
    
    private var imageSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Selection summary
                selectionSummaryCard
                
                // Crop option prompt
                cropOptionCard
                
                // Start button
                startExtractionButton
                
                // Selected images grid
                selectedImagesGrid
            }
            .padding()
        }
    }
    
    private var selectionSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.stack.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Images Selected")
                        .font(.headline)
                    let totalCount = selectedAssets.count + selectedImages.count
                    Text("\(totalCount) image\(totalCount == 1 ? "" : "s") ready for extraction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !selectedAssets.isEmpty && !selectedImages.isEmpty {
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.blue)
                                Text("\(selectedAssets.count)")
                            }
                            Text("•")
                            HStack(spacing: 2) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.purple)
                                Text("\(selectedImages.count)")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    } else if !selectedAssets.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 10))
                            Text("From Photos Library")
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    } else if !selectedImages.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            Text("From Files/iCloud Drive")
                        }
                        .font(.caption2)
                        .foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                Menu {
                    Button {
                        AppLog.info("User tapped add more from Photos", category: .ui)
                        showingImagePicker = true
                    } label: {
                        Label("From Photos", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        AppLog.info("User tapped add more from Files", category: .ui)
                        showingDocumentPicker = true
                    } label: {
                        Label("From Files", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private var cropOptionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: shouldCropImages ? "crop.rotate" : "rectangle.dashed")
                    .foregroundColor(shouldCropImages ? .green : .orange)
                
                Text("Cropping Options")
                    .font(.headline)
            }
            
            Toggle(isOn: $shouldCropImages) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crop each image before extraction")
                        .font(.subheadline)
                    Text("You'll be able to crop each image individually")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
            .onChange(of: shouldCropImages) { oldValue, newValue in
                AppLog.debug("User toggled crop option: \(newValue)", category: .ui)
            }
            
            if !shouldCropImages {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Images will be processed as-is up to 10 at a time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private var startExtractionButton: some View {
        Button {
            let totalCount = selectedAssets.count + selectedImages.count
            AppLog.info("Starting batch extraction with \(totalCount) images (\(selectedAssets.count) from Photos, \(selectedImages.count) from Files), cropping: \(shouldCropImages)", category: .extraction)
            
            if shouldCropImages {
                // Start with cropping workflow
                if !selectedImages.isEmpty {
                    // Extract from UIImages (Files/iCloud Drive)
                    viewModel.startBatchExtractionFromImages(
                        images: selectedImages,
                        shouldCrop: true
                    )
                } else {
                    // Extract from PHAssets (Photos)
                    viewModel.startBatchExtraction(
                        assets: selectedAssets,
                        photoManager: photoManager,
                        shouldCrop: true
                    )
                }
            } else {
                // Start without cropping
                if !selectedImages.isEmpty {
                    // Extract from UIImages (Files/iCloud Drive)
                    viewModel.startBatchExtractionFromImages(
                        images: selectedImages,
                        shouldCrop: false
                    )
                } else {
                    // Extract from PHAssets (Photos)
                    viewModel.startBatchExtraction(
                        assets: selectedAssets,
                        photoManager: photoManager,
                        shouldCrop: false
                    )
                }
            }
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(shouldCropImages ? "Start with Cropping" : "Start Extraction")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private var selectedImagesGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Images")
                    .font(.headline)
                Spacer()
                Text("Tap any image to zoom")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                // First show PHAssets from Photos
                ForEach(Array(selectedAssets.enumerated()), id: \.offset) { index, asset in
                    SelectedAssetThumbnail(
                        asset: asset,
                        index: index,
                        photoManager: photoManager,
                        onRemove: {
                            selectedAssets.remove(at: index)
                        }
                    )
                }
                
                // Then show UIImages from Files/iCloud Drive
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    SelectedImageThumbnail(
                        image: image,
                        index: selectedAssets.count + index,
                        onRemove: {
                            selectedImages.remove(at: index)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    // MARK: - Extraction Progress View
    
    private var extractionProgressView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Progress overview
                progressOverviewCard
                
                // Current extraction
                if viewModel.currentImage != nil {
                    currentImageCard
                }
                
                // Control buttons
                if viewModel.isWaitingForCrop {
                    cropDecisionButtons
                } else {
                    controlButtons
                }
                
                // Remaining queue
                remainingQueueSection
                
                // Error log
                if !viewModel.errorLog.isEmpty {
                    errorLogSection
                }
            }
            .padding()
        }
    }
    
    private var progressOverviewCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extracting Recipes")
                        .font(.headline)
                    Text(viewModel.currentStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            ProgressView(value: Double(viewModel.currentProgress), total: Double(viewModel.totalToExtract))
                .progressViewStyle(.linear)
                .tint(.purple)
            
            // Stats
            HStack(spacing: 20) {
                statItem(
                    label: "Progress",
                    value: "\(viewModel.currentProgress)/\(viewModel.totalToExtract)",
                    color: .blue
                )
                
                statItem(
                    label: "Success",
                    value: "\(viewModel.successCount)",
                    color: .green
                )
                
                if viewModel.failureCount > 0 {
                    statItem(
                        label: "Failed",
                        value: "\(viewModel.failureCount)",
                        color: .red
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var currentImageCard: some View {
        VStack(spacing: 12) {
            if let image = viewModel.currentImage {
                // Image preview with tap to expand
                CurrentImagePreview(image: image)
                
                if let recipe = viewModel.currentRecipe {
                    // Recipe preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Extracted: \(String(describing: recipe.title))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        if !recipe.ingredientSections.isEmpty {
                            Text("✓ \(recipe.ingredientSections.count) ingredient section\(recipe.ingredientSections.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if !recipe.instructionSections.isEmpty {
                            Text("✓ \(recipe.instructionSections.count) instruction section\(recipe.instructionSections.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var cropDecisionButtons: some View {
        VStack(spacing: 12) {
            Text("Would you like to crop this image?")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    AppLog.debug("User chose to skip cropping for current image", category: .image)
                    viewModel.skipCropping()
                } label: {
                    HStack {
                        Image(systemName: "arrow.forward")
                        Text("Skip")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    AppLog.debug("User chose to crop current image", category: .image)
                    viewModel.showCropping()
                } label: {
                    HStack {
                        Image(systemName: "crop.rotate")
                        Text("Crop")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private var controlButtons: some View {
        VStack(spacing: 12) {
            // Keep awake indicator
            if keepAwakeManager.isKeepAwakeEnabled {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.orange)
                    Text("Device will stay awake during extraction")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Background extraction indicator
            if !shouldCropImages && viewModel.isExtracting {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.purple)
                    Text("Extraction will continue if you close this screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Control buttons
            HStack(spacing: 12) {
                Button {
                    if viewModel.isPaused {
                        AppLog.info("User resumed batch extraction", category: .extraction)
                        viewModel.resume()
                    } else {
                        AppLog.info("User paused batch extraction", category: .extraction)
                        viewModel.pause()
                    }
                } label: {
                    HStack {
                        Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        Text(viewModel.isPaused ? "Resume" : "Pause")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isPaused ? Color.green : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                
                Button {
                    AppLog.warning("User stopped batch extraction at \(viewModel.currentProgress)/\(viewModel.totalToExtract)", category: .extraction)
                    viewModel.stop()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var remainingQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remaining Queue (\(viewModel.remainingCount))")
                .font(.headline)
            
            if viewModel.remainingCount == 0 {
                Text("All images processed!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                Text("Next \(min(10, viewModel.remainingCount)) images will be processed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Show PHAsset thumbnails
                        ForEach(0..<min(10, viewModel.remainingAssets.count), id: \.self) { index in
                            if index < viewModel.remainingAssets.count {
                                QueuedAssetThumbnail(
                                    asset: viewModel.remainingAssets[index],
                                    index: index + viewModel.currentProgress,
                                    photoManager: photoManager
                                )
                            }
                        }
                        
                        // Show UIImage thumbnails (if no PHAssets, or to fill remaining)
                        ForEach(0..<min(10 - viewModel.remainingAssets.count, viewModel.remainingImages.count), id: \.self) { index in
                            if index < viewModel.remainingImages.count {
                                QueuedUIImageThumbnail(
                                    image: viewModel.remainingImages[index],
                                    index: index + viewModel.currentProgress + viewModel.remainingAssets.count
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    private var errorLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Errors (\(viewModel.errorLog.count))")
                    .font(.headline)
            }
            
            VStack(spacing: 8) {
                ForEach(viewModel.errorLog.indices, id: \.self) { index in
                    let error = viewModel.errorLog[index]
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Image \(error.imageIndex + 1)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(error.error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 1)
    }
    
    // MARK: - Crop Options Sheet
    
    private var sourceSelectionSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Select Image Source")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose where to select your recipe images from")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button {
                        showingSourcePicker = false
                        showingImagePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            VStack(alignment: .leading) {
                                Text("Photos Library")
                                    .font(.headline)
                                Text("Select from your device's photos")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showingSourcePicker = false
                        showingDocumentPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            VStack(alignment: .leading) {
                                Text("Files (iCloud Drive)")
                                    .font(.headline)
                                Text("Select from Files app and iCloud Drive")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Select Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSourcePicker = false
                    }
                }
            }
        }
    }
    
    private var cropOptionsSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crop.rotate")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Crop Before Extraction?")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("You can crop each image individually before extraction, or skip cropping to process images faster.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button {
                        shouldCropImages = true
                        showingCropOptions = false
                        AppLog.info("User chose to crop each image in batch", category: .extraction)
                        viewModel.startBatchExtraction(
                            assets: selectedAssets,
                            photoManager: photoManager,
                            shouldCrop: true
                        )
                    } label: {
                        HStack {
                            Image(systemName: "crop.rotate")
                            Text("Crop Each Image")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        shouldCropImages = false
                        showingCropOptions = false
                        AppLog.info("User chose to skip cropping for batch extraction", category: .extraction)
                        viewModel.startBatchExtraction(
                            assets: selectedAssets,
                            photoManager: photoManager,
                            shouldCrop: false
                        )
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                            Text("Skip Cropping (Faster)")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Cropping Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingCropOptions = false
                    }
                }
            }
        }
    }
}

// MARK: - Document Picker for iCloud Drive

struct DocumentPickerView: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Binding var isLoadingImages: Bool
    @Binding var loadingProgress: LoadingProgress
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            AppLog.info("User selected \(urls.count) images from Files/iCloud Drive", category: .ui)
            
            // Log the URLs we received
            for (index, url) in urls.enumerated() {
                AppLog.debug("Document picker URL \(index + 1): \(url.path)", category: .storage)
                AppLog.debug("  - isFileURL: \(url.isFileURL)", category: .storage)
                AppLog.debug("  - lastPathComponent: \(url.lastPathComponent)", category: .storage)
            }
            
            // Show loading state immediately
            DispatchQueue.main.async {
                self.parent.isLoadingImages = true
                self.parent.loadingProgress = LoadingProgress(current: 0, total: urls.count)
            }
            
            // IMPORTANT: Since document picker uses asCopy: true, the URLs point to files
            // already copied to our app's temp directory - no security-scoped access needed
            // We must load them immediately before iOS cleans up the temp directory
            
            Task {
                var loadedImages: [UIImage] = []
                var successCount = 0
                var failureCount = 0
                
                for (index, url) in urls.enumerated() {
                    // Update progress on main thread
                    await MainActor.run {
                        self.parent.loadingProgress = LoadingProgress(
                            current: index,
                            total: urls.count,
                            currentFileName: url.lastPathComponent
                        )
                    }
                    
                    AppLog.debug("Processing file \(index + 1)/\(urls.count): \(url.lastPathComponent)", category: .storage)
                    
                    // Load image data directly (files are already in our sandbox from asCopy: true)
                    do {
                        // Check if file exists
                        let fileExists = FileManager.default.fileExists(atPath: url.path)
                        AppLog.debug("  File exists check: \(fileExists) at \(url.path)", category: .storage)
                        
                        guard fileExists else {
                            AppLog.warning("File does not exist at path: \(url.path)", category: .storage)
                            failureCount += 1
                            continue
                        }
                        
                        // Try to get file attributes for diagnostics
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                            let fileSize = attributes[.size] as? Int ?? 0
                            AppLog.debug("  File size: \(fileSize) bytes", category: .storage)
                        }
                        
                        // Load the image data
                        let imageData = try Data(contentsOf: url)
                        AppLog.debug("  Successfully loaded \(imageData.count) bytes from \(url.lastPathComponent)", category: .storage)
                        
                        // Create UIImage
                        if let image = UIImage(data: imageData) {
                            AppLog.debug("  ✅ Created UIImage (size: \(image.size.width)x\(image.size.height))", category: .image)
                            await MainActor.run {
                                loadedImages.append(image)
                            }
                            successCount += 1
                        } else {
                            AppLog.warning("  ❌ Failed to create UIImage from data - invalid image format", category: .image)
                            failureCount += 1
                        }
                    } catch {
                        AppLog.error("  ❌ Failed to load image: \(error.localizedDescription)", category: .storage)
                        AppLog.error("     Error details: \(String(describing: error))", category: .storage)
                        failureCount += 1
                    }
                    
                    // Small delay to prevent UI freezing with many files
                    if index % 10 == 0 && index > 0 {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                }
                
                // Update on main thread
                await MainActor.run {
                    self.parent.selectedImages.append(contentsOf: loadedImages)
                    self.parent.isLoadingImages = false
                    
                    AppLog.info("✅ File loading complete: \(successCount) succeeded, \(failureCount) failed", category: .image)
                    
                    if failureCount > 0 {
                        AppLog.warning("⚠️ Failed to load \(failureCount) out of \(urls.count) selected files", category: .storage)
                    }
                    
                    if successCount == 0 && failureCount > 0 {
                        AppLog.error("❌ All files failed to load! Check file formats and permissions.", category: .storage)
                    }
                }
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            AppLog.debug("User cancelled document picker", category: .ui)
            DispatchQueue.main.async {
                self.parent.isLoadingImages = false
            }
        }
    }
}

// MARK: - Loading Progress Model

struct LoadingProgress {
    var current: Int
    var total: Int
    var currentFileName: String = ""
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }
    
    var progressText: String {
        if !currentFileName.isEmpty {
            return "Loading \(current + 1) of \(total): \(currentFileName)"
        } else {
            return "Loading \(current) of \(total)"
        }
    }
}

// MARK: - Selected Image Thumbnail (for Files/iCloud Drive images)

struct SelectedImageThumbnail: View {
    let image: UIImage
    let index: Int
    let onRemove: () -> Void
    
    @State private var showingImageViewer = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showingImageViewer = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .clipped()
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Remove button
            Button {
                AppLog.debug("User removed iCloud Drive image \(index + 1) from selection", category: .ui)
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    )
            }
            .offset(x: 10, y: -10)
            .zIndex(1)
            
            // Index badge
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(6)
                    Spacer()
                }
            }
            .padding(6)
            .allowsHitTesting(false)
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            ExpandableImageViewer(image: image)
        }
    }
}

// MARK: - Supporting Views

struct SelectedAssetThumbnail: View {
    let asset: PHAsset
    let index: Int
    let photoManager: PhotoLibraryManager
    let onRemove: () -> Void
    
    @State private var thumbnail: UIImage?
    @State private var fullImage: UIImage?
    @State private var showingImageViewer = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = thumbnail {
                Button {
                    loadFullImageAndShow()
                } label: {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 150, height: 150)
                    .cornerRadius(12)
                    .overlay(ProgressView())
            }
            
            // Remove button
            Button {
                AppLog.debug("User removed image \(index + 1) from selection", category: .ui)
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    )
            }
            .offset(x: 10, y: -10)
            .zIndex(1)
            
            // Index badge
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 3) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 10))
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(6)
                    Spacer()
                }
            }
            .padding(6)
            .allowsHitTesting(false)
        }
        .task {
            thumbnail = await photoManager.loadThumbnail(for: asset)
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            if let fullImage = fullImage {
                ExpandableImageViewer(image: fullImage)
            }
        }
    }
    
    private func loadFullImageAndShow() {
        Task {
            if fullImage == nil {
                fullImage = await photoManager.loadFullImage(for: asset)
            }
            showingImageViewer = true
        }
    }
}

struct QueuedAssetThumbnail: View {
    let asset: PHAsset
    let index: Int
    let photoManager: PhotoLibraryManager
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        VStack(spacing: 4) {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .cornerRadius(8)
                    .overlay(ProgressView())
            }
            
            Text("\(index + 1)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .task {
            thumbnail = await photoManager.loadThumbnail(for: asset)
        }
    }
}

struct QueuedUIImageThumbnail: View {
    let image: UIImage
    let index: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipped()
                .cornerRadius(8)
            
            HStack(spacing: 2) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.purple)
                Text("\(index + 1)")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

struct PhotosPickerSheet: View {
    @Binding var selectedAssets: [PHAsset]
    @ObservedObject var photoManager: PhotoLibraryManager
    
    @Environment(\.dismiss) private var dismiss
    @State private var tempSelectedAssets: [PHAsset] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2),
                    GridItem(.flexible(), spacing: 2)
                ], spacing: 2) {
                    ForEach(photoManager.photoAssets, id: \.localIdentifier) { asset in
                        PhotoAssetCell(
                            asset: asset,
                            isSelected: tempSelectedAssets.contains(where: { $0.localIdentifier == asset.localIdentifier }),
                            photoManager: photoManager,
                            onTap: {
                                toggleSelection(asset)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Select Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(tempSelectedAssets.count))") {
                        AppLog.info("User added \(tempSelectedAssets.count) images to batch selection (total: \(selectedAssets.count + tempSelectedAssets.count))", category: .ui)
                        selectedAssets.append(contentsOf: tempSelectedAssets)
                        dismiss()
                    }
                    .disabled(tempSelectedAssets.isEmpty)
                }
            }
        }
        .onAppear {
            tempSelectedAssets = []
        }
    }
    
    private func toggleSelection(_ asset: PHAsset) {
        if let index = tempSelectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            tempSelectedAssets.remove(at: index)
            AppLog.debug("Deselected asset in photo picker", category: .ui)
        } else {
            tempSelectedAssets.append(asset)
            AppLog.debug("Selected asset in photo picker (temp count: \(tempSelectedAssets.count))", category: .ui)
        }
    }
}

struct PhotoAssetCell: View {
    let asset: PHAsset
    let isSelected: Bool
    let photoManager: PhotoLibraryManager
    let onTap: () -> Void
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .overlay(ProgressView())
                }
                
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(8)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .task {
            thumbnail = await photoManager.loadThumbnail(for: asset)
        }
    }
}

// MARK: - Current Image Preview with Tap to Expand

struct CurrentImagePreview: View {
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
                .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $showingImageViewer) {
            ExpandableImageViewer(image: image)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BatchImageExtractorView(
            apiKey: "test-api-key",
            modelContext: ModelContext(try! ModelContainer(for: RecipeX.self, Book.self, VersionHistoryRecord.self))
        )
    }
}
