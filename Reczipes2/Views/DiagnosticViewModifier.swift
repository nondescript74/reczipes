//
//  DiagnosticViewModifier.swift
//  Reczipes2
//
//  Created on 1/19/26.
//  View modifier to easily show diagnostics from anywhere in the app
//

import SwiftUI

/// Environment key for showing the diagnostic view
private struct ShowDiagnosticsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var showDiagnostics: () -> Void {
        get { self[ShowDiagnosticsKey.self] }
        set { self[ShowDiagnosticsKey.self] = newValue }
    }
}

/// View modifier that adds diagnostic capability to any view
struct DiagnosticsCapable: ViewModifier {
    @State private var showingDiagnostics = false
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    
    // Badge for unresolved failures
    private var hasUnresolvedFailures: Bool {
        !diagnosticManager.unresolvedFailures.isEmpty
    }
    
    private var failureCount: Int {
        diagnosticManager.unresolvedFailures.count
    }
    
    func body(content: Content) -> some View {
        content
            .environment(\.showDiagnostics, { showingDiagnostics = true })
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticView()
            }
    }
}

extension View {
    /// Enable diagnostic view presentation from this view
    func diagnosticsCapable() -> some View {
        modifier(DiagnosticsCapable())
    }
}

/// A button that shows the diagnostic view
struct DiagnosticButton: View {
    @Environment(\.showDiagnostics) private var showDiagnostics
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    
    var showBadge: Bool = true
    var style: Style = .icon
    
    enum Style {
        case icon
        case iconWithLabel
        case labelOnly
    }
    
    private var hasUnresolvedFailures: Bool {
        !diagnosticManager.unresolvedFailures.isEmpty
    }
    
    private var failureCount: Int {
        diagnosticManager.unresolvedFailures.count
    }
    
    var body: some View {
        Button(action: { showDiagnostics() }) {
            switch style {
            case .icon:
                iconContent
            case .iconWithLabel:
                Label("Diagnostics", systemImage: "stethoscope")
            case .labelOnly:
                Text("Diagnostics")
            }
        }
        .overlay(alignment: .topTrailing) {
            if showBadge && hasUnresolvedFailures {
                Text("\(failureCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .statusBadgeStyle(tone: .critical)
                    .offset(x: 8, y: -8)
            }
        }
    }
    
    @ViewBuilder
    private var iconContent: some View {
        Image(systemName: hasUnresolvedFailures ? "exclamationmark.triangle.fill" : "stethoscope")
            .foregroundStyle(hasUnresolvedFailures ? .red : .primary)
    }
}

/// A menu item for diagnostics (for use in menus)
struct DiagnosticMenuItem: View {
    @Environment(\.showDiagnostics) private var showDiagnostics
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    
    private var hasUnresolvedFailures: Bool {
        !diagnosticManager.unresolvedFailures.isEmpty
    }
    
    private var failureCount: Int {
        diagnosticManager.unresolvedFailures.count
    }
    
    var body: some View {
        Button(action: { showDiagnostics() }) {
            if hasUnresolvedFailures {
                Label {
                    Text("Diagnostics (\(failureCount) issues)")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.appCritical)
                }
            } else {
                Label("Diagnostics", systemImage: "stethoscope")
            }
        }
    }
}

// MARK: - Shake Gesture for Quick Diagnostics

/// Extension to detect shake gesture on iOS
#if os(iOS)
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// View modifier to show diagnostics on shake
struct ShakeToShowDiagnostics: ViewModifier {
    @Environment(\.showDiagnostics) private var showDiagnostics
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                showDiagnostics()
            }
    }
}

extension View {
    /// Show diagnostics when the device is shaken (iOS only)
    func shakeToShowDiagnostics() -> some View {
        modifier(ShakeToShowDiagnostics())
    }
}
#else
extension View {
    /// No-op stub on platforms without shake gestures.
    func shakeToShowDiagnostics() -> some View { self }
}
#endif

// MARK: - Quick Access Floating Button

/// A floating button that provides quick access to diagnostics
struct DiagnosticFloatingButton: View {
    @Environment(\.showDiagnostics) private var showDiagnostics
    @StateObject private var diagnosticManager = DiagnosticManager.shared
    @State private var isExpanded = false
    
    private var hasUnresolvedFailures: Bool {
        !diagnosticManager.unresolvedFailures.isEmpty
    }
    
    private var failureCount: Int {
        diagnosticManager.unresolvedFailures.count
    }
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                
                Button(action: { showDiagnostics() }) {
                    HStack(spacing: 8) {
                        Image(systemName: hasUnresolvedFailures ? "exclamationmark.triangle.fill" : "stethoscope")
                            .foregroundStyle(Color.onTint)
                        
                        if hasUnresolvedFailures {
                            Text("\(failureCount)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.onTint)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(hasUnresolvedFailures ? Color.red : Color.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
            }
            .padding()
        }
    }
}

extension View {
    /// Add a floating diagnostic button to the view
    func diagnosticFloatingButton() -> some View {
        overlay(alignment: .bottomTrailing) {
            DiagnosticFloatingButton()
        }
    }
}

// MARK: - Preview

#Preview("Diagnostic Button") {
    VStack(spacing: 20) {
        DiagnosticButton(style: .icon)
        DiagnosticButton(style: .iconWithLabel)
        DiagnosticButton(style: .labelOnly)
        
        Menu("More") {
            DiagnosticMenuItem()
            Button("Other Option") {}
        }
    }
    .padding()
    .diagnosticsCapable()
    .onAppear {
        // Add a sample failure for preview
        DiagnosticManager.shared.addEvent(.containerHealthCheckFailed(error: "Sample error"))
    }
}

#Preview("Floating Button") {
    NavigationStack {
        List(0..<20) { index in
            Text("Item \(index)")
        }
        .navigationTitle("Recipes")
    }
    .diagnosticFloatingButton()
    .diagnosticsCapable()
    .onAppear {
        DiagnosticManager.shared.addEvent(.containerHealthCheckFailed(error: "Sample error"))
        DiagnosticManager.shared.addEvent(.networkError(operation: "sync", error: "Timeout"))
    }
}
