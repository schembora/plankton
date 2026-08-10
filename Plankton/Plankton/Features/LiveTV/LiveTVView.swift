//
//  LiveTVView.swift
//  Plankton
//
//  The channel line-up, and what's on each one right now.
//

import JellyfinAPI
import SwiftUI

struct LiveTVView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads
    @Environment(PlaybackSettings.self) private var playback

    @State private var channels: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var launcher = PlaybackLauncher()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if channels.isEmpty {
                    // The tab only appears when the server has Live TV set up,
                    // so an empty line-up means a configured source with no
                    // channels behind it rather than a missing feature.
                    ContentUnavailableView(
                        "No Channels",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Your server has Live TV set up, but isn't offering any channels.")
                    )
                } else {
                    channelList
                }
            }
            .navigationTitle("Live TV")
            .task { await load() }
            .refreshable { await load() }
        }
        .playbackPresentation(launcher)
    }

    private var channelList: some View {
        List(channels) { channel in
            Button {
                // The whole line-up goes with it, so the player can change
                // channel without coming back here and rebuilding the engine.
                launcher.play(
                    channel,
                    jellyfin: jellyfin,
                    downloads: downloads,
                    settings: playback,
                    channels: channels
                )
            } label: {
                // Progress belongs on the row that was tapped. Disabling the
                // whole list while one channel opens dims every row, which
                // reads as though all of them had been selected.
                ChannelRow(channel: channel, isStarting: launcher.preparingItemID == channel.id)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    /// Channels come back as ordinary items, so the existing artwork and
    /// display helpers apply. `isAddCurrentProgram` is what fills in what's on
    /// now — without it a channel is just a name.
    private func load() async {
        var parameters = Paths.GetLiveTvChannelsParameters()
        parameters.userID = jellyfin.userID
        parameters.isAddCurrentProgram = true
        parameters.enableImageTypes = [.primary]
        parameters.enableUserData = true
        parameters.sortBy = [.sortName]

        let result = try? await jellyfin.send(Paths.getLiveTvChannels(parameters: parameters))
        channels = result?.items ?? []
        isLoading = false
    }
}

/// A channel and whatever it's showing at the moment.
private struct ChannelRow: View {

    let channel: BaseItemDto
    var isStarting = false

    var body: some View {
        HStack(spacing: 12) {
            // Logos are wide marks on a transparent ground, not posters. They
            // have no safe area to crop into, so the box holds the whole mark
            // and lets it letterbox rather than filling and cutting the middle
            // out of it.
            MediaImage(artwork: channel.artwork(.primary, maxWidth: 160), contentMode: .fit)
                .frame(width: 64, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text([channel.channelNumber, channel.name].metadataLine ?? "Channel")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let program = channel.currentProgram {
                    Text(program.name ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Opening a channel takes a moment: the server has to open the
            // live stream before anything can play.
            if isStarting {
                ProgressView()
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
