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

    /// Both shelves point at one specific episode, so that episode's own page
    /// is where they lead — its description included. The series is a tap
    /// further on from there.
    @ViewBuilder
    private func destination(for item: BaseItemDto) -> some View {
        if item.type == .episode {
            EpisodeDetailView(episode: item)
        } else {
            ItemDetailView(item: item)
        }
    }
}
