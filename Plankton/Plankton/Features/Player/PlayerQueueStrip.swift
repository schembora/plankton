//
//  PlayerQueueStrip.swift
//  Plankton
//
//  The rest of the season, reachable without leaving the player.
//

import JellyfinAPI
import SwiftUI

/// A horizontal run of what else this playthrough can reach.
///
/// Picking one swaps the stream inside the running engine, so moving through a
/// season costs a re-buffer rather than closing the player and opening it
/// again — which is the whole reason the queue exists.
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
                            EpisodeTile(
                                episode: item,
                                isCurrent: item.id == session.current.itemID,
                                width: 160
                            )
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
