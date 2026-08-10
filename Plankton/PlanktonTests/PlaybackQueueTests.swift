//
//  PlaybackQueueTests.swift
//  PlanktonTests
//
//  What a queue entry reads back as, from either source.
//

import Foundation
import JellyfinAPI
import Testing

@testable import Plankton

@Suite("Playback queue")
struct PlaybackQueueTests {

    private func downloadedEpisode(
        itemID: String = "episode-1",
        season: Int? = 2,
        episode: Int? = 4
    ) -> DownloadedMedia {
        DownloadedMedia(
            itemID: itemID,
            title: "The One Where",
            seriesName: "Show",
            seriesID: "series-1",
            seasonNumber: season,
            episodeNumber: episode,
            runtimeTicks: nil,
            isMovie: false,
            startedAt: .distantPast,
            status: .downloaded
        )
    }

    /// The two cases have to agree on identity, or the player can't tell which
    /// entry is playing and both queue controls go dead.
    @Test func bothSourcesIdentifyByTheServerItemID() {
        var item = BaseItemDto()
        item.id = "episode-1"

        #expect(PlaybackQueueEntry.server(item).itemID == "episode-1")
        #expect(PlaybackQueueEntry.downloaded(downloadedEpisode()).itemID == "episode-1")
    }

    @Test func aDownloadedEpisodeReadsBackItsLabelAndTitle() {
        let entry = PlaybackQueueEntry.downloaded(downloadedEpisode())

        #expect(entry.title == "The One Where")
        #expect(entry.episodeLabel == "S2 E4")
    }

    /// A download carries no watch position, so its tile must show no bar
    /// rather than one pinned at zero.
    @Test func aDownloadHasNoWatchedProgress() {
        #expect(PlaybackQueueEntry.downloaded(downloadedEpisode()).watchedProgress == nil)
    }

    @Test func onlyAServerChannelIsLive() {
        var channel = BaseItemDto()
        channel.id = "channel-1"
        channel.type = .tvChannel

        #expect(PlaybackQueueEntry.server(channel).isLiveChannel)
        #expect(PlaybackQueueEntry.server(channel).channel != nil)
        #expect(!PlaybackQueueEntry.downloaded(downloadedEpisode()).isLiveChannel)
        #expect(PlaybackQueueEntry.downloaded(downloadedEpisode()).channel == nil)
    }

    /// An ordinary episode is not a channel, so the strip draws it as an
    /// episode tile. Getting this wrong swaps every tile in a season strip.
    @Test func anEpisodeIsNotAChannel() {
        var item = BaseItemDto()
        item.id = "episode-1"
        item.type = .episode

        #expect(!PlaybackQueueEntry.server(item).isLiveChannel)
        #expect(PlaybackQueueEntry.server(item).channel == nil)
    }

    @Test func serverItemsConvertInOrder() {
        let ids = ["a", "b", "c"]
        let items = ids.map { id -> BaseItemDto in
            var item = BaseItemDto()
            item.id = id
            return item
        }

        #expect(items.asQueueEntries.map(\.itemID) == ids)
    }
}
