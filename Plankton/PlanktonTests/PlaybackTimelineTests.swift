//
//  PlaybackTimelineTests.swift
//  PlanktonTests
//
//  The player's clock formatting.
//

import Foundation
import Testing

@testable import Plankton

@MainActor
struct PlaybackTimelineTests {

    @Test(arguments: [
        (0.0, "0:00"),
        (7.0, "0:07"),
        (67.0, "1:07"),
        (599.0, "9:59"),
    ])
    func underAnHourDropsTheHourField(_ seconds: TimeInterval, _ expected: String) {
        #expect(PlaybackTimeline.timeText(seconds) == expected)
    }

    @Test(arguments: [
        (3600.0, "1:00:00"),
        (3852.0, "1:04:12"),
        (36000.0, "10:00:00"),
    ])
    func anHourAndOverPadsBothFields(_ seconds: TimeInterval, _ expected: String) {
        #expect(PlaybackTimeline.timeText(seconds) == expected)
    }

    @Test func secondsRoundRatherThanTruncate() {
        #expect(PlaybackTimeline.timeText(6.6) == "0:07")
    }

    /// The engine reports a NaN position before anything is loaded, and a
    /// remaining time can go briefly negative at the end of a file. Neither
    /// should render as a time.
    @Test(arguments: [-1.0, .nan, .infinity])
    func unusableValuesShowAPlaceholder(_ seconds: TimeInterval) {
        #expect(PlaybackTimeline.timeText(seconds) == "--:--")
    }
}
