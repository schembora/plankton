//
//  SeriesDownloadsView.swift
//  Plankton
//
//  A downloaded series, laid out like the library detail page: backdrop
//  banner, title block, season picker, and episode cards. Everything renders
//  from local artwork so it works offline.
//

import SwiftUI

struct SeriesDownloadsView: View {

    @Environment(DownloadService.self) private var downloads

    let groupID: String
    let seriesName: String

    @State private var selectedSeason: Int?
    @State private var playback: PlaybackItem?

    /// All downloaded episodes, in episode order.
    private var episodes: [DownloadedMedia] {
        downloads.media
            .filter { $0.seriesGroupID == groupID }
            .sorted {
                ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
            }
    }

    /// The seasons that have downloads, in order.
    private var seasons: [Int] {
        Array(Set(episodes.compactMap(\.seasonNumber))).sorted()
    }

    private var visibleEpisodes: [DownloadedMedia] {
        guard let selectedSeason = selectedSeason ?? seasons.first else { return episodes }
        return episodes.filter { $0.seasonNumber == selectedSeason }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                VStack(alignment: .leading, spacing: 20) {
                    titleBlock

                    episodeSection
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedSeason == nil {
                selectedSeason = seasons.first
            }
        }
        .fullScreenCover(item: $playback) { playback in
            PlayerContainerView(playback: playback)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        LocalPosterImage(
            url: downloads.seriesBackdropFileURL(forSeriesID: groupID),
            fallback: downloads.backdropFileURL(forItemID: firstEpisodeItemID)
        )
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.4)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            LocalPosterImage(
                url: downloads.seriesPosterFileURL(forSeriesID: groupID),
                fallback: downloads.posterFileURL(forItemID: firstEpisodeItemID)
            )
            .frame(width: 100, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(seriesName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                Picker("Season", selection: $selectedSeason) {
                    ForEach(seasons, id: \.self) { season in
                        Text("Season \(season)").tag(season as Int?)
                    }
                }
                .pickerStyle(.menu)
            }

            ForEach(visibleEpisodes) { media in
                Button {
                    play(media)
                } label: {
                    EpisodeCard(
                        label: media.episodeLabel,
                        title: media.title,
                        runtimeText: media.runtimeText
                    ) {
                        LocalPosterImage(url: downloads.posterFileURL(forItemID: media.itemID))
                    } accessory: {
                        accessory(for: media)
                    }
                }
                .buttonStyle(.plain)
                .downloadActions(for: media)
            }
        }
    }

    // MARK: - Helpers

    private var firstEpisodeItemID: String {
        episodes.first?.itemID ?? ""
    }

    private var metaLine: String {
        var parts: [String] = []
        if !seasons.isEmpty {
            parts.append("\(seasons.count) \(seasons.count == 1 ? "season" : "seasons")")
        }
        let count = episodes.count
        parts.append("\(count) \(count == 1 ? "episode" : "episodes")")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func accessory(for media: DownloadedMedia) -> some View {
        switch downloads.state(for: media.itemID) {
        case .downloading(let progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        default:
            Image(systemName: "play.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func play(_ media: DownloadedMedia) {
        guard let url = downloads.localURL(forItemID: media.itemID) else { return }
        // Downloads have no cached watch position, but reporting still
        // works whenever the server is reachable.
        playback = PlaybackItem(url: url, itemID: media.itemID)
    }
}
