//
//  ImageComparisonView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/29/26.
//

import SwiftUI

struct ImageComparisonView: View {
    let original: PlatformImage
    let processed: PlatformImage
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Original")
                            .font(.headline)
                        Image(platformImage: original)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Processed (Enhanced)")
                            .font(.headline)
                        Image(platformImage: processed)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Image Comparison")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
