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
