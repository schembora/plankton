//
//  DownloadScopeSheet.swift
//  Plankton
//
//  Scopes a series download — this season or the whole show — and shows what
//  it costs before committing.
//

import JellyfinAPI
import SwiftUI

struct DownloadScopeSheet: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    let seriesID: String
    let seasonNumber: Int?

    /// Episodes of the season on screen, already loaded by the detail page —
    /// used until the full-series fetch lands so the sheet opens populated.
    let seasonEpisodes: [BaseItemDto]

    private enum Scope: Hashable {
        case season, series
    }

    @State private var scope: Scope = .season
    @State private var allEpisodes: [BaseItemDto] = []
    @State private var isLoading = true
    @State private var isStarting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        option(
                            .season,
                            title: seasonNumber.map { "Rest of season \($0)" } ?? "Rest of this season",
                            episodes: pending(in: seasonPool),
                            isResolved: true
                        )
                        option(
                            .series,
                            title: "Whole series",
                            episodes: pending(in: allEpisodes),
                            isResolved: !isLoading
                        )
                    } footer: {
                        if let footer {
                            Text(footer)
                        }
                    }
                }

                downloadButton
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadSeries() }
        }
    }

    // MARK: - Options

    private func option(
        _ value: Scope,
        title: String,
        episodes: [BaseItemDto],
        isResolved: Bool
    ) -> some View {
        Button {
            scope = value
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle(for: episodes, isResolved: isResolved))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: scope == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(scope == value ? Color.accentColor : Color.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isResolved && episodes.isEmpty)
    }

    /// e.g. "6 episodes · ~7.1 GB". Sizes are the server's source-file sizes,
    /// so a transcoded download won't match exactly — hence the tilde.
    private func subtitle(for episodes: [BaseItemDto], isResolved: Bool) -> String {
        guard isResolved else { return "Checking…" }
        guard !episodes.isEmpty else { return "Nothing left to download" }

        var parts = ["\(episodes.count) \(episodes.count == 1 ? "episode" : "episodes")"]
        let bytes = totalBytes(of: episodes)
        if bytes > 0 {
            parts.append("~\(DownloadService.sizeText(bytes))")
        }
        return parts.joined(separator: " · ")
    }

    private var downloadButton: some View {
        let episodes = selectedEpisodes

        return Button {
            isStarting = true
            Task {
                await downloads.download(items: episodes)
                isStarting = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if isStarting {
                    ProgressView()
                }
                Text(episodes.isEmpty
                    ? "Nothing to Download"
                    : "Download \(episodes.count) \(episodes.count == 1 ? "Episode" : "Episodes")")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(episodes.isEmpty || isStarting)
    }

    /// "7.1 GB will leave 38 GB free."
    private var footer: String? {
        let bytes = totalBytes(of: selectedEpisodes)
        guard bytes > 0 else { return nil }

        let free = downloads.deviceAvailableBytes - bytes
        guard free > 0 else {
            return "Not enough space free for this download."
        }
        return "\(DownloadService.sizeText(bytes)) will leave \(DownloadService.sizeText(free)) free."
    }

    // MARK: - Data

    /// Prefer the full-series fetch once it lands — those carry media sources,
    /// so sizes resolve. The detail page's episodes stand in until then.
    private var seasonPool: [BaseItemDto] {
        guard !allEpisodes.isEmpty, let seasonNumber else { return seasonEpisodes }
        return allEpisodes.filter { $0.parentIndexNumber == seasonNumber }
    }

    private var selectedEpisodes: [BaseItemDto] {
        switch scope {
        case .season: pending(in: seasonPool)
        case .series: pending(in: allEpisodes)
        }
    }

    /// Skips anything already on device so the count reflects real work.
    private func pending(in episodes: [BaseItemDto]) -> [BaseItemDto] {
        episodes.filter { downloads.state(for: $0.id) != .downloaded }
    }

    private func totalBytes(of episodes: [BaseItemDto]) -> Int64 {
        episodes.reduce(Int64(0)) { total, episode in
            total + Int64(episode.mediaSources?.first?.size ?? 0)
        }
    }

    /// One request for every episode in the series, asking for media sources
    /// so sizes come back with them rather than needing a call per episode.
    private func loadSeries() async {
        defer { isLoading = false }
        guard let userID = jellyfin.userID else { return }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = seriesID
        parameters.isRecursive = true
        parameters.includeItemTypes = [.episode]
        parameters.fields = [.mediaSources]
        parameters.limit = 500

        guard let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) else { return }
        allEpisodes = result.items ?? []
    }
}
