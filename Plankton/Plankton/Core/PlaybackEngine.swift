//
//  PlaybackEngine.swift
//  Plankton
//
//  The playback surface the app talks to, independent of what decodes the video.
//

import Foundation
import UIKit

/// What decodes a video, and therefore how much work the server does.
///
/// AVPlayer can't demux Matroska, so today anything that isn't already
/// MP4/H.264 is re-encoded by the server before it reaches the device — which
/// is where the startup latency comes from. A decoder bundled into the app
/// plays the original file untouched. The trade is real enough in both
/// directions that it belongs to the user rather than being picked for them.
enum PlaybackEngineKind: String, CaseIterable, Identifiable {

    /// AVPlayer over the server's HLS stream. Picture in Picture, AirPlay and
    /// the native track picker come free; the server pays in CPU and latency.
    case server

    /// A decoder bundled into the app, playing the original file as-is.
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .server: "Server"
        case .direct: "Direct"
        }
    }

    var explanation: String {
        switch self {
        case .server:
            "The server converts anything this device can't play. Supports Picture in Picture and AirPlay."
        case .direct:
            "Plays files as they are. Faster to start and easier on the server, without Picture in Picture or AirPlay."
        }
    }

    /// The kinds Settings offers. `direct` is listed ahead of its engine on
    /// purpose, so the choice is visible while the decoder is being built —
    /// picking it currently still plays through AVPlayer.
    static var available: [PlaybackEngineKind] { [.server, .direct] }

    /// Builds the engine for this kind.
    ///
    /// `direct` falls through to the server engine for now; this is the one
    /// line that changes when the bundled decoder arrives.
    @MainActor
    func makeEngine(url: URL) -> any PlaybackEngine {
        switch self {
        case .server, .direct: AVPlaybackEngine(url: url)
        }
    }
}

/// What playback looks like to the rest of the app: a clock, a play/pause
/// state, and a view to put on screen.
///
/// `PlaybackReporter` and `NowPlayingCenter` both used to hold an `AVPlayer`
/// outright. Going through this instead means swapping the decoder doesn't
/// reach into progress reporting or the lock screen.
@MainActor
protocol PlaybackEngine: AnyObject {

    /// Current position in seconds, always finite — every caller feeds this
    /// straight into a tick count or the lock screen, so engines report 0
    /// rather than the NaN they hold before anything is loaded.
    var currentTime: TimeInterval { get }

    /// Total length once the engine knows it, nil while it's still resolving.
    /// An HLS playlist carries no duration until it loads.
    var duration: TimeInterval? { get }

    /// True only while frames are actually moving — not while buffering or
    /// seeking, so the lock screen's extrapolated clock doesn't run ahead.
    var isPlaying: Bool { get }

    func play()
    func pause()
    func seek(to seconds: TimeInterval)

    /// The video surface. Each engine brings its own: AVKit's controller has
    /// transport controls, PiP and a track picker built in, where a bundled
    /// decoder needs all three drawn by hand.
    func makeViewController() -> UIViewController

    /// Releases the decoder. Nothing is playable afterwards.
    func tearDown()

    /// Periodic position callback while playing — what heartbeats progress
    /// to the server.
    func observeTime(interval: TimeInterval, _ handler: @escaping (TimeInterval) -> Void)

    /// Play/pause flips, completed seeks, and duration resolving: everything
    /// the lock screen extrapolates its clock from. Handlers accumulate, since
    /// the lock screen won't necessarily be the only listener.
    func observeState(_ handler: @escaping () -> Void)

    /// Terminal playback failure, reported once with a user-facing message.
    func observeFailure(_ handler: @escaping (String) -> Void)
}
