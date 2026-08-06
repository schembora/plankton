//
//  OpenMediaIntent.swift
//  Plankton
//
//  Opens a movie or show chosen from Spotlight, Siri, or Shortcuts.
//

import AppIntents
import Foundation

/// Brings the app to the item the user picked.
///
/// Tapping a Spotlight result runs this rather than merely launching Plankton,
/// because the indexed entity and the intent's parameter are the same type.
struct OpenMediaIntent: OpenIntent {

    nonisolated static let title: LocalizedStringResource = "Open Media"

    nonisolated static let description = IntentDescription(
        "Opens a movie or show in Plankton."
    )

    @Parameter(title: "Media")
    var target: MediaEntity

    @Dependency private var router: AppRouter
    @Dependency private var jellyfin: JellyfinService
    @Dependency private var downloads: DownloadService

    // Drives navigation, so it runs where the router lives.
    @MainActor
    func perform() async throws -> some IntentResult {
        router.open(target, jellyfin: jellyfin, downloads: downloads)
        return .result()
    }
}

extension AppRouter {

    /// Opens media picked from system search. Shared with the Spotlight user
    /// activity path in `PlanktonApp`, which lands the same way for entries
    /// indexed before the intent existed.
    func open(_ entity: MediaEntity, jellyfin: JellyfinService, downloads: DownloadService) {
        // Where the item has to be shown when there's no server to load a
        // detail page from.
        let downloadedSeries = downloads.media
            .first { $0.itemID == entity.id }
            .flatMap { media in
                media.seriesGroupID.map { (groupID: $0, name: media.seriesName ?? media.title) }
            }

        open(entity.route, isOffline: jellyfin.isOffline, downloadedSeries: downloadedSeries)
    }
}
