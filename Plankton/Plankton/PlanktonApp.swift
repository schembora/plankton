//
//  PlanktonApp.swift
//  Plankton
//
//  Created by Connor Schembor on 7/22/26.
//

import SwiftUI
import UIKit

@main
struct PlanktonApp: App {

    @UIApplicationDelegateAdaptor(PlanktonAppDelegate.self) private var appDelegate

    @State private var jellyfin: JellyfinService
    @State private var downloads: DownloadService
    @State private var images: ImageCache

    init() {
        let jellyfin = JellyfinService()
        _jellyfin = State(initialValue: jellyfin)
        _downloads = State(initialValue: DownloadService(jellyfin: jellyfin))
        _images = State(initialValue: ImageCache(jellyfin: jellyfin))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(jellyfin)
                .environment(downloads)
                .environment(images)
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
