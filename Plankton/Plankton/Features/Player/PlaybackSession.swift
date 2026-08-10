//
//  PlaybackSession.swift
//  Plankton
//
//  One playthrough: the engine, what it reports, and what the controls show.
//

import AVFAudio
import Foundation
import JellyfinAPI
import Observation
import OSLog

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// How often the on-screen controls resample the engine's clock — smooth enough
/// for the scrubber to track, far cheaper than redrawing every frame.
private let controlRefreshInterval: TimeInterval = 0.25

/// Holds everything one playthrough needs and keeps a snapshot of the engine's
/// clock for SwiftUI to read.
///
/// The engine deliberately isn't `@Observable`: its position changes constantly
/// and reading it is a synchronous call into AVFoundation or libmpv. This
/// samples it instead, so views redraw on a cadence rather than per frame.
@MainActor
@Observable
final class PlaybackSession {

    let engine: any PlaybackEngine

    /// Built once at init. Asking the engine for it inside a SwiftUI body would
    /// hand back a fresh view on every redraw.
    @ObservationIgnored let surface: PlaybackSurface

    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval?
    private(set) var isPlaying = false

    private(set) var subtitleTracks: [PlaybackTrack] = []
    private(set) var selectedSubtitleTrack: PlaybackTrack.ID?

    /// Set while the user drags the scrubber. The engine's clock is ignored
    /// until they let go, otherwise the thumb fights the playhead.
    var isScrubbing = false

    /// What's playing right now. Not the item the session was opened with:
    /// changing channel replaces it in place, and the title, the live marker
    /// and the stream to release all follow from here.
    private(set) var current: PlaybackItem

    /// True while a channel change is in flight, so the picker can't be used
    /// to stack three switches on top of each other.
    private(set) var isSwitching = false

    var title: String? { current.metadata?.title }
    var subtitle: String? { current.metadata?.subtitle }
    var isLive: Bool { current.isLive }
    var channels: [BaseItemDto] { current.channels }

    @ObservationIgnored private let settings: PlaybackSettings
    @ObservationIgnored private let jellyfin: JellyfinService
    @ObservationIgnored private let reporter: PlaybackReporter?
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()

    /// Held from `start` so a channel change can republish the lock screen
    /// with the new channel's artwork.
    @ObservationIgnored private var artwork: ImageCache?

    /// The player can disappear more than once — a dismiss and a teardown can
    /// both land — and the stop report must only go out once.
    @ObservationIgnored private var hasEnded = false

    init(
        playback: PlaybackItem,
        engineKind: PlaybackEngineKind,
        settings: PlaybackSettings,
        jellyfin: JellyfinService,
        reporter: PlaybackReporter?
    ) {
        current = playback
        self.settings = settings
        self.jellyfin = jellyfin
        self.reporter = reporter
        engine = engineKind.makeEngine(url: playback.url)
        surface = engine.makeSurface()
    }

    /// Reads and writes the stored preference, so a size chosen mid-episode is
    /// still there for the next one.
    var subtitleScale: Double {
        get { settings.subtitleScale }
        set {
            settings.subtitleScale = newValue
            engine.setSubtitleScale(newValue)
        }
    }

    // MARK: - Lifecycle

    func start(artwork: ImageCache, onError: @escaping (String) -> Void) {
        self.artwork = artwork
        configureAudioSession()

        engine.observeFailure(onError)
        engine.observeState { [weak self] in
            self?.refresh()
            self?.refreshTracks()
        }

        engine.setSubtitleScale(settings.subtitleScale)

        if let metadata = current.metadata {
            nowPlaying.start(metadata, for: engine, artwork: artwork)
        }

        // Resume where the server says we left off, before play, so the start
        // report carries the resume point rather than zero.
        if let startTicks = current.startTicks {
            engine.seek(to: PlaybackReporter.seconds(fromTicks: startTicks))
        }

        beginReporting()

        // Only engines drawing their own controls need a clock to draw it from.
        if !engine.providesControls {
            engine.observeTime(interval: controlRefreshInterval) { [weak self] seconds in
                self?.refresh(position: seconds)
            }
        }

        engine.play()
        refresh()
    }

