//
//  PlayerQueueStrip.swift
//  Plankton
//
//  The rest of the season, reachable without leaving the player.
//

import JellyfinAPI
import SwiftUI

/// A horizontal run of what else this playthrough can reach: the rest of the
/// season, or the channel line-up with what's on each one.
///
/// Picking one swaps the stream inside the running engine, so moving through a
/// season or across a line-up costs a re-buffer rather than closing the player
/// and opening it again — which is the whole reason the queue exists. One
/// mechanism, two tiles, because what you need to recognise differs: an
/// episode by its still, a channel by its logo and what's on.
struct PlayerQueueStrip: View {

    @Environment(DownloadService.self) private var downloads

    @Bindable var session: PlaybackSession

    /// Fires on every pick, so the chrome's hide timer restarts rather than
    /// pulling the strip out from under a browsing thumb.
    let onInteraction: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(session.queue) { entry in
                        Button {
                            onInteraction()
                            Task { await session.switchTo(entry) }
                        } label: {
                            tile(for: entry, isCurrent: entry.itemID == session.current.itemID)
                        }
                        .buttonStyle(.plain)
                        .id(entry.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .disabled(session.isSwitching)
            // Opens on whatever is playing rather than at the start of the
            // season, and follows along as the queue moves.
            .task(id: session.current.itemID) {
                guard let itemID = session.current.itemID else { return }
                withAnimation { proxy.scrollTo(itemID, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private func tile(for entry: PlaybackQueueEntry, isCurrent: Bool) -> some View {
        if let channel = entry.channel {
            ChannelTile(channel: channel, isCurrent: isCurrent)
        } else {
            EpisodeTile(
                artwork: artwork(for: entry),
                label: entry.episodeLabel,
                title: entry.title,
                progress: entry.watchedProgress,
                isCurrent: isCurrent,
                width: 160
            )
        }
    }

    /// A download's art comes off the disk, so the strip draws the same way
    /// with no server to ask. No poster fallback: the saved 2:3 cover crops
    /// badly in a 16:9 tile, and the placeholder reads better than that does.
    private func artwork(for entry: PlaybackQueueEntry) -> Artwork? {
        switch entry {
        case let .server(item):
            item.artwork(.episodeStill, maxWidth: 500)
        case let .downloaded(media):
            .local(downloads.backdropFileURL(forItemID: media.itemID))
        }
    }
}
