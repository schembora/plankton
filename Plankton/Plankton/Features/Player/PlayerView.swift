//
//  PlayerView.swift
//  Plankton
//
//  Full-screen video playback, through whichever engine the user picked.
//

import AVFAudio
import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// Wraps the player with failure handling: shows the playback error and dismisses on OK.
struct PlayerContainerView: View {

    let playback: PlaybackItem

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(PlaybackSettings.self) private var settings
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
        PlayerView(playback: playback, engineKind: settings.engine, reporter: reporter) { message in
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

/// The engine owns its own view controller, so this representable is typed to
/// the base class rather than to AVKit's — the whole point is that what draws
/// the video can change underneath it.
struct PlayerView: UIViewControllerRepresentable {

    @Environment(ImageCache.self) private var images

    let playback: PlaybackItem
    let engineKind: PlaybackEngineKind
    let reporter: PlaybackReporter?
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(reporter: reporter, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        logger.info("Starting playback via \(engineKind.rawValue): \(playback.url.absoluteString, privacy: .private)")
        configureAudioSession()

        let engine = engineKind.makeEngine(url: playback.url)
        let controller = engine.makeViewController()
        context.coordinator.start(engine, playback: playback, artwork: images)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.stop()
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
        private let nowPlaying = NowPlayingCenter()
        private var engine: (any PlaybackEngine)?

        init(reporter: PlaybackReporter?, onError: @escaping (String) -> Void) {
            self.reporter = reporter
            self.onError = onError
        }

        /// Order matters: the resume seek has to be issued before the start
        /// report reads a position off the engine, or the server is told
        /// playback began at zero.
        func start(_ engine: any PlaybackEngine, playback: PlaybackItem, artwork cache: ImageCache) {
            self.engine = engine

            engine.observeFailure { [onError] message in
                onError(message)
            }

            if let metadata = playback.metadata {
                nowPlaying.start(metadata, for: engine, artwork: cache)
            }

            // Resume where the server says we left off. Seeking before play
            // avoids a visible jump from the opening frames.
            if let startTicks = playback.startTicks {
                engine.seek(to: PlaybackReporter.seconds(fromTicks: startTicks))
            }

            beginReporting(with: engine)
            engine.play()
        }

        func stop() {
            endReporting()
            nowPlaying.stop()
            engine?.tearDown()
            engine = nil
        }

        /// Announces the play and then heartbeats position on an interval, so
        /// the server's resume point tracks along even if the app is killed
        /// without a clean stop.
        private func beginReporting(with engine: any PlaybackEngine) {
            guard let reporter else { return }

            let start = engine.currentTime
            Task { await reporter.started(atSeconds: start) }

            engine.observeTime(interval: PlaybackReporter.progressInterval) { [weak engine] seconds in
                let isPaused = engine?.isPlaying != true
                Task { await reporter.progress(atSeconds: seconds, isPaused: isPaused) }
            }
        }

        private func endReporting() {
            guard let reporter else { return }

            // Captured now: the engine is torn down before the task runs.
            let position = engine?.currentTime ?? 0
            Task { await reporter.stopped(atSeconds: position) }
        }
    }
}
