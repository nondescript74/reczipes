//
//  ImageCropView.swift
//  Reczipes2
//
//  Created for recipe extraction image cropping
//

import SwiftUI

/// Interactive image cropping view for recipe extraction
struct ImageCropView: View {
    let image: PlatformImage
    let onCrop: (PlatformImage) -> Void
    let onCancel: () -> Void
    
    @State private var cropRect: CGRect = .zero
    @State private var imageSize: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isDraggingCropRect = false
    
    private let minCropSize: CGFloat = 100
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Instructions
                        Text("Drag corners to crop")
                            .font(.subheadline)
                            .foregroundStyle(Color.onTint)
                            .padding(.vertical, 8)
                        
                        // Image with crop overlay
                        ZStack {
                            // The image
                            Image(platformImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .allowsHitTesting(false) // Let gestures pass through to overlay
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { value in
                                            lastScale = scale
                                        }
                                )
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { value in
                                            lastOffset = offset
                                        }
                                )
                            
                            // Crop rectangle overlay
                            CropOverlayView(
                                cropRect: $cropRect,
                                imageSize: imageSize,
                                viewSize: viewSize,
                                minSize: minCropSize
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .onAppear {
                            viewSize = geometry.size
                            calculateInitialCropRect(in: geometry.size)
                            
                            // Pre-warm the gesture recognizers
                            // This eliminates first-touch lag by forcing gesture setup
                            DispatchQueue.main.async {
                                // Touch the binding to trigger gesture initialization
                                let _ = self.cropRect
                            }
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            viewSize = newSize
                            if cropRect == .zero {
                                calculateInitialCropRect(in: newSize)
                            }
                        }
                        
                        // Control buttons
                        HStack(spacing: 20) {
                            Button(action: {
                                resetCrop()
                            }) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .foregroundStyle(Color.onTint)
                                    .font(.subheadline)
                            }
                            
                            Spacer()
                            
                            Button(action: onCancel) {
                                Text("Cancel")
                                    .foregroundStyle(Color.onTint)
                                    .font(.subheadline)
                            }
                            
                            Button(action: {
                                // Skip cropping, use original image
                                onCrop(image)
                            }) {
                                Text("Skip")
                                    .foregroundStyle(Color.onTint)
                                    .font(.subheadline)
                            }
                            
                            Button(action: performCrop) {
                                Text("Crop & Use")
                                    .bold()
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                    }
                }
            }
            .platformNavigationBarHidden(true)
        }
    }
    
    // MARK: - Helper Methods
    
    private func calculateInitialCropRect(in viewSize: CGSize) {
        let imageAspectRatio = image.size.width / image.size.height
        let viewAspectRatio = viewSize.width / viewSize.height
        
        var displaySize: CGSize
        
        if imageAspectRatio > viewAspectRatio {
            // Image is wider than view
            displaySize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspectRatio
            )
        } else {
            // Image is taller than view
            displaySize = CGSize(
                width: viewSize.height * imageAspectRatio,
                height: viewSize.height
            )
        }
        
        imageSize = displaySize
        
        // Start with the image size minus a small inset on each edge
        let inset: CGFloat = 10
        let cropWidth = max(displaySize.width - inset * 2, minCropSize)
        let cropHeight = max(displaySize.height - inset * 2, minCropSize)
        let x = (viewSize.width - cropWidth) / 2
        let y = (viewSize.height - cropHeight) / 2
        
        cropRect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    }
    
    private func resetCrop() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
        calculateInitialCropRect(in: viewSize)
    }
    
    private func performCrop() {
        guard let croppedImage = cropImage() else {
            AppLog.error("Failed to crop image", category: .image)
            return
        }
        
        onCrop(croppedImage)
    }
    
    private func cropImage() -> PlatformImage? {
        // Calculate the scale factor between displayed image and actual image
        let scaleX = image.size.width / imageSize.width
        let scaleY = image.size.height / imageSize.height
        
        // Calculate the crop rect in image coordinates
        let imageX = (cropRect.origin.x - (viewSize.width - imageSize.width) / 2) * scaleX
        let imageY = (cropRect.origin.y - (viewSize.height - imageSize.height) / 2) * scaleY
        let imageWidth = cropRect.width * scaleX
        let imageHeight = cropRect.height * scaleY
        
        let imageCropRect = CGRect(x: imageX, y: imageY, width: imageWidth, height: imageHeight)
        
        // Perform the crop
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: imageCropRect) else {
            return nil
        }
        
        #if os(iOS)
        return PlatformImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        #else
        return PlatformImage(cgImage: croppedCGImage)
        #endif
    }
}

