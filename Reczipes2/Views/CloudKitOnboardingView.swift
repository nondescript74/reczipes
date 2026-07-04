//
//  CloudKitOnboardingView.swift
//  Reczipes2
//
//  Friendly onboarding UI for CloudKit community sharing setup
//

import SwiftUI

struct CloudKitOnboardingView: View {
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showDiagnosticsDetail = false
    @State private var showHelpSection = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    statusSection
                    
                    actionSection
                    
                    if let diagnostics = onboarding.diagnostics {
                        diagnosticsSection(diagnostics)
                    }
                    
                    communitySharingHelpSection
                }
                .padding()
            }
            .navigationTitle("Community Sharing Setup")
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .platformNavBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDiagnosticsDetail) {
                DiagnosticsDetailView()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 60))
                .foregroundStyle(statusColor)
                .symbolEffect(.bounce, value: onboarding.onboardingState)
            
            Text(statusTitle)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(statusMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Checklist")
                .font(.headline)
            
            if let step = onboarding.currentStep {
                OnboardingStepRow(step: step, isActive: true)
            }
            
            Divider()
            
            // Show what's working and what's not
            if let diagnostics = onboarding.diagnostics {
                ChecklistItem(
                    title: "iCloud Account",
                    status: diagnostics.accountStatus == "available",
                    detail: diagnostics.accountStatus
                )
                
                ChecklistItem(
                    title: "CloudKit Container",
                    status: diagnostics.containerAccessible,
                    detail: diagnostics.userRecordID ?? "Not accessible"
                )
                
                ChecklistItem(
                    title: "Public Database (Read)",
                    status: diagnostics.canReadFromPublic,
                    detail: diagnostics.canReadFromPublic ? "Can browse community recipes" : "Cannot access community content"
                )
                
                ChecklistItem(
                    title: "Public Database (Write)",
                    status: diagnostics.canShareToPublic,
                    detail: diagnostics.canShareToPublic ? "Can share your recipes" : "Cannot share to community"
                )
                
                ChecklistItem(
                    title: "User Discoverability",
                    status: diagnostics.userDiscoverable,
                    detail: diagnostics.userDiscoverable ? "Your name will show on shared content" : "You'll appear as 'Anonymous'"
                )
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Action Section
    
    @ViewBuilder
    private var actionSection: some View {
        VStack(spacing: 12) {
            switch onboarding.onboardingState {
            case .checking:
                ProgressView("Checking CloudKit status...")
                
            case .ready:
                successActions
                
            case .needsiCloudSignIn:
                iCloudSignInActions
                
            case .needsContainerPermission:
                containerPermissionActions
                
            case .needsPublicDBSetup:
                publicDBSetupActions
                
            case .needsUserIdentity:
                userIdentityActions
                
            case .restricted:
                restrictedActions
                
            case .failed(let error):
                failedActions(error: error)
            }
        }
        .padding()
    }
    
    // MARK: - Success State
    
    private var successActions: some View {
        VStack(spacing: 16) {
            Text("🎉 Everything is set up!")
                .font(.headline)
                .foregroundStyle(Color.appSuccess)
            
            Text("You're ready to share your recipes with the community and browse recipes shared by others.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                dismiss()
            }) {
                Label("Start Sharing", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                Task {
                    await onboarding.runComprehensiveDiagnostics()
                }
            }) {
                Label("Re-check Status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - iCloud Sign In
    
    private var iCloudSignInActions: some View {
        VStack(spacing: 16) {
            Text("Please sign in to iCloud to use community sharing features.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps:")
                    .font(.headline)
                
                OnboardingInstructionStep(number: 1, text: "Open the Settings app")
                OnboardingInstructionStep(number: 2, text: "Tap your name at the top")
                OnboardingInstructionStep(number: 3, text: "Sign in with your Apple ID")
                OnboardingInstructionStep(number: 4, text: "Enable iCloud Drive")
                OnboardingInstructionStep(number: 5, text: "Return to this app")
            }
            .padding()
            .background(Color.appTertiaryBackground)
            .cornerRadius(8)
            
            Button(action: {
                if let url = URL(string: "App-prefs:root=CASTLE") {
                    PlatformURLOpener.open(url)
                }
            }) {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                Task {
                    await onboarding.runComprehensiveDiagnostics()
                }
            }) {
                Label("I've Signed In - Recheck", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Container Permission
    
    private var containerPermissionActions: some View {
        VStack(spacing: 16) {
            Text("CloudKit container access is needed for community sharing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            Text("This usually happens automatically, but we can try to fix it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await onboarding.attemptRepair()
                }
            }) {
                Label("Request Access", systemImage: "key.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                Task {
                    await onboarding.runComprehensiveDiagnostics()
                }
            }) {
                Label("Recheck Status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Divider()
            
            troubleshootingTips
        }
    }
    
    // MARK: - Public DB Setup
    
    private var publicDBSetupActions: some View {
        VStack(spacing: 16) {
            Text("The public database needs to be initialized for community sharing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await onboarding.initializePublicDatabaseSchema()
                }
            }) {
                Label("Initialize Database", systemImage: "cylinder.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                Task {
                    await onboarding.runComprehensiveDiagnostics()
                }
            }) {
                Label("Recheck Status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - User Identity
    
    private var userIdentityActions: some View {
        VStack(spacing: 16) {
            Text("A user identity is needed to share content.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await onboarding.attemptRepair()
                }
            }) {
                Label("Create User Identity", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Restricted
    
    private var restrictedActions: some View {
        VStack(spacing: 16) {
            Text("CloudKit is restricted on this device.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            Text("This may be due to parental controls or Screen Time restrictions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("To fix this:")
                    .font(.headline)
                
                OnboardingInstructionStep(number: 1, text: "Open Settings → Screen Time")
                OnboardingInstructionStep(number: 2, text: "Tap Content & Privacy Restrictions")
                OnboardingInstructionStep(number: 3, text: "Ensure iCloud is allowed")
            }
            .padding()
            .background(Color.appTertiaryBackground)
            .cornerRadius(8)
            
            Button(action: {
                if let url = URL(string: "App-prefs:root=SCREEN_TIME") {
                    PlatformURLOpener.open(url)
                }
            }) {
                Label("Open Screen Time Settings", systemImage: "hourglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Failed State
    
    private func failedActions(error: Error) -> some View {
        VStack(spacing: 16) {
            Text("We encountered an issue setting up CloudKit.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            if let errorDetails = onboarding.errorDetails {
                Text(errorDetails)
                    .font(.caption)
                    .foregroundStyle(Color.appCritical)
                    .multilineTextAlignment(.center)
                    .padding()
                    .adaptiveToneBackground(.critical, baseOpacity: 0.1)
                    .cornerRadius(8)
            }
            
            Button(action: {
                Task {
                    await onboarding.attemptRepair()
                }
            }) {
                Label("Try to Fix", systemImage: "wrench.and.screwdriver")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button(action: {
                Task {
                    await onboarding.runComprehensiveDiagnostics()
                }
            }) {
                Label("Recheck Status", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(action: {
                showDiagnosticsDetail = true
            }) {
                Label("View Detailed Diagnostics", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Diagnostics Section
    
    private func diagnosticsSection(_ diagnostics: CloudKitOnboardingService.CloudKitDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Technical Details")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showDiagnosticsDetail = true
                }) {
                    Label("View Full Report", systemImage: "chevron.right")
                        .font(.caption)
                }
            }
            
            Text("Last checked: \(diagnostics.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack {
                Text("Environment:")
                Spacer()
                Text(diagnostics.isProductionEnvironment ? "Production" : "Development")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Troubleshooting Tips
    
    private var troubleshootingTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 Troubleshooting Tips")
                .font(.headline)
            
            Text("• Make sure you're signed into iCloud")
            Text("• Check that iCloud Drive is enabled")
            Text("• Restart the app and try again")
            Text("• If using TestFlight, make sure you're on the latest build")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding()
        .background(Color.appTertiaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - Community Sharing Help Section
    
    private var communitySharingHelpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation {
                    showHelpSection.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(Color.appInfo)
                    
                    Text("Community Sharing Help")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showHelpSection ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if showHelpSection {
                VStack(alignment: .leading, spacing: 16) {
                    // Getting Started
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Getting Started")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("If you're new to community sharing, the app will guide you through a quick setup the first time you try to share. This ensures CloudKit is properly configured on your device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Existing users: Your sharing should continue to work normally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // If You Experience Issues
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you experience issues:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HelpStep(number: "1", text: "Go to Settings → Community Sharing")
                            HelpStep(number: "2", text: "Tap Setup & Diagnostics")
                            HelpStep(number: "3", text: "Follow the on-screen instructions")
                        }
                        .font(.caption)
                    }
                    
                    Divider()
                    
                    // Reporting Issues
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A. Please provide:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HelpBullet(text: "Open Settings → Community Sharing")
                            HelpBullet(text: "Tap Setup & Diagnostics")
                            HelpBullet(text: "Screenshot the checklist")
                            HelpBullet(text: "OR export diagnostics JSON")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Common Fixes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("B. Common fixes:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HelpBullet(text: "Not signed into iCloud → Guide to Settings")
                            HelpBullet(text: "Container not accessible → Run Request Access")
                            HelpBullet(text: "Public DB not initialized → Run Initialize Database")
                            HelpBullet(text: "Restricted → Check Screen Time settings")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Advanced Troubleshooting
                    VStack(alignment: .leading, spacing: 8) {
                        Text("C. If diagnostics show ready but still failing:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HelpBullet(text: "Check CloudKit Dashboard for schema deployment")
                            HelpBullet(text: "Verify Production environment has record types")
                            HelpBullet(text: "Check for quota limits (rare)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.appTertiaryBackground)
                .cornerRadius(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color.appSecondaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: String {
        switch onboarding.onboardingState {
        case .checking: return "circle.dotted"
        case .ready: return "checkmark.circle.fill"
        case .needsiCloudSignIn: return "icloud.slash"
        case .needsContainerPermission: return "key.fill"
        case .needsPublicDBSetup: return "cylinder"
        case .needsUserIdentity: return "person.crop.circle.badge.questionmark"
        case .restricted: return "hand.raised.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        switch onboarding.onboardingState {
        case .checking: return .blue
        case .ready: return .green
        case .needsiCloudSignIn, .needsContainerPermission, .needsPublicDBSetup, .needsUserIdentity: return .orange
        case .restricted, .failed: return .red
        }
    }
    
    private var statusTitle: String {
        switch onboarding.onboardingState {
        case .checking: return "Checking Setup..."
        case .ready: return "Ready to Share!"
        case .needsiCloudSignIn: return "iCloud Sign-In Required"
        case .needsContainerPermission: return "Permission Needed"
        case .needsPublicDBSetup: return "Database Setup Required"
        case .needsUserIdentity: return "User Identity Required"
        case .restricted: return "CloudKit Restricted"
        case .failed: return "Setup Issue"
        }
    }
    
    private var statusMessage: String {
        switch onboarding.onboardingState {
        case .checking: return "Please wait while we verify your CloudKit setup..."
        case .ready: return "Your device is fully configured for community sharing."
        case .needsiCloudSignIn: return "Sign in to iCloud to enable community features."
        case .needsContainerPermission: return "We need permission to access the CloudKit container."
        case .needsPublicDBSetup: return "The community sharing database needs initialization."
        case .needsUserIdentity: return "We need to create your user identity for sharing."
        case .restricted: return "CloudKit features are restricted on this device."
        case .failed: return "We encountered an issue. Let's try to fix it."
        }
    }
}

// MARK: - Supporting Views

struct HelpStep: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(Color.appInfo)
                .frame(width: 20, alignment: .leading)
            
            Text(text)
            
            Spacer()
        }
    }
}

struct HelpBullet: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color.appInfo)
                .frame(width: 12, alignment: .leading)
            
            Text(text)
            
            Spacer()
        }
    }
}

struct ChecklistItem: View {
    let title: String
    let status: Bool
    let detail: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(status ? .green : .red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct OnboardingStepRow: View {
    let step: CloudKitOnboardingService.OnboardingStep
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if isActive {
                ProgressView()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
            }
            
            Text(stepTitle)
                .font(.subheadline)
                .foregroundStyle(isActive ? .primary : .secondary)
            
            Spacer()
        }
    }
    
    private var stepTitle: String {
        switch step {
        case .checkingAccount: return "Checking iCloud account..."
        case .requestingPermissions: return "Requesting permissions..."
        case .initializingPublicDB: return "Initializing public database..."
        case .creatingUserIdentity: return "Creating user identity..."
        case .verifyingAccess: return "Verifying access..."
        case .complete: return "Setup complete!"
        }
    }
}

struct OnboardingInstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.appInfo)
                .frame(width: 24, alignment: .leading)
            
            Text(text)
                .font(.subheadline)
            
            Spacer()
        }
    }
}

// MARK: - Diagnostics Detail View

struct DiagnosticsDetailView: View {
    @StateObject private var onboarding = CloudKitOnboardingService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if let diagnostics = onboarding.diagnostics {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(diagnostics.readableDescription)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                    }
                } else {
                    Text("No diagnostics available")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Diagnostics Report")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showShareSheet = true
                    }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let diagnostics = onboarding.diagnostics {
                    ShareSheet(items: [diagnostics.readableDescription])
                }
            }
        }
    }
}

// MARK: - Share Sheet Helper

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet: View {
    let items: [Any]
    var body: some View { MacShareView(items: items) }
}
#endif

// MARK: - Preview

#Preview {
    CloudKitOnboardingView()
}
