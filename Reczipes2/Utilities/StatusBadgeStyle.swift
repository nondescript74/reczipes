//
//  StatusBadgeStyle.swift
//  Reczipes2
//

import SwiftUI

enum StatusBadgeTone {
    case critical
    case warning
    case success
    case info
}

private struct StatusBadgeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tone: StatusBadgeTone

    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch tone {
        case .critical:
            return colorScheme == .dark ? Color.red.opacity(0.35) : Color.red.opacity(0.18)
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.35) : Color.orange.opacity(0.18)
        case .success:
            return colorScheme == .dark ? Color.green.opacity(0.35) : Color.green.opacity(0.18)
        case .info:
            return colorScheme == .dark ? Color.blue.opacity(0.35) : Color.blue.opacity(0.18)
        }
    }
}

extension View {
    func statusBadgeStyle(tone: StatusBadgeTone) -> some View {
        modifier(StatusBadgeModifier(tone: tone))
    }
}
