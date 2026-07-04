//
//  ExpandableImageViewer.swift
//  Reczipes2
//
//  Created for viewing recipe images with zoom and pan capabilities
//

import SwiftUI

/// A full-screen image viewer with zoom, pan, and pinch-to-zoom gestures
struct ExpandableImageViewer: View {
    let image: PlatformImage
    @Environment(\.dismiss) private var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 4.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                GeometryReader { geometry in
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    let newScale = scale * delta
                                    scale = min(max(newScale, minScale), maxScale)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    
                                    // Reset if zoomed out too much
                                    if scale < minScale {
                                        withAnimation(.spring()) {
                                            scale = minScale
                                            offset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    let newOffset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    
                                    // Only allow drag if zoomed in
                                    if scale > minScale {
                                        offset = limitOffset(newOffset, in: geometry.size)
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            // Double-tap to zoom in/out
                            withAnimation(.spring()) {
                                if scale > minScale {
                                    // Zoom out
                                    scale = minScale
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    // Zoom in
                                    scale = 2.0
                                }
                            }
                        }
                }
            }
            .navigationTitle("Image Viewer")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    HStack(spacing: 16) {
                        // Zoom out button
                        Button {
                            withAnimation(.spring()) {
                                scale = max(scale - 0.5, minScale)
                                if scale == minScale {
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .disabled(scale <= minScale)
                        
                        // Zoom in button
                        Button {
                            withAnimation(.spring()) {
                                scale = min(scale + 0.5, maxScale)
                            }
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .disabled(scale >= maxScale)
                        
                        // Reset button
                        if scale != minScale || offset != .zero {
                            Button {
                                withAnimation(.spring()) {
                                    scale = minScale
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            #endif
        }
    }
    
    /// Limits the offset to prevent dragging the image too far offscreen
    private func limitOffset(_ offset: CGSize, in size: CGSize) -> CGSize {
        // Calculate the maximum offset based on the scale
        let maxOffsetX = (size.width * (scale - 1)) / 2
        let maxOffsetY = (size.height * (scale - 1)) / 2
        
        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }
}

#Preview {
    ExpandableImageViewer(image: PlatformImage.systemSymbol("photo")!)
}
