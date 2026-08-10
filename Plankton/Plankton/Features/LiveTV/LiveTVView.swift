//
//  LiveTVView.swift
//  Plankton
//
//  The guide: every channel, what's on it now, and what's on next.
//

import JellyfinAPI
import SwiftUI

/// How far ahead the guide asks for. Matches the grid's own window, with a
/// little slack so the last column isn't empty.
private let guideWindow: TimeInterval = 7 * 60 * 60

struct LiveTVView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads
    @Environment(PlaybackSettings.self) private var playback

    @State private var channels: [BaseItemDto] = []

    /// Programmes for the window ahead, keyed by the channel they're on.
    @State private var programmes: [String: [BaseItemDto]] = [:]

    @State private var query = ""
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
                } else if visibleChannels.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    guide
                }
            }
            .navigationTitle("Live TV")
            .navigationBarTitleDisplayMode(.inline)
            // Always shown rather than revealed by scrolling: the grid scrolls
            // in two directions, and a search field that collapses with it
            // slides around under the pinned header.
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Channels and programmes"
            )
            .task { await load() }
        }
        .playbackPresentation(launcher)
    }

    private var guide: some View {
        LiveTVGuide(
            channels: visibleChannels,
            listings: programmes,
            startingChannelID: launcher.preparingItemID,
            onRefresh: load
        ) { channel in
            // Only what's on screen goes with it, so channel up and down in
            // the player walk the same line-up that was being read.
            launcher.play(
                channel,
                jellyfin: jellyfin,
                downloads: downloads,
                settings: playback,
                queue: visibleChannels
            )
        }
    }

    // MARK: - Guide data

    /// Matches a channel by number or name, and the programmes on it by title
    /// — so "what channel is the football on" is one search rather than
    /// scrolling the line-up looking for it.
    private var visibleChannels: [BaseItemDto] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return channels }

        return channels.filter { channel in
            let names = [channel.channelNumber, channel.name]
            if names.contains(where: { $0?.localizedCaseInsensitiveContains(term) == true }) {
                return true
            }
            return listings(for: channel).contains {
                $0.name?.localizedCaseInsensitiveContains(term) == true
            }
        }
    }

    private func listings(for channel: BaseItemDto) -> [BaseItemDto] {
        channel.id.flatMap { programmes[$0] } ?? []
    }

    // MARK: - Loading

    private func load() async {
        await loadChannels()
        await loadListings()
        isLoading = false
    }

    /// `isAddCurrentProgram` is what fills in what's on now — without it a
    /// channel is just a name.
    private func loadChannels() async {
        var parameters = Paths.GetLiveTvChannelsParameters()
        parameters.userID = jellyfin.userID
        parameters.isAddCurrentProgram = true
        parameters.enableImageTypes = [.primary]
        parameters.enableUserData = true
        parameters.sortBy = [.sortName]

        let result = try? await jellyfin.send(Paths.getLiveTvChannels(parameters: parameters))
        channels = result?.items ?? []
    }

    /// One request for the whole line-up rather than one per channel, bounded
    /// to the window ahead: anything still running now, or starting inside it.
    private func loadListings() async {
        let channelIDs = channels.compactMap(\.id)
        guard !channelIDs.isEmpty else { return }

        let now = Date()
        var parameters = Paths.GetLiveTvProgramsParameters()
        parameters.userID = jellyfin.userID
        parameters.channelIDs = channelIDs
        // Back an hour, not from now: the grid starts at the half hour on or
        // before the moment you looked, so anything that ended earlier in that
        // slot still belongs on screen. Asking from now leaves a hole at the
        // left of every row for most of each half hour.
        parameters.minEndDate = now.addingTimeInterval(-60 * 60)
        parameters.maxStartDate = now.addingTimeInterval(guideWindow)
        parameters.sortBy = [.startDate]
        // Without these the programmes come back with no image tags and no
        // description, and the selection readout has nothing to show.
        parameters.enableImageTypes = [.primary, .thumb]
        parameters.fields = [.overview]

        guard let result = try? await jellyfin.send(Paths.getLiveTvPrograms(parameters: parameters)) else {
            return
        }
        programmes = Dictionary(grouping: result.items ?? []) { $0.channelID ?? "" }
    }
}
