//
//  EpisodeRow.swift
//  Plankton
//
//  One episode in a list — still, label, title, and its download control.
//

import JellyfinAPI
import SwiftUI

/// A server episode in `EpisodeCard`'s shape, shared by the series page and
/// the full season list it opens.
///
/// The row itself opens the episode's page; only the play control starts
/// playback. Tapping the row used to play immediately, which left no way to
/// read what an episode was about before committing to it.
struct EpisodeRow: View {

    let episode: BaseItemDto
    let onPlay: () -> Void

    var body: some View {
        EpisodeCard(
            label: episode.episodeLabel,
            title: episode.name ?? "Episode",
            runtimeText: episode.runtimeText,
            watchedProgress: episode.watchedProgress
        ) {
            MediaImage(artwork: episode.artwork(.episodeStill, maxWidth: 420), placeholderIcon: "tv")
        } accessory: {
            HStack(spacing: 12) {
                DownloadButton(item: episode)
                    .font(.title3)

                Button(action: onPlay) {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play")
            }
        }
    }
}
