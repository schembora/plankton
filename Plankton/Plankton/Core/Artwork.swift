//
//  Artwork.swift
//  Plankton
//
//  Identifies a piece of artwork independently of the URL it loads from.
//

import Foundation
import JellyfinAPI

/// What a `MediaImage` should show, and the identity `ImageCache` keys on.
///
/// Server artwork is described by item, type, tag, and width rather than by its
/// URL: `JellyfinService.imageURL` puts the access token in the query string, so
/// a URL-keyed cache would orphan every entry the moment the token rotates on
/// re-sign-in. These four fields address the same bytes and never change.
enum Artwork: Hashable, Sendable {

    /// Artwork fetched from the Jellyfin server.
    case remote(itemID: String, type: ImageType, tag: String?, maxWidth: Int)

    /// Artwork already on the device — the snapshot `DownloadService` saves
    /// alongside a download. `fallback` covers downloads made before a given
    /// image was being saved.
    case local(URL, fallback: URL?)

    static func local(_ url: URL) -> Artwork {
        .local(url, fallback: nil)
    }

    /// Which of an item's images to show. The shape of the slot picks the kind:
    /// a 2:3 tile wants `.poster`, a 16:9 card `.wide` or `.episodeStill`.
    enum Kind {
        /// 2:3 cover art. Episodes prefer their series'.
        case poster
        /// The item's own primary image, whatever shape it is.
        case primary
        /// Wide backdrop for a hero banner.
        case backdrop
        /// 16:9 art for a resume card — an episode's still, otherwise a backdrop.
        case wide
        /// An episode's own still only, for a 16:9 row thumbnail.
        case episodeStill
    }

    /// Stable identity for both cache layers. Not a URL, and never contains the
    /// access token, so entries survive signing out and back in.
    var cacheKey: String {
        switch self {
        case let .remote(itemID, type, tag, maxWidth):
            "remote|\(itemID)|\(type.rawValue)|\(tag ?? "untagged")|\(maxWidth)"
        case let .local(url, _):
            "local|\(url.path)"
        }
    }

    /// Whether this artwork may be written to the on-disk cache.
    ///
    /// A server image's tag changes whenever the artwork itself does, so a
    /// tagged entry is safe to keep indefinitely and needs no revalidation. An
    /// untagged one has no such signal and would pin stale art forever, so it
    /// stays in memory only. Local files are already on disk — copying them
    /// into the cache would just spend the space twice.
    var isDiskCacheable: Bool {
        if case let .remote(_, _, tag, _) = self { return tag != nil }
        return false
    }
}
