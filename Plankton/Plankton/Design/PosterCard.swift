//
//  PosterCard.swift
//  Plankton
//
//  2:3 poster with title and year. Used in shelves and library grids.
//

import JellyfinAPI
import SwiftUI

struct PosterCard: View {

    @Environment(JellyfinService.self) private var jellyfin

    let item: BaseItemDto

    /// Fixed width for horizontal shelves. Pass `nil` to fill a grid cell.
    var width: CGFloat? = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    JellyfinImage(url: posterURL)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                }

            Text(item.displayTitle)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            if let year = item.productionYear {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
    }

    private var posterURL: URL? {
        guard let source = item.primaryImageSource else { return nil }
        return jellyfin.imageURL(itemID: source.itemID, type: .primary, tag: source.tag, maxWidth: 500)
    }
}
