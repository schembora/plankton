//
//  PlanktonTests.swift
//  PlanktonTests
//
//  Created by Connor Schembor on 7/22/26.
//

import Foundation
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