// MARK: - Crop Overlay View

struct CropOverlayView: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    let viewSize: CGSize
    let minSize: CGFloat
    
    @State private var dragState: DragState = .none
    @GestureState private var gestureActive = false // Pre-warm gesture system
    
    enum DragState {
        case none
        case topLeft, topRight, bottomLeft, bottomRight
        case moving
    }
    
    private let handleSize: CGFloat = 30
    
    var body: some View {
        ZStack {
            // Dimmed overlay outside crop area
            DimmedOverlay(cropRect: cropRect, viewSize: viewSize)
            
            // Crop rectangle border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
            
            // Grid lines (rule of thirds)
            GridLines(cropRect: cropRect)
            
            // Corner handles - use overlay to prevent layout recalculation
            overlayHandles
            
            // Drag to move entire crop rect
            Rectangle()
                .fill(Color.clear)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(moveDragGesture())
        }
    }
    
    // Extract handles into a computed property to improve layout performance
    @ViewBuilder
    private var overlayHandles: some View {
        CornerHandle(position: .topLeft)
            .position(x: cropRect.minX, y: cropRect.minY)
            .highPriorityGesture(handleDragGesture(.topLeft))
        
        CornerHandle(position: .topRight)
            .position(x: cropRect.maxX, y: cropRect.minY)
            .highPriorityGesture(handleDragGesture(.topRight))
        
        CornerHandle(position: .bottomLeft)
            .position(x: cropRect.minX, y: cropRect.maxY)
            .highPriorityGesture(handleDragGesture(.bottomLeft))
        
        CornerHandle(position: .bottomRight)
            .position(x: cropRect.maxX, y: cropRect.maxY)
            .highPriorityGesture(handleDragGesture(.bottomRight))
    }
    
    // MARK: - Gestures
    
    private func handleDragGesture(_ corner: DragState) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var newRect = cropRect
                
                switch corner {
                case .topLeft:
                    let newX = min(value.location.x, cropRect.maxX - minSize)
                    let newY = min(value.location.y, cropRect.maxY - minSize)
                    newRect = CGRect(
                        x: newX,
                        y: newY,
                        width: cropRect.maxX - newX,
                        height: cropRect.maxY - newY
                    )
                    
                case .topRight:
                    let newX = max(value.location.x, cropRect.minX + minSize)
                    let newY = min(value.location.y, cropRect.maxY - minSize)
                    newRect = CGRect(
                        x: cropRect.minX,
                        y: newY,
                        width: newX - cropRect.minX,
                        height: cropRect.maxY - newY
                    )
                    
                case .bottomLeft:
                    let newX = min(value.location.x, cropRect.maxX - minSize)
                    let newY = max(value.location.y, cropRect.minY + minSize)
                    newRect = CGRect(
                        x: newX,
                        y: cropRect.minY,
                        width: cropRect.maxX - newX,
                        height: newY - cropRect.minY
                    )
                    
                case .bottomRight:
                    let newX = max(value.location.x, cropRect.minX + minSize)
                    let newY = max(value.location.y, cropRect.minY + minSize)
                    newRect = CGRect(
                        x: cropRect.minX,
                        y: cropRect.minY,
                        width: newX - cropRect.minX,
                        height: newY - cropRect.minY
                    )
                    
                default:
                    break
                }
                
                // Constrain to view bounds and update without animation
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.animation = nil
                withTransaction(transaction) {
                    cropRect = constrainRect(newRect)
                }
            }
    }
    
    private func moveDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let newX = cropRect.origin.x + value.translation.width
                let newY = cropRect.origin.y + value.translation.height
                
                var newRect = CGRect(
                    x: newX,
                    y: newY,
                    width: cropRect.width,
                    height: cropRect.height
                )
                
                // Constrain to view bounds and update without animation
                newRect = constrainRect(newRect)
                
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.animation = nil
                withTransaction(transaction) {
                    cropRect = newRect
                }
            }
    }
    
    private func constrainRect(_ rect: CGRect) -> CGRect {
        var constrained = rect
        
        // Keep within view bounds
        if constrained.minX < 0 {
            constrained.origin.x = 0
        }
        if constrained.minY < 0 {
            constrained.origin.y = 0
        }
        if constrained.maxX > viewSize.width {
            constrained.origin.x = viewSize.width - constrained.width
        }
        if constrained.maxY > viewSize.height {
            constrained.origin.y = viewSize.height - constrained.height
        }
        
        return constrained
    }
}

