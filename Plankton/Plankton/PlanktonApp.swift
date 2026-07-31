//
//  PlanktonApp.swift
//  Plankton
//
//  Created by Connor Schembor on 7/22/26.
//

import SwiftUI

@main
struct PlanktonApp: App {

    @State private var jellyfin = JellyfinService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(jellyfin)
        }
    }
}
