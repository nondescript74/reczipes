//
//  ImageAssignmentDebugView.swift
//  Reczipes2
//
//  Debug view to check image assignments
//

import SwiftUI
import SwiftData

struct ImageAssignmentDebugView: View {
    @Query private var assignments: [RecipeImageAssignment]
    @Query private var savedRecipes: [RecipeX]
    
    var body: some View {
        NavigationStack {
            List {
                Section("Debug Info") {
                    Text("Total Assignments: \(assignments.count)")
                        .font(.headline)
                }
                
                Section("All Assignments") {
                    if assignments.isEmpty {
                        Text("No assignments found!")
                            .foregroundStyle(Color.appCritical)
                    } else {
                        ForEach(assignments, id: \.recipeID) { assignment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recipe ID:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(assignment.recipeID.uuidString)
                                    .font(.caption2)
                                    .monospaced()
                                
                                Text("Image Name:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(assignment.imageName)
                                    .font(.body)
                                    .bold()
                                
                                // Try to display the image
                                Image(assignment.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 100)
                                    .border(Color.blue, width: 2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("All Recipes (Bundled + SwiftData)") {
                    ForEach(RecipeCollection.shared.allRecipes(savedRecipes: savedRecipes)) { recipe in
                        VStack(alignment: .leading) {
                            Text(recipe.title ?? "No Title")
                                .font(.headline)
                            Text(recipe.id!.uuidString)
                                .font(.caption2)
                                .monospaced()
                        }
                    }
                }
            }
            .navigationTitle("Image Debug")
        }
    }
}

#Preview {
    ImageAssignmentDebugView()
        .modelContainer(for: [RecipeImageAssignment.self], inMemory: false)
}
