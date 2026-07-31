//
//  DownloadCard.swift
//  Plankton
//
//  Poster tiles backed by on-device downloads — everything comes from local
//  data so they render without a connection.
//

import SwiftUI

/// Tile for one downloaded (or downloading) movie/episode. Tap plays from
/// disk; long-press manages the download.
struct DownloadCard: View {

    @Environment(DownloadService.self) private var downloads

    let media: DownloadedMedia

    @State private var playback: PlaybackItem?

    var body: some View {
        PosterTile(
            title: media.title,
            subtitle: subtitle,
            badge: downloads.state(for: media.itemID)
        ) {
            LocalPosterImage(url: downloads.posterFileURL(forItemID: media.itemID))
        }
        .onTapGesture(perform: play)
        .downloadActions(for: media)
        .fullScreenCover(item: $playback) { playback in
            PlayerContainerView(url: playback.url)
        }
    }

    /// "S2 E4 · 45m" for episodes, "1h 32m" for movies.
    private var subtitle: String? {
        let parts = [media.episodeLabel, media.runtimeText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func play() {
        guard let url = downloads.localURL(forItemID: media.itemID) else { return }
        playback = PlaybackItem(url: url)
    }
}

/// Long-press actions for managing one download: cancel, retry, or remove.
struct DownloadActionsModifier: ViewModifier {

    @Environment(DownloadService.self) private var downloads

    let media: DownloadedMedia

    func body(content: Content) -> some View {
        content.contextMenu {
            switch downloads.state(for: media.itemID) {
            case .downloading:
                Button("Cancel Download", systemImage: "xmark") {
                    downloads.cancelDownload(itemID: media.itemID)
                }
            case .downloaded:
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    downloads.delete(itemID: media.itemID)
                }
            case .failed, .none:
                Button("Retry Download", systemImage: "arrow.clockwise") {
                    Task { await downloads.retry(itemID: media.itemID) }
                }
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    downloads.delete(itemID: media.itemID)
                }
            }
        }
    }
}

extension View {
    /// Long-press context actions for a downloaded item's card or row.
    func downloadActions(for media: DownloadedMedia) -> some View {
        modifier(DownloadActionsModifier(media: media))
    }
}

/// Tile for a series in the downloads grid, grouping its episodes behind one
/// poster — mirroring how the library shows series.
struct SeriesDownloadCard: View {

    @Environment(DownloadService.self) private var downloads

    let name: String
    let groupID: String
    let items: [DownloadedMedia]

    var body: some View {
        PosterTile(
            title: name,
            subtitle: "\(items.count) \(items.count == 1 ? "episode" : "episodes")",
            badge: badge
        ) {
            if let first = items.first {
                // The series' own cover art, falling back to the first
                // episode's art for downloads made before it was saved.
                LocalPosterImage(
                    url: downloads.seriesPosterFileURL(forSeriesID: groupID),
                    fallback: downloads.posterFileURL(forItemID: first.itemID)
                )
            }
        }
    }

    private var badge: DownloadService.State? {
        let states = items.compactMap { downloads.state(for: $0.itemID) }
        guard !states.isEmpty else { return nil }

        let inProgress = states.compactMap { state -> Double? in
            guard case .downloading(let progress) = state else { return nil }
            return progress
        }
        if !inProgress.isEmpty {
            return .downloading(progress: inProgress.reduce(0, +) / Double(inProgress.count))
        }
        if states.contains(.failed) { return .failed }
        return .downloaded
    }
}

/// Poster image loaded from the local snapshot saved with a download.
/// Falls back to another local file when the primary one is missing.
struct LocalPosterImage: View {

    let url: URL
    let fallback: URL?

    init(url: URL, fallback: URL? = nil) {
        self.url = url
        self.fallback = fallback
    }

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .task {
            if let loaded = UIImage(contentsOfFile: url.path) {
                image = loaded
            } else if let fallback, let loaded = UIImage(contentsOfFile: fallback.path) {
                image = loaded
            }
        }
    }
}
