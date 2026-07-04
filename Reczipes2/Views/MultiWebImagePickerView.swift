//
//  MultiWebImagePickerView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/29/26.
//

import SwiftUI

// MARK: - Supporting Views

struct MultiWebImagePickerView: View {
    let imageURLs: [String]
    @Binding var selectedURLs: [String]
    let onSelectionChange: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var tempSelectedURLs: [String]
    
    init(imageURLs: [String], selectedURLs: Binding<[String]>, onSelectionChange: @escaping () -> Void) {
        self.imageURLs = imageURLs
        self._selectedURLs = selectedURLs
        self.onSelectionChange = onSelectionChange
        self._tempSelectedURLs = State(initialValue: selectedURLs.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !tempSelectedURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(tempSelectedURLs.count) image\(tempSelectedURLs.count == 1 ? "" : "s") selected")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("The first image will be used as the main thumbnail")
                                .font(.caption)
                                .foregroundStyle(Color.appInfo)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                            ImageSelectionCard(
                                url: url,
                                isSelected: tempSelectedURLs.contains(url),
                                selectionIndex: tempSelectedURLs.firstIndex(of: url),
                                onTap: {
                                    toggleSelection(url)
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Select Images")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        selectedURLs = tempSelectedURLs
                        onSelectionChange()
                        dismiss()
                    }
                    .disabled(tempSelectedURLs.isEmpty)
                }
            }
        }
    }
    
    private func toggleSelection(_ url: String) {
        if let index = tempSelectedURLs.firstIndex(of: url) {
            tempSelectedURLs.remove(at: index)
        } else {
            tempSelectedURLs.append(url)
        }
    }
}

// MARK: - Preview

#Preview("Multi Image Picker") {
    MultiWebImagePickerView(
        imageURLs: [
            "https://example.com/image1.jpg",
            "https://example.com/image2.jpg",
            "https://example.com/image3.jpg"
        ],
        selectedURLs: .constant([]),
        onSelectionChange: {}
    )
}

#Preview {
    RecipeExtractorView(apiKey: "test-api-key")
}
