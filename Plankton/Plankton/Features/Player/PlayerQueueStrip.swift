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

    @Bindable var session: PlaybackSession

    /// Fires on every pick, so the chrome's hide timer restarts rather than
    /// pulling the strip out from under a browsing thumb.
    let onInteraction: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(session.queue) { item in
                        Button {
                            onInteraction()
                            Task { await session.switchTo(item) }
                        } label: {
                            let isCurrent = item.id == session.current.itemID

                            if item.isLiveChannel {
                                ChannelTile(channel: item, isCurrent: isCurrent)
                            } else {
                                EpisodeTile(episode: item, isCurrent: isCurrent, width: 160)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
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
}
