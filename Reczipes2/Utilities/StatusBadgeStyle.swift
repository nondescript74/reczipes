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

struct AdaptiveToneFill: View {
    @Environment(\.colorScheme) private var colorScheme
    let tone: StatusBadgeTone
    let baseOpacity: Double

    var body: some View {
        toneColor.opacity(adjustedOpacity)
    }

    private var toneColor: Color {
        switch tone {
        case .critical: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return .blue
        }
    }

    private var adjustedOpacity: Double {
        if colorScheme == .dark {
            return min(baseOpacity + 0.15, 0.5)
        }
        return baseOpacity
    }
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

    func adaptiveToneBackground(_ tone: StatusBadgeTone, baseOpacity: Double) -> some View {
        background(AdaptiveToneFill(tone: tone, baseOpacity: baseOpacity))
    }
}
