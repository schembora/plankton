//
//  MediaEntityQuery.swift
//  Plankton
//
//  Resolves searchable media for Spotlight, Siri, and Shortcuts.
//

import AppIntents
import Foundation
import JellyfinAPI

/// How the system looks media up: by identifier when reopening something it
/// already indexed, and by name when the user types or says a title.
///
/// Queries are created by the system, outside the SwiftUI environment, so the
/// services arrive through `AppDependencyManager` (registered in `PlanktonApp`)
/// rather than `@Environment`.
struct MediaEntityQuery: EntityStringQuery {

    @Dependency private var jellyfin: JellyfinService
    @Dependency private var downloads: DownloadService

    /// Server results asked for per query. Spotlight and Siri both show a
    /// handful; fetching more would slow the round trip for rows nobody sees.
    private static let resultLimit = 25

    // The query methods witness `nonisolated` requirements, which would
    // otherwise infer them nonisolated — and every service they read is on the
    // main actor.
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MediaEntity] {
        var found: [MediaEntity] = []

        for id in identifiers {
            // A downloaded item resolves without the network, which also keeps
            // its Spotlight entry working offline.
            if let media = downloads.media.first(where: { $0.itemID == id }) {
                found.append(MediaEntity(media: media, downloads: downloads))
                continue
            }

            if let item = try? await jellyfin.send(Paths.getItem(itemID: id, userID: jellyfin.userID)),
               let entity = MediaEntity(item: item) {
                found.append(entity)
            }
        }

        return found
    }

    @MainActor
    func entities(matching string: String) async throws -> [MediaEntity] {
        let term = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        // Offline the server can't be asked, but the downloads index is right
        // here and everything in it is playable.
        guard !jellyfin.isOffline, let userID = jellyfin.userID else {
            return matchingDownloads(term)
        }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.searchTerm = term
        parameters.includeItemTypes = [.movie, .series]
        parameters.isRecursive = true
        parameters.limit = Self.resultLimit
        // Overview and genres aren't in the default response, and both are
        // what make a Spotlight result readable rather than a bare title.
        parameters.fields = [.overview, .genres]

        guard let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) else {
            return matchingDownloads(term)
        }

        return (result.items ?? []).compactMap(MediaEntity.init(item:))
    }

    /// Offered before anything is typed. Downloads are the only media that is
    /// certain to be openable, so they're what gets suggested.
    @MainActor
    func suggestedEntities() async throws -> [MediaEntity] {
        downloads.media
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(Self.resultLimit)
            .map { MediaEntity(media: $0, downloads: downloads) }
    }

    private func matchingDownloads(_ term: String) -> [MediaEntity] {
        downloads.media
            .filter {
                $0.title.localizedCaseInsensitiveContains(term)
                    || $0.seriesName?.localizedCaseInsensitiveContains(term) == true
            }
            .map { MediaEntity(media: $0, downloads: downloads) }
    }
}
