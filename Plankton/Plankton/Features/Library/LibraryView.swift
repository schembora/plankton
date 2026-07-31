//
//  LibraryView.swift
//  Plankton
//
//  The user's movie and TV show libraries.
//

import JellyfinAPI
import SwiftUI

struct LibraryView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var libraries: [BaseItemDto] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(libraries) { library in
                NavigationLink {
                    LibraryGridView(library: library)
                } label: {
                    Label(
                        library.name ?? "Library",
                        systemImage: library.collectionType == .tvshows ? "tv" : "film"
                    )
                }
            }
            .overlay {
                if isLoading, libraries.isEmpty {
                    ProgressView()
                } else if libraries.isEmpty {
                    ContentUnavailableView {
                        Label("No Libraries", systemImage: "rectangle.stack")
                    } description: {
                        Text("No movie or TV show libraries were found.")
                    }
                }
            }
            .navigationTitle("Library")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        guard let userID = jellyfin.userID else { return }

        isLoading = true
        defer { isLoading = false }

        var parameters = Paths.GetUserViewsParameters()
        parameters.userID = userID

        let result = try? await jellyfin.send(Paths.getUserViews(parameters: parameters))
        libraries = (result?.items ?? []).filter {
            $0.collectionType == .movies || $0.collectionType == .tvshows
        }
    }
}
