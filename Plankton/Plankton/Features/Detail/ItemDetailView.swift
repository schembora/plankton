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

    /// Which engine plays this. Usually the user's setting, but a downloaded
    /// file overrides it: an original container can only be opened by the
    /// direct engine, and an HLS bundle only by AVPlayer, so the format on
    /// disk decides rather than the preference.
    var engine: PlaybackEngineKind = .server

    /// A stream with no end. There is nothing to seek within and no position
    /// worth reporting, so the controls and the reporter both stand down.
    var isLive = false

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
    @Environment(PlaybackSettings.self) private var playback

    let item: BaseItemDto

    /// Episode surfaced for resume when Continue Watching sent us here.
    var resumeEpisode: BaseItemDto?

    @State private var fullItem: BaseItemDto?
    @State private var seasons: [BaseItemDto] = []
    @State private var selectedSeasonID: String?
    @State private var episodes: [BaseItemDto] = []
    @State private var launcher = PlaybackLauncher()
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
        .playbackPresentation(launcher)
    }

    // MARK: - Sections

    private var hero: some View {
        DetailHero(artwork: displayed.artwork(.backdrop, maxWidth: 1600))
    }

    /// Resume banner plus a control to take the season offline.
    private var resumeRow: some View {
        HStack(spacing: 12) {
            Button {
                if let target = resumeTarget { play(target) }
            } label: {
                Label(resumeLabel, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .playbackSpinner(isPreparing: launcher.isPreparing)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(launcher.isPreparing || resumeTarget == nil)

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
        guard let detail = [target.episodeLabel, target.remainingText].metadataLine else { return verb }
        return "\(verb) \(detail)"
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
        DetailHeader(
            title: displayed.displayTitle,
            metadata: metadataLine,
            overview: displayed.overview,
            // A series has no file of its own — its episodes do.
            mediaSummary: isSeries ? nil : displayed.mediaSummary,
            rating: displayed.communityRatingText,
            ratingURL: displayed.imdbURL
        ) {
            DetailPoster(artwork: displayed.artwork(.primary, maxWidth: 400))
        }
    }

    /// Year, then whatever states how long the thing is — a runtime for a
    /// movie, a season count for a series — then certification and lead genre.
    private var metadataLine: String? {
        [
            displayed.productionYear.map(String.init),
            isSeries ? seasonCountText : displayed.runtimeText,
            displayed.officialRating,
            displayed.genres?.first,
        ].metadataLine
    }

    private var seasonCountText: String? {
        guard !seasons.isEmpty else { return nil }
        return "\(seasons.count) \(seasons.count == 1 ? "Season" : "Seasons")"
    }

    private var playButton: some View {
        Button {
            play(displayed)
        } label: {
            Label("Play", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
                .playbackSpinner(isPreparing: launcher.isPreparing)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(launcher.isPreparing)
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Shown even for a one-season show: the chip labels which season
            // the episodes below belong to, which a bare list doesn't.
            if !seasons.isEmpty {
                seasonChips
            }

            ForEach(episodes.prefix(Self.episodePreviewCount)) { episode in
                NavigationLink {
                    EpisodeDetailView(episode: episode)
                } label: {
                    EpisodeRow(episode: episode) { play(episode) }
                }
                .buttonStyle(.plain)
            }

            if episodes.count > Self.episodePreviewCount {
                seeAllEpisodesRow
            }
        }
    }

    /// How many episodes the series page shows before handing off to the full
    /// list. A 24-episode season would otherwise bury everything below it —
    /// the description of an episode now lives on its own page anyway, so this
    /// list only has to be long enough to pick from.
    private static let episodePreviewCount = 6

    private var seeAllEpisodesRow: some View {
        NavigationLink {
            SeasonEpisodesView(title: seasonTitle, episodes: episodes)
        } label: {
            GlassRow {
                Text("See All \(episodes.count) Episodes")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var seasonTitle: String {
        selectedSeasonNumber.map { "Season \($0)" } ?? "Episodes"
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
        launcher.play(item, jellyfin: jellyfin, downloads: downloads, settings: playback)
    }

}