// MARK: - Supporting Views

struct DimmedOverlay: View {
    let cropRect: CGRect
    let viewSize: CGSize
    
    var body: some View {
        // Use Canvas for efficient rendering - draws directly to GPU
        Canvas { context, size in
            let darkColor = Color.black.opacity(0.6)
            
            // Top rectangle
            if cropRect.minY > 0 {
                context.fill(
                    Path(CGRect(x: 0, y: 0, width: size.width, height: cropRect.minY)),
                    with: .color(darkColor)
                )
            }
            
            // Bottom rectangle
            if cropRect.maxY < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: cropRect.maxY, width: size.width, height: size.height - cropRect.maxY)),
                    with: .color(darkColor)
                )
            }
            
            // Left rectangle
            if cropRect.minX > 0 {
                context.fill(
                    Path(CGRect(x: 0, y: cropRect.minY, width: cropRect.minX, height: cropRect.height)),
                    with: .color(darkColor)
                )
            }
            
            // Right rectangle
            if cropRect.maxX < size.width {
                context.fill(
                    Path(CGRect(x: cropRect.maxX, y: cropRect.minY, width: size.width - cropRect.maxX, height: cropRect.height)),
                    with: .color(darkColor)
                )
            }
        }
    }
}

struct GridLines: View {
    let cropRect: CGRect
    
    var body: some View {
        Path { path in
            // Vertical lines
            let verticalSpacing = cropRect.width / 3
            path.move(to: CGPoint(x: cropRect.minX + verticalSpacing, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.minX + verticalSpacing, y: cropRect.maxY))
            path.move(to: CGPoint(x: cropRect.minX + verticalSpacing * 2, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.minX + verticalSpacing * 2, y: cropRect.maxY))
            
            // Horizontal lines
            let horizontalSpacing = cropRect.height / 3
            path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + horizontalSpacing))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + horizontalSpacing))
            path.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + horizontalSpacing * 2))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + horizontalSpacing * 2))
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 1)
    }
}

struct CornerHandle: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let position: Position
    private let handleSize: CGFloat = 44 // Larger hit area (Apple HIG recommends 44pt)
    private let visualSize: CGFloat = 15
    
    var body: some View {
        ZStack {
            // Larger, invisible touch target for easier grabbing
            Circle()
                .fill(Color.clear)
                .frame(width: handleSize, height: handleSize)
                .contentShape(Circle()) // Define hit testing shape
            
            // Visible handle
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: visualSize, height: visualSize)
                
                Circle()
                    .stroke(Color.black, lineWidth: 2)
                    .frame(width: visualSize, height: visualSize)
            }
            .allowsHitTesting(false) // Don't interfere with gesture
        }
    }
}

// MARK: - Preview

#Preview {
    ImageCropView(
        image: PlatformImage.systemSymbol("photo")!,
        onCrop: { _ in },
        onCancel: { }
    )
}
