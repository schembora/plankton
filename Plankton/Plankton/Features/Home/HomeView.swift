//
//  HomeView.swift
//  Plankton
//
//  Shelves of the latest movies and TV shows.
//

import JellyfinAPI
import SwiftUI

struct HomeView: View {

    @Environment(JellyfinService.self) private var jellyfin

    @State private var latestMovies: [BaseItemDto] = []
    @State private var latestShows: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var isEmpty: Bool {
        latestMovies.isEmpty && latestShows.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if jellyfin.isOffline {
                    OfflineView()
                } else if isLoading, isEmpty {
                    ProgressView()
                        .padding(.top, 120)
                } else if loadFailed, isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load Media", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Check your connection to the server.")
                    } actions: {
                        Button("Try Again") {
                            Task { await load() }
                        }
                        .buttonStyle(.glass)
                    }
                } else if isEmpty {
                    ContentUnavailableView {
                        Label("No Media Found", systemImage: "film.stack")
                    } description: {
                        Text("Your Jellyfin libraries are empty.")
                    }
                } else {
                    VStack(spacing: 28) {
                        if !latestMovies.isEmpty {
                            MediaRow(title: "Latest Movies", items: latestMovies)
                        }
                        if !latestShows.isEmpty {
                            MediaRow(title: "Latest TV Shows", items: latestShows)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Home")
            .refreshable { await load() }
            .task { await load() }
            // Back online after offline mode — load the shelves.
            .onChange(of: jellyfin.isOffline) { _, isOffline in
                if !isOffline, isEmpty {
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        guard let userID = jellyfin.userID else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        var movieParameters = Paths.GetLatestMediaParameters()
        movieParameters.userID = userID
        movieParameters.includeItemTypes = [.movie]
        movieParameters.limit = 20

        var showParameters = Paths.GetItemsParameters()
        showParameters.userID = userID
        showParameters.includeItemTypes = [.series]
        showParameters.isRecursive = true
        showParameters.sortBy = [.dateCreated]
        showParameters.sortOrder = [.descending]
        showParameters.limit = 20

        do {
            let movieRequest = Paths.getLatestMedia(parameters: movieParameters)
            let showRequest = Paths.getItems(parameters: showParameters)
            async let movies = jellyfin.send(movieRequest)
            async let shows = jellyfin.send(showRequest)

            latestMovies = try await movies
            latestShows = try await shows.items ?? []
        } catch {
            loadFailed = true
        }
    }
}
