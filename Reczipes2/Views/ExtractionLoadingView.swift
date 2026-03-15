//
//  ExtractionLoadingView.swift
//  Reczipes2
//
//  Provides enhanced loading feedback during long-running extraction operations
//

import SwiftUI

/// A comprehensive loading view for recipe extraction operations
struct ExtractionLoadingView: View {
    let extractionType: ExtractionType
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var currentMessageIndex = 0
    @State private var showSubMessage = false
    @State private var dotAnimationPhase: CGFloat = 0
    
    enum ExtractionType {
        case image
        case url
        case link
        
        var mainIcon: String {
            switch self {
            case .image:
                return "photo.on.rectangle.angled"
            case .url:
                return "globe"
            case .link:
                return "link"
            }
        }
        
        var primaryColor: Color {
            switch self {
            case .image:
                return .blue
            case .url:
                return .purple
            case .link:
                return .green
            }
        }
        
        var messages: [String] {
            switch self {
            case .image:
                return [
                    "Analyzing your recipe image...",
                    "Claude is reading the text...",
                    "Extracting ingredients...",
                    "Processing instructions...",
                    "Almost there..."
                ]
            case .url, .link:
                return [
                    "Fetching webpage content...",
                    "Claude is analyzing the page...",
                    "Extracting recipe data...",
                    "Processing ingredients...",
                    "Organizing instructions...",
                    "Almost done..."
                ]
            }
        }
        
        var subMessage: String {
            switch self {
            case .image:
                return "This typically takes 10-30 seconds"
            case .url, .link:
                return "This typically takes 15-45 seconds"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(extractionType.primaryColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 120, height: 120)
                
                // Rotating ring
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        extractionType.primaryColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(rotation))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: rotation)
                
                // Center icon with pulse effect
                Image(systemName: extractionType.mainIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(extractionType.primaryColor)
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scale)
            }
            .onAppear {
                rotation = 360
                scale = 1.15
            }
            
            // Status messages
            VStack(spacing: 12) {
                Text(currentMessageIndex < extractionType.messages.count ? extractionType.messages[currentMessageIndex] : extractionType.messages[0])
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                    .id("message-\(currentMessageIndex)")
                
                if showSubMessage {
                    Text(extractionType.subMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(height: 60)
            
            // Activity indicators
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(extractionType.primaryColor.opacity(0.7))
                        .frame(width: 8, height: 8)
                        .scaleEffect(scale(for: index))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(extractionType.primaryColor.opacity(0.08))
                .shadow(color: extractionType.primaryColor.opacity(0.1), radius: 10)
        )
        .onAppear {
            rotation = 360
            scale = 1.15
            
            // Start dot animation
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                dotAnimationPhase = 3
            }
            
            // Show sub-message after a brief delay
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation {
                    showSubMessage = true
                }
            }
        }
        .task {
            // Rotate through messages every 3 seconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeInOut(duration: 0.5)) {
                    currentMessageIndex = (currentMessageIndex + 1) % extractionType.messages.count
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func scale(for index: Int) -> CGFloat {
        let baseScale: CGFloat = 1.0
        let maxScale: CGFloat = 1.5
        
        // Calculate which dot should be scaled based on animation phase
        let cyclePosition = dotAnimationPhase.truncatingRemainder(dividingBy: 3)
        let activeIndex = Int(cyclePosition)
        
        // Add smooth transition between dots
        let progress = cyclePosition - CGFloat(activeIndex)
        if activeIndex == index {
            return baseScale + (maxScale - baseScale) * (1 - progress)
        } else if (activeIndex + 1) % 3 == index {
            return baseScale + (maxScale - baseScale) * progress
        }
        
        return baseScale
    }
}

/// A compact version for inline use
struct CompactExtractionLoadingView: View {
    let extractionType: ExtractionLoadingView.ExtractionType
    @State private var rotation: Double = 0
    
    var body: some View {
        HStack(spacing: 16) {
            // Spinner
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        extractionType.primaryColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(rotation))
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: rotation)
                
                Image(systemName: extractionType.mainIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(extractionType.primaryColor)
            }
            .onAppear {
                rotation = 360
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Processing recipe...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Please wait")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(extractionType.primaryColor.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Image Extraction") {
    VStack(spacing: 20) {
        ExtractionLoadingView(extractionType: .image)
        
        CompactExtractionLoadingView(extractionType: .image)
    }
    .padding()
}

#Preview("URL Extraction") {
    VStack(spacing: 20) {
        ExtractionLoadingView(extractionType: .url)
        
        CompactExtractionLoadingView(extractionType: .url)
    }
    .padding()
}

#Preview("Link Extraction") {
    VStack(spacing: 20) {
        ExtractionLoadingView(extractionType: .link)
        
        CompactExtractionLoadingView(extractionType: .link)
    }
    .padding()
}
