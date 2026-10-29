//
//  LibrarySyncBanner.swift
//  Reczipes2
//
//  A thin bar across the top of the app while this device's library is still
//  downloading or did not finish, so a half-loaded library never looks complete.
//  Hidden when everything is caught up.
//

import SwiftUI
import SwiftData

struct LibrarySyncBanner: View {
    @ObservedObject private var status = LibrarySyncStatus.shared
    @Environment(\.modelContext) private var modelContext
    @State private var retrying = false

    var body: some View {
        if let text = status.bannerText {
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    if status.isWorking || retrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundStyle(.orange)
                    }
                    Text(text)
                        .font(.footnote)
                        .lineLimit(2)
                        .accessibilityIdentifier("librarySyncBannerText")
                    Spacer(minLength: 8)
                    if status.canRetry && !retrying {
                        Button("Retry") { retry() }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
                if let fraction = status.progressFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
        }
    }

    private func retry() {
        retrying = true
        Task { @MainActor in
            defer { retrying = false }
            try? await CloudKitSharingService.shared.syncCommunityRecipesForViewing(
                modelContext: modelContext,
                limit: Int.max,
                includeSelf: true
            )
        }
    }
}