    func end() {
        guard !hasEnded else { return }
        hasEnded = true

        endReporting()
        releaseLiveStream()
        nowPlaying.stop()
        engine.tearDown()
    }

    /// Hands a live stream back to the server. It ties up a tuner until it gets
    /// one, and nothing else releases it — closing the player is the only
    /// signal the server ever sees.
    private func releaseLiveStream() {
        guard let liveStreamID = current.liveStreamID else { return }

        Task { [jellyfin] in
            try? await jellyfin.send(Paths.closeLiveStream(liveStreamID: liveStreamID))
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if engine.isPlaying {
            engine.pause()
        } else {
            engine.play()
        }
        refresh()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: engine.currentTime + seconds)
    }

    func seek(to seconds: TimeInterval) {
        let target = min(max(0, seconds), duration ?? .greatestFiniteMagnitude)

        // Move the thumb now: engines report the new position only once the
        // seek lands, which is long enough to look like a dropped input.
        position = target
        engine.seek(to: target)
    }

    /// Drags the thumb without touching the engine — seeking on every frame of
    /// a drag stutters playback for no benefit.
    func scrub(to seconds: TimeInterval) {
        position = seconds
    }

    func selectSubtitleTrack(_ id: PlaybackTrack.ID?) {
        engine.selectSubtitleTrack(id)
        refreshTracks()
    }

    /// Changes channel inside the running player.
    ///
    /// The engine is kept and handed a new URL, so the decoder, the audio
    /// session and the video surface all stay up — rebuilding it per channel
    /// would pay mpv's whole startup on every change. The outgoing stream is
    /// released first, since holding two open ties up a tuner that nothing
    /// will ever come back for.
    func switchTo(_ channel: BaseItemDto) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        releaseLiveStream()

        // Live only ever plays directly, so the engine can't change under us
        // and the surface stays valid.
        let source = await jellyfin.playbackSource(
            for: channel,
            engine: .direct,
            maxBitrate: settings.maxBitrate(expensive: jellyfin.isOnExpensiveNetwork)
        )
        guard let source else { return }

        current = PlaybackItem(
            url: source.url,
            engine: .direct,
            isLive: source.isLive,
            liveStreamID: source.liveStreamID,
            itemID: channel.id,
            metadata: NowPlayingMetadata(channel),
            channels: current.channels
        )

        // The lock screen is showing the channel we just left.
        nowPlaying.stop()
        if let metadata = current.metadata, let artwork {
            nowPlaying.start(metadata, for: engine, artwork: artwork)
        }

        engine.load(source.url)
        refresh()
        refreshTracks()
    }

    // MARK: - State

    private func refresh(position newPosition: TimeInterval? = nil) {
        if !isScrubbing {
            position = newPosition ?? engine.currentTime
        }
        duration = engine.duration
        isPlaying = engine.isPlaying
    }

    /// Tracks only change when the file or the selection does, and reading them
    /// means parsing mpv's track list — far too costly for the display tick.
    private func refreshTracks() {
        subtitleTracks = engine.subtitleTracks
        selectedSubtitleTrack = engine.selectedSubtitleTrack
    }

    /// `.playback` keeps audio on the speaker even with the silent switch on,
    /// which is what a video app should do.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Reporting

    /// Announces the play and then heartbeats position on an interval, so the
    /// server's resume point tracks along even if the app is killed without a
    /// clean stop.
    private func beginReporting() {
        guard let reporter else { return }

        let start = engine.currentTime
        Task { await reporter.started(atSeconds: start) }

        engine.observeTime(interval: PlaybackReporter.progressInterval) { [weak self] seconds in
            let isPaused = self?.engine.isPlaying != true
            Task { await reporter.progress(atSeconds: seconds, isPaused: isPaused) }
        }
    }

    private func endReporting() {
        guard let reporter else { return }

        // Captured now: the engine is torn down before the task runs.
        let position = engine.currentTime
        Task { await reporter.stopped(atSeconds: position) }
    }
}
