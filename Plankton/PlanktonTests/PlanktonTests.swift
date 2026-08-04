//
//  PlanktonTests.swift
//  PlanktonTests
//
//  Created by Connor Schembor on 7/22/26.
//

import Foundation
import Get
import JellyfinAPI
import Testing

@testable import Plankton

@MainActor
struct JellyfinServiceTests {

    @Test func bareHostDefaultsToHTTP() {
        let url = JellyfinService.normalizedURL(from: "192.168.1.10:8096")
        #expect(url?.absoluteString == "http://192.168.1.10:8096")
    }

    @Test func trailingSlashIsRemoved() {
        let url = JellyfinService.normalizedURL(from: "https://jellyfin.example.com/")
        #expect(url?.absoluteString == "https://jellyfin.example.com")
    }

    @Test func schemeIsPreserved() {
        let url = JellyfinService.normalizedURL(from: "https://jellyfin.example.com:8920")
        #expect(url?.scheme == "https")
        #expect(url?.port == 8920)
    }

    @Test func blankAddressIsRejected() {
        #expect(JellyfinService.normalizedURL(from: "   ") == nil)
    }
}

@MainActor
struct BaseItemDtoDisplayTests {

    @Test func episodeLabelFormatsSeasonAndEpisode() {
        var episode = BaseItemDto()
        episode.type = .episode
        episode.parentIndexNumber = 2
        episode.indexNumber = 4

        #expect(episode.episodeLabel == "S2 E4")
    }

    @Test func episodeFallsBackToSeriesPoster() {
        var episode = BaseItemDto()
        episode.id = "episode-1"
        episode.type = .episode
        episode.seriesID = "series-1"
        episode.seriesPrimaryImageTag = "abc123"

        #expect(episode.primaryImageSource?.itemID == "series-1")
        #expect(episode.primaryImageSource?.tag == "abc123")
    }

    @Test func backdropFallsBackToParent() {
        var item = BaseItemDto()
        item.id = "episode-1"
        item.parentBackdropItemID = "series-1"
        item.parentBackdropImageTags = ["def456"]

        #expect(item.backdropImageSource?.itemID == "series-1")
        #expect(item.backdropImageSource?.tag == "def456")
    }

    @Test func runtimeFormatsHoursAndMinutes() {
        var movie = BaseItemDto()
        movie.runTimeTicks = 92 * 600_000_000

        #expect(movie.runtimeText == "1h 32m")
    }

    @Test func runtimeFormatsMinutesOnly() {
        var episode = BaseItemDto()
        episode.runTimeTicks = 45 * 600_000_000

        #expect(episode.runtimeText == "45m")
    }
}

@MainActor
struct JellyfinServiceNetworkErrorTests {

    @Test func urlErrorsAreNetworkErrors() {
        #expect(JellyfinService.isNetworkError(URLError(.notConnectedToInternet)))
        #expect(JellyfinService.isNetworkError(URLError(.timedOut)))
        #expect(JellyfinService.isNetworkError(URLError(.cannotFindHost)))
    }

    @Test func otherErrorsAreNotNetworkErrors() {
        let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        #expect(!JellyfinService.isNetworkError(decodingError))
    }

    @Test func rejectedTokensAreAuthFailures() {
        #expect(JellyfinService.isAuthFailure(APIError.unacceptableStatusCode(401)))
        #expect(JellyfinService.isAuthFailure(APIError.unacceptableStatusCode(403)))
    }

    @Test func serverErrorsAreNotAuthFailures() {
        // A 5xx means the server is having trouble, not that the token is bad —
        // the app should go to offline mode, not sign out.
        #expect(!JellyfinService.isAuthFailure(APIError.unacceptableStatusCode(500)))
        #expect(!JellyfinService.isAuthFailure(APIError.unacceptableStatusCode(502)))
        #expect(!JellyfinService.isAuthFailure(URLError(.notConnectedToInternet)))
        #expect(!JellyfinService.isAuthFailure(URLError(.timedOut)))
    }
}

@MainActor
struct DownloadedMediaTests {

    @Test func episodeLabelFormatsSeasonAndEpisode() {
        let episode = DownloadedMedia(
            itemID: "episode-1",
            title: "The One Where",
            seriesName: "Show",
            seriesID: "series-1",
            seasonNumber: 2,
            episodeNumber: 4,
            runtimeTicks: nil,
            isMovie: false,
            startedAt: .distantPast,
            status: .downloading
        )

        #expect(episode.episodeLabel == "S2 E4")
    }

    @Test func moviesHaveNoEpisodeLabel() {
        let movie = DownloadedMedia(
            itemID: "movie-1",
            title: "Film",
            seriesName: nil,
            seriesID: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            runtimeTicks: nil,
            isMovie: true,
            startedAt: .distantPast,
            status: .downloading
        )

        #expect(movie.episodeLabel == nil)
    }

    @Test func recordRoundTripsThroughJSON() throws {
        let record = DownloadedMedia(
            itemID: "movie-1",
            title: "Film",
            seriesName: nil,
            seriesID: nil,
            seasonNumber: nil,
            episodeNumber: nil,
            runtimeTicks: 92 * 600_000_000,
            isMovie: true,
            startedAt: Date(timeIntervalSince1970: 1_000),
            status: .downloaded,
            fileBookmark: Data([1, 2, 3]),
            fileSize: 1_234_567
        )

        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([DownloadedMedia].self, from: data)

        #expect(decoded == [record])
        #expect(decoded.first?.runtimeText == "1h 32m")
    }
}

@MainActor
struct KeychainStoreTests {

    @Test func valueRoundTripsAndDeletes() {
        let store = KeychainStore()

        store.set("secret-token", forKey: "testKey")
        #expect(store.string(forKey: "testKey") == "secret-token")

        store.set("updated", forKey: "testKey")
        #expect(store.string(forKey: "testKey") == "updated")

        store.set(nil, forKey: "testKey")
        #expect(store.string(forKey: "testKey") == nil)
    }
}
