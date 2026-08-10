//
//  PlaybackLauncher.swift
//  Plankton
//
//  Resolves an item into something playable and holds what the player needs.
//

import JellyfinAPI
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

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

    /// Which item is being negotiated. A list needs this to show progress on
    /// the row that was tapped: keying off `isPreparing` alone dims every row
    /// at once, which reads as though the whole list had been selected.
    private(set) var preparingItemID: String?

    /// - Parameter channels: the line-up this item belongs to, when it's a live
    ///   channel. Carried into the player so it can change channel in place.
    func play(
        _ item: BaseItemDto,
        jellyfin: JellyfinService,
        downloads: DownloadService,
        settings: PlaybackSettings,
        channels: [BaseItemDto] = []
    ) {
        // A live channel is an unbounded MPEG-TS stream. AVPlayer plays
        // progressive HTTP by asking for byte ranges, which a stream with no
        // end can't answer, so it fails on the request rather than on the
        // codec. The preference doesn't apply for the same reason it doesn't
        // apply to a downloaded file only one engine can open.
        let engine = item.isLiveChannel ? .direct : settings.engine

        // Prefer the downloaded copy when there is one — instant and offline-capable.
        if let itemID = item.id, let localURL = downloads.localURL(forItemID: itemID) {
            // The file's own format decides, not the setting: an original
            // container can't be opened by AVPlayer, and an HLS bundle can't
            // be opened by mpv.
            let required = downloads.requiredEngine(forItemID: itemID)
            logger.info("""
                Playing \(itemID, privacy: .public) from disk on \
                \((required ?? engine).rawValue, privacy: .public) \
                (file says \(required?.rawValue ?? "nothing", privacy: .public))
                """)

            playback = PlaybackItem(
                url: localURL,
                engine: required ?? engine,
                itemID: itemID,
                startTicks: item.resumePositionTicks,
                metadata: NowPlayingMetadata(item)
            )
            return
        }

        guard !isPreparing else { return }
        isPreparing = true
        preparingItemID = item.id

        Task {
            let source = await jellyfin.playbackSource(
                for: item,
                engine: engine,
                // Resolved per play rather than held: the phone can change
                // networks between one episode and the next.
                maxBitrate: settings.maxBitrate(expensive: jellyfin.isOnExpensiveNetwork)
            )
            isPreparing = false
            preparingItemID = nil

            if let source {
                playback = PlaybackItem(
                    url: source.url,
                    engine: engine,
                    isLive: source.isLive,
                    liveStreamID: source.liveStreamID,
                    itemID: item.id,
                    startTicks: item.resumePositionTicks,
                    metadata: NowPlayingMetadata(item),
                    channels: channels
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
