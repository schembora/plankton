//
//  SearchTests.swift
//  PlanktonTests
//
//  Covers the searchable entity, its Spotlight attributes, and routing.
//

import CoreSpotlight
import Foundation
import JellyfinAPI
import Testing

@testable import Plankton

@MainActor
struct MediaEntityTests {

    private func movie(
        id: String = "movie-1",
        name: String? = "Arrival",
        year: Int? = 2016
    ) -> BaseItemDto {
        var item = BaseItemDto()
        item.id = id
        item.type = .movie
        item.name = name
        item.productionYear = year
        item.overview = "A linguist is recruited to communicate with aliens."
        item.genres = ["Science Fiction", "Drama"]
        item.runTimeTicks = 116 * 600_000_000
        item.communityRating = 7.9
        return item
    }

    private func episode() -> BaseItemDto {
        var item = BaseItemDto()
        item.id = "episode-1"
        item.type = .episode
        item.name = "Ozymandias"
        item.seriesName = "Breaking Bad"
        item.parentIndexNumber = 5
        item.indexNumber = 14
        return item
    }

    @Test func movieMapsFromServerItem() throws {
        let entity = try #require(MediaEntity(item: movie()))

        #expect(entity.id == "movie-1")
        #expect(entity.kind == .movie)
        #expect(entity.title == "Arrival")
        #expect(entity.year == 2016)
        #expect(entity.genres == ["Science Fiction", "Drama"])
        #expect(entity.isDownloaded == false)
    }

    /// `displayTitle` resolves an episode to its series name, which would file
    /// every episode of a show under one title.
    @Test func episodeKeepsItsOwnTitle() throws {
        let entity = try #require(MediaEntity(item: episode()))

        #expect(entity.title == "Ozymandias")
        #expect(entity.seriesName == "Breaking Bad")
        #expect(entity.episodeLabel == "S5 E14")
    }

    @Test func unsupportedTypesAreNotIndexed() {
        var season = BaseItemDto()
        season.id = "season-1"
        season.type = .season
        season.name = "Season 1"

        #expect(MediaEntity(item: season) == nil)
    }

    @Test func itemWithoutIDIsNotIndexed() {
        var idless = movie()
        idless.id = nil

        #expect(MediaEntity(item: idless) == nil)
    }

    @Test func movieSubtitleIsTheYear() throws {
        let entity = try #require(MediaEntity(item: movie()))
        #expect(entity.subtitle == "2016")
    }

    @Test func episodeSubtitleNamesTheSeriesAndEpisode() throws {
        let entity = try #require(MediaEntity(item: episode()))
        #expect(entity.subtitle == "Breaking Bad · S5 E14")
    }

    @Test func downloadMapsToADownloadedEntity() {
        let media = DownloadedMedia(
            itemID: "episode-1",
            title: "The One Where",
            seriesName: "Show",
            seriesID: "series-1",
            seasonNumber: 2,
            episodeNumber: 4,
            runtimeTicks: 45 * 600_000_000,
            isMovie: false,
            startedAt: .distantPast,
            status: .downloaded
        )

        let entity = MediaEntity(media: media, posterFileURL: nil)

        #expect(entity.id == "episode-1")
        #expect(entity.kind == .episode)
        #expect(entity.title == "The One Where")
        #expect(entity.episodeLabel == "S2 E4")
        #expect(entity.isDownloaded)
    }
}

@MainActor
struct MediaEntityAttributeTests {

    private func entity() -> MediaEntity {
        var item = BaseItemDto()
        item.id = "movie-1"
        item.type = .movie
        item.name = "Arrival"
        item.productionYear = 2016
        item.overview = "A linguist is recruited."
        item.genres = ["Science Fiction"]
        item.communityRating = 7.9
        return MediaEntity(item: item)!
    }

    @Test func attributesCarryTitleAndDescription() {
        let attributes = entity().attributeSet

        #expect(attributes.title == "Arrival")
        #expect(attributes.contentDescription?.contains("2016") == true)
        #expect(attributes.contentDescription?.contains("A linguist is recruited.") == true)
    }

    /// Genres and the series name are what people type when the title escapes
    /// them, so both have to be searchable text.
    @Test func keywordsIncludeGenresAndSeries() throws {
        var item = BaseItemDto()
        item.id = "episode-1"
        item.type = .episode
        item.name = "Ozymandias"
        item.seriesName = "Breaking Bad"
        item.genres = ["Crime"]

        let attributes = try #require(MediaEntity(item: item)).attributeSet

        #expect(attributes.keywords?.contains("Crime") == true)
        #expect(attributes.keywords?.contains("Breaking Bad") == true)
    }

    @Test func missingPosterLeavesNoThumbnail() {
        var entity = entity()
        entity.posterFileURL = URL(filePath: "/nonexistent/poster.jpg")

        #expect(entity.attributeSet.thumbnailURL == nil)
    }

