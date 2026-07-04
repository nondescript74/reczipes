//
//  NutritionalGoalsView.swift
//  Reczipes2
//
//  Created by Zahirudeen Premji on 1/2/26.
//

import SwiftUI

/// View for setting and managing nutritional goals for a user profile
struct NutritionalGoalsView: View {
    @Binding var profile: UserAllergenProfile
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedGoals: NutritionalGoals
    @State private var selectedPreset: GoalType?
    @State private var showingPresetPicker = false
    @State private var hasChanges = false
    
    init(profile: Binding<UserAllergenProfile>) {
        self._profile = profile
        // Initialize with current goals or empty
        let currentGoals = profile.wrappedValue.nutritionalGoals ?? NutritionalGoals()
        self._editedGoals = State(initialValue: currentGoals)
        self._selectedPreset = State(initialValue: currentGoals.goalType)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Preset Templates Section
                Section {
                    Button {
                        showingPresetPicker = true
                    } label: {
                        HStack {
                            Label(selectedPreset?.rawValue ?? "Choose a preset", systemImage: selectedPreset?.icon ?? "slider.horizontal.3")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Goal Template")
                } footer: {
                    if let preset = selectedPreset {
                        Text(preset.description)
                    }
                }
                
                // Macronutrients Section
                Section("Macronutrients") {
                    NutrientField(
                        title: "Daily Calories",
                        value: $editedGoals.dailyCalories,
                        unit: "kcal",
                        icon: "flame.fill",
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Protein",
                        value: $editedGoals.dailyProtein,
                        unit: "g",
                        icon: "p.circle.fill",
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Carbohydrates",
                        value: $editedGoals.dailyCarbohydrates,
                        unit: "g",
                        icon: "c.circle.fill",
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Total Fat",
                        value: $editedGoals.dailyTotalFat,
                        unit: "g",
                        icon: "f.circle.fill",
                        onChange: { hasChanges = true }
                    )
                }
                
                // Heart Health Section
                Section {
                    NutrientField(
                        title: "Saturated Fat",
                        value: $editedGoals.dailySaturatedFat,
                        unit: "g",
                        icon: "exclamationmark.triangle.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Trans Fat",
                        value: $editedGoals.dailyTransFat,
                        unit: "g",
                        icon: "exclamationmark.triangle.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Sodium",
                        value: $editedGoals.dailySodium,
                        unit: "mg",
                        icon: "drop.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Cholesterol",
                        value: $editedGoals.dailyCholesterol,
                        unit: "mg",
                        icon: "heart.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                } header: {
                    Text("Heart Health Limits")
                } footer: {
                    Text("Based on American Heart Association guidelines")
                        .font(.caption2)
                }
                
                // Blood Sugar Management Section
                Section {
                    NutrientField(
                        title: "Total Sugar",
                        value: $editedGoals.dailySugar,
                        unit: "g",
                        icon: "cube.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Added Sugar",
                        value: $editedGoals.dailyAddedSugar,
                        unit: "g",
                        icon: "cube.fill",
                        isLimit: true,
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Fiber",
                        value: $editedGoals.dailyFiber,
                        unit: "g",
                        icon: "leaf.fill",
                        onChange: { hasChanges = true }
                    )
                } header: {
                    Text("Blood Sugar Management")
                } footer: {
                    Text("Based on American Diabetes Association guidelines")
                        .font(.caption2)
                }
                
                // Additional Minerals Section
                Section("Additional Minerals") {
                    NutrientField(
                        title: "Potassium",
                        value: $editedGoals.dailyPotassium,
                        unit: "mg",
                        icon: "bolt.fill",
                        onChange: { hasChanges = true }
                    )
                    
                    NutrientField(
                        title: "Calcium",
                        value: $editedGoals.dailyCalcium,
                        unit: "mg",
                        icon: "diamond.fill",
                        onChange: { hasChanges = true }
                    )
                }
                
                // Medical Disclaimer
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Medical Disclaimer", systemImage: "info.circle.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appWarning)
                        
                        Text("These guidelines are based on recommendations from the American Heart Association, American Diabetes Association, and CDC. Always consult with your healthcare provider for personalized nutritional advice.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Nutritional Goals")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoals()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingPresetPicker) {
                PresetPickerView(selectedPreset: $selectedPreset, editedGoals: $editedGoals, hasChanges: $hasChanges)
            }
        }
    }
    
    private func saveGoals() {
        editedGoals.dateModified = Date()
        profile.nutritionalGoals = editedGoals
    }
}

// MARK: - Nutrient Field

struct NutrientField: View {
    let title: String
    @Binding var value: Double?
    let unit: String
    let icon: String
    var isLimit: Bool = false
    var onChange: () -> Void = {}
    
    @State private var textValue: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(isLimit ? .orange : .blue)
            }
            
            Spacer()
            
            TextField("Not set", text: $textValue)
                .platformKeyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($isFocused)
                .onChange(of: textValue) { _, newValue in
                    if let doubleValue = Double(newValue), doubleValue > 0 {
                        value = doubleValue
                        onChange()
                    } else if newValue.isEmpty {
                        value = nil
                        onChange()
                    }
                }
                .onAppear {
                    if let value = value {
                        textValue = String(format: "%.0f", value)
                    }
                }
            
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isFocused = false
                    }
                }
            }
        }
    }
}

// MARK: - Preset Picker

struct PresetPickerView: View {
    @Binding var selectedPreset: GoalType?
    @Binding var editedGoals: NutritionalGoals
    @Binding var hasChanges: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(GoalType.allCases, id: \.self) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: preset.icon)
                                        .foregroundStyle(Color.appInfo)
                                    Text(preset.rawValue)
                                        .font(.headline)
                                }
                                
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appInfo)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Choose Goal Type")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func applyPreset(_ preset: GoalType) {
        selectedPreset = preset
        editedGoals = NutritionalGoals.preset(for: preset)
        hasChanges = true
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var sampleProfile = UserAllergenProfile(
        name: "John Doe",
        isActive: true
    )
    
    NutritionalGoalsView(profile: $sampleProfile)
}
