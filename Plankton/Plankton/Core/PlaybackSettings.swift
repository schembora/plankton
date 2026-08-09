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

    /// Multiplier on the engine's own subtitle size. mpv sizes subtitles from
    /// the video's resolution rather than the screen's, so what's readable on
    /// a TV can be overbearing on a phone.
    var subtitleScale: Double {
        didSet { defaults.set(subtitleScale, forKey: Keys.subtitleScale) }
    }

    /// Bounds on the stored value, so a corrupt default can't render subtitles
    /// invisible or fill the screen.
    static let subtitleScaleRange: ClosedRange<Double> = 0.25...3

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let engine = "playbackEngine"
        static let subtitleScale = "subtitleScale"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Anything unrecognised — a build where the chosen engine hasn't
        // shipped yet, or one where it was withdrawn — falls back rather than
        // leaving playback pointed at an engine that can't be built.
        let stored = defaults.string(forKey: Keys.engine).flatMap(PlaybackEngineKind.init(rawValue:))
        engine = if let stored, PlaybackEngineKind.available.contains(stored) { stored } else { .server }

        // `double(forKey:)` answers 0 for a key that was never written, which
        // is indistinguishable from a stored zero and equally unusable.
        let storedScale = defaults.double(forKey: Keys.subtitleScale)
        subtitleScale = Self.subtitleScaleRange.contains(storedScale) ? storedScale : 1
    }
}
