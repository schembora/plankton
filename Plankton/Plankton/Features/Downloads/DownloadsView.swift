//
//  DownloadsView.swift
//  Plankton
//
//  Everything saved on the device, grouped like the library — movies as
//  individual tiles, series behind one tile each — playable without a
//  connection.
//

import SwiftUI

struct DownloadsView: View {

    @Environment(DownloadService.self) private var downloads
    @Environment(JellyfinService.self) private var jellyfin
    @Environment(AppRouter.self) private var router

    /// Sampled rather than read in `body`: it walks the download directory,
    /// which is not something to do on every redraw.
    @State private var storageUsed: Int64 = 0
    @State private var isConfirmingDelete = false

    /// Below a megabyte there is no media left, only the index file and the
    /// empty directories it sits beside — a cleared download folder still
    /// costs a few kilobytes. Reporting that would put a Delete All on screen
    /// that frees nothing.
    private var hasStoredMedia: Bool { storageUsed > 1_000_000 }

    /// One grid entry: a single movie, or a series grouping its episodes.
    private enum Entry: Identifiable {
        case movie(DownloadedMedia)
        case series(id: String, name: String, items: [DownloadedMedia])

        var id: String {
            switch self {
            case .movie(let media): media.itemID
            case .series(let id, _, _): id
            }
        }

        /// Newest activity in the entry, for sorting.
        var lastActivity: Date {
            switch self {
            case .movie(let media): media.startedAt
            case .series(_, _, let items): items.map(\.startedAt).max() ?? .distantPast
            }
        }
    }

    private var entries: [Entry] {
        var movies: [Entry] = []
        var series: [String: (name: String, items: [DownloadedMedia])] = [:]

        for media in downloads.media {
            if let groupID = media.seriesGroupID {
                series[groupID, default: (media.seriesName ?? media.title, [])].items.append(media)
            } else {
                movies.append(.movie(media))
            }
        }

        return movies + series.map { .series(id: $0.key, name: $0.value.name, items: $0.value.items) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var body: some View {
        // Path-bound so a Spotlight result can land on a downloaded series
        // while the server is unreachable and the Library tab is disabled.
        @Bindable var router = router

        NavigationStack(path: $router.downloadsPath) {
            PosterGrid {
                VStack(alignment: .leading, spacing: 14) {
                    if jellyfin.isOffline {
                        OfflineHeader()
                    }
                    if !downloads.media.isEmpty {
                        DownloadStrip()
                    }
                }
            } content: {
                ForEach(entries) { entry in
                    switch entry {
                    case .movie(let media):
                        DownloadCard(media: media)
                    case .series(let id, let name, let items):
                        NavigationLink(value: DownloadsRoute.series(groupID: id, name: name)) {
                            SeriesDownloadCard(name: name, groupID: id, items: items)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove Downloads", systemImage: "trash", role: .destructive) {
                                for media in items {
                                    downloads.delete(itemID: media.itemID)
                                }
                            }
                        }
                    }
                }
            } footer: {
                storageFooter
            }
            .overlay {
                if downloads.media.isEmpty && !hasStoredMedia {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Movies and episodes you download will appear here, ready to watch offline.")
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationDestination(for: DownloadsRoute.self) { route in
                switch route {
                case let .series(groupID, name):
                    SeriesDownloadsView(groupID: groupID, seriesName: name)
                }
            }
        }
        .task { refreshStorage() }
        .onChange(of: downloads.media) { _, _ in refreshStorage() }
        .confirmationDialog(
            "Delete all downloads?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(DownloadService.sizeText(storageUsed))", role: .destructive) {
                downloads.deleteAll()
                refreshStorage()
            }
        } message: {
            Text("Everything saved on this device will be removed. You can download it again from your server.")
        }
    }

    /// Shown whenever media is on disk — including when the grid is empty,
    /// which is the case worth having it for. Downloads live in Application
    /// Support, so a file the index lost can't be reached from the Files app
    /// either; this is the only way to be rid of it.
    @ViewBuilder
    private var storageFooter: some View {
        if hasStoredMedia {
            VStack(spacing: 8) {
                Text("\(DownloadService.sizeText(storageUsed)) used")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Delete All", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private func refreshStorage() {
        storageUsed = downloads.storageUsed
    }
}
