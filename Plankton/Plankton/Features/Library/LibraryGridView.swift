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

    let library: BaseItemDto

    @State private var items: [BaseItemDto] = []
    @State private var totalCount = 0
    @State private var isLoading = false

    private let pageSize = 50
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    private var itemTypes: [BaseItemKind]? {
        switch library.collectionType {
        case .movies: [.movie]
        case .tvshows: [.series]
        default: nil
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        PosterCard(item: item, width: nil)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadNextPage() }
                        }
                    }
                }
            }
            .padding()

            if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle(library.name ?? "Library")
        .task { await loadNextPage() }
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
