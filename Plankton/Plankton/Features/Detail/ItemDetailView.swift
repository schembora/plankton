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

    /// What the lock screen shows while this plays. Nil leaves the info center
    /// alone rather than publishing an untitled entry.
    var metadata: NowPlayingMetadata?
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
    @State private var similar: [BaseItemDto] = []

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
                    // Movies and series share one header: the poster with the
                    // title and details set beside it. Only the action row
                    // below differs, since a series resumes into an episode.
                    titleBlock

                    if isSeries {
                        resumeRow
                    } else if isPlayable {
                        HStack(spacing: 12) {
                            playButton
                            DownloadButton(item: displayed, style: .prominent)
                        }
                    }

                    if isSeries {
                        seriesSection
                    }
                }
                .padding(.horizontal)

                // Outside the padded stack: MediaRow insets its own content so
                // the shelf can scroll out to the screen edge.
                if !similar.isEmpty {
                    MediaRow(title: "More Like This", items: similar)
                }
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
    }

    /// Resume banner plus a control to take the season offline.
    private var resumeRow: some View {
        HStack(spacing: 12) {
            Button {
                if let target = resumeTarget { play(target) }
            } label: {
                Label(resumeLabel, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .playbackSpinner(isPreparing: isPreparingPlayback)
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

                // One string rather than a row of them: beside a poster there
                // isn't width for four details, and text wraps where an HStack
                // would push the last of them off the edge.
                Text(metadataLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Set beside the poster rather than under the whole header.
                // Four lines of this column run to about the poster's height,
                // so the block stays square before the description spills past.
                if let overview = displayed.overview, !overview.isEmpty {
                    ExpandableText(text: overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Year, then whatever states how long the thing is — a runtime for a
    /// movie, a season count for a series — then certification and lead genre.
    private var metadataLine: String {
        var parts: [String] = []

        if let year = displayed.productionYear {
            parts.append(String(year))
        }
        if isSeries {
            if !seasons.isEmpty {
                parts.append("\(seasons.count) \(seasons.count == 1 ? "Season" : "Seasons")")
            }
        } else if let runtime = displayed.runtimeText {
            parts.append(runtime)
        }
        if let rating = displayed.officialRating {
            parts.append(rating)
        }
        if let genre = displayed.genres?.first {
            parts.append(genre)
        }

        return parts.joined(separator: " · ")
    }

    private var playButton: some View {
        Button {
            play(displayed)
        } label: {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
                .playbackSpinner(isPreparing: isPreparingPlayback)
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
        async let related: Void = loadSimilar(itemID: itemID)
        fullItem = try? await jellyfin.send(Paths.getItem(itemID: itemID, userID: jellyfin.userID))
        await related

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

    /// The server's own similarity match — genre, people, and studio overlap.
    /// A failure here leaves the shelf out rather than surfacing an error: it
    /// is an extra, and the page is complete without it.
    private func loadSimilar(itemID: String) async {
        var parameters = Paths.GetSimilarItemsParameters()
        parameters.userID = jellyfin.userID
        parameters.limit = 20

        guard let result = try? await jellyfin.send(
            Paths.getSimilarItems(itemID: itemID, parameters: parameters)
        ) else { return }

        similar = result.items ?? []
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
                startTicks: item.resumePositionTicks,
                metadata: NowPlayingMetadata(item)
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
                    startTicks: item.resumePositionTicks,
                    metadata: NowPlayingMetadata(item)
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

private extension View {

    /// Swaps a play button's label for a spinner while playback is being
    /// negotiated. The spinner is overlaid rather than placed beside the label:
    /// adding a view to the button's own layout re-measures the row, so the
    /// button visibly resized the instant it was tapped.
    func playbackSpinner(isPreparing: Bool) -> some View {
        opacity(isPreparing ? 0 : 1)
            .overlay {
                if isPreparing {
                    ProgressView()
                }
            }
    }
}
