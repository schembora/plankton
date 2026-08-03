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
    @Environment(DownloadService.self) private var downloads

    @State private var resumeItems: [BaseItemDto] = []
    @State private var latestMovies: [BaseItemDto] = []
    @State private var latestShows: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private var isEmpty: Bool {
        resumeItems.isEmpty && latestMovies.isEmpty && latestShows.isEmpty
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
                        if !downloads.activeDownloads.isEmpty {
                            DownloadStrip(showsStorage: false)
                        }
                        if !resumeItems.isEmpty {
                            continueWatching
                        }
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

    /// Wide resume cards rather than posters — what you were part-way through
    /// leads the screen.
    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(resumeItems) { item in
                        NavigationLink {
                            destination(for: item)
                        } label: {
                            ResumeCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
        }
    }

    /// An episode lands on its series with itself surfaced for resume, rather
    /// than on a detail page for the single episode.
    @ViewBuilder
    private func destination(for item: BaseItemDto) -> some View {
        if item.type == .episode, let seriesID = item.seriesID {
            ItemDetailView(item: seriesStub(id: seriesID, name: item.seriesName), resumeEpisode: item)
        } else {
            ItemDetailView(item: item)
        }
    }

    /// `ItemDetailView` refetches by ID on appear, so an ID and type are enough
    /// to land on the series.
    private func seriesStub(id: String, name: String?) -> BaseItemDto {
        var stub = BaseItemDto()
        stub.id = id
        stub.type = .series
        stub.name = name
        return stub
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
        movieParameters.enableUserData = true

        var showParameters = Paths.GetItemsParameters()
        showParameters.userID = userID
        showParameters.includeItemTypes = [.series]
        showParameters.isRecursive = true
        showParameters.sortBy = [.dateCreated]
        showParameters.sortOrder = [.descending]
        showParameters.limit = 20
        showParameters.enableUserData = true

        // Movies and episodes only: a partly-watched series resumes at the
        // episode you stopped on, not the series itself.
        var resumeParameters = Paths.GetResumeItemsParameters()
        resumeParameters.userID = userID
        resumeParameters.includeItemTypes = [.movie, .episode]
        resumeParameters.enableUserData = true
        resumeParameters.limit = 20

        do {
            let movieRequest = Paths.getLatestMedia(parameters: movieParameters)
            let showRequest = Paths.getItems(parameters: showParameters)
            let resumeRequest = Paths.getResumeItems(parameters: resumeParameters)
            async let movies = jellyfin.send(movieRequest)
            async let shows = jellyfin.send(showRequest)
            async let resuming = jellyfin.send(resumeRequest)

            latestMovies = try await movies
            latestShows = try await shows.items ?? []
            resumeItems = try await resuming.items ?? []
        } catch {
            loadFailed = true
        }
    }
}
