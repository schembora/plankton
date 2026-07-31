//
//  BaseItemDto+Plankton.swift
//  Plankton
//
//  Display and image helpers for Jellyfin items.
//

import Foundation
import JellyfinAPI

extension BaseItemDto {

    /// Best title to show in lists — series name for episodes, otherwise the item name.
    var displayTitle: String {
        if type == .episode, let seriesName {
            return seriesName
        }
        return name ?? String(localized: "Unknown")
    }

    /// e.g. "1h 32m" or "45m".
    var runtimeText: String? {
        guard let runTimeTicks else { return nil }
        let minutes = runTimeTicks / 600_000_000
        guard minutes > 0 else { return nil }

        if minutes >= 60 {
            let remainder = minutes % 60
            return remainder > 0 ? "\(minutes / 60)h \(remainder)m" : "\(minutes / 60)h"
        }
        return "\(minutes)m"
    }

    /// e.g. "S2 E4" for episodes.
    var episodeLabel: String? {
        guard type == .episode else { return nil }
        var parts: [String] = []
        if let season = parentIndexNumber { parts.append("S\(season)") }
        if let episode = indexNumber { parts.append("E\(episode)") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Item ID and image tag for the primary (poster) image.
    /// Episodes fall back to their series poster when they have none of their own.
    var primaryImageSource: (itemID: String, tag: String?)? {
        if let itemID = id, let tag = imageTags?[ImageType.primary.rawValue] {
            return (itemID, tag)
        }
        if let seriesID, let tag = seriesPrimaryImageTag {
            return (seriesID, tag)
        }
        return nil
    }

    /// Item ID and image tag for the backdrop (hero) image, falling back to the parent's.
    var backdropImageSource: (itemID: String, tag: String?)? {
        if let itemID = id, let tag = backdropImageTags?.first {
            return (itemID, tag)
        }
        if let parentID = parentBackdropItemID, let tag = parentBackdropImageTags?.first {
            return (parentID, tag)
        }
        return nil
    }
}
