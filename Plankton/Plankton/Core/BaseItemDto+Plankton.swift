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

    /// How far through the item the user is, as 0...1. Nil when playback hasn't
    /// started or has finished, so callers can skip drawing a progress bar.
    var watchedProgress: Double? {
        guard let percentage = userData?.playedPercentage, percentage > 0, percentage < 100 else {
            return nil
        }
        return percentage / 100
    }

    /// Where playback should resume, in Jellyfin ticks. Nil when unwatched.
    var resumePositionTicks: Int? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return ticks
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

    /// e.g. "18m left" — how much of a part-watched item is still to go.
    var remainingText: String? {
        guard let runTimeTicks,
              let position = userData?.playbackPositionTicks,
              position > 0
        else { return nil }

        let minutes = (runTimeTicks - position) / 600_000_000
        guard minutes > 0 else { return nil }

        if minutes >= 60 {
            let remainder = minutes % 60
            return remainder > 0 ? "\(minutes / 60)h \(remainder)m left" : "\(minutes / 60)h left"
        }
        return "\(minutes)m left"
    }

    /// 16:9 art for a resume card. An episode's own primary image is the still,
    /// which is already the right shape here — unlike in a poster tile.
    var wideImageSource: (itemID: String, tag: String?)? {
        if type == .episode, let itemID = id, let tag = imageTags?[ImageType.primary.rawValue] {
            return (itemID, tag)
        }
        return backdropImageSource
    }

    /// Poster source for a 2:3 tile. Episodes prefer their series' artwork:
    /// an episode's own primary image is a 16:9 still that crops badly in a
    /// poster frame, and the series cover is what people recognise.
    var posterImageSource: (itemID: String, tag: String?)? {
        if type == .episode, let seriesID, let tag = seriesPrimaryImageTag {
            return (seriesID, tag)
        }
        return primaryImageSource
    }

    /// Second line on a poster tile: which episode this is for episodes,
    /// release year for everything else.
    var posterSubtitle: String? {
        if type == .episode {
            return episodeLabel
        }
        return productionYear.map(String.init)
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
