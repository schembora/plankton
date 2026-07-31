//
//  PosterGrid.swift
//  Plankton
//
//  The shared scrolling poster grid used by the library and downloads.
//

import SwiftUI

struct PosterGrid<Content: View, Footer: View>: View {

    let content: Content
    let footer: Footer

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                content
            }
            .padding()

            footer
        }
    }
}
