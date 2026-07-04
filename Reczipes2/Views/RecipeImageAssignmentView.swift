//
//  RecipeImageAssignmentView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI
import SwiftData
import Photos

struct RecipeImageAssignmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query private var savedRecipes: [RecipeX]
    
    @StateObject private var photoLibrary = PhotoLibraryManager()
    
    // All recipes as RecipeModel (stable UUIDs!)
    private var allRecipes: [RecipeX] {
        savedRecipes.compactMap { $0 }
    }
    
    // Helper to get RecipeX entity from RecipeModel
    private func getRecipe(for recipe: RecipeX) -> RecipeX? {
        savedRecipes.first { $0.id == recipe.id }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if allRecipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "book.closed",
                        description: Text("Extract recipes first before assigning images")
                    )
                } else {
                    switch photoLibrary.authorizationStatus {
                    case .notDetermined:
                        permissionPromptView
                    case .restricted, .denied:
                        permissionDeniedView
                    case .authorized, .limited:
                        if photoLibrary.isLoading {
                            loadingView
                        } else {
                            recipeListView
                        }
                    @unknown default:
                        permissionPromptView
                    }
                }
            }
            .navigationTitle("Recipe Images")
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Recipe Images")
                            .font(.headline)
                        Text("Change or assign photos")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task {
                // Load photos if we already have permission
                if photoLibrary.authorizationStatus == .authorized || photoLibrary.authorizationStatus == .limited {
                    await photoLibrary.loadPhotos()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var permissionPromptView: some View {
        ContentUnavailableView {
            Label("Photo Library Access", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Allow access to your photo library to assign images to recipes")
        } actions: {
            Button("Grant Access") {
                Task {
                    await photoLibrary.requestPermission()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Photo Library Access Denied", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Please enable photo library access in Settings to assign images to recipes")
        } actions: {
            if let settingsUrl = URL(string: PlatformURLOpener.settingsURLString) {
                Link("Open Settings", destination: settingsUrl)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading photos...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var recipeListView: some View {
        List {
            if photoLibrary.photoAssets.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Photos Found",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Your photo library appears to be empty or the app doesn't have access to any photos.")
                    )
                } footer: {
                    if photoLibrary.authorizationStatus == .limited {
                        Text("You've granted limited photo access. To see more photos, go to Settings and change photo access to 'Full Access'.")
                    }
                }
            } else {
                Section {
                    ForEach(allRecipes) { recipe in
                        if let recipeEntity = getRecipe(for: recipe) {
                            RecipePhotoRow(
                                recipe: recipe,
                                recipeEntity: recipeEntity,
                                photoLibrary: photoLibrary,
                                modelContext: modelContext
                            )
                        }
                    }
                } header: {
                    Text("Your Recipes")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(photoLibrary.photoAssets.count) photo(s) available in library")
                        Text("Tip: The main image is set during extraction. You can add additional images here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
}

// MARK: - Recipe Photo Row

struct RecipePhotoRow: View {
    let recipe: RecipeX
    let recipeEntity: RecipeX
    let photoLibrary: PhotoLibraryManager
    let modelContext: ModelContext
    
    @State private var showingPhotoPicker = false
    @State private var thumbnailImages: [PlatformImage] = []
    
    private var additionalImageCount: Int {
        recipeEntity.additionalImageNames?.count ?? 0
    }
    
    private var hasMainImage: Bool {
        recipeEntity.imageName != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recipe header with title
            HStack(spacing: 12) {
                // Main image thumbnail (read-only from imageData)
                Group {
                    if let image = recipeEntity.getMainImage() {
                        Image(platformImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if hasMainImage {
                        Text("MAIN")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.onTint)
                            .padding(2)
                            .background(AdaptiveToneSolidFill(tone: .info))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(2)
                    }
                }
                
                // Recipe info
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title ?? "No title")
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        if hasMainImage {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.appSuccess)
                            Text("Main image + \(additionalImageCount) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No main image · \(additionalImageCount) additional")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                Spacer()
                
                // Add button
                Button(action: { showingPhotoPicker = true }) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.appInfo)
                }
                .buttonStyle(.plain)
            }
            
            // Additional images grid (from imageData)
            let additionalImages = recipeEntity.getAdditionalImages()
            if !additionalImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(additionalImages.enumerated()), id: \.offset) { index, image in
                            Image(platformImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .overlay(alignment: .topTrailing) {
                                    Button(action: {
                                        recipeEntity.removeAdditionalImage(at: index)
                                        try? modelContext.save()
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(Color.onTint)
                                            .background(Circle().fill(Color.red))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(2)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingPhotoPicker) {
            MultiPhotoPickerSheet(
                recipe: recipe,
                recipeEntity: recipeEntity,
                photoLibrary: photoLibrary,
                modelContext: modelContext
            )
        }
    }
}

// MARK: - Multi Photo Picker Sheet

struct MultiPhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let recipe: RecipeX
    let recipeEntity: RecipeX
    let photoLibrary: PhotoLibraryManager
    let modelContext: ModelContext
    
    @State private var selectedAssets: Set<String> = []
    @State private var isSelecting = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(photoLibrary.photoAssets, id: \.localIdentifier) { asset in
                        SelectablePhotoThumbnailView(
                            asset: asset,
                            photoLibrary: photoLibrary,
                            isSelected: selectedAssets.contains(asset.localIdentifier),
                            onToggle: {
                                toggleSelection(for: asset)
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Add Photos")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedAssets.count)") {
                        Task {
                            await addSelectedPhotos()
                            dismiss()
                        }
                    }
                    .disabled(selectedAssets.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedAssets.isEmpty {
                    HStack {
                        Text("\(selectedAssets.count) photo(s) selected")
                            .font(.headline)
                        Spacer()
                        Button("Clear") {
                            selectedAssets.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
    }
    
    private func toggleSelection(for asset: PHAsset) {
        if selectedAssets.contains(asset.localIdentifier) {
            selectedAssets.remove(asset.localIdentifier)
        } else {
            selectedAssets.insert(asset.localIdentifier)
        }
    }
    
    private func addSelectedPhotos() async {
        var addedCount = 0
        
        for identifier in selectedAssets {
            guard let asset = photoLibrary.photoAssets.first(where: { $0.localIdentifier == identifier }),
                  let image = await photoLibrary.loadImage(for: asset, targetSize: PHImageManagerMaximumSize) else {
                continue
            }
            
            // Use the new setImage() method to save to SwiftData (CloudKit-synced)
            recipeEntity.setImage(image, isMainImage: false)
            addedCount += 1
        }
        
        // Save context
        if addedCount > 0 {
            try? modelContext.save()
            print("✅ Added \(addedCount) additional images to recipe '\(String(describing: recipe.title))' using setImage() (CloudKit-synced)")
        }
    }
}

// MARK: - Selectable Photo Thumbnail View

struct SelectablePhotoThumbnailView: View {
    let asset: PHAsset
    let photoLibrary: PhotoLibraryManager
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var thumbnail: PlatformImage?
    
    var body: some View {
        Button(action: onToggle) {
            Group {
                if let thumbnail {
                    Image(platformImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                        .overlay(
                            ProgressView()
                        )
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.onTint)
                        .background(Circle().fill(Color.blue))
                        .padding(6)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .task {
            thumbnail = await photoLibrary.loadThumbnail(for: asset)
        }
    }
}

#Preview {
    RecipeImageAssignmentView()
        .modelContainer(for: [RecipeX.self], inMemory: true)
}
