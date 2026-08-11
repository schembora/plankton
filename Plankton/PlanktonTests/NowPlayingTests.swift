//
//  NowPlayingTests.swift
//  PlanktonTests
//
//  What the lock screen is told about the playing item.
//

import Foundation
import JellyfinAPI
import Testing

@testable import Plankton

@Suite("Now playing")
struct NowPlayingTests {

    private let url = URL(string: "https://example.invalid/stream")!

    /// The live flag is resolved by the server, after the metadata is built,
    /// so only the item can put the two together. Getting it wrong puts a
    /// scrubber on the lock screen for a stream with nothing to seek.
    @Test func aLiveItemMarksItsMetadataLive() {
        let item = PlaybackItem(
            url: url,
            isLive: true,
            metadata: NowPlayingMetadata(title: "BBC One")
        )

        #expect(item.nowPlayingMetadata?.isLive == true)
    }

    @Test func aRecordedItemIsNotLive() {
        let item = PlaybackItem(
            url: url,
            metadata: NowPlayingMetadata(title: "The One Where")
        )

        #expect(item.nowPlayingMetadata?.isLive == false)
    }

    /// Nothing to publish rather than an untitled entry.
    @Test func anItemWithoutMetadataPublishesNothing() {
        #expect(PlaybackItem(url: url).nowPlayingMetadata == nil)
    }

    /// A channel leads with itself: it is what was chosen and what stays put,
    /// where the programme is whatever happens to be on it.
    @Test func aChannelLeadsWithItsOwnName() {
        var channel = BaseItemDto()
        channel.id = "channel-1"
        channel.type = .tvChannel
        channel.channelNumber = "101"
        channel.name = "BBC One"

        let metadata = NowPlayingMetadata(channel)

        #expect(metadata.title == "101 · BBC One")
    }

    /// An episode leads with its own name and puts the series underneath, the
    /// way a track sits under its artist.
    @Test func anEpisodeLeadsWithItsOwnName() {
        var episode = BaseItemDto()
        episode.id = "episode-1"
        episode.type = .episode
        episode.name = "The One Where"
        episode.seriesName = "Show"
        episode.parentIndexNumber = 2
        episode.indexNumber = 4

        let metadata = NowPlayingMetadata(episode)

        #expect(metadata.title == "The One Where")
        #expect(metadata.subtitle == "Show · S2 E4")
    }
}
