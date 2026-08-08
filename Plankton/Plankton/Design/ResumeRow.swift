//
//  ResumeRow.swift
//  Plankton
//
//  Horizontal shelf of wide resume cards — the episode-aware counterpart to
//  MediaRow, used by both Continue Watching and Next Up.
//

import JellyfinAPI
import SwiftUI

struct ResumeRow: View {

    let title: String
    let items: [BaseItemDto]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
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

    /// An episode lands on its series with itself surfaced for playback, rather
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
}
