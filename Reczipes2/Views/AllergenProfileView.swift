//
//  AllergenProfileView.swift
//  Reczipes2
//
//  Created on 12/17/25.
//

import SwiftUI
import SwiftData


struct AllergenProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserAllergenProfile]
    
    @State private var showingNewProfile = false
    @State private var selectedProfile: UserAllergenProfile?
    
    var body: some View {
        NavigationStack {
            List {
                if profiles.isEmpty {
                    ContentUnavailableView(
                        "No Allergen Profiles",
                        systemImage: "allergens",
                        description: Text("Create a profile to track your food sensitivities and get recipe safety scores.")
                    )
                } else {
                    ForEach(profiles) { profile in
                        NavigationLink(destination: ProfileEditorView(profile: profile)) {
                            ProfileRow(profile: profile)
                        }
                    }
                    .onDelete(perform: deleteProfiles)
                }
            }
            .navigationTitle("Allergen Profiles")
            .toolbar {
                ToolbarItem(placement: .platformNavBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    CloudKitSyncBadge()
                }
                
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button {
                        showingNewProfile = true
                    } label: {
                        Label("New Profile", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProfile) {
                NewProfileSheet()
            }
        }
    }
    
    private func deleteProfiles(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(profiles[index])
        }
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let profile: UserAllergenProfile
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(profile.name ?? "Unnamed Profile")
                        .font(.headline)
                    
                    if profile.diabetesStatus != .none {
                        Text(profile.diabetesStatus.icon)
                            .font(.caption)
                    }
                }
                
                HStack(spacing: 8) {
                    Text("\(profile.sensitivities.count) sensitivities")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if profile.diabetesStatus != .none {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(profile.diabetesStatus.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !profile.sensitivities.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(profile.sensitivities.prefix(5)) { sensitivity in
                                Text(sensitivity.icon)
                                    .font(.caption)
                            }
                            if profile.sensitivities.count > 5 {
                                Text("+\(profile.sensitivities.count - 5)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            
            Spacer()
            
            if profile.isActive ?? false {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            } else {
                Button {
                    setActiveProfile(profile)
                } label: {
                    Text("Set Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(Color.appInfo)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func setActiveProfile(_ profile: UserAllergenProfile) {
        // Deactivate all profiles
        let descriptor = FetchDescriptor<UserAllergenProfile>()
        if let allProfiles = try? modelContext.fetch(descriptor) {
            for p in allProfiles {
                p.isActive = false
            }
        }
        // Activate selected profile
        profile.isActive = true
    }
}

// MARK: - New Profile Sheet

struct NewProfileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var profileName = ""
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Profile Name", text: $profileName)
                    .platformTextInputAutocapitalization(.words)
            }
            .navigationTitle("New Profile")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createProfile()
                    }
                    .disabled(profileName.isEmpty)
                }
            }
        }
    }
    
    private func createProfile() {
        let newProfile = UserAllergenProfile(name: profileName)
        modelContext.insert(newProfile)
        dismiss()
    }
}

// MARK: - Profile Editor View

struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserAllergenProfile
    @State private var showingAddSensitivity = false
    
    var body: some View {
        List {
            Section("Profile Info") {
                TextField("Name", text: Binding(
                    get: { profile.name ?? "" },
                    set: { profile.name = $0 }
                ))
                
                Toggle("Active Profile", isOn: Binding(
                    get: { profile.isActive ?? false },
                    set: { newValue in
                        if newValue {
                            // When activating this profile, deactivate all others
                            let descriptor = FetchDescriptor<UserAllergenProfile>()
                            if let allProfiles = try? modelContext.fetch(descriptor) {
                                for p in allProfiles where p.id != profile.id {
                                    p.isActive = false
                                }
                            }
                        }
                        profile.isActive = newValue
                    }
                ))
            }
            Section {
                if profile.isActive ?? false {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appSuccess)
                        Text("This is your active profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.appInfo)
                        Text("Set as active to use for recipe filtering")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                Picker("Diabetes Status", selection: Binding(
                    get: { profile.diabetesStatus },
                    set: { profile.diabetesStatus = $0 }
                )) {
                    ForEach(DiabetesStatus.allCases, id: \.self) { status in
                        HStack {
                            if !status.icon.isEmpty {
                                Text(status.icon)
                            }
                            Text(status.rawValue)
                        }
                        .tag(status)
                    }
                }
                .pickerStyle(.menu)
                
                if profile.diabetesStatus != .none {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.appInfo)
                        Text(profile.diabetesStatus.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Health Considerations")
            } footer: {
                Text("Set diabetes status to receive personalized recipe recommendations based on blood sugar management needs.")
            }
            
            Section {
                ForEach(profile.sensitivities) { sensitivity in
                    SensitivityRow(sensitivity: sensitivity, profile: profile)
                }
                .onDelete(perform: deleteSensitivities)
                
                Button {
                    showingAddSensitivity = true
                } label: {
                    Label("Add Sensitivity", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Food Sensitivities")
            } footer: {
                if profile.sensitivities.isEmpty {
                    Text("Add food allergens or intolerances to track.")
                }
            }
            
            Section("Daily Targets") {
                NavigationLink {
                    NutritionalGoalsView(profile: Binding(
                        get: { profile },
                        set: { newValue in
                            // The profile is already managed by SwiftData
                            // Changes will be automatically persisted
                        }
                    ))
                } label: {
                    HStack {
                        Label("Nutritional Goals", systemImage: "heart.text.square.fill")
                        Spacer()
                        if profile.hasNutritionalGoals {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        }
                    }
                }
            }
        }
        .navigationTitle(profile.name ?? "Profile")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSensitivity) {
            AddSensitivitySheet(profile: profile)
        }
    }
    
    private func deleteSensitivities(at offsets: IndexSet) {
        let sensitivities = profile.sensitivities
        for index in offsets {
            profile.removeSensitivity(id: sensitivities[index].id)
        }
    }
}

// MARK: - Sensitivity Row

struct SensitivityRow: View {
    let sensitivity: UserSensitivity
    let profile: UserAllergenProfile
    
    var body: some View {
        HStack {
            Text(sensitivity.icon)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sensitivity.name)
                    .font(.headline)
                
                HStack {
                    Text(sensitivity.severity.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severityColor)
                        .foregroundStyle(Color.onTint)
                        .clipShape(Capsule())
                    
                    Text(sensitivity.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(sensitivity.severity.icon)
        }
    }
    
    private var severityColor: Color {
        switch sensitivity.severity.color {
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - Add Sensitivity Sheet

struct AddSensitivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: UserAllergenProfile
    
    @State private var selectedTab = 0
    @State private var selectedAllergen: FoodAllergen?
    @State private var selectedIntolerance: FoodIntolerance?
    @State private var selectedSeverity: SensitivitySeverity = .moderate
    @State private var notes: String = ""
    
    var body: some View {
        NavigationStack {
            VStack {
                Picker("Type", selection: $selectedTab) {
                    Text("Big 9 Allergens").tag(0)
                    Text("Intolerances").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
                    if selectedTab == 0 {
                        Section("Select Allergen") {
                            ForEach(FoodAllergen.allCases) { allergen in
                                Button {
                                    selectedAllergen = allergen
                                    selectedIntolerance = nil
                                } label: {
                                    HStack {
                                        Text(allergen.icon)
                                        Text(allergen.rawValue)
                                        Spacer()
                                        if selectedAllergen == allergen {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.appInfo)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    } else {
                        Section("Select Intolerance") {
                            ForEach(FoodIntolerance.allCases) { intolerance in
                                Button {
                                    selectedIntolerance = intolerance
                                    selectedAllergen = nil
                                } label: {
                                    HStack {
                                        Text(intolerance.icon)
                                        Text(intolerance.rawValue)
                                        Spacer()
                                        if selectedIntolerance == intolerance {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(Color.appInfo)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                    
                    Section("Severity") {
                        Picker("Severity Level", selection: $selectedSeverity) {
                            ForEach(SensitivitySeverity.allCases) { severity in
                                HStack {
                                    Text(severity.icon)
                                    Text(severity.rawValue)
                                }
                                .tag(severity)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section("Notes (Optional)") {
                        TextField("Additional notes", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Add Sensitivity")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSensitivity()
                    }
                    .disabled(selectedAllergen == nil && selectedIntolerance == nil)
                }
            }
        }
    }
    
    private func addSensitivity() {
        let sensitivity = UserSensitivity(
            allergen: selectedAllergen,
            intolerance: selectedIntolerance,
            severity: selectedSeverity,
            notes: notes.isEmpty ? nil : notes
        )
        profile.addSensitivity(sensitivity)
        dismiss()
    }
}

#Preview {
    AllergenProfileView()
        .modelContainer(for: [UserAllergenProfile.self], inMemory: true)
}
