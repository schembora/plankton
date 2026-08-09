//
//  SeasonEpisodesView.swift
//  Plankton
//
//  Every episode in one season, for when the series page's preview isn't enough.
//

import JellyfinAPI
import SwiftUI

/// The full episode list for a season.
///
/// Handed the episodes rather than fetching them: the series page has already
/// loaded the whole season to build its preview, so re-requesting them would
/// only put a spinner in front of a list that's ready to draw.
struct SeasonEpisodesView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads
    @Environment(PlaybackSettings.self) private var playback

    let title: String
    let episodes: [BaseItemDto]

    @State private var launcher = PlaybackLauncher()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(episodes) { episode in
                    NavigationLink {
                        EpisodeDetailView(episode: episode)
                    } label: {
                        EpisodeRow(episode: episode) {
                            launcher.play(episode, jellyfin: jellyfin, downloads: downloads, engine: playback.engine)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .playbackPresentation(launcher)
    }
}
