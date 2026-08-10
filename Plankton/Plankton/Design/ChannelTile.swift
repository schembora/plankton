//
//  ChannelTile.swift
//  Plankton
//
//  A channel and what's on it, for horizontal strips.
//

import JellyfinAPI
import SwiftUI

/// The channel counterpart to `EpisodeTile`: the logo, what channel it is, and
/// whatever happens to be on it now.
struct ChannelTile: View {

    let channel: BaseItemDto
    var isCurrent = false

    /// Matches the episode tile, so a strip is the same height whichever it
    /// is showing.
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    // Logos are marks on a transparent ground with no safe
                    // area to crop into, so the whole mark is fitted and
                    // padded rather than filled.
                    MediaImage(
                        artwork: channel.artwork(.primary, maxWidth: 300),
                        placeholderIcon: "antenna.radiowaves.left.and.right",
                        contentMode: .fit
                    )
                    .padding(10)
                }
                // Channel logos are near-universally light marks on a
                // transparent ground, and many carry transparent edges rather
                // than a solid plate. Dark behind them keeps the mark readable
                // and stops the video showing through the gaps.
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isCurrent ? Color.accentColor : .white.opacity(0.15),
                            lineWidth: isCurrent ? 2 : 0.5
                        )
                }

            VStack(alignment: .leading, spacing: 2) {
                Text([channel.channelNumber, channel.name].metadataLine ?? "Channel")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // What's on now, already loaded with the line-up. Absent where
                // the server has no guide data mapped to the channel.
                if let programme = channel.currentProgram?.name {
                    Text(programme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(width: width)
    }
}
