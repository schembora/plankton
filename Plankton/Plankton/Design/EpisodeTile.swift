//
//  EpisodeTile.swift
//  Plankton
//
//  The 16:9 episode tile used by horizontal strips.
//

import JellyfinAPI
import SwiftUI

/// One episode in the strip — the still, at the size Continue Watching uses.
struct EpisodeTile: View {

    let episode: BaseItemDto
    var isCurrent = false

    /// Narrower in the player, where it shares the screen with the transport.
    var width: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    MediaImage(
                        artwork: episode.artwork(.episodeStill, maxWidth: 500),
                        placeholderIcon: "tv"
                    )
                }
                .overlay(alignment: .bottom) {
                    if let progress = episode.watchedProgress {
                        WatchedProgressBar(progress: progress)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isCurrent ? Color.accentColor : .white.opacity(0.15),
                            lineWidth: isCurrent ? 2 : 0.5
                        )
                }

            VStack(alignment: .leading, spacing: 2) {
                if let label = episode.episodeLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(episode.name ?? "Episode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
        }
        .frame(width: width)
    }
}