    @Test func downloadedPosterBecomesTheThumbnail() throws {
        let poster = URL.temporaryDirectory.appending(path: "poster-\(UUID().uuidString).jpg")
        try Data([0xFF, 0xD8]).write(to: poster)
        defer { try? FileManager.default.removeItem(at: poster) }

        var entity = entity()
        entity.posterFileURL = poster

        #expect(entity.attributeSet.thumbnailURL == poster)
    }

    @Test func downloadsAreMarkedAsLocal() {
        var entity = entity()
        entity.isDownloaded = true

        #expect(entity.attributeSet.local == 1)
    }
}

@MainActor
struct MediaRouteTests {

    @Test func stubCarriesWhatTheDetailPageNeedsToLoad() {
        let route = MediaRoute(itemID: "series-1", type: .series, name: "Severance")
        let stub = route.detailItem

        #expect(stub.id == "series-1")
        #expect(stub.type == .series)
        #expect(stub.name == "Severance")
    }

    @Test func routeFromAnItemKeepsItForFirstPaint() throws {
        var item = BaseItemDto()
        item.id = "movie-1"
        item.type = .movie
        item.name = "Arrival"
        item.overview = "Already loaded."

        let route = try #require(MediaRoute(item: item))

        #expect(route.detailItem.overview == "Already loaded.")
    }

    @Test func itemWithoutIDMakesNoRoute() {
        var item = BaseItemDto()
        item.type = .movie
        #expect(MediaRoute(item: item) == nil)
    }

    /// The same item reached from a grid tap and from a Spotlight result has
    /// to be one destination, even though only one of them carries a payload.
    @Test func identityIgnoresThePayload() throws {
        var item = BaseItemDto()
        item.id = "movie-1"
        item.type = .movie
        item.name = "Arrival"

        let withItem = try #require(MediaRoute(item: item))
        let byID = MediaRoute(itemID: "movie-1", type: .movie)

        #expect(withItem == byID)
        #expect(withItem.hashValue == byID.hashValue)
    }

    @Test func entityRoutesToItsOwnType() {
        var item = BaseItemDto()
        item.id = "series-1"
        item.type = .series
        item.name = "Severance"

        let route = MediaEntity(item: item)!.route

        #expect(route.itemID == "series-1")
        #expect(route.type == .series)
    }
}

@MainActor
struct AppRouterTests {

    @Test func openingOnlineGoesToTheLibrary() {
        let router = AppRouter()
        let route = MediaRoute(itemID: "movie-1", type: .movie)

        router.open(route, isOffline: false)

        #expect(router.selectedTab == .library)
        #expect(router.libraryPath == [route])
    }

    /// Offline the Library tab is disabled and the detail page has no server
    /// to load from, so a downloaded episode has to be reached another way.
    @Test func openingOfflineGoesToTheDownloadedSeries() {
        let router = AppRouter()

        router.open(
            MediaRoute(itemID: "episode-1", type: .episode),
            isOffline: true,
            downloadedSeries: (groupID: "series-1", name: "Severance")
        )

        #expect(router.selectedTab == .downloads)
        #expect(router.downloadsPath == [.series(groupID: "series-1", name: "Severance")])
    }

    @Test func openingOfflineWithoutASeriesLandsOnTheDownloadsGrid() {
        let router = AppRouter()

        router.open(MediaRoute(itemID: "movie-1", type: .movie), isOffline: true)

        #expect(router.selectedTab == .downloads)
        #expect(router.downloadsPath.isEmpty)
    }

    @Test func openingReplacesWhateverWasPushed() {
        let router = AppRouter()
        let first = MediaRoute(itemID: "movie-1", type: .movie)
        let second = MediaRoute(itemID: "movie-2", type: .movie)

        router.open(first, isOffline: false)
        router.open(second, isOffline: false)

        #expect(router.libraryPath == [second])
    }
}

@MainActor
struct SpotlightIndexerTests {

    @Test func aLibraryNeverIndexedIsStale() {
        #expect(SpotlightIndexer.isStale(lastIndexed: nil))
    }

    @Test func aFreshIndexIsLeftAlone() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SpotlightIndexer.isStale(lastIndexed: now.addingTimeInterval(-60 * 60), now: now) == false)
    }

    @Test func aDayOldIndexIsRefreshed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SpotlightIndexer.isStale(lastIndexed: now.addingTimeInterval(-25 * 60 * 60), now: now))
    }

    /// A clock that moved backwards would otherwise pin the index as fresh
    /// until it caught up again.
    @Test func aTimestampInTheFutureIsStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SpotlightIndexer.isStale(lastIndexed: now.addingTimeInterval(60 * 60), now: now))
    }
}
