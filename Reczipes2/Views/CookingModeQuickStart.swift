//
//  CookingModeQuickStart.swift
//  Reczipes2
//
//  Quick start guide for Cooking Mode
//

import SwiftUI

/// Quick start guide shown on first launch of cooking mode
struct CookingModeQuickStart: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    private let pages: [QuickStartPage] = [
        QuickStartPage(
            icon: "flame.fill",
            title: "Welcome to Cooking Mode",
            description: "View up to two recipes side-by-side while you cook. Perfect for following multiple recipes or keeping instructions visible hands-free.",
            color: .orange
        ),
        QuickStartPage(
            icon: "rectangle.split.2x1",
            title: "Dual Recipe View",
            description: "Select up to two recipes to view simultaneously. On iPad, they appear side-by-side. On iPhone, swipe between them.",
            color: .blue
        ),
        QuickStartPage(
            icon: "eye.fill",
            title: "Keep Awake",
            description: "Tap the eye icon to keep your screen on while cooking. No more unlocking with messy hands!",
            color: .green
        ),
        QuickStartPage(
            icon: "arrow.triangle.2.circlepath",
            title: "Easy Recipe Switching",
            description: "Use the swap button to change recipes or the X to clear a slot. Your session is automatically saved.",
            color: .purple
        )
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        QuickStartPageView(page: page)
                            .tag(index)
                    }
                }
                .platformPageTabViewStyle(indexDisplayMode: .always)
                .platformPageIndexViewStyle(backgroundDisplayMode: .always)
                
                // Bottom button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundStyle(Color.onTint)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                
                // Skip button
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Quick Start")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct QuickStartPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

private struct QuickStartPageView: View {
    let page: QuickStartPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.color)
                .symbolRenderingMode(.hierarchical)
            
            // Content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Quick Tips View

/// Compact tips view that can be shown as a popover or sheet
struct CookingModeTips: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .font(.title)
                                .foregroundStyle(.yellow)
                            
                            Text("Cooking Mode Tips")
                                .font(.title2.bold())
                        }
                        
                        Text("Make the most of your cooking experience")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    // Tips
                    CookingTipCard(
                        icon: "plus.circle.fill",
                        title: "Getting Started",
                        tip: "Tap the '+' button on an empty slot to select your first recipe. You can add up to two recipes."
                    )
                    
                    CookingTipCard(
                        icon: "eye.fill",
                        title: "Keep Screen On",
                        tip: "Enable 'Keep Awake' (eye icon) to prevent your screen from sleeping while you cook."
                    )
                    
                    CookingTipCard(
                        icon: "ipad.and.iphone",
                        title: "Device Layouts",
                        tip: "On iPad: recipes appear side-by-side. On iPhone: swipe between recipes using the page dots."
                    )
                    
                    CookingTipCard(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Swap Recipes",
                        tip: "Tap the circular swap icon to choose a different recipe without losing your other selection."
                    )
                    
                    CookingTipCard(
                        icon: "xmark.circle.fill",
                        title: "Clear Slots",
                        tip: "Tap the X button to remove a recipe from a slot. You can cook with just one recipe if you prefer."
                    )
                    
                    CookingTipCard(
                        icon: "arrow.clockwise",
                        title: "Auto-Save",
                        tip: "Your cooking session is automatically saved. Return anytime to find your recipes exactly as you left them."
                    )
                    
                    // Full help link
                    Button {
                        // This would open the full help browser
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                            Text("View Complete Help Guide")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.onTint)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Tips")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tip Card

private struct CookingTipCard: View {
    let icon: String
    let title: String
    let tip: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(tip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.appSecondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Inline Help Banner

/// Small inline help banner that can appear at the top of cooking mode
struct CookingModeHelpBanner: View {
    @Binding var isVisible: Bool
    let onShowTips: () -> Void
    
    var body: some View {
        if isVisible {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.appInfo)
                
                Text("New to Cooking Mode?")
                    .font(.subheadline)
                
                Spacer()
                
                Button("Tips") {
                    onShowTips()
                }
                .font(.subheadline.weight(.medium))
                
                Button {
                    withAnimation {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color.appSecondaryGroupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Previews

#Preview("Quick Start") {
    CookingModeQuickStart()
}

#Preview("Tips Sheet") {
    CookingModeTips()
}

#Preview("Help Banner") {
    CookingModeHelpBanner(isVisible: .constant(true)) {
        print("Show tips tapped")
    }
}
