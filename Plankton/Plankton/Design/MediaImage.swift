//
//  MediaImage.swift
//  Plankton
//
//  The one artwork view — server or on-device — backed by ImageCache.
//

import SwiftUI

/// Draws a piece of `Artwork`, with a placeholder until it arrives.
///
/// Server-backed and downloaded media go through the same view for the same
/// reason `PosterTile` is shared: both should look identical, and both benefit
/// from the same cache. Pass `nil` when an item has no artwork of this kind.
struct MediaImage: View {

    @Environment(ImageCache.self) private var cache

    let artwork: Artwork?
    var placeholderIcon: String = "film"

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        // Keyed on the artwork: a recycled cell has to drop the previous
        // item's image rather than keep showing it under a new title.
        .task(id: artwork) {
            guard let artwork else {
                image = nil
                return
            }

            // A cached poster scrolling back into view should draw immediately
            // instead of flashing its placeholder for a frame.
            if let hit = cache.cached(artwork) {
                image = hit
                didFail = false
                return
            }

            image = nil
            didFail = false

            let loaded = await cache.image(for: artwork)
            image = loaded
            didFail = loaded == nil
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: didFail ? "photo" : placeholderIcon)
                .font(.title2)
                .foregroundStyle(.tertiary)
        }
    }
}
