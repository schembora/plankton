//
//  PlayerView.swift
//  Plankton
//
//  Full-screen video playback via the native player.
//

import AVFAudio
import AVKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// Wraps the player with failure handling: shows the playback error and dismisses on OK.
struct PlayerContainerView: View {

    let playback: PlaybackItem

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// Only server-backed playback reports; a local file played offline has
    /// nothing to report to.
    private var reporter: PlaybackReporter? {
        guard let itemID = playback.itemID, jellyfin.isSignedIn else { return nil }
        return PlaybackReporter(jellyfin: jellyfin, itemID: itemID)
    }

    var body: some View {
        PlayerView(playback: playback, reporter: reporter) { message in
            errorMessage = message
        }
        .ignoresSafeArea()
        .alert("Couldn't Play Video", isPresented: isShowingError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

struct PlayerView: UIViewControllerRepresentable {

    let playback: PlaybackItem
    let reporter: PlaybackReporter?
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(reporter: reporter, onError: onError)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        logger.info("Starting playback: \(playback.url.absoluteString, privacy: .private)")
        configureAudioSession()

        let item = AVPlayerItem(url: playback.url)
        context.coordinator.observe(item)

        let controller = AVPlayerViewController()
        let player = AVPlayer(playerItem: item)
        controller.player = player

        // Picture in Picture: show the PiP button and start PiP automatically
        // when the user leaves the app during fullscreen playback.
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        // Resume where the server says we left off. Seeking before play avoids
        // a visible jump from the opening frames.
        if let startTicks = playback.startTicks {
            let start = PlaybackReporter.seconds(fromTicks: startTicks)
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }

        context.coordinator.beginReporting(for: player)
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.endReporting(for: uiViewController.player)
        uiViewController.player?.pause()
        uiViewController.player = nil
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

    @MainActor
    final class Coordinator {
        private let reporter: PlaybackReporter?
        private let onError: (String) -> Void
        private var observation: NSKeyValueObservation?
        private var timeObserver: Any?

        init(reporter: PlaybackReporter?, onError: @escaping (String) -> Void) {
            self.reporter = reporter
            self.onError = onError
        }

        /// Announces the play and then heartbeats position on an interval, so
        /// the server's resume point tracks along even if the app is killed
        /// without a clean stop.
        func beginReporting(for player: AVPlayer) {
            guard let reporter else { return }

            let start = player.currentTime().seconds
            Task { await reporter.started(atSeconds: start.isFinite ? start : 0) }

            let interval = CMTime(seconds: PlaybackReporter.progressInterval, preferredTimescale: 1)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
                guard time.seconds.isFinite else { return }
                let isPaused = (player?.timeControlStatus ?? .paused) != .playing
                Task { await reporter.progress(atSeconds: time.seconds, isPaused: isPaused) }
            }
        }

        func endReporting(for player: AVPlayer?) {
            if let timeObserver {
                player?.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
            guard let reporter else { return }

            // Captured now: the player is torn down before the task runs.
            let position = player?.currentTime().seconds ?? 0
            Task { await reporter.stopped(atSeconds: position.isFinite ? position : 0) }
        }

        func observe(_ item: AVPlayerItem) {
            observation = item.observe(\.status, options: [.new]) { [onError] item, _ in
                guard item.status == .failed else { return }

                let message = item.error?.localizedDescription ?? "Unknown playback error"
                logger.error("Playback failed: \(message)")

                if let errorLog = item.errorLog() {
                    for event in errorLog.events {
                        logger.error("HLS: \(event.errorStatusCode) \(event.errorComment ?? "-") \(event.uri ?? "-", privacy: .private)")
                    }
                }

                Task { @MainActor in onError(message) }
            }
        }
    }
}
