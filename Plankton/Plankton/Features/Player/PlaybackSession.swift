//
//  PlaybackSession.swift
//  Plankton
//
//  One playthrough: the engine, what it reports, and what the controls show.
//

import AVFAudio
import Foundation
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

    @ObservationIgnored private let playback: PlaybackItem
    @ObservationIgnored private let settings: PlaybackSettings
    @ObservationIgnored private let reporter: PlaybackReporter?
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()

    /// The player can disappear more than once — a dismiss and a teardown can
    /// both land — and the stop report must only go out once.
    @ObservationIgnored private var hasEnded = false

    init(
        playback: PlaybackItem,
        engineKind: PlaybackEngineKind,
        settings: PlaybackSettings,
        reporter: PlaybackReporter?
    ) {
        self.playback = playback
        self.settings = settings
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
        configureAudioSession()

        engine.observeFailure(onError)
        engine.observeState { [weak self] in
            self?.refresh()
            self?.refreshTracks()
        }

        engine.setSubtitleScale(settings.subtitleScale)

        if let metadata = playback.metadata {
            nowPlaying.start(metadata, for: engine, artwork: artwork)
        }

        // Resume where the server says we left off, before play, so the start
        // report carries the resume point rather than zero.
        if let startTicks = playback.startTicks {
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
        nowPlaying.stop()
        engine.tearDown()
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
