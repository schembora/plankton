//
//  PosterCard.swift
//  Plankton
//
//  Poster tile backed by a Jellyfin item. Used in shelves and library grids.
//

import JellyfinAPI
import SwiftUI

struct PosterCard: View {

    @Environment(DownloadService.self) private var downloads

    let item: BaseItemDto

    /// Fixed width for horizontal shelves. Pass `nil` to fill a grid cell.
    var width: CGFloat? = 120

    var body: some View {
        PosterTile(
            // For an episode this reads as the series name over "S2 E4".
            title: item.displayTitle,
            subtitle: item.posterSubtitle,
            badge: downloads.state(for: item.id),
            watchedProgress: item.watchedProgress
        ) {
            MediaImage(artwork: item.artwork(.poster, maxWidth: 500))
        }
        .frame(width: width)
    }
}
