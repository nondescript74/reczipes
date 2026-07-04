//
//  RecipeImageView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/4/25.
//

import SwiftUI

/// A view that displays a recipe's image with a fallback placeholder
/// Supports SwiftData imageData (CloudKit-synced), Assets catalog, and Documents directory files
struct RecipeImageView: View {
    let imageName: String?
    let imageData: Data? // NEW: Direct image data from SwiftData (CloudKit-synced)
    let size: CGSize?
    let aspectRatio: ContentMode
    let cornerRadius: CGFloat
    
    @State private var loadedImage: PlatformImage?
    
    init(imageName: String?, 
         imageData: Data? = nil, // NEW: Optional image data parameter
         size: CGSize? = CGSize(width: 100, height: 100),
         aspectRatio: ContentMode = .fill,
         cornerRadius: CGFloat = 8) {
        self.imageName = imageName
        self.imageData = imageData
        self.size = size
        self.aspectRatio = aspectRatio
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if let loadedImage {
                // Display loaded image from documents
                if let size {
                    Image(platformImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: aspectRatio)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    Image(platformImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: aspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            } else if let imageName = imageName, let assetImage = PlatformImage(named: imageName) {
                // Try to load from Assets catalog
                if let size {
                    Image(platformImage: assetImage)
                        .resizable()
                        .aspectRatio(contentMode: aspectRatio)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    Image(platformImage: assetImage)
                        .resizable()
                        .aspectRatio(contentMode: aspectRatio)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            } else {
                // Placeholder
                if let size {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size.width, height: size.height)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: size.width * 0.4))
                                .foregroundStyle(.secondary)
                        )
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
        .task(id: imageName) {
            // Priority 1: Try imageData from SwiftData (CloudKit-synced)
            if let imageData, let image = PlatformImage(data: imageData) {
                loadedImage = image
                return
            }
            
            // Priority 2: Try loading from Documents directory (legacy file-based)
            if let imageName {
                if let image = loadImageFromDocuments(imageName) {
                    loadedImage = image
                    return
                }
            }
            
            // Priority 3: No image available
            loadedImage = nil
        }
        .onChange(of: imageData) { _, newValue in
            // Reload when imageData changes (e.g., after migration)
            if let newValue, let image = PlatformImage(data: newValue) {
                loadedImage = image
            }
        }
    }
    
    private func loadImageFromDocuments(_ filename: String) -> PlatformImage? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(filename)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return PlatformImage(data: data)
    }
}

#Preview("With Image") {
    RecipeImageView(imageName: "recipe1")
}

#Preview("Without Image") {
    RecipeImageView(imageName: nil)
}

#Preview("Large Size") {
    RecipeImageView(
        imageName: "recipe1",
        size: CGSize(width: 300, height: 300),
        cornerRadius: 16
    )
}
