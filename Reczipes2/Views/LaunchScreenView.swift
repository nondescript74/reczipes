//
//  LaunchScreenView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/16/25.
//

import SwiftUI
import SwiftData

struct LaunchScreenView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var wipeProgress: CGFloat = 0
    @State private var imageOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var accentScale: CGFloat = 0.8
    @State private var isComplete = false
    @State private var latestFeatures: [String] = []
    
    let onComplete: () -> Void
    
    // App version information
    private var appVersion: String {
        VersionHistoryService.shared.currentVersion
    }
    
    private var buildNumber: String {
        VersionHistoryService.shared.currentBuildNumber
    }
    
    private var appName: String {
        "RecipeExtract"
    }
    
    private var logFileSize: String {
        DiagnosticLogger.shared.getFormattedLogFileSize()
    }

    private var backgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.09, green: 0.10, blue: 0.14),
                Color(red: 0.13, green: 0.11, blue: 0.16),
                Color(red: 0.16, green: 0.12, blue: 0.14),
                Color(red: 0.10, green: 0.09, blue: 0.12)
            ]
        } else {
            return [
                Color(red: 1.0, green: 0.95, blue: 0.85),
                Color(red: 0.98, green: 0.92, blue: 0.80),
                Color(red: 1.0, green: 0.88, blue: 0.70),
                Color(red: 0.95, green: 0.85, blue: 0.75)
            ]
        }
    }
    
    private var titleGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 1.0, green: 0.72, blue: 0.42),
                Color(red: 1.0, green: 0.86, blue: 0.55)
            ]
        } else {
            return [
                Color(red: 0.8, green: 0.3, blue: 0.1),
                Color(red: 0.9, green: 0.5, blue: 0.3)
            ]
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Beautiful gradient background with recipe-inspired colors
                LinearGradient(
                    colors: backgroundGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Decorative accent circles for visual interest
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(colorScheme == .dark ? 0.25 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.15)
                    .scaleEffect(accentScale)
                    .blur(radius: 20)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.pink.opacity(colorScheme == .dark ? 0.20 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 250
                        )
                    )
                    .frame(width: 500, height: 500)
                    .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.85)
                    .scaleEffect(accentScale)
                    .blur(radius: 30)
                
                // Recipe image that fades in (optional)
                if let _ = UIImage(named: "launch_recipe_image") {
                    Image("launch_recipe_image")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width * 0.5)
                        .opacity(imageOpacity * 0.15) // Very subtle background image
                        .blur(radius: 8)
                }
                
                // Main content
                VStack(spacing: 0) {
                    Spacer()
                    
                    // App Icon-style header with recipe emoji
                    VStack(spacing: 20) {
                        // Large app icon style circle
                        ZStack {
                            
                            Image("Butter-Basted-Eggs")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 90, height: 90)
                                .clipShape(.capsule, style: FillStyle(eoFill: true))
                        }
                        .scaleEffect(accentScale)
                        
                        // App name
                        Text(appName)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: titleGradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
                        
                        // Tagline
                        Text("Your Digital Recipe Collection")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .opacity(textOpacity)
                    }
                    .opacity(textOpacity)
                    
                    Spacer()
                        .frame(height: 60)
                    
                    // What's New section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.orange)
                            
                            Text("Enjoy!")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(latestFeatures, id: \.self) { feature in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(feature)
                                        .font(.system(size: 15, weight: .medium, design: .default))
                                        .foregroundColor(.primary.opacity(0.9))
                                }
                            }
                        }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 5)
                    )
                    .padding(.horizontal, 40)
                    .opacity(textOpacity)
                    
                    Spacer()
                    
                    // Version info footer
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Version")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Text(appVersion)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                            Text("•")
                            Text("Build")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Text(buildNumber)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 11))
                            Text("iCloud Sync")
                            Text("•")
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 11))
                            Text("Diagnostic Log: \(logFileSize)")
                        }
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(.bottom, 30)
                    .opacity(textOpacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Liquid Glass overlay that wipes left to right
                if wipeProgress < 1.0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: geometry.size.width * (1 - wipeProgress))
                        .glassEffect(
                            .regular.tint(
                                colorScheme == .dark
                                    ? .black.opacity(0.25)
                                    : .white.opacity(0.3)
                            )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            // Initialize version history service
            VersionHistoryService.shared.initialize(modelContext: modelContext)
            
            // Load latest features from SwiftData
            loadLatestFeatures()
            
            // Smooth animations sequence
            
            // Start background image fade
            withAnimation(.easeIn(duration: 0.4)) {
                imageOpacity = 1.0
            }
            
            // Animate accent circles
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                accentScale = 1.0
            }
            
            // Fade in text content
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                textOpacity = 1.0
            }
            
            // Wipe away liquid glass
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 1.4)) {
                    wipeProgress = 1.0
                }
            }
            
            // Complete after 2.2 seconds total
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                isComplete = true
                // Mark this version as shown
                VersionHistoryService.shared.markWhatsNewAsShown()
                onComplete()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Load the latest version's features from SwiftData
    private func loadLatestFeatures() {
        do {
            // Try to get the latest version entry from SwiftData
            if let latestEntry = try VersionHistoryService.shared.getCurrentVersionEntry() {
                latestFeatures = latestEntry.changes
            } else {
                // Fallback if no entry found
                latestFeatures = ["Welcome to Reczipes!", "📱 Your Digital Recipe Collection"]
            }
        } catch {
            // Fallback on error
            print("⚠️ Error loading version history: \(error.localizedDescription)")
            latestFeatures = ["Welcome to Reczipes!", "📱 Your Digital Recipe Collection"]
        }
    }
}

#Preview {
    LaunchScreenView {
        print("Launch screen completed")
    }
}
