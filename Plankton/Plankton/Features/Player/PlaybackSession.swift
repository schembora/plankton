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
import UIKit

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

    private(set) var audioTracks: [PlaybackTrack] = []
    private(set) var selectedAudioTrack: PlaybackTrack.ID?

    /// Set while the user drags the scrubber. The engine's clock is ignored
    /// until they let go, otherwise the thumb fights the playhead.
    ///
    /// Anything that clears this has to be certain, because it suppresses the
    /// clock: a drag whose trailing callback never arrives, which is what a
    /// cancelled gesture is, would otherwise freeze the displayed time for the
    /// rest of the playthrough while the video carried on.
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

    /// What else this playthrough can move to. A channel line-up, or the
    /// episodes around this one.
    var queue: [PlaybackQueueEntry] { current.queue }

    /// Where `current` sits in the queue, when it's in there at all. Matched by
    /// item rather than held as an index, so it survives the queue being
    /// reloaded underneath.
    var queueIndex: Int? {
        guard let itemID = current.itemID else { return nil }
        return queue.firstIndex { $0.itemID == itemID }
    }

    var hasPreviousInQueue: Bool { (queueIndex ?? 0) > 0 }
    var hasNextInQueue: Bool { (queueIndex ?? queue.count) < queue.count - 1 }

    @ObservationIgnored private let settings: PlaybackSettings
    @ObservationIgnored private let jellyfin: JellyfinService

    /// Consulted on every move through the queue, not just at launch: the next
    /// episode may be on disk even when this one was streamed, and offline it
    /// is the only thing that can answer.
    @ObservationIgnored private let downloads: DownloadService

    /// The engine this session was built on. Moving through the queue
    /// negotiates against it rather than the current preference: the surface
    /// was built once, so the decoder can't change underneath it.
    @ObservationIgnored private let engineKind: PlaybackEngineKind

    /// Rebuilt whenever `current` changes. One reporter belongs to one item,
    /// and moving to the next has to stop reporting against the last.
    @ObservationIgnored private var reporter: PlaybackReporter?
    @ObservationIgnored private let nowPlaying = NowPlayingCenter()

    /// Held from `start` so a channel change can republish the lock screen
    /// with the new channel's artwork.
    @ObservationIgnored private var artwork: ImageCache?

    /// The player can disappear more than once — a dismiss and a teardown can
    /// both land — and the stop report must only go out once.
    @ObservationIgnored private var hasEnded = false

    @ObservationIgnored private var audioObservers: [any NSObjectProtocol] = []

    /// Whether the interruption is ours to undo. Resuming something the user
    /// paused themselves, just because a call ended, is worse than leaving it.
    @ObservationIgnored private var wasPlayingBeforeInterruption = false

    init(
        playback: PlaybackItem,
        engineKind: PlaybackEngineKind,
        settings: PlaybackSettings,
        jellyfin: JellyfinService,
        downloads: DownloadService
    ) {
        current = playback
        self.engineKind = engineKind
        self.settings = settings
        self.jellyfin = jellyfin
        self.downloads = downloads
        engine = engineKind.makeEngine(url: playback.url)
        surface = engine.makeSurface()
        reporter = Self.makeReporter(for: playback, jellyfin: jellyfin)
    }

    /// Only server-backed playback reports. A local file played offline has
    /// nothing to report to, and a live channel has no position worth keeping —
    /// posting one would put a resume point on a stream nobody can resume.
    private static func makeReporter(
        for item: PlaybackItem,
        jellyfin: JellyfinService
    ) -> PlaybackReporter? {
        guard let itemID = item.itemID, jellyfin.isSignedIn, !item.isLive else { return nil }
        return PlaybackReporter(jellyfin: jellyfin, itemID: itemID)
    }

    /// How the picture sits on screen. Deliberately not persisted: it answers
    /// a question about the thing being watched, not a standing preference,
    /// and carrying it into unrelated content would surprise.
    var videoFill: VideoFill = .fit {
        didSet { engine.setVideoFill(videoFill) }
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

        startNowPlaying(artwork: artwork)
        observeAudioSession()

        // Resume where the server says we left off, before play, so the start
        // report carries the resume point rather than zero.
        if let startTicks = current.startTicks {
            engine.seek(to: PlaybackReporter.seconds(fromTicks: startTicks))
        }

        observeProgress()
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

        for observer in audioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        audioObservers.removeAll()

        engine.tearDown()
    }

    /// Publishes the current item to the lock screen, wired to the queue so
    /// the next episode or channel is reachable without unlocking.
    private func startNowPlaying(artwork: ImageCache) {
        guard let metadata = current.nowPlayingMetadata else { return }

        nowPlaying.start(
            metadata,
            for: engine,
            artwork: artwork,
            queue: queue.isEmpty ? nil : NowPlayingQueue(
                goToPrevious: { [weak self] in
                    Task { await self?.goToPreviousInQueue() }
                },
                goToNext: { [weak self] in
                    Task { await self?.goToNextInQueue() }
                }
            )
        )
        nowPlaying.setQueueAvailability(previous: hasPreviousInQueue, next: hasNextInQueue)
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

        // A seek is the end of a scrub by definition, and it also arrives from
        // the skip buttons and the lock screen. Clearing it here means the
        // clock restarts even if the slider never reported letting go.
        isScrubbing = false

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

    func selectAudioTrack(_ id: PlaybackTrack.ID) {
        engine.selectAudioTrack(id)
        refreshTracks()
    }

    /// Changes channel inside the running player.
    ///
    /// The engine is kept and handed a new URL, so the decoder, the audio
    /// session and the video surface all stay up — rebuilding it per channel
    /// would pay mpv's whole startup on every change. The outgoing stream is
    /// released first, since holding two open ties up a tuner that nothing
    /// will ever come back for.
    func switchTo(_ entry: PlaybackQueueEntry) async {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        // Finish with what's playing before opening the next: a stop report
        // has to name the item it belongs to, and a live stream left open
        // holds a tuner nothing will come back for.
        endReporting()
        releaseLiveStream()

        guard let next = await resolve(entry) else { return }
        current = next
        duration = nil

        // The lock screen is still showing what we just left.
        nowPlaying.stop()
        if let artwork {
            startNowPlaying(artwork: artwork)
        }

        engine.load(current.url, startingAt: current.startTicks.map(PlaybackReporter.seconds(fromTicks:)))

        reporter = Self.makeReporter(for: current, jellyfin: jellyfin)
        beginReporting()

        refresh()
        refreshTracks()
    }

    /// Where the next thing to play comes from.
    ///
    /// A downloaded copy is preferred for server entries too, which is what
    /// lets a part-downloaded season keep moving while offline: the queue is
    /// the same list either way, and each stop resolves to whichever source
    /// can actually answer for it.
    private func resolve(_ entry: PlaybackQueueEntry) async -> PlaybackItem? {
        switch entry {
        case let .downloaded(media):
            return localItem(
                for: media.itemID,
                metadata: NowPlayingMetadata(
                    media,
                    poster: downloads.posterFileURL(forItemID: media.itemID)
                )
            )

        case let .server(item):
            if let itemID = item.id,
               let local = localItem(
                   for: itemID,
                   startTicks: item.resumePositionTicks,
                   metadata: NowPlayingMetadata(item)
               ) {
                return local
            }

            // Negotiated against the engine already running, not the
            // preference. The surface was built for it and can't be swapped
            // mid-playthrough.
            let source = await jellyfin.playbackSource(
                for: item,
                engine: engineKind,
                maxBitrate: settings.maxBitrate(expensive: jellyfin.isOnExpensiveNetwork)
            )
            guard let source else { return nil }

            return PlaybackItem(
                url: source.url,
                engine: engineKind,
                isLive: source.isLive,
                liveStreamID: source.liveStreamID,
                itemID: item.id,
                startTicks: item.resumePositionTicks,
                metadata: NowPlayingMetadata(item),
                queue: current.queue
            )
        }
    }

    /// The download for an item, when there is one the running engine can
    /// open. A file in the other engine's format is left alone rather than
    /// forced through this one: the surface exists for the whole playthrough,
    /// so a server entry falls back to streaming and a downloaded entry
    /// simply can't be reached.
    private func localItem(
        for itemID: String,
        startTicks: Int? = nil,
        metadata: NowPlayingMetadata?
    ) -> PlaybackItem? {
        guard let url = downloads.localURL(forItemID: itemID),
              downloads.requiredEngine(forItemID: itemID) == engineKind
        else { return nil }

        return PlaybackItem(
            url: url,
            engine: engineKind,
            itemID: itemID,
            startTicks: startTicks,
            metadata: metadata,
            queue: current.queue
        )
    }

    /// Moves through the queue. For a channel line-up these are channel down
    /// and up; for episodes, the previous and next one.
    func goToPreviousInQueue() async {
        guard let index = queueIndex, index > 0 else { return }
        await switchTo(queue[index - 1])
    }

    func goToNextInQueue() async {
        guard let index = queueIndex, index < queue.count - 1 else { return }
        await switchTo(queue[index + 1])
    }

    // MARK: - State

    private func refresh(position newPosition: TimeInterval? = nil) {
        if !isScrubbing {
            position = newPosition ?? engine.currentTime
        }

        // Sticky, because a file's length doesn't change but an engine can
        // briefly answer "unknown" while a seek settles. Letting that through
        // disables the scrubber under a moving thumb, which cancels the drag
        // and is one of the ways the trailing callback goes missing.
        if let known = engine.duration {
            duration = known
        }
        isPlaying = engine.isPlaying
    }

    /// Tracks only change when the file or the selection does, and reading them
    /// means parsing mpv's track list — far too costly for the display tick.
    private func refreshTracks() {
        subtitleTracks = engine.subtitleTracks
        selectedSubtitleTrack = engine.selectedSubtitleTrack
        audioTracks = engine.audioTracks
        selectedAudioTrack = engine.selectedAudioTrack
    }

    /// Phone calls, alarms, and headphones being pulled out.
    ///
    /// `AVPlayer` handles most of this on its own, but mpv does not: it is a
    /// decoder with an audio output, and it will happily keep running against a
    /// deactivated session, so a call would cost you however long it lasted.
    /// Both engines go through the same handling rather than one relying on
    /// AVFoundation and the other not.
    private func observeAudioSession() {
        let center = NotificationCenter.default

        audioObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.logBackgroundState() }
            },

            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleInterruption(notification) }
            },

            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleRouteChange(notification) }
            },
        ]
    }

    /// Whether the decoder is still running once the screen is off decides
    /// which half of the lock screen problem this is: an entry that is never
    /// published, or audio that has already stopped so there is no entry to
    /// publish. Debug only.
    private func logBackgroundState() {
        #if DEBUG
        logger.info("backgrounded: playing=\(self.engine.isPlaying, privacy: .public)")

        // Again once the transition has settled. The question is not whether
        // audio survives the moment of locking but whether it is still going
        // a few seconds later.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            logger.info("backgrounded +3s: playing=\(self.engine.isPlaying, privacy: .public)")
        }
        #endif
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = engine.isPlaying
            engine.pause()
            refresh()

        case .ended:
            // Only when the system says so. An interruption that ended because
            // the user switched to another player should not start two of them.
            let raw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: raw)

            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                try? AVAudioSession.sharedInstance().setActive(true)
                engine.play()
                refresh()
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    /// Headphones pulled out, or a Bluetooth device walking away. Pausing is
    /// what every other player does, and the alternative is a phone that starts
    /// playing out loud in a quiet room.
    private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable
        else { return }

        engine.pause()
        refresh()
    }

    /// `.playback` keeps audio on the speaker even with the silent switch on,
    /// which is what a video app should do.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)

            #if DEBUG
            let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
            logger.info("audio session active: category=\(session.category.rawValue, privacy: .public) outputs=\(outputs, privacy: .public)")
            #endif
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Reporting

    /// Announces the play. Called again for each item the session moves to,
    /// which is why it registers nothing: an observer per channel change would
    /// stack up one heartbeat per switch.
    private func beginReporting() {
        guard let reporter else { return }

        let start = engine.currentTime
        Task { await reporter.started(atSeconds: start) }
    }

    /// Heartbeats position on an interval so the server's resume point tracks
    /// along even if the app is killed without a clean stop. Registered once
    /// for the session and reads whichever reporter is current, since the item
    /// underneath it can change.
    private func observeProgress() {
        engine.observeTime(interval: PlaybackReporter.progressInterval) { [weak self] seconds in
            guard let self, let reporter else { return }

            let isPaused = !engine.isPlaying
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
