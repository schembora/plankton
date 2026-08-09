//
//  PlaybackSettings.swift
//  Plankton
//
//  User's playback preferences, persisted across launches.
//

import Foundation
import Observation

/// A ceiling on what the server is allowed to send.
///
/// Worth understanding before changing one: this is a transcode trigger, not a
/// quality dial. Jellyfin re-encodes anything above the cap, even when the
/// codec and container would have played untouched — so capping below the
/// file's own bitrate is what *causes* the transcoding the direct engine
/// exists to avoid. It earns its place for links that genuinely can't carry a
/// remux, which in practice means cellular.
enum BitrateLimit: Int, CaseIterable, Identifiable {

    /// No cap. The server sends the file as it is.
    case unlimited = 0

    case mbps120 = 120_000_000
    case mbps80 = 80_000_000
    case mbps40 = 40_000_000
    case mbps20 = 20_000_000
    case mbps10 = 10_000_000
    case mbps8 = 8_000_000
    case mbps4 = 4_000_000
    case mbps2 = 2_000_000

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unlimited: "Maximum"
        default: "\(rawValue / 1_000_000) Mbps"
        }
    }

    /// Bits per second, or nil when uncapped — which is what the server wants
    /// to see for "send it as-is".
    var bitsPerSecond: Int? {
        self == .unlimited ? nil : rawValue
    }
}

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

    /// Uncapped by default: on a home network the whole point is that the
    /// server copies rather than converts.
    var maxBitrateWiFi: BitrateLimit {
        didSet { defaults.set(maxBitrateWiFi.rawValue, forKey: Keys.maxBitrateWiFi) }
    }

    /// Capped by default, because the alternative is a remux that stalls. This
    /// is the one case where paying for a transcode is the better trade.
    var maxBitrateCellular: BitrateLimit {
        didSet { defaults.set(maxBitrateCellular.rawValue, forKey: Keys.maxBitrateCellular) }
    }

    /// The cap for the link in use. `expensive` covers cellular and personal
    /// hotspots — both are metered and neither carries a remux comfortably.
    func maxBitrate(expensive: Bool) -> Int? {
        (expensive ? maxBitrateCellular : maxBitrateWiFi).bitsPerSecond
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let engine = "playbackEngine"
        static let subtitleScale = "subtitleScale"
        static let maxBitrateWiFi = "maxBitrateWiFi"
        static let maxBitrateCellular = "maxBitrateCellular"
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

        maxBitrateWiFi = Self.storedLimit(in: defaults, forKey: Keys.maxBitrateWiFi) ?? .unlimited
        maxBitrateCellular = Self.storedLimit(in: defaults, forKey: Keys.maxBitrateCellular) ?? .mbps8
    }

    /// Nil for a key never written, so the caller's default applies — as
    /// opposed to a stored 0, which is a deliberate "no cap".
    private static func storedLimit(in defaults: UserDefaults, forKey key: String) -> BitrateLimit? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return BitrateLimit(rawValue: defaults.integer(forKey: key))
    }
}
