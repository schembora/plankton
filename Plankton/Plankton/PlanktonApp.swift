//
//  PlanktonApp.swift
//  Plankton
//
//  Created by Connor Schembor on 7/22/26.
//

import AppIntents
import CoreSpotlight
import SwiftUI
import UIKit

@main
struct PlanktonApp: App {

    @UIApplicationDelegateAdaptor(PlanktonAppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    @State private var jellyfin: JellyfinService
    @State private var downloads: DownloadService
    @State private var images: ImageCache
    @State private var router: AppRouter
    @State private var indexer: SpotlightIndexer

    init() {
        let jellyfin = JellyfinService()
        let downloads = DownloadService(jellyfin: jellyfin)
        let router = AppRouter()

        _jellyfin = State(initialValue: jellyfin)
        _downloads = State(initialValue: downloads)
        _images = State(initialValue: ImageCache(jellyfin: jellyfin))
        _router = State(initialValue: router)
        _indexer = State(initialValue: SpotlightIndexer(jellyfin: jellyfin, downloads: downloads))

        // App Intents types are created by the system, outside the SwiftUI
        // environment, so the entity query and open intent reach these same
        // instances through the dependency registry instead of `@Environment`.
        AppDependencyManager.shared.add(dependency: jellyfin)
        AppDependencyManager.shared.add(dependency: downloads)
        AppDependencyManager.shared.add(dependency: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(jellyfin)
                .environment(downloads)
                .environment(images)
                .environment(router)
                .task { await indexer.refreshIfStale() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await indexer.refreshIfStale() }
                }
                // Signing in fills the index; signing out empties it, so one
                // person's library never surfaces in the next person's search.
                .onChange(of: jellyfin.isSignedIn) { _, isSignedIn in
                    Task {
                        if isSignedIn {
                            await indexer.refresh()
                        } else {
                            await indexer.clear()
                        }
                    }
                }
                // Downloads change far more often than the library, and their
                // entries are the ones that carry artwork and work offline.
                .onChange(of: downloads.media) { _, _ in
                    Task { await indexer.indexDownloads() }
                }
                .onContinueUserActivity(CSSearchableItemActionType, perform: openSpotlightResult)
        }
    }

    /// Fallback for Spotlight results that arrive as a user activity rather
    /// than as `OpenMediaIntent` — entries written before the intent was
    /// associated with the entity still land this way.
    private func openSpotlightResult(_ activity: NSUserActivity) {
        guard let itemID = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

        Task {
            guard let entity = try? await MediaEntityQuery().entities(for: [itemID]).first else { return }
            router.open(entity, jellyfin: jellyfin, downloads: downloads)
        }
    }
}

/// Routes background download events to the download service when the system
/// relaunches the app after transfers finish while suspended.
final class PlanktonAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadService.backgroundCompletionHandler = completionHandler
    }
}
