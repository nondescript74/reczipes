//
//  RecipeEditorView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 12/10/25.
//

import SwiftUI
import SwiftData
import PhotosUI

/// A comprehensive, guided recipe editor with separate detail views for each section
struct RecipeEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    let recipe: RecipeX
    
    // Editable properties
    @State private var title: String
    @State private var headerNotes: String
    @State private var recipeYield: String
    @State private var reference: String
    
    // Editable sections
    @State private var ingredientSections: [EditableIngredientSection]
    @State private var instructionSections: [EditableInstructionSection]
    @State private var notes: [EditableRecipeNote]
    
    @State private var showingSaveConfirmation = false
    @State private var hasUnsavedChanges = false
    
    // Navigation states for separate detail views
    @State private var showingBasicInfo = false
    @State private var showingIngredients = false
    @State private var showingInstructions = false
    @State private var showingNotes = false
    @State private var showingImages = false
    
    init(recipe: RecipeX) {
        self.recipe = recipe
        
        // Initialize state from recipe
        _title = State(initialValue: recipe.title ?? "")
        _headerNotes = State(initialValue: recipe.headerNotes ?? "")
        _recipeYield = State(initialValue: recipe.recipeYield ?? "")
        _reference = State(initialValue: recipe.reference ?? "")
        
        // Decode and convert sections
        let decoder = JSONDecoder()
        
        // Ingredient sections
        let decodedIngredients: [IngredientSection]
        if let ingredientsData = recipe.ingredientSectionsData,
           let decoded = try? decoder.decode([IngredientSection].self, from: ingredientsData) {
            decodedIngredients = decoded
        } else {
            decodedIngredients = []
        }
        _ingredientSections = State(initialValue: decodedIngredients.map { EditableIngredientSection(from: $0) })
        
        // Instruction sections
        let decodedInstructions: [InstructionSection]
        if let instructionsData = recipe.instructionSectionsData,
           let decoded = try? decoder.decode([InstructionSection].self, from: instructionsData) {
            decodedInstructions = decoded
        } else {
            decodedInstructions = []
        }
        _instructionSections = State(initialValue: decodedInstructions.map { EditableInstructionSection(from: $0) })
        
        // Notes
        let decodedNotes: [RecipeNote]
        if let notesData = recipe.notesData,
           let decoded = try? decoder.decode([RecipeNote].self, from: notesData) {
            decodedNotes = decoded
        } else {
            decodedNotes = []
        }
        _notes = State(initialValue: decodedNotes.map { EditableRecipeNote(from: $0) })
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Hero Section with Recipe Title
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        if !title.isEmpty {
                            Text(title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        } else {
                            Text("Untitled Recipe")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                        
                        if hasUnsavedChanges {
                            Label("You have unsaved changes", systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.appWarning)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)
                
                // Guide Text
                Section {
                    Text("Edit your recipe by tapping on any section below. Each part of your recipe can be edited in its own dedicated view.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Basic Information
                Section {
                    NavigationLink {
                        BasicInfoEditorView(
                            title: $title,
                            headerNotes: $headerNotes,
                            recipeYield: $recipeYield,
                            reference: $reference,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        EditorSectionRow(
                            icon: "info.circle.fill",
                            title: "Basic Information",
                            subtitle: "Title, notes, yield, and reference",
                            color: .blue,
                            isComplete: !title.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                    }
                } header: {
                    Text("Essential Details")
                }
                
                // Ingredients Section
                Section {
                    NavigationLink {
                        IngredientsEditorView(
                            sections: $ingredientSections,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        EditorSectionRow(
                            icon: "list.bullet.clipboard.fill",
                            title: "Ingredients",
                            subtitle: ingredientCountText,
                            color: .green,
                            isComplete: !ingredientSections.isEmpty
                        )
                    }
                } header: {
                    Text("What You'll Need")
                }
                
                // Instructions Section
                Section {
                    NavigationLink {
                        InstructionsEditorView(
                            sections: $instructionSections,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        EditorSectionRow(
                            icon: "list.number",
                            title: "Instructions",
                            subtitle: instructionCountText,
                            color: .orange,
                            isComplete: !instructionSections.isEmpty
                        )
                    }
                } header: {
                    Text("How to Make It")
                }
                
                // Notes Section
                Section {
                    NavigationLink {
                        NotesEditorView(
                            notes: $notes,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        EditorSectionRow(
                            icon: "note.text",
                            title: "Notes & Tips",
                            subtitle: notesCountText,
                            color: .purple,
                            isComplete: false // Notes are optional
                        )
                    }
                } header: {
                    Text("Additional Information")
                }
                
                // Images Section
                Section {
                    NavigationLink {
                        RecipeImagesEditorView(recipe: recipe)
                    } label: {
                        EditorSectionRow(
                            icon: "photo.on.rectangle.angled",
                            title: "Images",
                            subtitle: imageCountText,
                            color: .pink,
                            isComplete: recipe.imageCount > 0
                        )
                    }
                } header: {
                    Text("Visual Content")
                } footer: {
                    Text("Add additional photos to complement your recipe")
                }
            }
            .navigationTitle("Edit Recipe")
#if os(iOS)
            .platformNavigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasUnsavedChanges {
                            showingSaveConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .alert("Unsaved Changes", isPresented: $showingSaveConfirmation) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var ingredientCountText: String {
        let ingredientCount = ingredientSections.flatMap { $0.ingredients }.count
        let sectionCount = ingredientSections.count
        
        if sectionCount == 0 {
            return "No ingredients yet"
        } else if sectionCount == 1 {
            return "\(ingredientCount) ingredient\(ingredientCount == 1 ? "" : "s")"
        } else {
            return "\(ingredientCount) ingredients in \(sectionCount) sections"
        }
    }
    
    private var instructionCountText: String {
        let stepCount = instructionSections.flatMap { $0.steps }.count
        let sectionCount = instructionSections.count
        
        if sectionCount == 0 {
            return "No instructions yet"
        } else if sectionCount == 1 {
            return "\(stepCount) step\(stepCount == 1 ? "" : "s")"
        } else {
            return "\(stepCount) steps in \(sectionCount) sections"
        }
    }
    
    private var notesCountText: String {
        let count = notes.count
        if count == 0 {
            return "No notes yet"
        } else {
            return "\(count) note\(count == 1 ? "" : "s")"
        }
    }
    
    private var imageCountText: String {
        let count = recipe.imageCount
        if count == 0 {
            return "No images"
        } else if count == 1 {
            return "1 image"
        } else {
            return "\(count) images"
        }
    }
    
    private func saveChanges() {
        let encoder = JSONEncoder()
        
        // Convert editable sections back to model types
        let ingredientSectionModels = ingredientSections.map { $0.toModel() }
        let instructionSectionModels = instructionSections.map { $0.toModel() }
        let noteModels = notes.map { $0.toModel() }
        
        // Encode ingredients to check if they changed
        let newIngredientsData = try? encoder.encode(ingredientSectionModels)
        let ingredientsChanged = (newIngredientsData != recipe.ingredientSectionsData)
        
        // Update recipe properties
        recipe.title = title
        recipe.headerNotes = headerNotes.isEmpty ? nil : headerNotes
        recipe.recipeYield = recipeYield.isEmpty ? nil : recipeYield
        recipe.reference = reference.isEmpty ? nil : reference
        
        recipe.instructionSectionsData = try? encoder.encode(instructionSectionModels)
        recipe.notesData = try? encoder.encode(noteModels)
        
        // Always save ingredients, but only update hash/version if they changed
        if ingredientsChanged, let ingredientsData = newIngredientsData {
            print("📝 Ingredients changed - updating version and hash")
            recipe.updateIngredients(ingredientsData)
            
            // Clear any cached diabetic analysis since ingredients changed
            Task {
                if let recipeID = recipe.id {
                    DiabeticInfoCache.shared.clear(recipeId: recipeID)
                    print("🗑️ Cleared in-memory diabetic cache for recipe: \(recipe.title ?? "Unknown")")
                }
            }
        } else if let ingredientsData = newIngredientsData {
            // Even if ingredients didn't change, still save them (for consistency)
            recipe.ingredientSectionsData = ingredientsData
            // Still update lastModified even if ingredients didn't change
            recipe.lastModified = Date()
        } else {
            // Still update lastModified even if ingredients didn't change
            recipe.lastModified = Date()
        }
        
        // Save context
        do {
            try modelContext.save()
            print("💾 Recipe saved successfully with version \(recipe.currentVersion)")
        } catch {
            print("❌ Failed to save recipe: \(error)")
        }
        
        dismiss()
    }
}

// MARK: - Editor Section Row

/// A row displaying an editor section with icon, title, subtitle, and completion status
struct EditorSectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Basic Info Editor View

struct BasicInfoEditorView: View {
    @Binding var title: String
    @Binding var headerNotes: String
    @Binding var recipeYield: String
    @Binding var reference: String
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("Recipe Title", text: $title)
                    .font(.title3)
                    .onChange(of: title) { hasUnsavedChanges = true }
            } header: {
                Text("Recipe Title")
            } footer: {
                Text("Give your recipe a memorable name")
            }
            
            Section {
                TextField("Add header notes here...", text: $headerNotes, axis: .vertical)
                    .lineLimit(5...10)
                    .onChange(of: headerNotes) { hasUnsavedChanges = true }
            } header: {
                Text("Header Notes")
            } footer: {
                Text("Add a brief description or introduction to your recipe")
            }
            
            Section {
                TextField("e.g., Serves 4, Makes 12 cookies", text: $recipeYield)
                    .onChange(of: recipeYield) { hasUnsavedChanges = true }
            } header: {
                Text("Yield")
            } footer: {
                Text("How many servings or portions does this recipe make?")
            }
            
            Section {
                TextField("Source, book, website, or author", text: $reference)
                    .onChange(of: reference) { hasUnsavedChanges = true }
            } header: {
                Text("Reference")
            } footer: {
                Text("Where did you find this recipe?")
            }
        }
        .navigationTitle("Basic Information")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Ingredients Editor View

struct IngredientsEditorView: View {
    @Binding var sections: [EditableIngredientSection]
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var selectedSection: EditableIngredientSection?
    
    var body: some View {
        List {
            if sections.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Ingredients Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Tap the + button to add your first ingredient section")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array($sections.enumerated()), id: \.element.id) { index, $section in
                    Section {
                        NavigationLink {
                            IngredientSectionDetailView(
                                section: $section,
                                hasUnsavedChanges: $hasUnsavedChanges
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionTitle(for: section, at: index))
                                    .font(.headline)
                                
                                Text("\(section.ingredients.count) ingredient\(section.ingredients.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .onDelete { indices in
                    sections.remove(atOffsets: indices)
                    hasUnsavedChanges = true
                }
                .onMove { source, destination in
                    sections.move(fromOffsets: source, toOffset: destination)
                    hasUnsavedChanges = true
                }
            }
        }
        .navigationTitle("Ingredients")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let newSection = EditableIngredientSection()
                    sections.append(newSection)
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
            }
            
            ToolbarItem(placement: .platformNavBarTrailing) {
                PlatformEditButton()
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }
    
    // Helper function to generate contextual section titles
    private func sectionTitle(for section: EditableIngredientSection, at index: Int) -> String {
        if !section.title.isEmpty {
            return section.title
        }
        
        // If there's only one section, just call it "Ingredients"
        if sections.count == 1 {
            return "Ingredients"
        }
        
        // If multiple sections, use "Section 1", "Section 2", etc.
        return "Section \(index + 1)"
    }
}

// MARK: - Ingredient Section Detail View

struct IngredientSectionDetailView: View {
    @Binding var section: EditableIngredientSection
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var body: some View {
        Form {
            Section {
                TextField("Section Title (Optional)", text: $section.title)
                    .font(.headline)
                    .onChange(of: section.title) { hasUnsavedChanges = true }
            } header: {
                Text("Section Title")
            } footer: {
                Text("e.g., 'For the Dough', 'Sauce Ingredients', or leave blank")
            }
            
            Section {
                ForEach($section.ingredients) { $ingredient in
                    NavigationLink {
                        IngredientDetailView(
                            ingredient: $ingredient,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.name.isEmpty ? "New Ingredient" : ingredient.name)
                                .font(.body)
                            
                            if !ingredient.quantity.isEmpty || !ingredient.unit.isEmpty {
                                Text("\(ingredient.quantity) \(ingredient.unit)".trimmingCharacters(in: .whitespaces))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indices in
                    section.ingredients.remove(atOffsets: indices)
                    hasUnsavedChanges = true
                }
                .onMove { source, destination in
                    section.ingredients.move(fromOffsets: source, toOffset: destination)
                    hasUnsavedChanges = true
                }
                
                Button {
                    section.ingredients.append(EditableIngredient())
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Ingredient", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Ingredients")
            }
            
            Section {
                TextField("Transition note (Optional)", text: $section.transitionNote, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: section.transitionNote) { hasUnsavedChanges = true }
            } header: {
                Text("Transition Note")
            } footer: {
                Text("Add a note that appears after this ingredient section, like 'Set aside while preparing the next step'")
            }
        }
        .navigationTitle("Edit Section")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .platformNavBarTrailing) {
                PlatformEditButton()
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }
}

// MARK: - Ingredient Detail View

struct IngredientDetailView: View {
    @Binding var ingredient: EditableIngredient
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("Ingredient Name", text: $ingredient.name)
                    .font(.title3)
                    .onChange(of: ingredient.name) { hasUnsavedChanges = true }
            } header: {
                Text("Ingredient Name")
            } footer: {
                Text("e.g., 'All-purpose flour', 'Eggs', 'Olive oil'")
            }
            
            Section {
                HStack {
                    TextField("Amount", text: $ingredient.quantity)
                        .platformKeyboardType(.decimalPad)
                        .onChange(of: ingredient.quantity) { hasUnsavedChanges = true }
                    
                    Divider()
                    
                    TextField("Unit", text: $ingredient.unit)
                        .onChange(of: ingredient.unit) { hasUnsavedChanges = true }
                }
            } header: {
                Text("Quantity")
            } footer: {
                Text("Enter the amount and unit (e.g., '2' 'cups', '1' 'tablespoon')")
            }
            
            Section {
                TextField("Preparation instructions", text: $ingredient.preparation, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: ingredient.preparation) { hasUnsavedChanges = true }
            } header: {
                Text("Preparation")
            } footer: {
                Text("How should this ingredient be prepared? (e.g., 'diced', 'beaten', 'at room temperature')")
            }
            
            Section {
                HStack {
                    TextField("Metric Amount", text: $ingredient.metricQuantity)
                        .platformKeyboardType(.decimalPad)
                        .onChange(of: ingredient.metricQuantity) { hasUnsavedChanges = true }
                    
                    Divider()
                    
                    TextField("Metric Unit", text: $ingredient.metricUnit)
                        .onChange(of: ingredient.metricUnit) { hasUnsavedChanges = true }
                }
            } header: {
                Text("Metric Conversion (Optional)")
            } footer: {
                Text("Provide metric measurements for international users")
            }
        }
        .navigationTitle("Edit Ingredient")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Instructions Editor View

struct InstructionsEditorView: View {
    @Binding var sections: [EditableInstructionSection]
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var body: some View {
        List {
            if sections.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "list.number")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Instructions Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Tap the + button to add your first instruction section")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(Array($sections.enumerated()), id: \.element.id) { index, $section in
                    Section {
                        NavigationLink {
                            InstructionSectionDetailView(
                                section: $section,
                                hasUnsavedChanges: $hasUnsavedChanges
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionTitle(for: section, at: index))
                                    .font(.headline)
                                
                                Text("\(section.steps.count) step\(section.steps.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .onDelete { indices in
                    sections.remove(atOffsets: indices)
                    hasUnsavedChanges = true
                }
                .onMove { source, destination in
                    sections.move(fromOffsets: source, toOffset: destination)
                    hasUnsavedChanges = true
                }
            }
        }
        .navigationTitle("Instructions")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let newSection = EditableInstructionSection()
                    sections.append(newSection)
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
            }
            
            ToolbarItem(placement: .platformNavBarTrailing) {
                PlatformEditButton()
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }
    
    // Helper function to generate contextual section titles
    private func sectionTitle(for section: EditableInstructionSection, at index: Int) -> String {
        if !section.title.isEmpty {
            return section.title
        }
        
        // If there's only one section, just call it "Instructions"
        if sections.count == 1 {
            return "Instructions"
        }
        
        // If multiple sections, use "Section 1", "Section 2", etc.
        return "Section \(index + 1)"
    }
}

// MARK: - Instruction Section Detail View

struct InstructionSectionDetailView: View {
    @Binding var section: EditableInstructionSection
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var body: some View {
        Form {
            Section {
                TextField("Section Title (Optional)", text: $section.title)
                    .font(.headline)
                    .onChange(of: section.title) { hasUnsavedChanges = true }
            } header: {
                Text("Section Title")
            } footer: {
                Text("e.g., 'Preparing the Dough', 'Baking Instructions', or leave blank")
            }
            
            Section {
                ForEach($section.steps) { $step in
                    NavigationLink {
                        InstructionStepDetailView(
                            step: $step,
                            hasUnsavedChanges: $hasUnsavedChanges
                        )
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            if !step.stepNumber.isEmpty {
                                Text(step.stepNumber)
                                    .font(.headline)
                                    .foregroundStyle(Color.appWarning)
                                    .frame(width: 30, alignment: .leading)
                            }
                            
                            Text(step.text.isEmpty ? "New Step" : step.text)
                                .lineLimit(3)
                        }
                    }
                }
                .onDelete { indices in
                    section.steps.remove(atOffsets: indices)
                    hasUnsavedChanges = true
                }
                .onMove { source, destination in
                    section.steps.move(fromOffsets: source, toOffset: destination)
                    hasUnsavedChanges = true
                }
                
                Button {
                    let stepNumber = section.steps.count + 1
                    section.steps.append(EditableInstructionStep(stepNumber: "\(stepNumber)"))
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Step", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Steps")
            }
        }
        .navigationTitle("Edit Section")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .platformNavBarTrailing) {
                PlatformEditButton()
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }
}

// MARK: - Instruction Step Detail View

struct InstructionStepDetailView: View {
    @Binding var step: EditableInstructionStep
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("Step Number", text: $step.stepNumber)
                    .platformKeyboardType(.numberPad)
                    .onChange(of: step.stepNumber) { hasUnsavedChanges = true }
            } header: {
                Text("Step Number")
            } footer: {
                Text("Optional - Steps will be numbered automatically if left blank")
            }
            
            Section {
                TextEditor(text: $step.text)
                    .frame(minHeight: 200)
                    .onChange(of: step.text) { hasUnsavedChanges = true }
            } header: {
                Text("Instructions")
            } footer: {
                Text("Describe what needs to be done in this step. Be clear and detailed.")
            }
        }
        .navigationTitle("Edit Step")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Notes Editor View

struct NotesEditorView: View {
    @Binding var notes: [EditableRecipeNote]
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    
    var body: some View {
        List {
            if notes.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "note.text")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Notes Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Add tips, substitutions, warnings, or other helpful information")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach($notes, id: \.id) { note in
                    Section {
                        NavigationLink {
                            NoteDetailView(
                                note: note,
                                hasUnsavedChanges: $hasUnsavedChanges
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle")   // note.iconName
                                    .foregroundColor(.secondary)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("This is a note")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
//                                    Text(note.text.isEmpty ? "New Note" : note.text)
//                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .onDelete { indices in
                    notes.remove(atOffsets: indices)
                    hasUnsavedChanges = true
                }
            }
        }
        .navigationTitle("Notes & Tips")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    notes.append(EditableRecipeNote())
                    hasUnsavedChanges = true
                } label: {
                    Label("Add Note", systemImage: "plus")
                }
            }
            
            ToolbarItem(placement: .platformNavBarTrailing) {
                PlatformEditButton()
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, $editMode)
        #endif
    }
}

// MARK: - Note Detail View

struct NoteDetailView: View {
    @Binding var note: EditableRecipeNote
    @Binding var hasUnsavedChanges: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                Picker("Note Type", selection: $note.type) {
                    ForEach(RecipeNoteType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: note.type) { hasUnsavedChanges = true }
            } header: {
                Text("Type")
            }
            
            Section {
                TextEditor(text: $note.text)
                    .frame(minHeight: 200)
                    .onChange(of: note.text) { hasUnsavedChanges = true }
            } header: {
                Text("Note Content")
            } footer: {
                Text(note.type.helpText)
            }
        }
        .navigationTitle("Edit Note")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Recipe Images Editor View

struct RecipeImagesEditorView: View {
    let recipe: RecipeX
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var showingDeleteConfirmation = false
    @State private var imageToDelete: String?
    
    var body: some View {
        List {
            // Main Image Section
            if let mainImage = recipe.imageName {
                Section {
                    VStack(spacing: 16) {
                        RecipeImageView(
                            imageName: mainImage,
                            imageData: recipe.imageData,
                            size: CGSize(width: 300, height: 300),
                            cornerRadius: 12
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text("Main recipe image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Main Image")
                } footer: {
                    Text("The main image is set during recipe extraction and cannot be changed here.")
                }
            }
            
            // Additional Images Section
            Section {
                if let additionalImages = recipe.additionalImageNames, !additionalImages.isEmpty {
                    ForEach(additionalImages, id: \.self) { imageName in
                        HStack {
                            RecipeImageView(
                                imageName: imageName,
                                imageData: nil,
                                size: CGSize(width: 80, height: 80),
                                cornerRadius: 8
                            )
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                imageToDelete = imageName
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Color.appCritical)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No additional images")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Tap the + button to add photos")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                
                // Photo Picker Button
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Add Photo", systemImage: "plus.circle.fill")
                }
                .disabled(isProcessingImage)
                
                if isProcessingImage {
                    HStack {
                        ProgressView()
                        Text("Processing image...")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Additional Images")
            } footer: {
                Text("Add step-by-step photos or additional views of the finished dish")
            }
            
            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Tips for Great Recipe Photos", systemImage: "lightbulb.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("• Use natural lighting when possible")
                    Text("• Show key steps or techniques")
                    Text("• Include the finished dish from multiple angles")
                    Text("• Keep backgrounds clean and simple")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Images")
#if os(iOS)
        .platformNavigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                await loadImage(from: newItem)
            }
        }
        .alert("Delete Image", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let imageToDelete = imageToDelete {
                    deleteImage(imageToDelete)
                }
            }
        } message: {
            Text("Are you sure you want to delete this image? This action cannot be undone.")
        }
    }
    
    // MARK: - Image Loading
    
    private func loadImage(from photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }
        
        isProcessingImage = true
        defer { isProcessingImage = false }
        
        do {
            guard let data = try await photoItem.loadTransferable(type: Data.self),
                  let uiImage = PlatformImage(data: data) else {
                print("❌ Failed to load image data")
                return
            }
            
            // Use centralized compression utility to keep images under 100KB
            guard let jpegData = ImageCompressionUtility.compressImage(uiImage) else {
                print("❌ Failed to compress image")
                return
            }

            // Save the image
            let recipeID = recipe.id ?? UUID()
            let imageName = "recipe_\(recipeID.uuidString)_\(UUID().uuidString).jpg"
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent(imageName)

            // Write compressed data
            do {
                try jpegData.write(to: fileURL)
                
                await MainActor.run {
                    // Add to recipe's additional images
                    if recipe.additionalImageNames == nil {
                        recipe.additionalImageNames = []
                    }
                    recipe.additionalImageNames?.append(imageName)

                    // Save context
                    do {
                        try modelContext.save()
                        print("✅ Added image: \(imageName) - Size: \(ImageCompressionUtility.formatSize(jpegData.count))")
                    } catch {
                        print("❌ Failed to save context: \(error)")
                    }
                }
            } catch {
                print("❌ Error writing image: \(error)")
            }
        } catch {
            print("❌ Error loading image: \(error)")
        }
        
        // Clear the selection for next time
        await MainActor.run {
            selectedPhotoItem = nil
        }
    }
    
    // MARK: - Image Deletion
    
    private func deleteImage(_ imageName: String) {
        // Remove from recipe's additional images
        recipe.additionalImageNames?.removeAll { $0 == imageName }
        
        // Delete the file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(imageName)
        try? FileManager.default.removeItem(at: fileURL)
        
        // Save context
        do {
            try modelContext.save()
            print("✅ Deleted image: \(imageName)")
        } catch {
            print("❌ Failed to save context: \(error)")
        }
        
        imageToDelete = nil
    }
}

// MARK: - Editable Models

struct EditableIngredientSection: Identifiable {
    let id: UUID
    var title: String
    var ingredients: [EditableIngredient]
    var transitionNote: String
    
    init(id: UUID = UUID(), title: String = "", ingredients: [EditableIngredient] = [], transitionNote: String = "") {
        self.id = id
        self.title = title
        self.ingredients = ingredients.isEmpty ? [EditableIngredient()] : ingredients
        self.transitionNote = transitionNote
    }
    
    init(from section: IngredientSection) {
        self.id = section.id
        self.title = section.title ?? ""
        self.ingredients = section.ingredients.map { EditableIngredient(from: $0) }
        self.transitionNote = section.transitionNote ?? ""
    }
    
    func toModel() -> IngredientSection {
        IngredientSection(
            id: id,
            title: title.isEmpty ? nil : title,
            ingredients: ingredients.map { $0.toModel() },
            transitionNote: transitionNote.isEmpty ? nil : transitionNote
        )
    }
}

struct EditableIngredient: Identifiable {
    let id: UUID
    var quantity: String
    var unit: String
    var name: String
    var preparation: String
    var metricQuantity: String
    var metricUnit: String
    
    init(id: UUID = UUID(), quantity: String = "", unit: String = "", name: String = "",
         preparation: String = "", metricQuantity: String = "", metricUnit: String = "") {
        self.id = id
        self.quantity = quantity
        self.unit = unit
        self.name = name
        self.preparation = preparation
        self.metricQuantity = metricQuantity
        self.metricUnit = metricUnit
    }
    
    init(from ingredient: Ingredient) {
        self.id = ingredient.id
        self.quantity = ingredient.quantity ?? ""
        self.unit = ingredient.unit ?? ""
        self.name = ingredient.name
        self.preparation = ingredient.preparation ?? ""
        self.metricQuantity = ingredient.metricQuantity ?? ""
        self.metricUnit = ingredient.metricUnit ?? ""
    }
    
    func toModel() -> Ingredient {
        Ingredient(
            id: id,
            quantity: quantity.isEmpty ? nil : quantity,
            unit: unit.isEmpty ? nil : unit,
            name: name,
            preparation: preparation.isEmpty ? nil : preparation,
            metricQuantity: metricQuantity.isEmpty ? nil : metricQuantity,
            metricUnit: metricUnit.isEmpty ? nil : metricUnit
        )
    }
}

struct EditableInstructionSection: Identifiable {
    let id: UUID
    var title: String
    var steps: [EditableInstructionStep]
    
    init(id: UUID = UUID(), title: String = "", steps: [EditableInstructionStep] = []) {
        self.id = id
        self.title = title
        self.steps = steps.isEmpty ? [EditableInstructionStep()] : steps
    }
    
    init(from section: InstructionSection) {
        self.id = section.id
        self.title = section.title ?? ""
        self.steps = section.steps.map { EditableInstructionStep(from: $0) }
    }
    
    func toModel() -> InstructionSection {
        InstructionSection(
            id: id,
            title: title.isEmpty ? nil : title,
            steps: steps.map { $0.toModel() }
        )
    }
}

struct EditableInstructionStep: Identifiable {
    let id: UUID
    var stepNumber: String
    var text: String
    
    init(id: UUID = UUID(), stepNumber: String = "", text: String = "") {
        self.id = id
        self.stepNumber = stepNumber
        self.text = text
    }
    
    init(from step: InstructionStep) {
        self.id = step.id
        self.stepNumber = step.stepNumber.description
        self.text = step.text
    }
    
    func toModel() -> InstructionStep {
        InstructionStep(
            id: id,
            stepNumber: Int(stepNumber) ?? 0,
            text: text
        )
    }
}

struct EditableRecipeNote: Identifiable {
    let id: UUID
    var type: RecipeNoteType
    var text: String
    
    init(id: UUID = UUID(), type: RecipeNoteType = .general, text: String = "") {
        self.id = id
        self.type = type
        self.text = text
    }
    
    init(from note: RecipeNote) {
        self.id = note.id
        self.type = note.type
        self.text = note.text
    }
    
    func toModel() -> RecipeNote {
        RecipeNote(id: id, type: type, text: text)
    }
}

// MARK: - Editor Components

struct IngredientSectionEditor: View {
    @Binding var section: EditableIngredientSection
    let onChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Section Title (optional)", text: $section.title)
                .font(.headline)
                .onChange(of: section.title) { onChange() }
            
            ForEach($section.ingredients) { $ingredient in
                VStack(spacing: 8) {
                    HStack {
                        TextField("Qty", text: $ingredient.quantity)
                            .frame(width: 50)
                            .onChange(of: ingredient.quantity) { onChange() }
                        
                        TextField("Unit", text: $ingredient.unit)
                            .frame(width: 60)
                            .onChange(of: ingredient.unit) { onChange() }
                        
                        TextField("Ingredient Name", text: $ingredient.name)
                            .onChange(of: ingredient.name) { onChange() }
                    }
                    
                    TextField("Preparation (optional)", text: $ingredient.preparation)
                        .font(.caption)
                        .onChange(of: ingredient.preparation) { onChange() }
                }
                .padding(.vertical, 4)
            }
            .onDelete { indices in
                section.ingredients.remove(atOffsets: indices)
                onChange()
            }
            
            Button {
                section.ingredients.append(EditableIngredient())
                onChange()
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle")
                    .font(.caption)
            }
            
            TextField("Transition Note (optional)", text: $section.transitionNote)
                .font(.caption)
                .italic()
                .onChange(of: section.transitionNote) { onChange() }
            
            Divider()
        }
    }
}

struct InstructionSectionEditor: View {
    @Binding var section: EditableInstructionSection
    let onChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Section Title (optional)", text: $section.title)
                .font(.headline)
                .onChange(of: section.title) { onChange() }
            
            ForEach($section.steps) { $step in
                HStack(alignment: .top) {
                    TextField("#", text: $step.stepNumber)
                        .frame(width: 40)
                        .onChange(of: step.stepNumber) { onChange() }
                    
                    TextField("Step instructions", text: $step.text, axis: .vertical)
                        .lineLimit(2...10)
                        .onChange(of: step.text) { onChange() }
                }
                .padding(.vertical, 4)
            }
            .onDelete { indices in
                section.steps.remove(atOffsets: indices)
                onChange()
            }
            
            Button {
                section.steps.append(EditableInstructionStep())
                onChange()
            } label: {
                Label("Add Step", systemImage: "plus.circle")
                    .font(.caption)
            }
            
            Divider()
        }
    }
}

struct RecipeNoteEditor: View {
    @Binding var note: EditableRecipeNote
    let onChange: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Note Type", selection: $note.type) {
                Text("General").tag(RecipeNoteType.general)
                Text("Tip").tag(RecipeNoteType.tip)
                Text("Substitution").tag(RecipeNoteType.substitution)
                Text("Warning").tag(RecipeNoteType.warning)
                Text("Timing").tag(RecipeNoteType.timing)
            }
            .onChange(of: note.type) { onChange() }
            
            TextField("Note text", text: $note.text, axis: .vertical)
                .lineLimit(2...6)
                .onChange(of: note.text) { onChange() }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: RecipeX.self, configurations: config)
    
    // Create a sample recipe
    let encoder = JSONEncoder()
    let recipe = RecipeX(
        title: "Sample Recipe",
        headerNotes: "A delicious recipe",
        recipeYield: "Serves 4",
        ingredientSectionsData: try? encoder.encode([
            IngredientSection(ingredients: [
                Ingredient(quantity: "2", unit: "cups", name: "flour")
            ])
        ]),
        instructionSectionsData: try? encoder.encode([
            InstructionSection(steps: [
                InstructionStep(stepNumber: 1, text: "Mix ingredients")
            ])
        ])
    )
    container.mainContext.insert(recipe)
    
    return RecipeEditorView(recipe: recipe)
        .modelContainer(container)
}
