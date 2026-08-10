//
//  PlaybackSettingsTests.swift
//  PlanktonTests
//
//  The engine preference: what persists, and what it falls back to.
//

import Foundation
import Testing

@testable import Plankton

@MainActor
struct PlaybackSettingsTests {

    private static let key = "playbackEngine"

    /// A defaults store of its own per test, so one test's engine choice can't
    /// leak into the next or into the simulator's real preferences.
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PlaybackSettingsTests.\(UUID().uuidString)")!
    }

    /// A fresh install plays directly: that's the point of the engine, and it
    /// is what an install that never chose gets.
    @Test func freshInstallPlaysDirectly() {
        #expect(PlaybackEngineKind.defaultEngine == .direct)
        #expect(PlaybackSettings(defaults: makeDefaults()).engine == .direct)
    }

    /// Nothing writes the preference except the user, so an install that
    /// already picked Server keeps it rather than being moved.
    @Test func anExplicitChoiceIsNotOverriddenByTheDefault() {
        let defaults = makeDefaults()
        defaults.set(PlaybackEngineKind.server.rawValue, forKey: Self.key)

        #expect(PlaybackSettings(defaults: defaults).engine == .server)
    }

    /// There's no save step in the UI, so the choice has to land on the way out.
    @Test func choiceIsWrittenThrough() {
        let defaults = makeDefaults()
        let settings = PlaybackSettings(defaults: defaults)

        settings.engine = .direct

        #expect(defaults.string(forKey: Self.key) == PlaybackEngineKind.direct.rawValue)
    }

    /// Restoring shouldn't write anything — only an explicit choice should.
    @Test func constructionDoesNotPersistTheDefault() {
        let defaults = makeDefaults()
        _ = PlaybackSettings(defaults: defaults)

        #expect(defaults.string(forKey: Self.key) == nil)
    }

    /// The whole point of `available`: a stored engine this build doesn't
    /// offer must not leave playback pointed at nothing. Vacuous while every
    /// case is offered, but it keeps the guarantee pinned for the next kind
    /// that gets added ahead of its engine.
    @Test func unavailableEngineFallsBackToTheDefault() {
        for kind in PlaybackEngineKind.allCases where !PlaybackEngineKind.available.contains(kind) {
            let defaults = makeDefaults()
            defaults.set(kind.rawValue, forKey: Self.key)

            #expect(PlaybackSettings(defaults: defaults).engine == .defaultEngine)
        }
    }

    @Test func unrecognisedEngineFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set("quicktime-vr", forKey: Self.key)

        #expect(PlaybackSettings(defaults: defaults).engine == .defaultEngine)
    }

    // MARK: - Subtitle scale

    @Test func subtitleScaleDefaultsToUnscaled() {
        #expect(PlaybackSettings(defaults: makeDefaults()).subtitleScale == 1)
    }

    @Test func subtitleScaleSurvivesRelaunch() {
        let defaults = makeDefaults()

        let settings = PlaybackSettings(defaults: defaults)
        settings.subtitleScale = 0.6

        #expect(PlaybackSettings(defaults: defaults).subtitleScale == 0.6)
    }

    /// `double(forKey:)` answers 0 for a key never written, which would
    /// otherwise render subtitles at zero size.
    @Test func unwrittenSubtitleScaleIsNotTakenAsZero() {
        let defaults = makeDefaults()
        #expect(defaults.double(forKey: "subtitleScale") == 0)
        #expect(PlaybackSettings(defaults: defaults).subtitleScale == 1)
    }

    @Test(arguments: [0.0, -1.0, 12.0])
    func outOfRangeSubtitleScaleFallsBack(_ stored: Double) {
        let defaults = makeDefaults()
        defaults.set(stored, forKey: "subtitleScale")

        #expect(PlaybackSettings(defaults: defaults).subtitleScale == 1)
    }

    @Test func everyPresetIsWithinTheAcceptedRange() {
        for preset in SubtitleScale.allCases {
            #expect(PlaybackSettings.subtitleScaleRange.contains(preset.rawValue))
        }
    }

    @Test func presetsRoundTripThroughNearest() {
        for preset in SubtitleScale.allCases {
            #expect(SubtitleScale.nearest(to: preset.rawValue) == preset)
        }
    }

    @Test func nearestSnapsAnArbitraryScaleToAPreset() {
        #expect(SubtitleScale.nearest(to: 0.62) == .small)
        #expect(SubtitleScale.nearest(to: 1.4) == .larger)
        #expect(SubtitleScale.nearest(to: 100) == .larger)
    }

    // MARK: - Bitrate

    /// Uncapped on Wi-Fi is what keeps direct play working; a cap below the
    /// file's own bitrate is what makes the server transcode.
    @Test func wiFiIsUncappedByDefault() {
        let settings = PlaybackSettings(defaults: makeDefaults())

        #expect(settings.maxBitrateWiFi == .unlimited)
        #expect(settings.maxBitrate(expensive: false) == nil)
    }

    @Test func cellularIsCappedByDefault() {
        let settings = PlaybackSettings(defaults: makeDefaults())

        #expect(settings.maxBitrateCellular == .mbps8)
        #expect(settings.maxBitrate(expensive: true) == 8_000_000)
    }

    @Test func eachNetworkResolvesToItsOwnLimit() {
        let settings = PlaybackSettings(defaults: makeDefaults())
        settings.maxBitrateWiFi = .mbps40
        settings.maxBitrateCellular = .mbps2

        #expect(settings.maxBitrate(expensive: false) == 40_000_000)
        #expect(settings.maxBitrate(expensive: true) == 2_000_000)
    }

    /// Unlimited has to survive a relaunch as a real choice. It stores as 0,
    /// which is also what an unwritten key reads back as.
    @Test func explicitlyUncappedCellularIsNotMistakenForUnset() {
        let defaults = makeDefaults()

        let settings = PlaybackSettings(defaults: defaults)
        settings.maxBitrateCellular = .unlimited

        let restored = PlaybackSettings(defaults: defaults)
        #expect(restored.maxBitrateCellular == .unlimited)
        #expect(restored.maxBitrate(expensive: true) == nil)
    }

    @Test func limitsSurviveRelaunch() {
        let defaults = makeDefaults()

        let settings = PlaybackSettings(defaults: defaults)
        settings.maxBitrateWiFi = .mbps80
        settings.maxBitrateCellular = .mbps4

        let restored = PlaybackSettings(defaults: defaults)
        #expect(restored.maxBitrateWiFi == .mbps80)
        #expect(restored.maxBitrateCellular == .mbps4)
    }

    @Test func unrecognisedLimitFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set(7_777, forKey: "maxBitrateWiFi")

        #expect(PlaybackSettings(defaults: defaults).maxBitrateWiFi == .unlimited)
    }

    @Test func onlyUnlimitedResolvesToNoCap() {
        for limit in BitrateLimit.allCases {
            #expect((limit.bitsPerSecond == nil) == (limit == .unlimited))
        }
    }

    // MARK: - Engines

    /// Anything the Settings picker can offer has to survive a relaunch —
    /// otherwise selecting it would silently revert on next launch.
    @Test func everyAvailableKindSurvivesRelaunch() {
        #expect(!PlaybackEngineKind.available.isEmpty)

        for kind in PlaybackEngineKind.available {
            let defaults = makeDefaults()
            let settings = PlaybackSettings(defaults: defaults)
            settings.engine = kind

            #expect(PlaybackSettings(defaults: defaults).engine == kind)
        }
    }
}
