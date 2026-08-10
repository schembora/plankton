//
//  EpisodeTile.swift
//  Plankton
//
//  The 16:9 episode tile used by horizontal strips.
//

import JellyfinAPI
import SwiftUI

/// One episode in the strip — the still, at the size Continue Watching uses.
///
/// Takes the pieces rather than an item, so a downloaded episode renders here
/// exactly as a server one does. Only the artwork really differs between them,
/// and `Artwork` already covers that.
struct EpisodeTile: View {

    let artwork: Artwork?
    let label: String?
    let title: String
    var progress: Double?
    var isCurrent = false

    /// Narrower in the player, where it shares the screen with the transport.
    var width: CGFloat = 200

    init(
        artwork: Artwork?,
        label: String?,
        title: String,
        progress: Double? = nil,
        isCurrent: Bool = false,
        width: CGFloat = 200
    ) {
        self.artwork = artwork
        self.label = label
        self.title = title
        self.progress = progress
        self.isCurrent = isCurrent
        self.width = width
    }

    init(episode: BaseItemDto, isCurrent: Bool = false, width: CGFloat = 200) {
        self.init(
            artwork: episode.artwork(.episodeStill, maxWidth: 500),
            label: episode.episodeLabel,
            title: episode.name ?? String(localized: "Episode"),
            progress: episode.watchedProgress,
            isCurrent: isCurrent,
            width: width
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    MediaImage(artwork: artwork, placeholderIcon: "tv")
                }
                .overlay(alignment: .bottom) {
                    if let progress {
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
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
            }
        }
        .frame(width: width)
    }
}
