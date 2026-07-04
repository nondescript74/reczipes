//
//  FODMAPProfileSettingsView.swift
//  Reczipes2
//
//  FODMAP category selection interface for user profiles
//  Created on 12/18/25.
//

import SwiftUI
import SwiftData

struct FODMAPProfileSettingsView: View {
    @Binding var sensitivity: UserFoodSensitivity
    @State private var selectedCategories: Set<FODMAPCategory>
    @State private var showInfo = false
    
    init(sensitivity: Binding<UserFoodSensitivity>) {
        self._sensitivity = sensitivity
        // Initialize with existing categories or all if none selected
        self._selectedCategories = State(initialValue: sensitivity.wrappedValue.selectedFODMAPCategories)
    }
    
    var body: some View {
        Form {
            Section {
                Text("Select which FODMAP categories affect you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button {
                    showInfo = true
                } label: {
                    Label("What is FODMAP?", systemImage: "info.circle")
                        .font(.subheadline)
                }
            }
            
            Section("FODMAP Categories") {
                ForEach(FODMAPCategory.allCases, id: \.self) { category in
                    FODMAPCategorySelectionRow(
                        category: category,
                        isSelected: selectedCategories.contains(category)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCategory(category)
                    }
                }
            }
            
            Section {
                HStack {
                    Button("Select All") {
                        selectedCategories = Set(FODMAPCategory.allCases)
                        updateSensitivity()
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    Button("Clear All") {
                        selectedCategories.removeAll()
                        updateSensitivity()
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Section {
                MonashAttributionView()
            }
        }
        .navigationTitle("FODMAP Settings")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInfo) {
            FODMAPInfoView()
        }
    }
    
    private func toggleCategory(_ category: FODMAPCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        updateSensitivity()
    }
    
    private func updateSensitivity() {
        sensitivity = UserFoodSensitivity(
            id: sensitivity.id,
            intolerance: sensitivity.intolerance,
            severity: sensitivity.severity,
            notes: sensitivity.notes,
            fodmapCategories: selectedCategories.isEmpty ? nil : selectedCategories
        )
    }
}

// MARK: - FODMAP Category Selection Row

struct FODMAPCategorySelectionRow: View {
    let category: FODMAPCategory
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .gray)
                .font(.title3)
                .imageScale(.large)
            
            // Icon
            Text(category.icon)
                .font(.title2)
            
            // Category info
            VStack(alignment: .leading, spacing: 4) {
                Text(category.rawValue)
                    .font(.headline)
                
                Text(category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - FODMAP Info View

struct FODMAPInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What is FODMAP?")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("FODMAP stands for Fermentable Oligosaccharides, Disaccharides, Monosaccharides And Polyols")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // The 4 Categories
                    VStack(alignment: .leading, spacing: 20) {
                        Text("The Four FODMAP Categories")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(FODMAPCategory.allCases, id: \.self) { category in
                            CategoryDetailCard(category: category)
                        }
                    }
                    
                    Divider()
                    
                    // Who should use it
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who should follow a low FODMAP diet?")
                            .font(.headline)
                        
                        Text("The low FODMAP diet is primarily used to manage symptoms of Irritable Bowel Syndrome (IBS) including bloating, gas, abdominal pain, diarrhea, and constipation. It should be followed under the guidance of a registered dietitian.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How does it work?")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            PhaseCard(
                                number: 1,
                                title: "Elimination Phase",
                                description: "Remove all high FODMAP foods for 2-6 weeks",
                                icon: "1.circle.fill"
                            )
                            
                            PhaseCard(
                                number: 2,
                                title: "Reintroduction Phase",
                                description: "Systematically test each FODMAP category",
                                icon: "2.circle.fill"
                            )
                            
                            PhaseCard(
                                number: 3,
                                title: "Personalization Phase",
                                description: "Create your personalized long-term diet",
                                icon: "3.circle.fill"
                            )
                        }
                    }
                    
                    Divider()
                    
                    // Monash attribution
                    MonashAttributionView()
                }
                .padding()
            }
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

// MARK: - Category Detail Card

struct CategoryDetailCard: View {
    let category: FODMAPCategory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.icon)
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.description)
                        .font(.headline)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Examples
            Text("Common sources:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            FlowLayoutFPSV(spacing: 6) {
                ForEach(category.examples, id: \.self) { example in
                    Text(example)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(Color.appInfo)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.appGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Phase Card

struct PhaseCard: View {
    let number: Int
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.appInfo)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.appGray4, lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayoutFPSV: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: result.frames[index].origin, proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    // New line
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(
                    x: currentX,
                    y: currentY,
                    width: size.width,
                    height: size.height
                ))
                
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            
            self.size = CGSize(
                width: maxWidth,
                height: currentY + lineHeight
            )
        }
    }
}

// MARK: - Preview

#Preview("FODMAP Settings") {
    NavigationStack {
        FODMAPProfileSettingsView(
            sensitivity: .constant(UserFoodSensitivity(
                intolerance: .fodmap,
                severity: .moderate,
                fodmapCategories: [.oligosaccharides, .polyols]
            ))
        )
    }
}

#Preview("FODMAP Info") {
    FODMAPInfoView()
}

//#Preview("Category Row") {
//    List {
//        FODMAPCategoryRow(categoryScore: <#T##FODMAPCategoryScore#>, category: .oligosaccharides, isSelected: false)
//        
//        FODMAPCategoryRow(
//            category: .disaccharides,
//            isSelected: false
//        )
//    }
//}
