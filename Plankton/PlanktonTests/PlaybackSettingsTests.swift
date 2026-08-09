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

    @Test func defaultsToTheServerEngine() {
        #expect(PlaybackSettings(defaults: makeDefaults()).engine == .server)
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
    @Test func unavailableEngineFallsBackToServer() {
        for kind in PlaybackEngineKind.allCases where !PlaybackEngineKind.available.contains(kind) {
            let defaults = makeDefaults()
            defaults.set(kind.rawValue, forKey: Self.key)

            #expect(PlaybackSettings(defaults: defaults).engine == .server)
        }
    }

    @Test func unrecognisedEngineFallsBackToServer() {
        let defaults = makeDefaults()
        defaults.set("quicktime-vr", forKey: Self.key)

        #expect(PlaybackSettings(defaults: defaults).engine == .server)
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
