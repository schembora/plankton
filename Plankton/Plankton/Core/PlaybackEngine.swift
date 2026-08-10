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
enum PlaybackEngineKind: String, Codable, CaseIterable, Identifiable {

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

    /// The kinds Settings offers.
    static var available: [PlaybackEngineKind] { [.server, .direct] }

    /// What a fresh install plays on, and what an unusable stored choice falls
    /// back to.
    ///
    /// Direct, because it's the reason the engine exists: the server hands over
    /// the file instead of re-encoding it, which is most of the wait before a
    /// video starts. It costs Picture in Picture and AirPlay, so anyone who
    /// picked Server keeps it — only an install that never chose moves.
    static var defaultEngine: PlaybackEngineKind {
        available.contains(.direct) ? .direct : .server
    }

    @MainActor
    func makeEngine(url: URL) -> any PlaybackEngine {
        switch self {
        case .server: AVPlaybackEngine(url: url)
        case .direct: MPVPlaybackEngine(url: url)
        }
    }
}

/// How the picture is laid into the screen.
///
/// Worth having because the two rarely agree: 4:3 material on a 16:9 phone,
/// or a 2.39:1 film on a 16:9 screen, both leave bars that some people would
/// rather lose than keep.
enum VideoFill: String, CaseIterable, Identifiable {

    /// The whole picture, with bars wherever the shapes differ.
    case fit

    /// Fills the screen and crops whatever overhangs it.
    case fill

    /// Fills the screen by distorting the picture. Ugly on purpose, and the
    /// only way to get 4:3 material edge to edge without losing any of it.
    case stretch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: "Fit"
        case .fill: "Fill"
        case .stretch: "Stretch"
        }
    }
}

/// One selectable track in the file being played.
struct PlaybackTrack: Identifiable, Hashable {

    /// The engine's own identifier for the track, not an index into any list.
    let id: Int
    let title: String?
    let language: String?

    /// A second line for the picker, where the name alone doesn't separate
    /// two tracks. Audio uses it: "English" and "English" is a common pairing
    /// that only the codec and channel count tell apart.
    var detail: String?

    /// What the picker shows. Files routinely carry a title or a language but
    /// not both, so this falls through before naming the track by number.
    var displayName: String {
        switch (title, language) {
        case let (title?, language?): "\(title) (\(language.uppercased()))"
        case let (title?, nil): title
        case let (nil, language?): language.uppercased()
        case (nil, nil): "Track \(id)"
        }
    }
}

/// What an engine draws into.
///
/// mpv needs nothing but a layer-backed view, and giving it a view controller
/// makes SwiftUI reparent the whole hierarchy — UIKit warns about that and the
/// picture can break. AVKit's player has to stay a controller: its transport,
/// PiP and fullscreen behaviour all live there.
enum PlaybackSurface {
    case view(UIView)
    case controller(UIViewController)
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

    /// Replaces what's playing without tearing the engine down. The decoder,
    /// the audio session and the video surface all stay up, which is the
    /// difference between changing channel and restarting the player.
    ///
    /// `startingAt` opens at a position rather than seeking to one afterwards.
    /// A seek issued straight after a load lands before the file is open, and
    /// engines differ on whether they remember it.
    func load(_ url: URL, startingAt seconds: TimeInterval?)

    /// Whether the engine's surface arrives with transport controls already on
    /// it. AVKit's does; a decoder drawing into a bare layer has nothing, and
    /// the app has to supply them.
    var providesControls: Bool { get }

    /// The video surface, built once. Each engine brings its own: AVKit's
    /// controller has transport, PiP and a track picker built in, where a
    /// bundled decoder needs all three drawn by hand.
    func makeSurface() -> PlaybackSurface

    /// Subtitle tracks in the open file, empty before it opens. Engines that
    /// bring their own picker leave this empty — the app doesn't draw a second
    /// one over the top of AVKit's.
    var subtitleTracks: [PlaybackTrack] { get }

    /// The showing subtitle track, or nil when subtitles are off.
    var selectedSubtitleTrack: PlaybackTrack.ID? { get }

    /// Shows a subtitle track, or turns subtitles off with nil.
    func selectSubtitleTrack(_ id: PlaybackTrack.ID?)

    /// Audio tracks in the open file, empty before it opens. A file the server
    /// handed over untouched keeps every one it was mastered with, which is
    /// the whole reason this is worth picking from. Engines that bring their
    /// own picker leave it empty.
    var audioTracks: [PlaybackTrack] { get }

    /// The playing audio track.
    var selectedAudioTrack: PlaybackTrack.ID? { get }

    /// Switches audio track. Unlike subtitles there is no "off": silence is
    /// what the mute control is for.
    func selectAudioTrack(_ id: PlaybackTrack.ID)

    /// Scales rendered subtitles, 1 being the engine's own size. Engines with
    /// their own picker ignore it — AVKit takes subtitle sizing from the
    /// system's accessibility settings instead.
    func setSubtitleScale(_ scale: Double)

    /// Lays the picture into the screen. Applies to whatever is playing now
    /// and to anything loaded afterwards.
    func setVideoFill(_ fill: VideoFill)

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
