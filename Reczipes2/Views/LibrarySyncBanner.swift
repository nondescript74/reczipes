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
    @State private var showingErrorDetail = false

    /// The private-iCloud error is the one with more to say than fits on the bar.
    private var hasErrorDetail: Bool {
        status.privateImportErrorDetail != nil && status.bannerText?.hasPrefix("iCloud sync problem") == true
    }

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
                    if hasErrorDetail {
                        Button("Details") { showingErrorDetail = true }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
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
            .contentShape(Rectangle())
            .onTapGesture { if hasErrorDetail { showingErrorDetail = true } }
            .sheet(isPresented: $showingErrorDetail) { errorDetailSheet }
        }
    }

    private var errorDetailSheet: some View {
        NavigationStack {
            List {
                if let date = status.privateImportErrorDate {
                    Section("When") {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                    }
                }
                Section {
                    Text(status.privateImportErrorDetail ?? status.privateImportError ?? "")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("iCloud error")
                } footer: {
                    Text("This is about the copy of your own library in your iCloud account. Shared recipes still come from the community library. The message clears by itself after the next successful sync.")
                }
                Section {
                    Button {
                        PlatformPasteboard.copy(detailForCopy)
                    } label: {
                        Label("Copy details", systemImage: "doc.on.doc")
                    }
                }
            }
            .navigationTitle("iCloud Sync Problem")
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingErrorDetail = false }
                }
            }
        }
        .macOSSheetFrame()
    }

    private var detailForCopy: String {
        var parts = ["Reczipes2 \(AppBuildInfo.statusLine)"]
        if let date = status.privateImportErrorDate {
            parts.append("When: \(date.formatted(date: .abbreviated, time: .standard))")
        }
        parts.append(status.privateImportErrorDetail ?? status.privateImportError ?? "")
        return parts.joined(separator: "\n")
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
