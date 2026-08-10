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
                launcher.play(channel, jellyfin: jellyfin, downloads: downloads, settings: playback)
            } label: {
                ChannelRow(channel: channel)
            }
            .buttonStyle(.plain)
            .disabled(launcher.isPreparing)
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

    var body: some View {
        HStack(spacing: 12) {
            // Channel logos are wide marks on a transparent ground, not
            // posters, so they get a fixed box to sit in rather than a crop.
            MediaImage(artwork: channel.artwork(.primary, maxWidth: 160))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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

            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
