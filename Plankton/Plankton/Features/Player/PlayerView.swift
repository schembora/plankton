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

    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        PlayerView(url: url) { message in
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

    let url: URL
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        logger.info("Starting playback: \(url.absoluteString, privacy: .private)")
        configureAudioSession()

        let item = AVPlayerItem(url: url)
        context.coordinator.observe(item)

        let controller = AVPlayerViewController()
        controller.player = AVPlayer(playerItem: item)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
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
        private let onError: (String) -> Void
        private var observation: NSKeyValueObservation?

        init(onError: @escaping (String) -> Void) {
            self.onError = onError
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
