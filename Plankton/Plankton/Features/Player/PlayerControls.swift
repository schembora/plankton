//
//  PlayerControls.swift
//  Plankton
//
//  Transport controls for engines that don't bring their own.
//

import JellyfinAPI
import SwiftUI

/// How long the controls stay up after the last touch.
private let autoHideDelay: Duration = .seconds(3.5)

/// What the skip buttons jump, matching the lock screen's own interval.
private let skipInterval: TimeInterval = 15

/// Clear glass, darkened a touch.
///
/// Fully clear gives up its own contrast, and white glyphs disappear whenever
/// the frame behind them goes bright. A little black in the tint keeps the
/// transparency while giving them something to sit on.
private let playerGlass: Glass = .clear.tint(.black.opacity(0.28))

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

    /// For the compact row in the subtitles panel, where five full words
    /// wouldn't fit and the order carries the meaning anyway.
    var shortTitle: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .standard: "D"
        case .large: "L"
        case .larger: "XL"
        }
    }

    /// Maps a stored scale onto the closest preset, so a value written by an
    /// older build (or hand-edited) still selects something in the menu.
    static func nearest(to scale: Double) -> SubtitleScale {
        allCases.min { abs($0.rawValue - scale) < abs($1.rawValue - scale) } ?? .standard
    }
}

/// The chrome AVKit would have supplied: transport, track pickers, a timeline
/// and a way out. Shown only over engines that draw into a bare layer.
struct PlayerControls: View {

    @Bindable var session: PlaybackSession

    let onClose: () -> Void

    /// Skipping is the only part of the transport that depends on this; where
    /// the playhead sits is `PlaybackTimeline`'s business.
    private var isLive: Bool { session.isLive }

    /// The options panels, drawn by us rather than by `Menu`.
    ///
    /// A SwiftUI menu presents a UIKit context menu, which arrives in a light
    /// material that looks foreign over video, and re-hosts the view tree the
    /// video surface lives in — which is what UIKit complains about when it
    /// reparents our representable.
    private enum OptionsPanel: String, Identifiable {
        case subtitles, audio, videoSize
        var id: String { rawValue }
    }

    @State private var isVisible = true
    @State private var isShowingQueue = false
    @State private var openPanel: OptionsPanel?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Catches taps across the whole video, including while the controls
            // are hidden — tapping is how they come back.
            Color.clear
                .contentShape(.rect)
                .onTapGesture { toggle() }

