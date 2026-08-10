//
//  PlaybackQueueEntry.swift
//  Plankton
//
//  One stop in a playthrough's queue, from the server or from disk.
//

import Foundation
import JellyfinAPI

/// Something the player can move to without being rebuilt.
///
/// Two cases because the two sources are genuinely different: a server item is
/// negotiated over the network and carries a resume position, a downloaded one
/// is a file that has to keep working with no server to ask. Holding only
/// `BaseItemDto` is what left the Downloads tab with no queue at all, since
/// nothing offline can produce one.
enum PlaybackQueueEntry: Identifiable {

    case server(BaseItemDto)
    case downloaded(DownloadedMedia)

    /// The Jellyfin item this stands for. Downloads keep the server's ID, so
    /// the same value identifies an episode either way and the queue can find
    /// what's playing whichever case it arrived as.
    var itemID: String? {
        switch self {
        case let .server(item): item.id
        case let .downloaded(media): media.itemID
        }
    }

    var id: String { itemID ?? title }

    var title: String {
        switch self {
        case let .server(item): item.name ?? String(localized: "Episode")
        case let .downloaded(media): media.title
        }
    }

    /// e.g. "S2 E4".
    var episodeLabel: String? {
        switch self {
        case let .server(item): item.episodeLabel
        case let .downloaded(media): media.episodeLabel
        }
    }

    /// Only server items know this. A download carries no watch position of
    /// its own, so its tile shows no progress rather than a bar stuck at zero.
    var watchedProgress: Double? {
        switch self {
        case let .server(item): item.watchedProgress
        case .downloaded: nil
        }
    }

    var isLiveChannel: Bool {
        switch self {
        case let .server(item): item.isLiveChannel
        case .downloaded: false
        }
    }

    /// The channel behind a live entry, for the tile that draws one.
    var channel: BaseItemDto? {
        guard case let .server(item) = self, item.isLiveChannel else { return nil }
        return item
    }
}

extension [BaseItemDto] {
    /// Server items as queue entries, for the call sites that browse online.
    var asQueueEntries: [PlaybackQueueEntry] { map(PlaybackQueueEntry.server) }
}

extension [DownloadedMedia] {
    /// Downloads as queue entries, keeping only what the running engine can
    /// open. A season downloaded across an engine change holds both an HLS
    /// bundle and an original container, and the surface was built for one of
    /// them: offering the other would put a dead tile in the strip.
    func asQueueEntries(playableOn engine: PlaybackEngineKind, in downloads: DownloadService) -> [PlaybackQueueEntry] {
        filter { downloads.requiredEngine(forItemID: $0.itemID) == engine }
            .map(PlaybackQueueEntry.downloaded)
    }
}
