//
//  PosterGrid.swift
//  Plankton
//
//  The shared scrolling poster grid used by the library and downloads.
//

import SwiftUI

struct PosterGrid<Header: View, Content: View, Footer: View>: View {

    let header: Header
    let content: Content
    let footer: Footer

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    init(
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            header

            LazyVGrid(columns: columns, spacing: 16) {
                content
            }
            .padding()

            footer
        }
    }
}
