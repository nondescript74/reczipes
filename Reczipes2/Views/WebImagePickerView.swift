//
//  WebImagePickerView.swift
//  Reczipes2
//
//  Created for selecting images from web-extracted recipes
//

import SwiftUI
import Combine

struct WebImagePickerView: View {
    let imageURLs: [String]
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: String?
    @State private var loadingStates: [String: Bool] = [:]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Select a Recipe Image")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("Choose the image that best represents this recipe, or skip to save without an image.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    // Image grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(imageURLs, id: \.self) { urlString in
                            imageCard(for: urlString)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Choose Image")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarLeading) {
                    Button("Skip") {
                        onSelect(nil)
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button("Done") {
                        onSelect(selectedURL)
                        dismiss()
                    }
                    .disabled(selectedURL == nil)
                }
            }
        }
    }
    
    @ViewBuilder
    private func imageCard(for urlString: String) -> some View {
        Button {
            selectedURL = urlString
        } label: {
            ZStack {
                // Async image loader
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(height: 150)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 150)
                            .clipped()
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.title)
                                .foregroundStyle(Color.appCritical)
                            Text("Failed to load")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 150)
                    @unknown default:
                        EmptyView()
                    }
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(12)
                
                // Selection overlay
                if selectedURL == urlString {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 3)
                    
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.appInfo)
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    WebImagePickerView(
        imageURLs: [
            "https://www.seriouseats.com/thmb/example1.jpg",
            "https://www.seriouseats.com/thmb/example2.jpg",
            "https://www.seriouseats.com/thmb/example3.jpg"
        ],
        onSelect: { url in
            print("Selected: \(url ?? "none")")
        }
    )
}
