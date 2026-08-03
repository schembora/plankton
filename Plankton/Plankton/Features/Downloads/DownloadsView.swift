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
        NavigationStack {
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
                        NavigationLink {
                            SeriesDownloadsView(groupID: id, seriesName: name)
                        } label: {
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
            }
            .overlay {
                if downloads.media.isEmpty {
                    ContentUnavailableView {
                        Label("No Downloads", systemImage: "arrow.down.circle")
                    } description: {
                        Text("Movies and episodes you download will appear here, ready to watch offline.")
                    }
                }
            }
            .navigationTitle("Downloads")
        }
    }
}
