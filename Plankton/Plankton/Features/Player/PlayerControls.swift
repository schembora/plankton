//
//  PlayerControls.swift
//  Plankton
//
//  Transport controls for engines that don't bring their own.
//

import SwiftUI

/// How long the controls stay up after the last touch.
private let autoHideDelay: Duration = .seconds(3.5)

/// What the skip buttons jump, matching the lock screen's own interval.
private let skipInterval: TimeInterval = 15

/// Preset subtitle sizes. Presets rather than a slider because a menu can't
/// show a live preview, and picking a number blind is worse than picking a word.
enum SubtitleScale: Double, CaseIterable, Identifiable {

    case small = 0.6
    case medium = 0.8
    case standard = 1
    case large = 1.25
    case larger = 1.5

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    /// Maps a stored scale onto the closest preset, so a value written by an
    /// older build (or hand-edited) still selects something in the menu.
    static func nearest(to scale: Double) -> SubtitleScale {
        allCases.min { abs($0.rawValue - scale) < abs($1.rawValue - scale) } ?? .standard
    }
}

/// The chrome AVKit would have supplied: scrubber, transport, timings and a way
/// out. Shown only over engines that draw into a bare layer.
struct PlayerControls: View {

    @Bindable var session: PlaybackSession

    let title: String?
    let onClose: () -> Void

    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Catches taps across the whole video. Nearly transparent rather
            // than clear so it still takes hits while the controls are hidden.
            Color.black
                .opacity(isVisible ? 0.3 : 0.001)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { toggle() }

            if isVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    transport
                    Spacer(minLength: 0)
                    scrubber
                }
                .padding(20)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
        // Pausing should leave the controls up; resuming starts the clock again.
        .onChange(of: session.isPlaying) { _, _ in scheduleHide() }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel("Close")

            if let title {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .shadow(radius: 4)
            }

            Spacer(minLength: 0)

            // Nothing to choose between on a file with no subtitles.
            if !session.subtitleTracks.isEmpty {
                subtitleMenu
            }
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Picker("Subtitles", selection: subtitleSelection) {
                Text("Off").tag(PlaybackTrack.ID?.none)

                ForEach(session.subtitleTracks) { track in
                    Text(track.displayName).tag(PlaybackTrack.ID?.some(track.id))
                }
            }

            // Sizing is meaningless with nothing on screen to size.
            if session.selectedSubtitleTrack != nil {
                Picker("Size", selection: scaleSelection) {
                    ForEach(SubtitleScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
            }
        } label: {
            Image(systemName: session.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill")
                .font(.headline)
                .padding(12)
                .glassEffect(.regular, in: .circle)
        }
        .accessibilityLabel("Subtitles")
    }

    private var subtitleSelection: Binding<PlaybackTrack.ID?> {
        Binding(
            get: { session.selectedSubtitleTrack },
            set: {
                session.selectSubtitleTrack($0)
                scheduleHide()
            }
        )
    }

    private var scaleSelection: Binding<SubtitleScale> {
        Binding(
            get: { SubtitleScale.nearest(to: session.subtitleScale) },
            set: {
                session.subtitleScale = $0.rawValue
                scheduleHide()
            }
        )
    }

    private var transport: some View {
        HStack(spacing: 44) {
            skipButton("gobackward.15", by: -skipInterval)

            Button(action: act(session.togglePlayPause)) {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .frame(width: 74, height: 74)
                    .glassEffect(.regular, in: .circle)
            }
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            skipButton("goforward.15", by: skipInterval)
        }
    }

    private func skipButton(_ symbol: String, by seconds: TimeInterval) -> some View {
        Button(action: act { session.skip(by: seconds) }) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: .circle)
        }
        .accessibilityLabel(seconds < 0 ? "Skip back 15 seconds" : "Skip forward 15 seconds")
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    // The engine's clock can overshoot the reported duration by
                    // a frame or two at the end of a file; the slider must not
                    // be handed a value outside its own range.
                    get: { min(session.position, session.duration ?? 1) },
                    set: { session.scrub(to: $0) }
                ),
                // A track needs a positive range even before the duration is
                // known, or the slider renders as a dead line.
                in: 0...(session.duration ?? 1),
                onEditingChanged: scrubbingChanged
            )
            .disabled(session.duration == nil)

            HStack {
                Text(Self.timeText(session.position))
                Spacer()
                if let duration = session.duration {
                    Text("-" + Self.timeText(duration - session.position))
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .tint(.white)
    }

    // MARK: - Behaviour

    private func scrubbingChanged(_ isScrubbing: Bool) {
        session.isScrubbing = isScrubbing

        if isScrubbing {
            hideTask?.cancel()
        } else {
            session.seek(to: session.position)
            scheduleHide()
        }
    }

    /// Wraps a control's action so using it also keeps the controls up.
    private func act(_ action: @escaping () -> Void) -> () -> Void {
        {
            action()
            scheduleHide()
        }
    }

    private func toggle() {
        isVisible.toggle()
        if isVisible {
            scheduleHide()
        }
    }

    /// Controls stay up while paused or scrubbing — there's nothing to watch
    /// underneath them, and hiding would just cost another tap.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: autoHideDelay)

            guard !Task.isCancelled, session.isPlaying, !session.isScrubbing else { return }
            isVisible = false
        }
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }

        let total = Int(seconds.rounded())
        let (hours, minutes, remainder) = (total / 3600, (total % 3600) / 60, total % 60)

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%d:%02d", minutes, remainder)
    }
}
