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

private enum AppTab {
    case home, library, downloads, settings
}

private struct MainTabView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var selection: AppTab = .home
    @State private var showOfflineNotice = false
    @State private var showOfflineOptions = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeView()
            }
            .disabled(jellyfin.isOffline)

            Tab("Library", systemImage: "square.grid.2x2", value: .library) {
                LibraryView()
            }
            .disabled(jellyfin.isOffline)

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
        // Persistent offline indicator; tapping it offers a way back out.
        .safeAreaInset(edge: .top, spacing: 0) {
            if jellyfin.isOffline {
                Button {
                    showOfflineOptions = true
                } label: {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.default, value: jellyfin.isOffline)
        .confirmationDialog("You're Offline", isPresented: $showOfflineOptions, titleVisibility: .visible) {
            Button("Change Server Address") {
                Task { await jellyfin.leaveOfflineMode() }
            }
            Button("Stay Offline", role: .cancel) {}
        } message: {
            Text("Your downloads keep working while offline.")
        }
    }

    private func handleOfflineMode() {
        guard jellyfin.isOffline else { return }
        selection = .downloads
        showOfflineNotice = true
    }
}
