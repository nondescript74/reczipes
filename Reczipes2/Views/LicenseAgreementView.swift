//
//  LicenseAgreementView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/16/25.
//

import SwiftUI

struct LicenseAgreementView: View {
    @Binding var isPresented: Bool
    @State private var hasScrolledToBottom = false
    @State private var hasReadLicense = false
    @State private var showingDeclineAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.appInfo)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("License Agreement")
                                .font(.title2)
                                .bold()
                            Text("Version \(LicenseHelper.currentLicenseVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Please read the following terms carefully before using Reczipes.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                }
                .padding()
                .background(Color.appSystemBackground)
                
                // License content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(LicenseHelper.licenseText)
                            .font(.system(.body, design: .default))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                        
                        // Spacer to detect scroll to bottom
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // If the content is short enough to not scroll, mark as scrolled
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    hasScrolledToBottom = true
                                }
                            }
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).minY
                                    )
                                }
                            )
                    }
                    .padding()
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    // Consider "scrolled to bottom" when close to the end
                    // Dispatch to avoid publishing state changes during a view update
                    if value < 50 && !hasScrolledToBottom {
                        DispatchQueue.main.async {
                            hasScrolledToBottom = true
                            // Haptic feedback when reaching bottom
                            #if os(iOS)
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            #endif
                        }
                    }
                }
                
                Divider()
                
                // Scroll indicator
                if !hasScrolledToBottom {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.appInfo)
                        Text("Scroll to read the entire agreement")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.appSystemBackground)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Acknowledgment checkbox
                if hasScrolledToBottom {
                    VStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hasReadLicense.toggle()
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: hasReadLicense ? "checkmark.square.fill" : "square")
                                    .font(.title2)
                                    .foregroundStyle(hasReadLicense ? .blue : .secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("I have read and agree to the terms")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text("I accept responsibility for content I use or share")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        // Action buttons
                        HStack(spacing: 12) {
                            Button("Decline") {
                                showingDeclineAlert = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            
                            Button("I Accept") {
                                acceptLicense()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasReadLicense)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .background(Color.appSystemBackground)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .platformNavigationBarTitleDisplayMode(.inline)
            .alert("Decline License Agreement", isPresented: $showingDeclineAlert) {
                Button("Continue Reading", role: .cancel) { }
                Button("Exit App", role: .destructive) {
                    // Exit the app
                    #if os(iOS)
                    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        exit(0)
                    }
                    #else
                    NSApplication.shared.terminate(nil)
                    #endif
                }
            } message: {
                Text("You must accept the license agreement to use Reczipes. If you decline, the app will close.")
            }
        }
        .interactiveDismissDisabled(true) // Prevent swipe to dismiss
    }
    
    private func acceptLicense() {
        // Haptic feedback
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        
        // Record acceptance
        LicenseHelper.acceptLicense()
        
        // Dismiss with animation
        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - Preference Key for Scroll Detection

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    LicenseAgreementView(isPresented: .constant(true))
}
