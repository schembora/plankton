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

    /// The item's page on IMDb, when the server knows its ID.
    ///
    /// The provider key is matched case-insensitively: Jellyfin writes "Imdb",
    /// but the casing has varied between metadata plugins, and an exact match
    /// would drop the link with nothing to show for it.
    var imdbURL: URL? {
        let id = providerIDs?
            .first { $0.key.caseInsensitiveCompare("Imdb") == .orderedSame }?
            .value

        guard let id, !id.isEmpty else { return nil }
        return URL(string: "https://www.imdb.com/title/\(id)/")
    }

    /// e.g. "8.6" — the community score out of ten.
    ///
    /// Whichever metadata provider the server used supplied this, so it isn't
    /// labelled as IMDb's even where the two agree.
    var communityRatingText: String? {
        guard let communityRating else { return nil }
        return String(format: "%.1f", communityRating)
    }

    /// e.g. "4K Dolby Vision · HEVC · 38 Mbps" — the shape of the file the
    /// server actually holds.
    ///
    /// Worth showing now that bitrate is capped per network: the number is what
    /// tells you whether an item plays as it is or gets converted on the way.
    /// It describes the source only — deliberately not a prediction of what
    /// will happen, since that's the server's call to make at playback time.
    var mediaSummary: String? {
        guard let source = mediaSources?.first else { return nil }
        let video = source.mediaStreams?.first { $0.type == .video }

        return [
            video.flatMap(Self.resolutionText),
            video?.codec.flatMap(Self.codecText),
            source.bitrate.flatMap(Self.bitrateText),
        ].metadataLine
    }

    /// Named the way a release is described rather than by exact pixel count —
    /// a "4K" file is rarely exactly 3840 wide once it's been cropped.
    private static func resolutionText(_ stream: MediaStream) -> String? {
        guard let width = stream.width else { return nil }

        let resolution: String? = switch width {
        case 3000...: "4K"
        case 1900...: "1080p"
        case 1260...: "720p"
        case 640...: "SD"
        default: nil
        }

        guard let resolution else { return nil }
        guard let range = dynamicRangeText(stream) else { return resolution }
        return "\(resolution) \(range)"
    }

    /// Only the distinctions worth a badge. HDR10 and HLG both read as "HDR"
    /// because nothing the viewer decides turns on which one it is, where
    /// Dolby Vision is the thing people go looking for.
    private static func dynamicRangeText(_ stream: MediaStream) -> String? {
        switch stream.videoRangeType {
        case .dovi, .doviWithHDR10, .doviWithHLG, .doviWithSDR, .doviWithEL,
             .doviWithHDR10Plus, .doviWithELHDR10Plus:
            "Dolby Vision"
        case .hdr10, .hdr10Plus, .hlg:
            "HDR"
        default:
            // Older servers fill in the coarse field and not the specific one.
            stream.videoRange == .hdr ? "HDR" : nil
        }
    }

    private static func codecText(_ codec: String) -> String? {
        switch codec.lowercased() {
        case "h264", "avc": "H.264"
        case "hevc", "h265": "HEVC"
        case "av1": "AV1"
        case "vp9": "VP9"
        case "vp8": "VP8"
        case "mpeg2video": "MPEG-2"
        case "mpeg4": "MPEG-4"
        case "vc1": "VC-1"
        default: codec.uppercased()
        }
    }

    /// Whole megabits above ten: the figure swings shot to shot, and a decimal
    /// there would imply a precision it doesn't have.
    private static func bitrateText(_ bitsPerSecond: Int) -> String? {
        let megabits = Double(bitsPerSecond) / 1_000_000
        guard megabits >= 0.1 else { return nil }

        return megabits >= 10
            ? "\(Int(megabits.rounded())) Mbps"
            : String(format: "%.1f Mbps", megabits)
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

    /// The episode's own still, with no series fallback — unlike
    /// `primaryImageSource`. A series poster is the wrong shape in a 16:9
    /// thumbnail slot, so an episode without a still of its own gets nothing.
    var episodeStillImageSource: (itemID: String, tag: String?)? {
        guard let itemID = id, let tag = imageTags?[ImageType.primary.rawValue] else { return nil }
        return (itemID, tag)
    }

    // MARK: - Artwork

    /// Resolves one of the item's images into an `Artwork` for `MediaImage`, so
    /// no view builds an image URL by hand. The `*ImageSource` properties above
    /// stay as the lower-level pieces — `DownloadService` uses them directly to
    /// snapshot art to disk.
    func artwork(_ kind: Artwork.Kind, maxWidth: Int) -> Artwork? {
        let source: (itemID: String, tag: String?)?
        let imageType: ImageType

        switch kind {
        case .poster:
            source = posterImageSource
            imageType = .primary
        case .primary:
            source = primaryImageSource
            imageType = .primary
        case .backdrop:
            source = backdropImageSource
            imageType = .backdrop
        case .wide:
            source = wideImageSource
            // An episode's wide art is its own still, which is a primary image.
            imageType = type == .episode ? .primary : .backdrop
        case .episodeStill:
            source = episodeStillImageSource
            imageType = .primary
        }

        guard let source else { return nil }
        return .remote(itemID: source.itemID, type: imageType, tag: source.tag, maxWidth: maxWidth)
    }
}
