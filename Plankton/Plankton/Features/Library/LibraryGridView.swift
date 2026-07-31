//
//  LibraryGridView.swift
//  Plankton
//
//  Paged poster grid for a single library.
//

import JellyfinAPI
import SwiftUI

struct LibraryGridView: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads

    let library: BaseItemDto

    @State private var items: [BaseItemDto] = []
    @State private var totalCount = 0
    @State private var isLoading = false

    private let pageSize = 50

    private var itemTypes: [BaseItemKind]? {
        switch library.collectionType {
        case .movies: [.movie]
        case .tvshows: [.series]
        default: nil
        }
    }

    var body: some View {
        PosterGrid {
            ForEach(items) { item in
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    PosterCard(item: item, width: nil)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if item.type == .movie {
                        downloadAction(for: item)
                    }
                }
                .onAppear {
                    if item.id == items.last?.id {
                        Task { await loadNextPage() }
                    }
                }
            }
        } footer: {
            if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle(library.name ?? "Library")
        .task { await loadNextPage() }
    }

    /// Long-press action matching the item's download state.
    @ViewBuilder
    private func downloadAction(for item: BaseItemDto) -> some View {
        switch downloads.state(for: item.id) {
        case .none, .failed:
            Button("Download", systemImage: "arrow.down") {
                Task { await downloads.download(item: item) }
            }
        case .downloading:
            Button("Cancel Download", systemImage: "xmark") {
                if let itemID = item.id {
                    downloads.cancelDownload(itemID: itemID)
                }
            }
        case .downloaded:
            Button("Remove Download", systemImage: "trash", role: .destructive) {
                if let itemID = item.id {
                    downloads.delete(itemID: itemID)
                }
            }
        }
    }

    private func loadNextPage() async {
        guard !isLoading, let userID = jellyfin.userID, let libraryID = library.id else { return }
        guard totalCount == 0 || items.count < totalCount else { return }

        isLoading = true
        defer { isLoading = false }

        var parameters = Paths.GetItemsParameters()
        parameters.userID = userID
        parameters.parentID = libraryID
        parameters.includeItemTypes = itemTypes
        parameters.isRecursive = true
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
        parameters.startIndex = items.count
        parameters.limit = pageSize

        guard let result = try? await jellyfin.send(Paths.getItems(parameters: parameters)) else { return }

        totalCount = result.totalRecordCount ?? 0
        items.append(contentsOf: result.items ?? [])
    }
}
