//
//  PlaybackSettings.swift
//  Plankton
//
//  User's playback preferences, persisted across launches.
//

import Foundation
import Observation

@Observable
final class PlaybackSettings {

    /// Which engine plays video. Written straight through on change: there's
    /// no save step in the UI, and losing the choice on a crash would be a
    /// silent reversion to server transcoding.
    var engine: PlaybackEngineKind {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let engine = "playbackEngine"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Anything unrecognised — a build where the chosen engine hasn't
        // shipped yet, or one where it was withdrawn — falls back rather than
        // leaving playback pointed at an engine that can't be built.
        let stored = defaults.string(forKey: Keys.engine).flatMap(PlaybackEngineKind.init(rawValue:))
        engine = if let stored, PlaybackEngineKind.available.contains(stored) { stored } else { .server }
    }
}
