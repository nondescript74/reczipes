//
//  AppDynamicColors.swift
//  Reczipes2
//

import SwiftUI

#if canImport(UIKit)
import UIKit

extension Color {
    /// Foreground for high-emphasis content on tinted surfaces/buttons.
    static let onTint = Color(
        UIColor { _ in
            UIColor.white
        }
    )

    static let appCritical = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
                : UIColor(red: 0.78, green: 0.12, blue: 0.12, alpha: 1.0)
        }
    )

    static let appWarning = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1.0)
                : UIColor(red: 0.78, green: 0.45, blue: 0.00, alpha: 1.0)
        }
    )

    static let appInfo = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.52, green: 0.74, blue: 1.0, alpha: 1.0)
                : UIColor(red: 0.12, green: 0.40, blue: 0.85, alpha: 1.0)
        }
    )

    static let appSuccess = Color(
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.47, green: 0.88, blue: 0.56, alpha: 1.0)
                : UIColor(red: 0.07, green: 0.55, blue: 0.24, alpha: 1.0)
        }
    )
}
#else
extension Color {
    static let onTint = Color.white

    static let appCritical = Color(red: 0.78, green: 0.12, blue: 0.12)
    static let appWarning = Color(red: 0.78, green: 0.45, blue: 0.00)
    static let appInfo = Color(red: 0.12, green: 0.40, blue: 0.85)
    static let appSuccess = Color(red: 0.07, green: 0.55, blue: 0.24)
}
#endif

struct AdaptiveToneSolidFill: View {
    @Environment(\.colorScheme) private var colorScheme
    let tone: StatusBadgeTone

    var body: some View {
        toneColor
    }

    private var toneColor: Color {
        switch tone {
        case .critical:
            return colorScheme == .dark ? Color.red.opacity(0.85) : Color.red
        case .warning:
            return colorScheme == .dark ? Color.orange.opacity(0.85) : Color.orange
        case .success:
            return colorScheme == .dark ? Color.green.opacity(0.85) : Color.green
        case .info:
            return colorScheme == .dark ? Color.blue.opacity(0.85) : Color.blue
        }
    }
}
