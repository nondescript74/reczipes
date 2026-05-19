//
//  PhotoLibraryManager.swift
//  Reczipes2
//
//  Created for photo library access
//

import Photos
#if os(iOS)
import UIKit
#endif
import SwiftUI
import Combine

@MainActor
class PhotoLibraryManager: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var photoAssets: [PHAsset] = []
    @Published var isLoading = false
    
    init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
    
    // Request permission to access photos
    func requestPermission() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        
        if status == .authorized || status == .limited {
            await loadPhotos()
        }
    }
    
    // Load all photos from the library
    func loadPhotos() async {
        isLoading = true
        defer { isLoading = false }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1000 // Limit to 1000 most recent photos
        
        let results = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var assets: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        photoAssets = assets
        print("📷 Loaded \(assets.count) photos from library")
    }
    
    // Get UIImage for a specific asset
    func loadImage(for asset: PHAsset, targetSize: CGSize = CGSize(width: 300, height: 300)) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    // Get a thumbnail image for display in grid
    func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await loadImage(for: asset, targetSize: CGSize(width: 200, height: 200))
    }
    
    // Get full resolution image for detailed viewing
    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            options.resizeMode = .none // Request full resolution
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