            if isVisible {
                // Legibility where the text actually is, rather than a flat dim
                // over the picture. Glass samples what's behind it, so dimming
                // the whole frame is what made the buttons look solid — and
                // animating that dim is why they only settled a beat later.
                scrim

                // Grouped so the glass renders as one system rather than a
                // handful of unrelated panes.
                GlassEffectContainer {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)

                        // The transport steps aside for the season rather than
                        // stacking above it: on a phone in landscape there
                        // isn't room for both, and browsing is what the strip
                        // is open for.
                        if !isShowingQueue {
                            transport
                            Spacer(minLength: 0)
                        }

                        if isShowingQueue {
                            PlayerQueueStrip(session: session, onInteraction: scheduleHide)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .padding(.bottom, 12)
                        }

                        PlaybackTimeline(session: session) { isScrubbing in
                            // A drag holds the chrome open; letting go restarts
                            // the clock that hides it.
                            if isScrubbing {
                                hideTask?.cancel()
                            } else {
                                scheduleHide()
                            }
                        }

                        optionsBar
                    }
                    // Floated over the controls rather than placed among them:
                    // in the layout flow it pushed the timeline up every time
                    // a panel opened, which moved the scrubber out from under
                    // whoever was reaching for it.
                    .overlay(alignment: .bottomTrailing) {
                        if let openPanel {
                            panel(for: openPanel)
                                .padding(.bottom, 60)
                                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
                        }
                    }
                }
                .padding(20)
                // The controls cover the whole frame, so the catcher behind
                // them never sees a tap while they're up. Taking them here
                // instead: buttons win for their own frames, and everything
                // else — the video showing between them — lands on this.
                .contentShape(.rect)
                .onTapGesture {
                    if openPanel != nil {
                        withAnimation(.easeInOut(duration: 0.2)) { openPanel = nil }
                        scheduleHide()
                    } else if isShowingQueue {
                        closeQueue()
                    } else {
                        toggle()
                    }
                }
                .transition(.opacity)
                // Player chrome is monochrome, the way AVKit's is. Control
                // glyphs otherwise inherit the app's accent colour, which puts
                // blue over the video and reads as a link rather than a
                // transport. Tint carries it into the slider and the menus.
                .foregroundStyle(.white)
                .tint(.white)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
        // Pausing should leave the controls up; resuming starts the clock again.
        .onChange(of: session.isPlaying) { _, _ in scheduleHide() }
    }

    // MARK: - Pieces

    /// Dark at the two edges the text sits against and clear through the
    /// middle, so the picture stays visible and the glass has something honest
    /// to sample. Never takes hits: the tap target underneath owns those.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.7),
                .init(color: .black.opacity(0.55), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .glassEffect(playerGlass.interactive(), in: .circle)
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 1) {
                if let title = session.title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                }

                // What's on, under what it's on. Only live carries one today.
                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .shadow(radius: 4)

            Spacer(minLength: 0)

            // Live puts channel up and down in the transport, where a
            // recording keeps its skip buttons — so next episode lives here
            // instead of crowding that row with a fifth control.
            if !isLive, session.hasNextInQueue {
                nextInQueueButton
            }

            if session.queue.count > 1 {
                queueStripButton
            }
        }
    }

    /// How it looks and sounds, rather than where to go next. Kept apart from
    /// the top bar so navigation stays in one place and presentation in
    /// another, and so neither row grows past a thumb's reach.
    private var optionsBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            // Nothing to choose between on a file with no subtitles.
            if !session.subtitleTracks.isEmpty {
                subtitleButton
            }

            // One audio track is not a choice. Most files have exactly one,
            // and a button that opens a list of it would be noise.
            if session.audioTracks.count > 1 {
                audioButton
            }

            fillButton
        }
        .padding(.top, 8)
    }

    /// How the picture sits on screen. Always offered: whether it's useful
    /// depends on the shape of what's playing against the shape of the phone,
    /// and the player can't know that until frames arrive.
    private var subtitleButton: some View {
        panelButton(
            symbol: session.selectedSubtitleTrack == nil ? "captions.bubble" : "captions.bubble.fill",
            label: "Subtitles",
            panel: .subtitles
        )
    }

    private var audioButton: some View {
        panelButton(symbol: "waveform", label: "Audio", panel: .audio)
    }

    private var fillButton: some View {
        panelButton(
            symbol: session.videoFill == .fit ? "aspectratio" : "aspectratio.fill",
            label: "Video size",
            panel: .videoSize
        )
    }

    private func panelButton(symbol: String, label: String, panel: OptionsPanel) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                openPanel = openPanel == panel ? nil : panel
            }
            scheduleHide()
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .padding(12)
                .glassEffect(playerGlass.interactive(), in: .circle)
        }
        .accessibilityLabel(label)
    }

    /// Drawn by us rather than by `Menu`: the same clear glass as everything
    /// else here, and nothing gets re-hosted to present it.
    @ViewBuilder
    private func panel(for panel: OptionsPanel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch panel {
            case .subtitles:
                // Only the tracks scroll. Size is pinned below them, because a
                // file with a dozen subtitle tracks would otherwise bury it.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        optionRow("Off", isSelected: session.selectedSubtitleTrack == nil) {
                            session.selectSubtitleTrack(nil)
                        }

                        ForEach(session.subtitleTracks) { track in
                            optionRow(
                                track.displayName,
                                isSelected: session.selectedSubtitleTrack == track.id
                            ) {
                                session.selectSubtitleTrack(track.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 190)

                // Sizing is meaningless with nothing on screen to size.
                if session.selectedSubtitleTrack != nil {
                    Divider().overlay(.white.opacity(0.2))
                    subtitleSizeRow
                }

            case .audio:
                // No "Off" row: silence belongs to the mute control, and an
                // audio list that can turn itself off is a way to end up with
                // a silent player and no obvious way back.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(session.audioTracks) { track in
                            optionRow(
                                track.displayName,
                                detail: track.detail,
                                isSelected: session.selectedAudioTrack == track.id
                            ) {
                                session.selectAudioTrack(track.id)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 220)

            case .videoSize:
                ForEach(VideoFill.allCases) { fill in
                    optionRow(fill.title, isSelected: session.videoFill == fill) {
                        session.videoFill = fill
                    }
                }
            }
        }
        .frame(minWidth: 210)
        .fixedSize(horizontal: true, vertical: false)
        .glassEffect(playerGlass, in: .rect(cornerRadius: 16))
    }

    /// Five sizes in a row rather than five more rows in the list: they're an
    /// ordered scale, so the order carries the meaning and the labels can be
    /// short enough to sit side by side.
    private var subtitleSizeRow: some View {
        HStack(spacing: 8) {
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            ForEach(SubtitleScale.allCases) { scale in
                let isSelected = SubtitleScale.nearest(to: session.subtitleScale) == scale

                Button {
                    session.subtitleScale = scale.rawValue
                    scheduleHide()
                } label: {
                    Text(scale.shortTitle)
                        .font(.caption.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background {
                            Circle().fill(.white.opacity(isSelected ? 0.3 : 0.1))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(scale.title) subtitles")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func optionRow(
        _ title: String,
        detail: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            scheduleHide()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)

                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                // Reserved rather than conditional, so choosing a different
                // row doesn't change the width of the panel under your thumb.
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Opens the line-up along the bottom: the rest of the season, or the
    /// channels with what's on each. The transport's next and channel-up are
    /// the quick ways on; this is for picking somewhere else entirely.
    private var queueStripButton: some View {
        Button {
            if isShowingQueue {
                closeQueue()
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { isShowingQueue = true }
                scheduleHide()
            }
        } label: {
            Image(systemName: queueSymbol)
                .font(.headline)
                .padding(12)
                .glassEffect(playerGlass.interactive(), in: .circle)
        }
        .accessibilityLabel(isShowingQueue ? "Hide \(queueNoun)" : "Show \(queueNoun)")
    }

    private var queueNoun: String { isLive ? "channels" : "episodes" }

    private var queueSymbol: String {
        if isLive {
            isShowingQueue ? "tv.fill" : "tv"
        } else {
            isShowingQueue ? "rectangle.stack.fill" : "rectangle.stack"
        }
    }

    /// Plays the next episode without leaving the player. Reuses the engine,
    /// so it costs a re-buffer rather than mpv's whole startup, and it resumes
    /// wherever the server says that episode was left.
    private var nextInQueueButton: some View {
        Button {
            scheduleHide()
            Task { await session.goToNextInQueue() }
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.headline)
                .padding(12)
                .glassEffect(playerGlass.interactive(), in: .circle)
                .opacity(session.isSwitching ? 0.4 : 1)
        }
        .disabled(session.isSwitching)
        .accessibilityLabel("Next episode")
    }

    private var transport: some View {
        HStack(spacing: 44) {
            // A live stream has no timeline to skip along, so the slots either
            // side of play/pause carry channel down and up instead — the thing
            // there actually is to move between.
            if isLive {
                queueButton("chevron.down", label: "Channel down", enabled: session.hasPreviousInQueue) {
                    await session.goToPreviousInQueue()
                }
            } else {
                skipButton("gobackward.15", by: -skipInterval)
            }

            Button(action: act(session.togglePlayPause)) {
                Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .frame(width: 74, height: 74)
                    .glassEffect(playerGlass.interactive(), in: .circle)
            }
            .accessibilityLabel(session.isPlaying ? "Pause" : "Play")

            if isLive {
                queueButton("chevron.up", label: "Channel up", enabled: session.hasNextInQueue) {
                    await session.goToNextInQueue()
                }
            } else {
                skipButton("goforward.15", by: skipInterval)
            }
        }
    }

    /// Moves to the next or previous thing in the queue. Disabled at the ends
    /// rather than wrapping: a line-up has a first and last channel, and
    /// looping past them is disorienting when you're holding the button.
    private func queueButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            scheduleHide()
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .glassEffect(playerGlass.interactive(), in: .circle)
        }
        .disabled(!enabled || session.isSwitching)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func skipButton(_ symbol: String, by seconds: TimeInterval) -> some View {
        Button(action: act { session.skip(by: seconds) }) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 56, height: 56)
                .glassEffect(playerGlass.interactive(), in: .circle)
        }
        .accessibilityLabel(seconds < 0 ? "Skip back 15 seconds" : "Skip forward 15 seconds")
    }

    // MARK: - Behaviour

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

    /// Tapping away from an open season closes it rather than dismissing the
    /// whole chrome: one tap should undo one thing.
    private func closeQueue() {
        withAnimation(.easeInOut(duration: 0.25)) { isShowingQueue = false }
        scheduleHide()
    }

    /// Controls stay up while paused or scrubbing — there's nothing to watch
    /// underneath them, and hiding would just cost another tap.
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: autoHideDelay)

            // Browsing the season counts as using the player: pulling the
            // strip out from under a thumb mid-scroll would be its own bug.
            guard !Task.isCancelled, session.isPlaying, !session.isScrubbing,
                  !isShowingQueue, openPanel == nil
            else {
                return
            }
            isVisible = false
        }
    }

}
