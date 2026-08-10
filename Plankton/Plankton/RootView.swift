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
            // Offline mode opens the app without a session: downloads are
            // on the device, so they don't need a server.
            if jellyfin.isSignedIn || jellyfin.isOffline {
                MainTabView()
            } else {
                ConnectView()
            }
        }
        .animation(.default, value: jellyfin.isSignedIn)
        .animation(.default, value: jellyfin.isOffline)
    }
}

private struct MainTabView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(AppRouter.self) private var router

    @State private var showOfflineNotice = false

    var body: some View {
        // Which tab is showing lives on the router, not in local state: a
        // Spotlight result or an intent has to be able to move it.
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }
            .disabled(jellyfin.isOffline)

            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                LibraryView()
            }
            .disabled(jellyfin.isOffline)

            // Live TV is a server-side add-on, so the tab only exists where the
            // server actually offers it — an empty one would be a control that
            // does nothing on most setups.
            if jellyfin.hasLiveTV {
                Tab("Live TV", systemImage: "antenna.radiowaves.left.and.right", value: .liveTV) {
                    LiveTVView()
                }
                .disabled(jellyfin.isOffline)
            }

            Tab("Downloads", systemImage: "arrow.down.circle", value: .downloads) {
                DownloadsView()
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        // Offline mode puts you on your downloads, and says why.
        .onAppear(perform: handleOfflineMode)
        .onChange(of: jellyfin.isOffline) { _, _ in handleOfflineMode() }
        .alert("Connection Failed", isPresented: $showOfflineNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't reach \(jellyfin.serverName ?? "your server"). You're in offline mode — your downloads are still available.")
        }
        // The offline state is stated by OfflineHeader at the top of the
        // Downloads tab, rather than floating over whatever is on screen.
        .animation(.default, value: jellyfin.isOffline)
    }

    private func handleOfflineMode() {
        guard jellyfin.isOffline else { return }
        router.selectedTab = .downloads
        showOfflineNotice = true
    }
}
