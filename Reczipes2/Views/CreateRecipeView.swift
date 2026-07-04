import SwiftUI
import SwiftData

struct CreateRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Basic fields
    @State private var title: String = ""
    @State private var headerNotes: String = ""
    @State private var recipeYield: String = ""
    @State private var reference: String = ""
    
    // Image (store as PlatformImage for now; conversion happens on save)
    @State private var pickedImage: PlatformImage?
    @State private var showingPhotoPicker = false
    
    // Ingredients (sectioned)
    @State private var ingredientSections: [IngredientSection] = [
        IngredientSection(title: nil, ingredients: [Ingredient(quantity: nil, unit: nil, name: "", preparation: nil)], transitionNote: nil)
    ]
    
    // Instructions (sectioned)
    @State private var instructionSections: [InstructionSection] = [
        InstructionSection(title: nil, steps: [InstructionStep(stepNumber: 1, text: "")])
    ]
    
    // Notes
    @State private var notes: [RecipeNote] = []
    
    // MARK: - Binding helpers to reduce type-checking complexity
    private func bindingForIngredientSectionTitle(_ sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let section = ingredientSections.first(where: { $0.id == sectionID }) else { return "" }
                return section.title ?? ""
            },
            set: { newValue in
                guard let index = ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }
                ingredientSections[index].title = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForIngredientQuantity(ingredientID: UUID, in sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return ""
                }
                return ingredientSections[sectionIndex].ingredients[ingredientIndex].quantity ?? ""
            },
            set: { newValue in
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return
                }
                ingredientSections[sectionIndex].ingredients[ingredientIndex].quantity = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForIngredientUnit(ingredientID: UUID, in sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return ""
                }
                return ingredientSections[sectionIndex].ingredients[ingredientIndex].unit ?? ""
            },
            set: { newValue in
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return
                }
                ingredientSections[sectionIndex].ingredients[ingredientIndex].unit = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForIngredientName(ingredientID: UUID, in sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return ""
                }
                return ingredientSections[sectionIndex].ingredients[ingredientIndex].name
            },
            set: { newValue in
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return
                }
                ingredientSections[sectionIndex].ingredients[ingredientIndex].name = newValue
            }
        )
    }
    
    private func bindingForIngredientPrep(ingredientID: UUID, in sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return ""
                }
                return ingredientSections[sectionIndex].ingredients[ingredientIndex].preparation ?? ""
            },
            set: { newValue in
                guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
                      let ingredientIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredientID }) else {
                    return
                }
                ingredientSections[sectionIndex].ingredients[ingredientIndex].preparation = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForIngredientTransition(_ sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let section = ingredientSections.first(where: { $0.id == sectionID }) else { return "" }
                return section.transitionNote ?? ""
            },
            set: { newValue in
                guard let index = ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }
                ingredientSections[index].transitionNote = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForInstructionSectionTitle(_ sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let section = instructionSections.first(where: { $0.id == sectionID }) else { return "" }
                return section.title ?? ""
            },
            set: { newValue in
                guard let index = instructionSections.firstIndex(where: { $0.id == sectionID }) else { return }
                instructionSections[index].title = newValue.isEmpty ? nil : newValue
            }
        )
    }
    
    private func bindingForInstructionStepText(stepID: UUID, in sectionID: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }),
                      let stepIndex = instructionSections[sectionIndex].steps.firstIndex(where: { $0.id == stepID }) else {
                    return ""
                }
                return instructionSections[sectionIndex].steps[stepIndex].text
            },
            set: { newValue in
                guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }),
                      let stepIndex = instructionSections[sectionIndex].steps.firstIndex(where: { $0.id == stepID }) else {
                    return
                }
                instructionSections[sectionIndex].steps[stepIndex].text = newValue
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                imageSection
                ingredientsSection
                instructionsSection
                notesSection
            }
            .navigationTitle("New Recipe")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRecipe() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstructionsEmpty || isIngredientsEmpty)
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                ImagePicker(
                    sourceType: .photoLibrary,
                    onImageSelected: { image in
                        pickedImage = image
                    },
                    onCancel: {
                        // Sheet will dismiss automatically
                    }
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title)
                .platformTextInputAutocapitalization(.words)
            TextField("Header notes (optional)", text: $headerNotes, axis: .vertical)
            TextField("Yield (e.g. 4 servings)", text: $recipeYield)
            TextField("Reference (optional)", text: $reference)
        }
    }
    
    private var imageSection: some View {
        Section("Image") {
            HStack(spacing: 12) {
                imagePreview
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Button("Choose Photo") { showingPhotoPicker = true }
            }
        }
    }
    
    @ViewBuilder
    private var imagePreview: some View {
        if let pickedImage {
            Image(platformImage: pickedImage)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach(ingredientSections) { section in
                ingredientSectionView(section: section)
            }
            Button {
                ingredientSections.append(IngredientSection(title: nil, ingredients: [Ingredient(quantity: nil, unit: nil, name: "", preparation: nil)], transitionNote: nil))
            } label: {
                Label("Add Section", systemImage: "plus")
            }
        }
    }
    
    private func ingredientSectionView(section: IngredientSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Section title (optional)", text: bindingForIngredientSectionTitle(section.id))
                .font(.headline)
            
            ForEach(section.ingredients) { ingredient in
                ingredientRowView(ingredient: ingredient, in: section.id)
            }
            
            Button {
                guard let index = ingredientSections.firstIndex(where: { $0.id == section.id }) else { return }
                ingredientSections[index].ingredients.append(Ingredient(quantity: nil, unit: nil, name: "", preparation: nil))
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle")
            }
            
            TextField("Transition note (optional)", text: bindingForIngredientTransition(section.id), axis: .vertical)
                .font(.caption)
                .italic()
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ingredientSections.removeAll(where: { $0.id == section.id })
            } label: {
                Label("Delete Section", systemImage: "trash")
            }
        }
    }
    
    private func ingredientRowView(ingredient: Ingredient, in sectionID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Qty", text: bindingForIngredientQuantity(ingredientID: ingredient.id, in: sectionID))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                
                TextField("Unit", text: bindingForIngredientUnit(ingredientID: ingredient.id, in: sectionID))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                
                TextField("Ingredient", text: bindingForIngredientName(ingredientID: ingredient.id, in: sectionID))
                    .textFieldStyle(.roundedBorder)
                
                Button(role: .destructive) {
                    guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }
                    ingredientSections[sectionIndex].ingredients.removeAll(where: { $0.id == ingredient.id })
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Color.appCritical)
                }
                .disabled(
                    ingredientSections.first(where: { $0.id == sectionID })?.ingredients.count ?? 0 <= 1
                )
            }
            
            // Preparation field on its own row for more space
            TextField("Preparation (optional)", text: bindingForIngredientPrep(ingredientID: ingredient.id, in: sectionID))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.appGray6.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private var instructionsSection: some View {
        Section("Instructions") {
            ForEach(instructionSections) { section in
                instructionSectionView(section: section)
            }
            Button {
                instructionSections.append(InstructionSection(title: nil, steps: [InstructionStep(stepNumber: 1, text: "")]))
            } label: {
                Label("Add Section", systemImage: "plus")
            }
        }
    }
    
    private func instructionSectionView(section: InstructionSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Section title (optional)", text: bindingForInstructionSectionTitle(section.id))
            
            ForEach(section.steps) { step in
                instructionStepView(step: step, in: section.id)
            }
            
            Button {
                guard let index = instructionSections.firstIndex(where: { $0.id == section.id }) else { return }
                let nextNumber = (instructionSections[index].steps.last?.stepNumber ?? 0) + 1
                instructionSections[index].steps.append(InstructionStep(stepNumber: nextNumber, text: ""))
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                instructionSections.removeAll(where: { $0.id == section.id })
            } label: {
                Label("Delete Section", systemImage: "trash")
            }
        }
    }
    
    private func instructionStepView(step: InstructionStep, in sectionID: UUID) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.stepNumber).")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
            
            TextField("Step text", text: bindingForInstructionStepText(stepID: step.id, in: sectionID), axis: .vertical)
                .textFieldStyle(.roundedBorder)
            
            Button(role: .destructive) {
                guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }) else { return }
                instructionSections[sectionIndex].steps.removeAll(where: { $0.id == step.id })
                renumberSteps(in: sectionID)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.appCritical)
            }
            .disabled(
                instructionSections.first(where: { $0.id == sectionID })?.steps.count ?? 0 <= 1
            )
        }
        .padding(.vertical, 4)
    }
    
    private var notesSection: some View {
        Section("Notes") {
            ForEach(notes) { note in
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    noteRowView(at: index)
                }
            }
            Button {
                notes.append(RecipeNote(type: .general, text: ""))
            } label: {
                Label("Add Note", systemImage: "plus")
            }
        }
    }
    
    private func noteRowView(at i: Int) -> some View {
        HStack(alignment: .top) {
            Picker("Type", selection: $notes[i].type) {
                Text("Tip").tag(RecipeNoteType.tip)
                Text("Substitution").tag(RecipeNoteType.substitution)
                Text("Warning").tag(RecipeNoteType.warning)
                Text("Timing").tag(RecipeNoteType.timing)
                Text("General").tag(RecipeNoteType.general)
            }
            .pickerStyle(.menu)
            
            TextField("Note", text: $notes[i].text, axis: .vertical)
            
            Button(role: .destructive) {
                notes.remove(at: i)
            } label: {
                Image(systemName: "trash")
            }
        }
    }
    
    private var isIngredientsEmpty: Bool {
        ingredientSections.allSatisfy { section in
            section.ingredients.allSatisfy { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
    
    private var isInstructionsEmpty: Bool {
        instructionSections.allSatisfy { section in
            section.steps.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
    
    private func renumberSteps(in sectionID: UUID) {
        guard let sectionIndex = instructionSections.firstIndex(where: { $0.id == sectionID }) else { return }
        for i in instructionSections[sectionIndex].steps.indices {
            instructionSections[sectionIndex].steps[i].stepNumber = i + 1
        }
    }
    
    private func saveRecipe() {
        let encoder = JSONEncoder()
        guard let ingredientsData = try? encoder.encode(ingredientSections),
              let instructionsData = try? encoder.encode(instructionSections) else {
            return
        }
        
        let recipe = RecipeX(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            headerNotes: headerNotes.isEmpty ? nil : headerNotes,
            recipeYield: recipeYield.isEmpty ? nil : recipeYield,
            reference: reference.isEmpty ? nil : reference,
            imageName: nil,
            dateAdded: Date()
        )
        
        // Set sections data
        recipe.updateIngredients(ingredientsData)
        recipe.updateInstructions(instructionsData)
        
        // Notes
        if !notes.isEmpty {
            if let notesData = try? encoder.encode(notes) {
                recipe.notesData = notesData
            }
        }
        
        // Image
        if let pickedImage, let jpeg = pickedImage.jpegData(compressionQuality: 0.85) {
            recipe.setImage(PlatformImage(data: jpeg) ?? pickedImage, isMainImage: true)
        }
        
        modelContext.insert(recipe)
        do { try modelContext.save() } catch { }
        dismiss()
    }
}

#Preview {
    CreateRecipeView()
        .modelContainer(for: [RecipeX.self], inMemory: true)
}

