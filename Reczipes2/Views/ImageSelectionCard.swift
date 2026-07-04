//
//  ImageSelectionCard.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/29/26.
//

import SwiftUI

struct ImageSelectionCard: View {
    let url: String
    let isSelected: Bool
    let selectionIndex: Int?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 150)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(Color.red.opacity(0.2))
                            .frame(height: 150)
                            .overlay(
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(Color.appCritical)
                                    Text("Failed to load")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appCritical)
                                }
                            )
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 150)
                            .overlay(ProgressView())
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 32, height: 32)
                        
                        if let index = selectionIndex, index == 0 {
                            Image(systemName: "star.fill")
                                .foregroundStyle(Color.onTint)
                                .font(.system(size: 14))
                        } else if let index = selectionIndex {
                            Text("\(index + 1)")
                                .foregroundStyle(Color.onTint)
                                .font(.system(size: 14, weight: .bold))
                        } else {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.onTint)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .offset(x: -8, y: 8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
