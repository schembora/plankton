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

    /// Server item being played, for resume and progress reporting. Nil for
    /// local playback with no session to report against.
    var itemID: String?

    /// Where to resume from, in Jellyfin ticks.
    var startTicks: Int?
}

struct ItemDetailView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads

    let item: BaseItemDto

    /// Episode surfaced for resume when Continue Watching sent us here.
    var resumeEpisode: BaseItemDto?

    @State private var fullItem: BaseItemDto?
    @State private var seasons: [BaseItemDto] = []
    @State private var selectedSeasonID: String?
    @State private var episodes: [BaseItemDto] = []
    @State private var playback: PlaybackItem?
    @State private var isPreparingPlayback = false
    @State private var playbackError: String?
    @State private var showDownloadScope = false

    private var displayed: BaseItemDto { fullItem ?? item }

    private var isPlayable: Bool {
        displayed.type == .movie || displayed.type == .episode
    }

    private var isSeries: Bool { displayed.type == .series }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero

                VStack(alignment: .leading, spacing: 20) {
                    // A series states its identity over the backdrop, so the
                    // resume control can lead instead of a poster.
                    if isSeries {
                        resumeRow
                    } else {
                        titleBlock

                        if isPlayable {
                            HStack(spacing: 12) {
                                playButton
                                DownloadButton(item: displayed, style: .prominent)
                            }
                        }
                    }

                    // Before the season list: on a series the episode rows are
                    // long enough to push the description off-screen entirely.
                    if let overview = displayed.overview, !overview.isEmpty {
                        Text(overview)
                            .foregroundStyle(.secondary)
                    }

                    if isSeries {
                        seriesSection
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
            PlayerContainerView(playback: playback)
        }
        .sheet(isPresented: $showDownloadScope) {
            if let seriesID = displayed.id {
                DownloadScopeSheet(
                    seriesID: seriesID,
                    seasonNumber: selectedSeasonNumber,
                    seasonEpisodes: episodes
                )
                .presentationDetents([.medium, .large])
            }
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
        MediaImage(artwork: displayed.artwork(.backdrop, maxWidth: 1600), placeholderIcon: "photo")
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                if isSeries {
                    seriesHeroTitle
                }
            }
    }

    private var seriesHeroTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayed.displayTitle)
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                if let year = displayed.productionYear {
                    Text(String(year))
                }
                if !seasons.isEmpty {
                    Text("\(seasons.count) \(seasons.count == 1 ? "season" : "seasons")")
                }
                if let rating = displayed.officialRating {
                    Text(rating)
                }
                if let genre = displayed.genres?.first {
                    Text(genre)
                }
            }
            .font(.subheadline)
        }
        .foregroundStyle(.white)
        .shadow(radius: 6)
        .padding(16)
    }

    /// Resume banner plus a control to take the season offline.
    private var resumeRow: some View {
        HStack(spacing: 12) {
            Button {
                if let target = resumeTarget { play(target) }
            } label: {
                HStack(spacing: 8) {
                    if isPreparingPlayback {
                        ProgressView()
                    }
                    Label(resumeLabel, systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isPreparingPlayback || resumeTarget == nil)

            Button {
                showDownloadScope = true
            } label: {
                Label("Download", systemImage: "arrow.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(episodes.isEmpty)
        }
    }

    /// "Resume S2 E4 · 18m left", or a plain play when nothing is part-watched.
    private var resumeLabel: String {
        guard let target = resumeTarget else { return "Play" }
        let verb = target.resumePositionTicks == nil ? "Play" : "Resume"
        let parts = [target.episodeLabel, target.remainingText].compactMap { $0 }
        return parts.isEmpty ? verb : "\(verb) \(parts.joined(separator: " · "))"
    }

    /// The episode Continue Watching sent us to, otherwise the first one still
    /// part-watched, otherwise the first unwatched, otherwise the first.
    private var resumeTarget: BaseItemDto? {
        if let resumeEpisode { return resumeEpisode }
        if let partWatched = episodes.first(where: { $0.resumePositionTicks != nil }) {
            return partWatched
        }
        if let unwatched = episodes.first(where: { $0.userData?.isPlayed != true }) {
            return unwatched
        }
        return episodes.first
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            MediaImage(artwork: displayed.artwork(.primary, maxWidth: 400))
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
        VStack(alignment: .leading, spacing: 14) {
            // Shown even for a one-season show: the chip labels which season
            // the episodes below belong to, which a bare list doesn't.
            if !seasons.isEmpty {
                seasonChips
            }

            if !episodes.isEmpty {
                seasonDownloadRow
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

    private var seasonChips: some View {
        SeasonPicker(
            seasons: seasons,
            selection: $selectedSeasonID,
            // A season without an ID can't be fetched anyway, so it simply
            // never matches the selection.
            id: { $0.id ?? "" },
            label: { $0.indexNumber.map { "S\($0)" } ?? ($0.name ?? "Season") }
        )
    }

    /// States what taking this season offline actually costs before opening
    /// the scope sheet.
    private var seasonDownloadRow: some View {
        Button {
            showDownloadScope = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.to.line")
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedSeasonNumber.map { "Download season \($0)" } ?? "Download season")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(seasonDownloadDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// "3 of 8 already on this device", or that everything is saved.
    private var seasonDownloadDetail: String {
        let saved = episodes.filter { downloads.state(for: $0.id) == .downloaded }.count
        if saved == episodes.count {
            return "All \(episodes.count) on this device"
        }
        return "\(saved) of \(episodes.count) already on this device"
    }

    private var selectedSeasonNumber: Int? {
        seasons.first { $0.id == selectedSeasonID }?.indexNumber
            ?? episodes.first?.parentIndexNumber
    }

    // MARK: - Loading

    private func load() async {
        guard let itemID = item.id else { return }

        // Fetch the full item for media sources and complete metadata.
        fullItem = try? await jellyfin.send(Paths.getItem(itemID: itemID, userID: jellyfin.userID))

        if displayed.type == .series {
            if let result = try? await jellyfin.send(Paths.getSeasons(seriesID: itemID)) {
                seasons = result.items ?? []
                // Open on the season holding the episode we were sent to
                // resume, otherwise the first. Triggers `onChange`, which
                // loads the episodes.
                let resumeSeason = resumeEpisode?.parentIndexNumber
                selectedSeasonID = seasons.first { $0.indexNumber == resumeSeason }?.id
                    ?? seasons.first?.id
            }
        }
    }

    private func loadEpisodes() async {
        guard let seasonID = selectedSeasonID, let userID = jellyfin.userID else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = seasonID
        parameters.limit = 200
        // Carries playbackPositionTicks, so playing an episode resumes.
        parameters.enableUserData = true

        if let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) {
            episodes = result.items ?? []
        }
    }

    // MARK: - Playback & URLs

    private func play(_ item: BaseItemDto) {
        // Prefer the downloaded copy when there is one — instant and offline-capable.
        if let itemID = item.id, let localURL = downloads.localURL(forItemID: itemID) {
            playback = PlaybackItem(
                url: localURL,
                itemID: itemID,
                startTicks: item.resumePositionTicks
            )
            return
        }

        guard !isPreparingPlayback else { return }
        isPreparingPlayback = true

        Task {
            let url = await jellyfin.playbackURL(for: item)
            isPreparingPlayback = false

            if let url {
                playback = PlaybackItem(
                    url: url,
                    itemID: item.id,
                    startTicks: item.resumePositionTicks
                )
            } else {
                playbackError = "This video isn't playable. The server may not support transcoding for it."
            }
        }
    }

}

private struct EpisodeRow: View {

    let episode: BaseItemDto

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

                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
