//
//  PosterCard.swift
//  Plankton
//
//  Poster tile backed by a Jellyfin item. Used in shelves and library grids.
//

import JellyfinAPI
import SwiftUI

struct PosterCard: View {

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(DownloadService.self) private var downloads

    let item: BaseItemDto

    /// Fixed width for horizontal shelves. Pass `nil` to fill a grid cell.
    var width: CGFloat? = 120

    var body: some View {
        PosterTile(
            title: item.displayTitle,
            subtitle: item.productionYear.map(String.init),
            badge: downloads.state(for: item.id)
        ) {
            JellyfinImage(url: posterURL)
        }
        .frame(width: width)
    }

    private var posterURL: URL? {
        guard let source = item.primaryImageSource else { return nil }
        return jellyfin.imageURL(itemID: source.itemID, type: .primary, tag: source.tag, maxWidth: 500)
    }
}
