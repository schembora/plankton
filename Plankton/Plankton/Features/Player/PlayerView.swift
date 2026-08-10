//
//  PlayerView.swift
//  Plankton
//
//  Full-screen video playback, through whichever engine the user picked.
//

import OSLog
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// Composes a playthrough: the engine's video surface, the controls it doesn't
/// bring itself, and the alert that closes the player when playback fails.
struct PlayerContainerView: View {

    let playback: PlaybackItem

    @Environment(JellyfinService.self) private var jellyfin
    @Environment(PlaybackSettings.self) private var settings
    @Environment(DownloadService.self) private var downloads
    @Environment(ImageCache.self) private var images
    @Environment(\.dismiss) private var dismiss

    @State private var session: PlaybackSession?
    @State private var errorMessage: String?

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session {
                PlayerSurface(surface: session.surface)
                    .ignoresSafeArea()
                    // The controls hang off the surface rather than sitting
                    // beside it in the stack: as a sibling, SwiftUI drops the
                    // representable's wrapper straight into the hosting
                    // controller's view, which UIKit warns about.
                    .overlay {
                        // AVKit arrives with a scrubber and transport; an engine
                        // drawing into a bare layer has none.
                        if !session.engine.providesControls {
                            // Title and live state come from the session, not
                            // the item this opened with: changing channel
                            // replaces what's playing underneath.
                            PlayerControls(session: session) {
                                dismiss()
                            }
                        }
                    }
            }
        }
        .statusBarHidden()
        .onAppear(perform: startPlayback)
        .onDisappear { session?.end() }
        .alert("Couldn't Play Video", isPresented: isShowingError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startPlayback() {
        guard session == nil else { return }

        logger.info("Starting playback via \(playback.engine.rawValue): \(playback.url.absoluteString, privacy: .private)")

        let session = PlaybackSession(
            playback: playback,
            engineKind: playback.engine,
            settings: settings,
            jellyfin: jellyfin,
            downloads: downloads
        )
        session.start(artwork: images) { message in
            errorMessage = message
        }
        self.session = session
    }
}

/// Hosts whatever the engine vends. A plain view wraps as a view, not as a
/// controller: wrapping mpv's layer-backed view in a view controller made
/// SwiftUI reparent it into the hosting controller, which UIKit warns about.
private struct PlayerSurface: View {

    let surface: PlaybackSurface

    var body: some View {
        switch surface {
        case .view(let view):
            SurfaceView(view: view)
        case .controller(let controller):
            SurfaceController(controller: controller)
        }
    }
}

private struct SurfaceView: UIViewRepresentable {

    let view: UIView

    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct SurfaceController: UIViewControllerRepresentable {

    let controller: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
