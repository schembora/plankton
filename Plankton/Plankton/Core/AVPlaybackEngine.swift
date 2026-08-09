//
//  AVPlaybackEngine.swift
//  Plankton
//
//  Playback through AVPlayer, fed by the server's HLS or direct-play stream.
//

import AVKit
import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// The engine the app has always used: `AVPlayer` inside `AVPlayerViewController`,
/// playing whatever the server negotiated in `JellyfinService.playbackURL(for:)`.
@MainActor
final class AVPlaybackEngine: PlaybackEngine {

    private let player: AVPlayer

    /// Held weakly so the view hierarchy stays the owner — `tearDown` still
    /// needs it to drop the player reference AVKit is holding.
    private weak var controller: AVPlayerViewController?

    private var observations: [NSKeyValueObservation] = []
    private var timeObservers: [Any] = []

    private var stateHandlers: [() -> Void] = []
    private var failureHandlers: [(String) -> Void] = []

    /// Set once and kept. Failure is terminal, and the status observation can
    /// fire repeatedly for the same item — two alerts over one broken stream is
    /// one alert too many. Retaining the message also means a stream that dies
    /// before anyone is listening still gets reported when they start.
    private var failureMessage: String?

    init(url: URL) {
        player = AVPlayer(playerItem: AVPlayerItem(url: url))
        observePlayer()
    }

    // MARK: - State

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    var duration: TimeInterval? {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite else { return nil }
        return seconds
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    // MARK: - Transport

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: TimeInterval) {
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target) { [weak self] _ in
            // A seek moves the clock without touching `timeControlStatus`, so
            // nothing else would tell listeners the position changed.
            Task { @MainActor in self?.notifyState() }
        }
    }

    // MARK: - Presentation

    func makeViewController() -> UIViewController {
        let controller = AVPlayerViewController()
        controller.player = player

        // Picture in Picture: show the PiP button and start PiP automatically
        // when the user leaves the app during fullscreen playback.
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        // NowPlayingCenter fills the lock screen instead: AVKit would publish
        // the stream's own metadata, which for Jellyfin HLS is nothing at all.
        controller.updatesNowPlayingInfoCenter = false

        self.controller = controller
        return controller
    }

    func tearDown() {
        for observer in timeObservers {
            player.removeTimeObserver(observer)
        }
        timeObservers.removeAll()
        observations.removeAll()
        stateHandlers.removeAll()
        failureHandlers.removeAll()

        player.pause()
        controller?.player = nil
    }

    // MARK: - Observation

    func observeTime(interval: TimeInterval, _ handler: @escaping (TimeInterval) -> Void) {
        let interval = CMTime(seconds: interval, preferredTimescale: 1)
        let observer = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard time.seconds.isFinite else { return }
            // Periodic observers on the main queue are delivered on the main
            // thread, so there is nowhere to hop to.
            MainActor.assumeIsolated { handler(time.seconds) }
        }
        timeObservers.append(observer)
    }

    func observeState(_ handler: @escaping () -> Void) {
        stateHandlers.append(handler)
    }

    func observeFailure(_ handler: @escaping (String) -> Void) {
        failureHandlers.append(handler)

        // KVO delivers asynchronously, so a stream that fails immediately can
        // land between construction and the first listener registering.
        if let failureMessage {
            handler(failureMessage)
        }
    }

    private func observePlayer() {
        observations = [
            player.observe(\.timeControlStatus) { [weak self] _, _ in
                Task { @MainActor in self?.notifyState() }
            },
            player.observe(\.currentItem?.duration) { [weak self] _, _ in
                Task { @MainActor in self?.notifyState() }
            },
            player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
                guard player.currentItem?.status == .failed else { return }
                Task { @MainActor in self?.reportFailure(of: player.currentItem) }
            },
        ]
    }

    private func notifyState() {
        for handler in stateHandlers {
            handler()
        }
    }

    private func reportFailure(of item: AVPlayerItem?) {
        guard failureMessage == nil else { return }

        let message = item?.error?.localizedDescription ?? "Unknown playback error"
        failureMessage = message
        logger.error("Playback failed: \(message)")

        // The HLS error log names the segment that broke, which the item's own
        // error never does — usually the difference between "it failed" and
        // "the server stopped transcoding".
        if let errorLog = item?.errorLog() {
            for event in errorLog.events {
                logger.error("HLS: \(event.errorStatusCode) \(event.errorComment ?? "-") \(event.uri ?? "-", privacy: .private)")
            }
        }

        for handler in failureHandlers {
            handler(message)
        }
    }
}
