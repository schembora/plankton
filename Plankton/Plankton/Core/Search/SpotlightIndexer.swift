//
//  SpotlightIndexer.swift
//  Plankton
//
//  Keeps the system search index in step with the library and downloads.
//

import AppIntents
import CoreSpotlight
import Foundation
import JellyfinAPI
import Observation

/// Writes the library into Spotlight so movies and shows are findable from
/// system search, and keeps that index honest as things change.
///
/// The index outlives the app, which cuts both ways: results stay searchable
/// with the app closed and the server unreachable, but they also stay after
/// signing out — so `clear()` is not optional housekeeping.
@Observable
final class SpotlightIndexer {

    private let jellyfin: JellyfinService
    private let downloads: DownloadService
    private let defaults = UserDefaults.standard
    private let index = CSSearchableIndex.default()

    private(set) var isIndexing = false

    private enum Keys {
        static let lastIndexed = "spotlightLastIndexed"
        static let indexedIDs = "spotlightIndexedIDs"
    }

    /// A library changes on the scale of new releases, not minutes, so a daily
    /// pass is enough. Downloads are indexed separately as they happen.
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    /// Items are handed to Spotlight in batches rather than one array: a large
    /// library is thousands of entries, and a single call would hold them all
    /// in memory while the index churns through them.
    private static let batchSize = 200

    /// Ceiling on how much of a library gets indexed. Someone with a 40,000
    /// item server shouldn't have the app grinding through all of it on a
    /// phone; the first few thousand by name covers what search is for.
    private static let maxItems = 5_000

    init(jellyfin: JellyfinService, downloads: DownloadService) {
        self.jellyfin = jellyfin
        self.downloads = downloads
    }

    // MARK: - Refreshing

    /// Full pass, but only when the last one has aged out. Safe to call on
    /// every launch and every return to the foreground.
    func refreshIfStale() async {
        guard Self.isStale(lastIndexed: defaults.object(forKey: Keys.lastIndexed) as? Date) else {
            // Downloads still get a look in — they change far more often than
            // the library does.
            await indexDownloads()
            return
        }
        await refresh()
    }

    func refresh() async {
        guard jellyfin.isSignedIn, !jellyfin.isOffline, !isIndexing else { return }

        isIndexing = true
        defer { isIndexing = false }

        var entities: [MediaEntity] = []
        var startIndex = 0

        while startIndex < Self.maxItems {
            guard let page = await fetchPage(startIndex: startIndex), !page.items.isEmpty else { break }

            entities.append(contentsOf: page.items.compactMap(MediaEntity.init(item:)))
            startIndex += page.items.count

            if startIndex >= page.total { break }
        }

        // A partial library is worse than a stale one: it would leave things
        // findable that the next pass silently drops.
        guard !entities.isEmpty else { return }

        // Downloads go in last so their entry wins for anything held twice —
        // it's the one that carries artwork and works without the server.
        let downloaded = downloads.media.map { MediaEntity(media: $0, downloads: downloads) }
        let all = entities + downloaded

        do {
            try await write(all)
            try await deleteEntries(missingFrom: all)
            defaults.set(all.map(\.id), forKey: Keys.indexedIDs)
            defaults.set(Date.now, forKey: Keys.lastIndexed)
        } catch {
            // Nothing to tell the user: search quietly keeps whatever the last
            // successful pass wrote, and the next launch tries again.
        }
    }

    /// Re-indexes just the downloads, for when one finishes or is deleted.
    func indexDownloads() async {
        let entities = downloads.media.map { MediaEntity(media: $0, downloads: downloads) }
        guard !entities.isEmpty else { return }

        try? await write(entities)
    }

    /// Drops everything from the index. Called on sign-out: another person's
    /// library has no business showing up in this phone's search results.
    func clear() async {
        try? await index.deleteAppEntities(ofType: MediaEntity.self)
        defaults.removeObject(forKey: Keys.indexedIDs)
        defaults.removeObject(forKey: Keys.lastIndexed)
    }

    // MARK: - Helpers

    static func isStale(lastIndexed: Date?, now: Date = .now) -> Bool {
        guard let lastIndexed else { return true }
        // A clock that has moved backwards (time zone, manual change) would
        // otherwise pin the index as fresh indefinitely.
        return now.timeIntervalSince(lastIndexed) >= refreshInterval || now < lastIndexed
    }

    private func write(_ entities: [MediaEntity]) async throws {
        for batch in stride(from: 0, to: entities.count, by: Self.batchSize) {
            let end = min(batch + Self.batchSize, entities.count)
            try await index.indexAppEntities(Array(entities[batch..<end]))
        }
    }

    /// Removes entries for items that have since left the library, which
    /// indexing alone never does.
    private func deleteEntries(missingFrom entities: [MediaEntity]) async throws {
        let previous = Set(defaults.stringArray(forKey: Keys.indexedIDs) ?? [])
        let removed = Array(previous.subtracting(entities.map(\.id)))
        guard !removed.isEmpty else { return }

        try await index.deleteAppEntities(identifiedBy: removed, ofType: MediaEntity.self)
    }

    private func fetchPage(startIndex: Int) async -> (items: [BaseItemDto], total: Int)? {
        guard let userID = jellyfin.userID else { return nil }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.sortBy = [.sortName]
        parameters.startIndex = startIndex
        parameters.limit = Self.batchSize
        // Not in the default response, and both are what make a Spotlight
        // result readable rather than a bare title.
        parameters.fields = [.overview, .genres]

        guard let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) else { return nil }
        return (result.items ?? [], result.totalRecordCount ?? 0)
    }
}
