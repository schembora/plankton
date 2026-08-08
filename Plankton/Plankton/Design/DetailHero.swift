//
//  DetailHero.swift
//  Plankton
//
//  The banner image every detail page opens with.
//

import SwiftUI

/// Full-bleed artwork at the top of a detail page, faded into the content below.
///
/// The gradient is part of the hero rather than the page: it exists so the
/// image doesn't end on a hard edge, and every page that shows one wants it.
struct DetailHero: View {

    let artwork: Artwork?
    var placeholderIcon: String = "photo"

    /// Holds the previous image while the next loads — for a hero that swaps
    /// between siblings, rather than one that appears once.
    var keepsPreviousWhileLoading = false

    var body: some View {
        MediaImage(
            artwork: artwork,
            placeholderIcon: placeholderIcon,
            keepsPreviousWhileLoading: keepsPreviousWhileLoading
        )
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }
}
