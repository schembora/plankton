//
//  DownloadButton.swift
//  Plankton
//
//  Single control that starts, cancels, or removes a download for an item.
//

import JellyfinAPI
import SwiftUI

struct DownloadButton: View {

    enum Style {
        /// Glass circle next to the Play button on detail pages.
        case prominent
        /// Plain icon for episode rows and menus.
        case compact
    }

    @Environment(DownloadService.self) private var downloads

    let item: BaseItemDto
    var style: Style = .compact

    @State private var isStarting = false
    @State private var showRemoveConfirmation = false

    private var state: DownloadService.State? {
        downloads.state(for: item.id)
    }

    var body: some View {
        Group {
            switch style {
            case .prominent:
                button
                    .buttonStyle(.glass)
                    .controlSize(.large)
            case .compact:
                button
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isStarting)
        .confirmationDialog(
            "Remove Download?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Download", role: .destructive) {
                if let itemID = item.id {
                    downloads.delete(itemID: itemID)
                }
            }
            Button("Keep", role: .cancel) {}
        }
    }

    private var button: some View {
        Button(action: handleTap) {
            if isStarting {
                ProgressView()
            } else {
                label(for: state)
            }
        }
    }

    @ViewBuilder
    private func label(for state: DownloadService.State?) -> some View {
        switch state {
        case .none:
            Label("Download", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark")
                .labelStyle(.iconOnly)
        case .failed:
            Label("Retry Download", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
    }

    private func handleTap() {
        guard let itemID = item.id else { return }

        switch state {
        case .none, .failed:
            isStarting = true
            Task {
                await downloads.download(item: item)
                isStarting = false
            }
        case .downloading:
            downloads.cancelDownload(itemID: itemID)
        case .downloaded:
            showRemoveConfirmation = true
        }
    }
}
