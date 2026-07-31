//
//  MediaRow.swift
//  Plankton
//
//  Horizontal scrolling shelf of posters with a section header.
//

import JellyfinAPI
import SwiftUI

struct MediaRow: View {

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
                            ItemDetailView(item: item)
                        } label: {
                            PosterCard(item: item)
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
}
