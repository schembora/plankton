//
//  MediaEntity.swift
//  Plankton
//
//  The searchable representation of a movie, show, or downloaded episode.
//

import AppIntents
import CoreSpotlight
import Foundation
import JellyfinAPI
import UniformTypeIdentifiers

/// A single searchable piece of media.
///
/// One type serves both halves of system search: as an `AppEntity` it's what
/// Shortcuts and Siri resolve, and as an `IndexedEntity` the same values are
/// what `SpotlightIndexer` writes into Spotlight. Keeping them together is why
/// a result found in Spotlight can be opened by the same intent Shortcuts runs.
struct MediaEntity: AppEntity, IndexedEntity {

    /// What the entity is, narrowed to the three things Plankton indexes.
    /// Everything else the server can return (seasons, collections, people)
    /// has no detail page worth landing on.
    enum Kind: String, Codable, Sendable {
        case movie, series, episode

        init?(_ type: BaseItemKind?) {
            switch type {
            case .movie: self = .movie
            case .series: self = .series
            case .episode: self = .episode
            default: return nil
            }
        }

        var itemType: BaseItemKind {
            switch self {
            case .movie: .movie
            case .series: .series
            case .episode: .episode
            }
        }
    }

    /// The Jellyfin item ID, which is also the Spotlight identifier.
    let id: String

    let kind: Kind
    let title: String

    /// Series name for an episode, nil otherwise.
    var seriesName: String?

    /// e.g. "S2 E4".
    var episodeLabel: String?

    var year: Int?
    var overview: String?
    var genres: [String] = []
    var runtimeTicks: Int?
    var communityRating: Float?

    /// Poster snapshot saved next to a download, used as the Spotlight
    /// thumbnail. Only downloaded items have one — see `attributeSet`.
    var posterFileURL: URL?

    /// Whether the item is on the device, which decides where it can be opened
    /// when the server is unreachable.
    var isDownloaded = false

    // MARK: - AppEntity

    nonisolated static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Media",
        numericFormat: "\(placeholder: .int) items"
    )

    nonisolated static let defaultQuery = MediaEntityQuery()

    nonisolated var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { "\($0)" },
            image: .init(systemName: kind == .movie ? "film" : "tv")
        )
    }

    /// Second line wherever the entity is listed: which episode this is, or
    /// the release year. Mirrors `BaseItemDto.posterSubtitle`.
    var subtitle: String? {
        switch kind {
        case .episode:
            [seriesName, episodeLabel].compactMap { $0 }.joined(separator: " · ")
        case .movie, .series:
            year.map(String.init)
        }
    }

    // MARK: - IndexedEntity

    nonisolated var attributeSet: CSSearchableItemAttributeSet {
        // Built from the default set rather than a fresh one: it carries the
        // wiring that ties the Spotlight result back to this entity, which is
        // what lets a tap run `OpenMediaIntent` instead of a bare launch.
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = [subtitle, overview]
            .compactMap { $0 }
            .joined(separator: "\n")
        // Genres and the series name are what people actually type when they
        // can't remember a title.
        attributes.keywords = genres + [seriesName].compactMap { $0 }
        attributes.genre = genres.first
        attributes.rating = communityRating.map(NSNumber.init(value:))
        attributes.local = NSNumber(value: isDownloaded)

        if kind != .series {
            attributes.contentType = UTType.movie.identifier
            attributes.duration = runtimeTicks.map { NSNumber(value: Double($0) / 10_000_000) }
        }

        // Only downloads have artwork on disk. Fetching posters for the whole
        // library at index time would mean a request per item, so server-only
        // entries go in without a thumbnail rather than paying that.
        if let posterFileURL, FileManager.default.fileExists(atPath: posterFileURL.path) {
            attributes.thumbnailURL = posterFileURL
        }

        return attributes
    }
}

// MARK: - Mapping

extension MediaEntity {

    /// Builds an entity from a server item, or nil for a type Plankton doesn't
    /// index.
    init?(item: BaseItemDto) {
        guard let id = item.id, let kind = Kind(item.type) else { return nil }

        self.id = id
        self.kind = kind
        // Not `displayTitle`: that resolves an episode to its series name,
        // which would index every episode of a show under the same title.
        title = item.name ?? String(localized: "Unknown")
        seriesName = item.seriesName
        episodeLabel = item.episodeLabel
        year = item.productionYear
        overview = item.overview
        genres = item.genres ?? []
        runtimeTicks = item.runTimeTicks
        communityRating = item.communityRating
    }

    /// Builds an entity from a download, so anything on the device stays
    /// searchable — and openable — with no server involved.
    init(media: DownloadedMedia, posterFileURL: URL?) {
        id = media.itemID
        kind = media.isMovie ? .movie : .episode
        title = media.title
        seriesName = media.seriesName
        episodeLabel = media.episodeLabel
        runtimeTicks = media.runtimeTicks
        self.posterFileURL = posterFileURL
        isDownloaded = true
    }

    /// Builds an entity from a download, resolving its poster snapshot: an
    /// episode has no artwork of its own on disk and shares its series' cover.
    init(media: DownloadedMedia, downloads: DownloadService) {
        let own = downloads.posterFileURL(forItemID: media.itemID)
        let shared = media.seriesID.map(downloads.seriesPosterFileURL(forSeriesID:))
        let poster = [own, shared]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }

        self.init(media: media, posterFileURL: poster)
    }

    var route: MediaRoute {
        MediaRoute(itemID: id, type: kind.itemType, name: title)
    }
}
