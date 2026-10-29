//
//  UserDeletedBadge.swift
//  Reczipes2
//
//  Δ-163: shown on a community recipe, book or meal its owner deleted. It stays
//  on this device until this person chooses to remove it.
//

import SwiftUI

struct UserDeletedBadge: View {
    var body: some View {
        Text("User Deleted")
            .font(.caption2)
            .fontWeight(.bold)
            .statusBadgeStyle(tone: .warning)
            .accessibilityLabel("Deleted by its owner; kept on this device")
    }
}

/// One line explaining the badge, for detail screens.
struct UserDeletedNote: View {
    var kind: String = "recipe"
    var body: some View {
        HStack(spacing: 6) {
            UserDeletedBadge()
            Text("Its owner deleted this \(kind). It stays on this device until you remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
