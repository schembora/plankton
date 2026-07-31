//
//  OfflineView.swift
//  Plankton
//
//  Shown in place of server content when the app is in offline mode.
//

import SwiftUI

struct OfflineView: View {

    @Environment(JellyfinService.self) private var jellyfin

    var body: some View {
        ContentUnavailableView {
            Label("You're Offline", systemImage: "wifi.slash")
        } description: {
            Text("Can't reach your server. Your downloads are available in the Downloads tab.")
        } actions: {
            Button("Change Server Address") {
                Task { await jellyfin.leaveOfflineMode() }
            }
            .buttonStyle(.glass)
        }
    }
}
