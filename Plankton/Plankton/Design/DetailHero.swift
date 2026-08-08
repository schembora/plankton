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
        // `Color.clear` decides the size, with the artwork laid over it — the
        // same shape the poster cards use, and for the same reason. A resizable
        // Image reports the pixel size of whatever loaded as its ideal width, so
        // letting one size the hero puts a 1600pt-wide backdrop's width onto the
        // page the moment it arrives, and every padded row below is then laid
        // out in a canvas far wider than the screen. `Color.clear` has no
        // intrinsic size, so it can never do that.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .overlay {
                MediaImage(
                    artwork: artwork,
                    placeholderIcon: placeholderIcon,
                    keepsPreviousWhileLoading: keepsPreviousWhileLoading
                )
            }
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
