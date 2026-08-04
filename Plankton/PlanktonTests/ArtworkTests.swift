//
//  ArtworkTests.swift
//  PlanktonTests
//
//  Cache identity for artwork, and how items resolve to it.
//

import Foundation
import JellyfinAPI
import Testing

@testable import Plankton

@MainActor
struct ArtworkTests {

    @Test func cacheKeyIgnoresEverythingButTheImageItself() {
        let a = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-1", maxWidth: 500)
        let b = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-1", maxWidth: 500)

        #expect(a.cacheKey == b.cacheKey)
        // The access token lives in the image URL's query string; if it ever
        // leaked into the key, re-signing in would orphan the whole cache.
        #expect(!a.cacheKey.contains("api_key"))
    }

    @Test func cacheKeySeparatesSizesTypesAndTags() {
        let base = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-1", maxWidth: 500)

        let widths = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-1", maxWidth: 1600)
        let types = Artwork.remote(itemID: "item-1", type: .backdrop, tag: "tag-1", maxWidth: 500)
        let tags = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-2", maxWidth: 500)

        #expect(base.cacheKey != widths.cacheKey)
        #expect(base.cacheKey != types.cacheKey)
        #expect(base.cacheKey != tags.cacheKey)
    }

    @Test func onlyTaggedRemoteArtworkReachesDisk() {
        let tagged = Artwork.remote(itemID: "item-1", type: .primary, tag: "tag-1", maxWidth: 500)
        let untagged = Artwork.remote(itemID: "item-1", type: .primary, tag: nil, maxWidth: 500)
        let local = Artwork.local(URL(filePath: "/tmp/poster.jpg"))

        // A tag changes whenever the artwork does, so tagged entries never go stale.
        #expect(tagged.isDiskCacheable)
        // Nothing would ever invalidate these, so they stay in memory only.
        #expect(!untagged.isDiskCacheable)
        // Already on disk — caching it again would just spend the space twice.
        #expect(!local.isDiskCacheable)
    }

    @Test func posterKindPrefersSeriesArtForEpisodes() {
        var episode = BaseItemDto()
        episode.id = "episode-1"
        episode.type = .episode
        episode.seriesID = "series-1"
        episode.seriesPrimaryImageTag = "series-tag"

        #expect(
            episode.artwork(.poster, maxWidth: 500)
                == .remote(itemID: "series-1", type: .primary, tag: "series-tag", maxWidth: 500)
        )
    }

    @Test func wideKindUsesTheEpisodeStillNotTheBackdrop() {
        var episode = BaseItemDto()
        episode.id = "episode-1"
        episode.type = .episode
        episode.imageTags = ["Primary": "still-tag"]

        #expect(
            episode.artwork(.wide, maxWidth: 700)
                == .remote(itemID: "episode-1", type: .primary, tag: "still-tag", maxWidth: 700)
        )
    }

    @Test func episodeStillKindDoesNotFallBackToTheSeries() {
        var episode = BaseItemDto()
        episode.id = "episode-1"
        episode.type = .episode
        episode.seriesID = "series-1"
        episode.seriesPrimaryImageTag = "series-tag"

        // A 2:3 series poster is the wrong shape for a 16:9 row thumbnail, so
        // an episode with no still of its own gets a placeholder instead.
        #expect(episode.artwork(.episodeStill, maxWidth: 420) == nil)
    }
}
