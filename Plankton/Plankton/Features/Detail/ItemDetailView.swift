//
//  ItemDetailView.swift
//  Plankton
//
//  Detail page for a movie or series, with a backdrop hero and playback.
//

import JellyfinAPI
import SwiftUI

struct PlaybackItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ItemDetailView: View {

    @Environment(JellyfinService.self) private var jellyfin

    let item: BaseItemDto

    @State private var fullItem: BaseItemDto?
    @State private var seasons: [BaseItemDto] = []
    @State private var selectedSeasonID: String?
    @State private var episodes: [BaseItemDto] = []
    @State private var playback: PlaybackItem?
    @State private var isPreparingPlayback = false
    @State private var playbackError: String?

    private var displayed: BaseItemDto { fullItem ?? item }

    private var isPlayable: Bool {
        displayed.type == .movie || displayed.type == .episode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                VStack(alignment: .leading, spacing: 20) {
                    titleBlock

                    if isPlayable {
                        playButton
                    }

                    if displayed.type == .series {
                        seriesSection
                    }

                    if let overview = displayed.overview, !overview.isEmpty {
                        Text(overview)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: selectedSeasonID) { _, _ in
            Task { await loadEpisodes() }
        }
        .fullScreenCover(item: $playback) { playback in
            PlayerContainerView(url: playback.url)
        }
        .alert("Couldn't Play Video", isPresented: .init(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    // MARK: - Sections

    private var hero: some View {
        JellyfinImage(url: backdropURL, placeholderIcon: "photo")
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
            JellyfinImage(url: posterURL)
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayed.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    if let year = displayed.productionYear {
                        Text(String(year))
                    }
                    if let runtime = displayed.runtimeText {
                        Text(runtime)
                    }
                    if let rating = displayed.officialRating {
                        Text(rating)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playButton: some View {
        Button {
            play(displayed)
        } label: {
            HStack(spacing: 8) {
                if isPreparingPlayback {
                    ProgressView()
                }
                Label("Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(isPreparingPlayback)
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if seasons.count > 1 {
                Picker("Season", selection: $selectedSeasonID) {
                    ForEach(seasons) { season in
                        Text(season.name ?? "Season").tag(season.id)
                    }
                }
                .pickerStyle(.menu)
            }

            ForEach(episodes) { episode in
                Button {
                    play(episode)
                } label: {
                    EpisodeRow(episode: episode)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        guard let itemID = item.id else { return }

        // Fetch the full item for media sources and complete metadata.
        fullItem = try? await jellyfin.send(Paths.getItem(itemID: itemID, userID: jellyfin.userID))

        if displayed.type == .series {
            if let result = try? await jellyfin.send(Paths.getSeasons(seriesID: itemID)) {
                seasons = result.items ?? []
                // Triggers `onChange`, which loads the episodes.
                selectedSeasonID = seasons.first?.id
            }
        }
    }

    private func loadEpisodes() async {
        guard let seasonID = selectedSeasonID, let userID = jellyfin.userID else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = seasonID
        parameters.limit = 200

        if let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) {
            episodes = result.items ?? []
        }
    }

    // MARK: - Playback & URLs

    private func play(_ item: BaseItemDto) {
        guard !isPreparingPlayback else { return }
        isPreparingPlayback = true

        Task {
            let url = await jellyfin.playbackURL(for: item)
            isPreparingPlayback = false

            if let url {
                playback = PlaybackItem(url: url)
            } else {
                playbackError = "This video isn't playable. The server may not support transcoding for it."
            }
        }
    }

    private var backdropURL: URL? {
        guard let source = displayed.backdropImageSource else { return nil }
        return jellyfin.imageURL(itemID: source.itemID, type: .backdrop, tag: source.tag, maxWidth: 1600)
    }

    private var posterURL: URL? {
        guard let source = displayed.primaryImageSource else { return nil }
        return jellyfin.imageURL(itemID: source.itemID, type: .primary, tag: source.tag, maxWidth: 400)
    }
}

private struct EpisodeRow: View {

    @Environment(JellyfinService.self) private var jellyfin

    let episode: BaseItemDto

    var body: some View {
        HStack(spacing: 12) {
            JellyfinImage(url: thumbURL, placeholderIcon: "tv")
                .frame(width: 140, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                if let label = episode.episodeLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(episode.name ?? "Episode")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                if let runtime = episode.runtimeText {
                    Text(runtime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var thumbURL: URL? {
        guard let episodeID = episode.id else { return nil }
        return jellyfin.imageURL(itemID: episodeID, type: .primary, maxWidth: 420)
    }
}
