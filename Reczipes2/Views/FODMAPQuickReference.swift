//
//  FODMAPQuickReference.swift
//  Reczipes2
//
//  Quick reference cards and educational content for FODMAP
//  Created on 12/20/25.
//

import SwiftUI

// MARK: - Quick Reference View

struct FODMAPQuickReferenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: FODMAPCategory = .oligosaccharides
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("FODMAP Quick Reference")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Common high FODMAP foods and their low FODMAP alternatives")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    
                    // Category Picker
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(FODMAPCategory.allCases, id: \.self) { category in
                            HStack {
                                Text(category.icon)
                                Text(category.rawValue)
                            }
                            .tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // Category info card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(selectedCategory.icon)
                                .font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedCategory.rawValue)
                                    .font(.headline)
                                Text(selectedCategory.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Text("Common High FODMAP Foods:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        FlowLayout_FMQRV(spacing: 8) {
                            ForEach(selectedCategory.examples, id: \.self) { example in
                                Text(example)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .adaptiveToneBackground(.critical, baseOpacity: 0.2)
                                    .foregroundStyle(Color.appCritical)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding()
                    .background(Color.appSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    // Substitution cards for this category
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Substitution Guide")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(substitutionsForCategory(selectedCategory)) { substitution in
                            FODMAPSubstitutionCard(substitution: substitution)
                        }
                    }
                    
                    // General tips
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Helpful Tips", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(Color.appInfo)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(text: "Start with small portions when testing new foods")
                            TipRow(text: "Read ingredient labels carefully for hidden FODMAPs")
                            TipRow(text: "Green parts of spring onions are safe, white parts are not")
                            TipRow(text: "Garlic-infused oil is safe if garlic solids are strained out")
                            TipRow(text: "Lactose-free dairy is nutritionally identical to regular dairy")
                            TipRow(text: "Canned lentils (rinsed) are lower FODMAP than dried")
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("FODMAP Guide")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func substitutionsForCategory(_ category: FODMAPCategory) -> [FODMAPSubstitution] {
        // Get all substitutions from the database that match this category
        let allSubs = FODMAPSubstitutionDatabase.shared.getAllSubstitutions()
        return allSubs.filter { substitution in
            substitution.fodmapCategories.contains(category)
        }
    }
}

// MARK: - FODMAP Substitution Card

struct FODMAPSubstitutionCard: View {
    let substitution: FODMAPSubstitution
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Original ingredient
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.appCritical)
                Text(substitution.originalIngredient.capitalized)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            // Substitutes
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                        .font(.caption)
                    Text("Substitute with:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                ForEach(Array(substitution.substitutes.prefix(2))) { substitute in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                        Text(substitute.name)
                            .font(.caption)
                        if let quantity = substitute.quantity {
                            Text("(\(quantity))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                if substitution.substitutes.count > 2 {
                    Text("+ \(substitution.substitutes.count - 2) more option\(substitution.substitutes.count - 2 == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                        .padding(.leading, 10)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
}

// MARK: - Tip Row

struct TipRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.appInfo)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout_FMQRV: Layout {
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
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
    
    struct FlowResult {
        var size: CGSize
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - FODMAP Cheat Sheet (Compact Version)

struct FODMAPCheatSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FODMAP Cheat Sheet")
                .font(.title2)
                .fontWeight(.bold)
            
            // Quick swaps
            VStack(alignment: .leading, spacing: 8) {
                CheatSheetRow(
                    avoid: "Onion/Garlic",
                    use: "Spring onion greens, garlic-infused oil",
                    icon: "🧅"
                )
                CheatSheetRow(
                    avoid: "Wheat bread",
                    use: "Gluten-free bread, sourdough spelt",
                    icon: "🍞"
                )
                CheatSheetRow(
                    avoid: "Regular milk",
                    use: "Lactose-free milk, almond milk",
                    icon: "🥛"
                )
                CheatSheetRow(
                    avoid: "Honey",
                    use: "Maple syrup, table sugar",
                    icon: "🍯"
                )
                CheatSheetRow(
                    avoid: "Apples",
                    use: "Bananas, strawberries, blueberries",
                    icon: "🍎"
                )
                CheatSheetRow(
                    avoid: "Mushrooms",
                    use: "Eggplant, zucchini",
                    icon: "🍄"
                )
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct CheatSheetRow: View {
    let avoid: String
    let use: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(Color.appCritical)
                    Text(avoid)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(Color.appSuccess)
                    Text(use)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}



// MARK: - Preview

#Preview("Quick Reference") {
    FODMAPQuickReferenceView()
}

#Preview("Cheat Sheet") {
    FODMAPCheatSheet()
        .padding()
}
