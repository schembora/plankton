//
//  PlaybackLauncher.swift
//  Plankton
//
//  Resolves an item into something playable and holds what the player needs.
//

import JellyfinAPI
import Observation
import SwiftUI

/// Turns a tapped item into a `PlaybackItem`, preferring a downloaded copy.
///
/// Shared by the two detail pages rather than written out in each: which
/// source wins, when the spinner shows, and what gets reported are one
/// behaviour, and two copies of it would drift apart the first time any of
/// them changed.
@MainActor
@Observable
final class PlaybackLauncher {

    var playback: PlaybackItem?
    var errorMessage: String?
    private(set) var isPreparing = false

    func play(_ item: BaseItemDto, jellyfin: JellyfinService, downloads: DownloadService) {
        // Prefer the downloaded copy when there is one — instant and offline-capable.
        if let itemID = item.id, let localURL = downloads.localURL(forItemID: itemID) {
            playback = PlaybackItem(
                url: localURL,
                itemID: itemID,
                startTicks: item.resumePositionTicks,
                metadata: NowPlayingMetadata(item)
            )
            return
        }

        guard !isPreparing else { return }
        isPreparing = true

        Task {
            let url = await jellyfin.playbackURL(for: item)
            isPreparing = false

            if let url {
                playback = PlaybackItem(
                    url: url,
                    itemID: item.id,
                    startTicks: item.resumePositionTicks,
                    metadata: NowPlayingMetadata(item)
                )
            } else {
                errorMessage = "This video isn't playable. The server may not support transcoding for it."
            }
        }
    }
}

extension View {

    /// The player sheet and its failure alert, which every page that can start
    /// playback needs in the same shape.
    func playbackPresentation(_ launcher: PlaybackLauncher) -> some View {
        modifier(PlaybackPresentation(launcher: launcher))
    }

    /// Swaps a play button's label for a spinner while playback is being
    /// negotiated. The spinner is overlaid rather than placed beside the label:
    /// adding a view to the button's own layout re-measures the row, so the
    /// button visibly resized the instant it was tapped.
    func playbackSpinner(isPreparing: Bool) -> some View {
        opacity(isPreparing ? 0 : 1)
            .overlay {
                if isPreparing {
                    ProgressView()
                }
            }
    }
}

private struct PlaybackPresentation: ViewModifier {

    @Bindable var launcher: PlaybackLauncher

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $launcher.playback) { playback in
                PlayerContainerView(playback: playback)
            }
            .alert("Couldn't Play Video", isPresented: .init(
                get: { launcher.errorMessage != nil },
                set: { if !$0 { launcher.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launcher.errorMessage ?? "")
            }
    }
}
