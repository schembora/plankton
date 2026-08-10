//
//  EpisodeDetailView.swift
//  Plankton
//
//  One episode — its still, description, the rest of its season, and a way
//  into the series it belongs to.
//

import JellyfinAPI
import SwiftUI

/// Detail page for a single episode.
///
/// Continue Watching and Next Up land here rather than on the series: both
/// point at one specific episode, and sending them to the series meant the
/// episode's own description was nowhere to be seen.
struct EpisodeDetailView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads
    @Environment(PlaybackSettings.self) private var playback

    /// The episode the page opened on. `current` takes over once loading
    /// starts, and again whenever the strip below moves to a sibling.
    let episode: BaseItemDto

    @State private var current: BaseItemDto?
    @State private var seasonEpisodes: [BaseItemDto] = []
    @State private var launcher = PlaybackLauncher()
    @State private var hasPositionedStrip = false

    private var displayed: BaseItemDto { current ?? episode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Keeps the last still up while the next loads: this hero swaps
                // every time the strip below moves, and blanking to a
                // placeholder each time is the whole of the flicker.
                DetailHero(
                    artwork: displayed.artwork(.wide, maxWidth: 1600),
                    placeholderIcon: "tv",
                    keepsPreviousWhileLoading: true
                )

                VStack(alignment: .leading, spacing: 20) {
                    header

                    HStack(spacing: 12) {
                        playButton
                        DownloadButton(item: displayed, style: .prominent)
                    }
                }
                .padding(.horizontal)

                // Outside the padded stack so the strip can run to the edge,
                // the same way the shelves on Home do.
                if seasonEpisodes.count > 1 {
                    episodeStrip
                }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await open(episode) }
        .playbackPresentation(launcher)
    }

    // MARK: - Sections

    private var header: some View {
        DetailHeader(
            // The episode's own name: `displayTitle` answers with the series,
            // which is right in a grid tile and wrong here.
            title: displayed.name ?? "Episode",
            metadata: [
                displayed.episodeLabel,
                displayed.runtimeText,
                airDate,
            ].metadataLine,
            overview: displayed.overview,
            mediaSummary: displayed.mediaSummary,
            rating: displayed.communityRatingText,
            ratingURL: displayed.imdbURL,
            // Sliding between episodes would otherwise resize this block and
            // shift the strip out from under the finger tapping it.
            reservesDescriptionSpace: true
        ) {
            seriesPoster
        } lead: {
            if displayed.seriesID != nil {
                seriesBreadcrumb
            }
        }
    }

    private var airDate: String? {
        displayed.premiereDate?.formatted(date: .abbreviated, time: .omitted)
    }

    /// The poster is the way back to the show — an episode has no cover art of
    /// its own, so the art already standing here is the series'. The badge is
    /// what says so, since a poster alone doesn't look tappable.
    @ViewBuilder
    private var seriesPoster: some View {
        if displayed.seriesID != nil {
            NavigationLink {
                ItemDetailView(item: seriesStub)
            } label: {
                DetailPoster(artwork: displayed.artwork(.poster, maxWidth: 400))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular, in: .circle)
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to \(displayed.seriesName ?? "series")")
        } else {
            DetailPoster(artwork: displayed.artwork(.poster, maxWidth: 400))
        }
    }

    /// The series name above the episode title, so the page says which show
    /// this belongs to without a row of its own taking up the space.
    private var seriesBreadcrumb: some View {
        NavigationLink {
            ItemDetailView(item: seriesStub)
        } label: {
            Text(displayed.seriesName ?? "Series")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    private var playButton: some View {
        Button {
            launcher.play(
                displayed,
                jellyfin: jellyfin,
                downloads: downloads,
                settings: playback,
                queue: seasonEpisodes
            )
        } label: {
            Label(playLabel, systemImage: "play.fill")
                .frame(maxWidth: .infinity)
                .playbackSpinner(isPreparing: launcher.isPreparing)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(launcher.isPreparing)
    }

    private var playLabel: String {
        guard displayed.resumePositionTicks != nil else { return "Play" }
        return displayed.remainingText.map { "Resume · \($0)" } ?? "Resume"
    }

    /// The rest of the season, opened on whichever episode this page is showing.
    /// Picking one swaps the page in place rather than pushing another copy of
    /// it, so sliding through a season doesn't build a stack to back out of.
    private var episodeStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(seasonTitle)
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(seasonEpisodes) { sibling in
                            Button {
                                Task { await open(sibling) }
                            } label: {
                                EpisodeTile(
                                    episode: sibling,
                                    isCurrent: sibling.id == displayed.id
                                )
                            }
                            .buttonStyle(.plain)
                            .id(sibling.id)
                        }
                    }
                    .padding(.horizontal)
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                // `task(id:)` rather than `onChange`: this strip only exists
                // once the season has loaded, and `onChange` doesn't fire for
                // the change that brings a view into existence — so arriving
                // from the series page left the strip parked on episode one.
                // It runs on first appearance and on every swap after.
                .task(id: displayed.id) {
                    positionStrip(proxy)
                }
            }
        }
    }

    /// Centres the strip on the episode being shown. The first time is a jump —
    /// the strip should simply open in the right place — and every swap after
    /// it slides, so the movement reads as coming from the tap.
    private func positionStrip(_ proxy: ScrollViewProxy) {
        guard hasPositionedStrip else {
            proxy.scrollTo(displayed.id, anchor: .center)
            hasPositionedStrip = true
            return
        }
        withAnimation(.snappy) { proxy.scrollTo(displayed.id, anchor: .center) }
    }

    private var seasonTitle: String {
        displayed.parentIndexNumber.map { "Season \($0)" } ?? "Episodes"
    }

    /// `ItemDetailView` refetches by ID on appear, so an ID and type are enough.
    private var seriesStub: BaseItemDto {
        var stub = BaseItemDto()
        stub.id = displayed.seriesID
        stub.type = .series
        stub.name = displayed.seriesName
        return stub
    }

    // MARK: - Loading

    /// Shows an episode straight away, then fills in what the shelves don't
    /// carry — the description and media sources come from the full record.
    private func open(_ target: BaseItemDto) async {
        // Deliberately unanimated. The whole page hangs off `current`, so
        // animating the swap re-lays out the play button as its label changes
        // between "Play" and a resume time, which reads as the button bouncing.
        current = target

        guard let itemID = target.id else { return }
        if let full = try? await jellyfin.send(Paths.getItem(itemID: itemID, userID: jellyfin.userID)) {
            // Guard against a slow response for an episode already swapped away
            // from: without this it would yank the page back.
            guard displayed.id == itemID else { return }
            current = full
        }

        await loadSeasonIfNeeded()
    }

    private func loadSeasonIfNeeded() async {
        guard seasonEpisodes.isEmpty,
              let seasonID = displayed.seasonID,
              let userID = jellyfin.userID
        else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = seasonID
        parameters.limit = 200
        // Drives the watched bar on each tile, and the resume label above.
        parameters.enableUserData = true

        if let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) {
            seasonEpisodes = result.items ?? []
        }
    }
}
