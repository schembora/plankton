//
//  MediaSummaryTests.swift
//  PlanktonTests
//
//  The source-file line on a detail page: resolution, codec and bitrate.
//

import Foundation
import JellyfinAPI
import Testing

@testable import Plankton

@MainActor
struct MediaSummaryTests {

    /// An item carrying one video stream, the way the server returns it.
    private func makeItem(
        width: Int? = 1920,
        codec: String? = "h264",
        bitrate: Int? = 8_000_000,
        range: VideoRange? = nil,
        rangeType: VideoRangeType? = nil
    ) -> BaseItemDto {
        var stream = MediaStream()
        stream.type = .video
        stream.width = width
        stream.codec = codec
        stream.videoRange = range
        stream.videoRangeType = rangeType

        var source = MediaSourceInfo()
        source.bitrate = bitrate
        source.mediaStreams = [stream]

        var item = BaseItemDto()
        item.type = .movie
        item.mediaSources = [source]
        return item
    }

    @Test func summarisesResolutionCodecAndBitrate() {
        #expect(makeItem().mediaSummary == "1080p · H.264 · 8.0 Mbps")
    }

    /// Nothing to describe without media sources — the caller leaves the line
    /// out rather than drawing an empty one.
    @Test func itemWithoutMediaSourcesHasNoSummary() {
        var item = BaseItemDto()
        item.type = .series

        #expect(item.mediaSummary == nil)
    }

    @Test(arguments: [
        (3840, "4K"), (3200, "4K"), (1920, "1080p"), (1280, "720p"), (854, "SD"),
    ])
    func widthMapsToAReleaseName(_ width: Int, _ expected: String) {
        let summary = makeItem(width: width, codec: nil, bitrate: nil).mediaSummary
        #expect(summary == expected)
    }

    @Test func unrecognisablyNarrowVideoHasNoResolution() {
        #expect(makeItem(width: 320, codec: nil, bitrate: nil).mediaSummary == nil)
    }

    @Test(arguments: [
        ("h264", "H.264"), ("avc", "H.264"), ("hevc", "HEVC"), ("h265", "HEVC"),
        ("av1", "AV1"), ("vc1", "VC-1"), ("mpeg2video", "MPEG-2"),
    ])
    func knownCodecsGetTheirUsualName(_ codec: String, _ expected: String) {
        #expect(makeItem(width: nil, codec: codec, bitrate: nil).mediaSummary == expected)
    }

    /// An unknown codec is still worth showing — better the raw name than a
    /// gap where the codec should be.
    @Test func unknownCodecFallsBackToItsRawName() {
        #expect(makeItem(width: nil, codec: "ffv1", bitrate: nil).mediaSummary == "FFV1")
    }

    // MARK: - Bitrate

    /// A decimal past ten megabits implies a precision the figure doesn't have.
    @Test func bitrateLosesItsDecimalAboveTenMegabits() {
        #expect(makeItem(width: nil, codec: nil, bitrate: 38_400_000).mediaSummary == "38 Mbps")
        #expect(makeItem(width: nil, codec: nil, bitrate: 9_600_000).mediaSummary == "9.6 Mbps")
    }

    @Test func negligibleBitrateIsOmitted() {
        #expect(makeItem(width: nil, codec: nil, bitrate: 0).mediaSummary == nil)
    }

    // MARK: - Dynamic range

    @Test func dolbyVisionIsNamedSeparatelyFromHDR() {
        let item = makeItem(width: 3840, codec: nil, bitrate: nil, rangeType: .doviWithHDR10)
        #expect(item.mediaSummary == "4K Dolby Vision")
    }

    @Test(arguments: [VideoRangeType.hdr10, .hdr10Plus, .hlg])
    func hdrFlavoursAllReadAsHDR(_ rangeType: VideoRangeType) {
        let item = makeItem(width: 3840, codec: nil, bitrate: nil, rangeType: rangeType)
        #expect(item.mediaSummary == "4K HDR")
    }

    /// Older servers fill in the coarse field and leave the specific one unset.
    @Test func coarseRangeIsUsedWhenTheSpecificOneIsMissing() {
        let item = makeItem(width: 1920, codec: nil, bitrate: nil, range: .hdr)
        #expect(item.mediaSummary == "1080p HDR")
    }

    @Test func standardRangeIsNotLabelled() {
        let item = makeItem(width: 1920, codec: nil, bitrate: nil, range: .sdr, rangeType: .sdr)
        #expect(item.mediaSummary == "1080p")
    }
}
