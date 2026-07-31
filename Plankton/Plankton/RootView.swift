//
//  RootView.swift
//  Plankton
//
//  Gates the app on session state and hosts the main tabs.
//

import SwiftUI

struct RootView: View {

    @Environment(JellyfinService.self) private var jellyfin

    var body: some View {
        Group {
            if jellyfin.isRestoringSession {
                ProgressView("Connecting…")
            } else if jellyfin.isSignedIn {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .animation(.default, value: jellyfin.isRestoringSession)
        .animation(.default, value: jellyfin.isSignedIn)
    }
}

private struct MainTabView: View {

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Library", systemImage: "square.grid.2x2") {
                LibraryView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}
