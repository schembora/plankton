//
//  LibraryView.swift
//  Plankton
//
//  Everything on the server in one grid — filter by media type or genre,
//  sort, and drill into any item. Replaces the old two-row library list,
//  which cost a tap to reach the only thing anyone wanted.
//

import JellyfinAPI
import SwiftUI

struct LibraryView: View {

    @Environment(JellyfinService.self) private var jellyfin

    /// Which kind of media the grid is showing.
    private enum MediaFilter: String, CaseIterable, Identifiable {
        case all, movies, shows

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .movies: "Movies"
            case .shows: "Shows"
            }
        }

        var itemTypes: [BaseItemKind] {
            switch self {
            case .all: [.movie, .series]
            case .movies: [.movie]
            case .shows: [.series]
            }
        }
    }

    /// Sort field, paired with the server's sort key.
    private enum SortOption: String, CaseIterable, Identifiable {
        case dateAdded, name, releaseYear, rating

        var id: Self { self }

        var title: String {
            switch self {
            case .dateAdded: "Date Added"
            case .name: "Name"
            case .releaseYear: "Release Year"
            case .rating: "Rating"
            }
        }

        var sortBy: ItemSortBy {
            switch self {
            case .dateAdded: .dateCreated
            case .name: .sortName
            case .releaseYear: .premiereDate
            case .rating: .communityRating
            }
        }

        /// A–Z reads right for names; everything else wants newest/highest first.
        var prefersAscending: Bool { self == .name }
    }

    /// Everything that decides which items the server returns. Bundled so a
    /// single `onChange` can restart the query no matter which control moved.
    private struct Query: Equatable {
        var filter: MediaFilter
        var sort: SortOption
        var isAscending: Bool
        var genre: String?
    }

    @State private var items: [BaseItemDto] = []
    @State private var genres: [String] = []
    @State private var totalCount = 0
    @State private var isLoading = false

    @State private var filter: MediaFilter = .all
    @State private var sort: SortOption = .dateAdded
    @State private var isAscending = false
    @State private var genre: String?

    @State private var showSearchNotice = false
    @State private var loadFailed = false

    /// Bumped on every restart so results from a superseded query are dropped.
    @State private var generation = 0

    private let pageSize = 60

    private var query: Query {
        Query(filter: filter, sort: sort, isAscending: isAscending, genre: genre)
    }

    private var hasActiveFilter: Bool {
        filter != .all || genre != nil
    }

    var body: some View {
        NavigationStack {
            PosterGrid {
                ForEach(items) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        PosterCard(item: item, width: nil)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }
            } footer: {
                if isLoading, !items.isEmpty {
                    ProgressView()
                        .padding()
                }
            }
            // Applied before the inset below, deliberately: `refreshable` is
            // inherited through the environment, and if the filter bar sits
            // inside its subtree the horizontal chip strip grows its own
            // pull-to-refresh and reloads when dragged sideways.
            .refreshable { await reload() }
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .overlay { emptyState }
            // No navigation bar: the filter bar is the header, and a large
            // title fought the pinned inset for the same space.
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard items.isEmpty else { return }
                await reload()
                await loadGenres()
            }
            .onChange(of: query) { _, _ in
                Task { await reload() }
            }
            // Back online after offline mode — populate the grid.
            .onChange(of: jellyfin.isOffline) { _, isOffline in
                if !isOffline, items.isEmpty {
                    Task {
                        await reload()
                        await loadGenres()
                    }
                }
            }
            .alert("Search Is Coming Soon", isPresented: $showSearchNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Searching your server isn't wired up yet. For now, narrow things down with the filters and sort options.")
            }
        }
    }

    // MARK: - Filter bar

    /// Search field and filter chips, pinned above the grid so they stay
    /// reachable while scrolling.
    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    showSearchNotice = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)

                sortMenu
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MediaFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            chipLabel(option.title, isSelected: filter == option)
                        }
                        .buttonStyle(.plain)
                    }

                    if !genres.isEmpty {
                        genreMenu
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 10)
        // Thin enough to keep the blur of the artwork scrolling underneath,
        // while still stopping titles reading through the gaps. Runs up under
        // the status bar since there's no navigation bar covering that strip.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var genreMenu: some View {
        Menu {
            Button("All Genres") { genre = nil }
            Divider()
            ForEach(genres, id: \.self) { name in
                Button(name) { genre = name }
            }
        } label: {
            chipLabel(genre ?? "Genre", systemImage: "chevron.down", isSelected: genre != nil)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, systemImage: String? = nil, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if isSelected {
                Capsule().fill(Color.accentColor)
            } else {
                // Outlined rather than filled. A translucent fill stacks on
                // the bar's material and renders lighter than it, which is
                // what made the gaps between chips look dark by comparison.
                Capsule().strokeBorder(.tertiary, lineWidth: 1)
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(SortOption.allCases) { option in
                    Button {
                        sort = option
                        isAscending = option.prefersAscending
                    } label: {
                        if sort == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            }
            Section {
                Button {
                    isAscending.toggle()
                } label: {
                    Label(
                        isAscending ? "Ascending" : "Descending",
                        systemImage: isAscending ? "arrow.up" : "arrow.down"
                    )
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort")
    }

    @ViewBuilder
    private var emptyState: some View {
        if jellyfin.isOffline {
            OfflineView()
        } else if isLoading, items.isEmpty {
            ProgressView()
        } else if loadFailed, items.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Library", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection to the server.")
            } actions: {
                Button("Try Again") {
                    Task { await reload() }
                }
                .buttonStyle(.glass)
            }
        } else if items.isEmpty {
            ContentUnavailableView {
                Label("Nothing Here", systemImage: "rectangle.stack")
            } description: {
                Text(hasActiveFilter
                    ? "No media matches these filters."
                    : "No movies or TV shows were found on your server.")
            } actions: {
                if hasActiveFilter {
                    Button("Clear Filters") {
                        filter = .all
                        genre = nil
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    // MARK: - Loading

    /// Restarts the query from the first page. The existing items stay on
    /// screen until replacements arrive, so a failed or cancelled refresh
    /// (pull-to-refresh tasks do get cancelled) leaves the grid intact
    /// instead of emptying it into the "Nothing Here" state.
    private func reload() async {
        generation += 1
        let requested = generation

        isLoading = true
        defer { isLoading = false }

        guard let page = await fetchPage(startIndex: 0) else {
            // Only surface an error when there's nothing already on screen.
            loadFailed = items.isEmpty
            return
        }
        guard requested == generation else { return }  // Superseded by a newer query.

        loadFailed = false
        items = page.items
        totalCount = page.total
    }

    private func loadMore() async {
        guard !isLoading, items.count < totalCount else { return }
        let requested = generation

        isLoading = true
        defer { isLoading = false }

        guard let page = await fetchPage(startIndex: items.count),
              requested == generation
        else { return }

        items.append(contentsOf: page.items)
        totalCount = page.total
    }

    /// One page of the current query, or nil if the request failed.
    private func fetchPage(startIndex: Int) async -> (items: [BaseItemDto], total: Int)? {
        guard let userID = jellyfin.userID else { return nil }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.includeItemTypes = filter.itemTypes
        parameters.isRecursive = true
        parameters.sortBy = [sort.sortBy]
        parameters.sortOrder = [isAscending ? .ascending : .descending]
        parameters.startIndex = startIndex
        parameters.limit = pageSize
        // Drives the watched-progress bar on each poster.
        parameters.enableUserData = true
        if let genre {
            parameters.genres = [genre]
        }

        guard let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) else { return nil }
        return (result.items ?? [], result.totalRecordCount ?? 0)
    }

    /// Genres are loaded once across both media types, so switching between
    /// Movies and Shows never invalidates the chosen genre.
    private func loadGenres() async {
        guard let userID = jellyfin.userID else { return }

        var parameters = Paths.GetGenresParameters()
        parameters.userID = userID
        parameters.includeItemTypes = [.movie, .series]
        parameters.sortBy = [.sortName]

        guard let result = try? await jellyfin.send(Paths.getGenres(parameters: parameters)) else { return }
        genres = (result.items ?? []).compactMap(\.name)
    }
}
