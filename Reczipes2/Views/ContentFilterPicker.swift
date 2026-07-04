//
//  ContentFilterPicker.swift
//  Reczipes2
//
//  Created on 1/17/26.
//

import SwiftUI

/// A segmented picker for filtering content between user's own, shared by others, and all
struct ContentFilterPicker: View {
    @Binding var selectedFilter: ContentFilterMode
    let contentType: String // "Recipes" or "Books"
    
    var body: some View {
        VStack(spacing: 8) {
            Picker("Content Filter", selection: $selectedFilter) {
                ForEach(ContentFilterMode.allCases) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Description of current filter
            HStack {
                Image(systemName: selectedFilter.systemImage)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                
                Text(filterDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .background(Color.appGroupedBackground)
    }
    
    private var filterDescription: String {
        switch selectedFilter {
        case .mine:
            return "Showing only your \(contentType.lowercased())"
        case .shared:
            return "Showing \(contentType.lowercased()) shared by others"
        }
    }
}

#Preview {
    VStack {
        ContentFilterPicker(
            selectedFilter: .constant(.mine),
            contentType: "Recipes"
        )
        
        ContentFilterPicker(
            selectedFilter: .constant(.shared),
            contentType: "Books"
        )
    }
}
