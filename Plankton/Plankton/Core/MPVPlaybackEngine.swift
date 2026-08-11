//
//  MPVPlaybackEngine.swift
//  Plankton
//
//  Playback through a bundled mpv, decoding the original file on the device.
//

import Foundation
import Libmpv
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// mpv draws into a `CAMetalLayer` we hand it and decodes with VideoToolbox, so
/// the server can hand over its original file untouched — no transcode, no
/// remux, no HLS. What it costs is everything AVKit gave away for free:
/// Picture in Picture, AirPlay, and the native track picker.
@MainActor
final class MPVPlaybackEngine: PlaybackEngine {

    private let url: URL
    private let renderView = MPVRenderView()

    /// libmpv's handle, read from mpv's own event thread as well as from the
    /// main actor. Written only in `configure` and `tearDown` — and `tearDown`
    /// drains the event queue before destroying what it points at.
    nonisolated(unsafe) private var handle: OpaquePointer?

    /// mpv wakes us from its internal thread; events are drained here so the
    /// handle is never destroyed with a read in flight.
    private let events = DispatchQueue(label: "com.schembor.Plankton.mpv", qos: .userInitiated)

    /// One per `observeTime` caller — progress reporting and the on-screen
    /// controls both want a clock, at very different cadences.
    private var progressTimers: [DispatchSourceTimer] = []
    private var lifecycleObservers: [any NSObjectProtocol] = []

    private var stateHandlers: [() -> Void] = []
    private var failureHandlers: [(String) -> Void] = []

    /// Kept so a failure that lands before anyone is listening still gets
    /// reported, and so one broken file only ever raises one alert.
    private var failureMessage: String?

    /// mpv opens the file when playback actually starts. A resume position set
    /// before then goes in as mpv's own `start` option, since seeking into a
    /// file that isn't open yet just fails.
    private var pendingStart: TimeInterval?
    private var hasIssuedLoad = false
    private var isFileOpen = false

    private enum Property {
        static let pause = "pause"
        static let coreIdle = "core-idle"
        static let duration = "duration"
        static let timePos = "time-pos"
        static let start = "start"
        static let videoTrack = "vid"
        static let trackList = "track-list"
        static let subtitleTrack = "sid"
        static let audioTrack = "aid"
        static let subtitleScale = "sub-scale"
        static let keepAspect = "keepaspect"
        static let panscan = "panscan"

        /// The size mpv believes its window is, as opposed to the layer's own.
        /// The two disagreeing is what puts the picture in a corner.
        static let osdWidth = "osd-dimensions/w"
        static let osdHeight = "osd-dimensions/h"
    }

    /// One entry of mpv's `track-list`, which comes back as JSON when the
    /// property is read as a string.
    private struct TrackEntry: Decodable {
        let id: Int
        let type: String
        let title: String?
        let lang: String?
        let codec: String?

        /// mpv's own layout string, e.g. "5.1" or "stereo".
        let channels: String?

        enum CodingKeys: String, CodingKey {
            case id, type, title, lang, codec
            case channels = "demux-channels"
        }

        /// e.g. "EAC3 · 5.1", for telling two same-language tracks apart.
        var detail: String? {
            [codec?.uppercased(), channels].metadataLine
        }
    }

    init(url: URL) {
        self.url = url
        configure()
    }

    // MARK: - Setup

    private func configure() {
        guard let handle = mpv_create() else {
            logger.error("mpv_create returned nothing; playback will fail")
            return
        }
        self.handle = handle

        // mpv takes the render target as an integer "window id". The engine
        // owns the view backing the layer, so it outlives the handle.
        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(renderView.layer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &windowID)

        // gpu-next reaches Metal through MoltenVK: mpv has no native Metal
        // backend, and its OpenGL ES one is deprecated on iOS.
        setOption("vo", "gpu-next")
        setOption("gpu-api", "vulkan")
        setOption("gpu-context", "moltenvk")

        // The entire point of this engine — VideoToolbox decodes on device, so
        // the server never re-encodes.
        setOption("hwdec", "videotoolbox")

        // HDR passthrough (`target-colorspace-hint`) is deliberately left off.
        // Asking for a non-default colorspace makes MoltenVK set one on the
        // layer from mpv's render thread, and UIKit raises on layer properties
        // being touched off the main thread. The setter it uses is private, so
        // it can't be funnelled to the main thread the way the EDR flag is.
        // HDR content plays tone-mapped instead, which is the same trade other
        // iOS mpv clients make.

        // Match the subtitle behaviour users get from other Jellyfin clients:
        // prefer the system language, fall back rather than showing nothing.
        setOption("subs-match-os-language", "yes")
        setOption("subs-fallback", "yes")

        // Without this, sub-scale is ignored for ASS/SSA — mpv honours the
        // subtitle script's own sizing, and the size control does nothing on
        // exactly the files most likely to need it.
        setOption("sub-ass-override", "scale")

        #if DEBUG
        mpv_request_log_messages(handle, "warn")
        #else
        mpv_request_log_messages(handle, "no")
        #endif

        check(mpv_initialize(handle), "initialize")

        // Format none: these only signal that something changed, and the
        // values are read back on demand.
        for property in [
            Property.pause, Property.coreIdle, Property.duration,
            Property.trackList, Property.subtitleTrack,
        ] {
            mpv_observe_property(handle, 0, property, MPV_FORMAT_NONE)
        }

        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            Unmanaged<MPVPlaybackEngine>.fromOpaque(context).takeUnretainedValue().drainEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        observeAppLifecycle()
        observeGeometry()
    }

    /// Logs the layer's size next to mpv's own idea of its window after every
    /// layout. When those two disagree the video is laid out for one size and
    /// drawn into another, which is what a rotation leaving the picture in a
    /// corner looks like.
    private func observeGeometry() {
        #if DEBUG
        renderView.onLayout = { [weak self] renderSize, scale in
            guard let self else { return }

            let mpvWidth = self.double(Property.osdWidth)
            let mpvHeight = self.double(Property.osdHeight)
            // Info rather than debug: debug-level messages aren't captured by
            // default, and this exists to be read.
            logger.info(
                """
                geometry: layer \(Int(renderSize.width))x\(Int(renderSize.height)) @\(scale, format: .fixed(precision: 1))x \
                | mpv \(Int(mpvWidth))x\(Int(mpvHeight))
                """
            )
        }
        #endif
    }

    /// MoltenVK can't present while the app is backgrounded, and coming back
    /// with the video track still attached leaves a black picture. Dropping the
    /// track on the way out keeps audio playing and restores cleanly.
    ///
    /// Through the property interface, and off the main thread. `vid` was being
    /// set as an option, which mpv only accepts before `mpv_initialize` and
    /// silently ignores afterwards, so the track was never actually dropped:
    /// mpv kept rendering into a layer it could not present, which is what put
    /// an uncommitted CATransaction on its render thread at lock. It has to
    /// leave the main thread as well, since changing the track makes the video
    /// output reconfigure and its setter blocks until that lands.
    private func observeAppLifecycle() {
        let center = NotificationCenter.default

        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPropertyOffMain(Property.videoTrack, "no") }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setPropertyOffMain(Property.videoTrack, "auto") }
            },
        ]
    }

    // MARK: - State

    var currentTime: TimeInterval {
        // Before the file opens there's no clock to read, and the resume point
        // is the honest answer — it's what gets reported as the start position.
        guard isFileOpen else { return pendingStart ?? 0 }

        let position = double(Property.timePos)
        return position.isFinite ? position : 0
    }

    var duration: TimeInterval? {
        guard isFileOpen else { return nil }

        let length = double(Property.duration)
        return length.isFinite && length > 0 ? length : nil
    }

    var isPlaying: Bool {
        // core-idle covers paused, buffering and seeking in a single flag,
        // which is exactly the "frames aren't moving" the lock screen wants.
        guard isFileOpen else { return false }
        return !flag(Property.coreIdle)
    }

    // MARK: - Transport

    func play() {
        if !hasIssuedLoad {
            hasIssuedLoad = true

            // Opening at a position is mpv's job, and has to be set before the
            // file is handed over.
            if let pendingStart {
                setOption(Property.start, String(format: "%.3f", pendingStart))
            }
            command("loadfile", url.absoluteString, "replace")
        }
        setFlag(Property.pause, false)
    }

    func pause() {
        setFlag(Property.pause, true)
    }

    /// mpv swaps the file inside the running instance, so the Vulkan surface,
    /// the decoder and the audio session all survive. Rebuilding the engine
    /// per channel would pay mpv's whole startup on every change.
    func load(_ url: URL, startingAt seconds: TimeInterval?) {
        hasIssuedLoad = true
        isFileOpen = false
        pendingStart = seconds
        // The previous stream's failure has nothing to say about this one.
        failureMessage = nil

        // Set before the file is handed over: mpv opens at this position, and
        // a seek issued afterwards would arrive before there is a file to seek.
        setOption(Property.start, seconds.map { String(format: "%.3f", max(0, $0)) } ?? "none")

        command("loadfile", url.absoluteString, "replace")
        setFlag(Property.pause, false)
        notifyState()
    }

    func seek(to seconds: TimeInterval) {
        let target = max(0, seconds)

        guard isFileOpen else {
            pendingStart = target
            return
        }
        command("seek", String(format: "%.3f", target), "absolute")
    }

    // MARK: - Tracks

    /// mpv reads embedded subtitles itself and rasterises them through libass,
    /// so ASS/SSA styling and PGS bitmaps both survive — the thing the server
    /// otherwise had to burn into the video.
    var subtitleTracks: [PlaybackTrack] {
        tracks(ofType: "sub")
    }

    var selectedSubtitleTrack: PlaybackTrack.ID? {
        // mpv answers "no" when subtitles are off, which is not an Int — and
        // nil is exactly what that should become.
        Int(string(Property.subtitleTrack) ?? "no")
    }

    func selectSubtitleTrack(_ id: PlaybackTrack.ID?) {
        setProperty(Property.subtitleTrack, id.map(String.init) ?? "no")
    }

    /// Every track the file carries, because the file arrived whole. This is
    /// the direct engine's other quiet win: a server transcode collapses the
    /// audio to one stream, so there is nothing left to choose from.
    var audioTracks: [PlaybackTrack] {
        tracks(ofType: "audio")
    }

    var selectedAudioTrack: PlaybackTrack.ID? {
        Int(string(Property.audioTrack) ?? "no")
    }

    func selectAudioTrack(_ id: PlaybackTrack.ID) {
        setProperty(Property.audioTrack, String(id))
    }

    func setSubtitleScale(_ scale: Double) {
        setProperty(Property.subtitleScale, String(format: "%.2f", scale))
    }

    /// `panscan` zooms until the frame is covered and crops the overhang;
    /// `keepaspect` off lets the picture distort to fit. They're separate
    /// properties, so both get set every time rather than left where the last
    /// choice put them.
    func setVideoFill(_ fill: VideoFill) {
        switch fill {
        case .fit:
            setPropertyOffMain(Property.keepAspect, "yes")
            setPropertyOffMain(Property.panscan, "0")
        case .fill:
            setPropertyOffMain(Property.keepAspect, "yes")
            setPropertyOffMain(Property.panscan, "1")
        case .stretch:
            setPropertyOffMain(Property.keepAspect, "no")
            setPropertyOffMain(Property.panscan, "0")
        }
    }

    private func tracks(ofType type: String) -> [PlaybackTrack] {
        guard let json = string(Property.trackList),
              let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([TrackEntry].self, from: data)
        else { return [] }

        return entries
            .filter { $0.type == type }
            .map { PlaybackTrack(id: $0.id, title: $0.title, language: $0.lang, detail: $0.detail) }
    }

    // MARK: - Presentation

    /// mpv draws frames into a layer and nothing else — every control is ours.
    let providesControls = false

    func makeSurface() -> PlaybackSurface {
        .view(renderView)
    }

    func tearDown() {
        for timer in progressTimers {
            timer.cancel()
        }
        progressTimers.removeAll()

        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
        stateHandlers.removeAll()
        failureHandlers.removeAll()

        guard let handle else { return }
        self.handle = nil

        // Stop new wake-ups, then destroy on the event queue rather than here.
        // Being a serial queue it already orders behind any drain still in
        // flight, so the handle can't be freed mid-read — and unlike waiting
        // for that here, it doesn't block the main thread inside a call that
        // waits on mpv's own threads to finish.
        mpv_set_wakeup_callback(handle, nil, nil)
        events.async {
            mpv_terminate_destroy(handle)
        }
    }

    // MARK: - Observation

    func observeTime(interval: TimeInterval, _ handler: @escaping (TimeInterval) -> Void) {
        // mpv can observe `time-pos`, but it updates every frame — orders of
        // magnitude more often than progress needs reporting. A timer keeps the
        // cadence the same as the AVPlayer engine's periodic observer.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { handler(self.currentTime) }
        }
        timer.resume()
        progressTimers.append(timer)
    }

    func observeState(_ handler: @escaping () -> Void) {
        stateHandlers.append(handler)
    }

    func observeFailure(_ handler: @escaping (String) -> Void) {
        failureHandlers.append(handler)

        // Events arrive asynchronously, so a file that fails to open can do so
        // before the first listener registers.
        if let failureMessage {
            handler(failureMessage)
        }
    }

    private func notifyState() {
        for handler in stateHandlers {
            handler()
        }
    }

    private func reportFailure(_ message: String) {
        guard failureMessage == nil else { return }

        failureMessage = message
        logger.error("Playback failed: \(message)")

        for handler in failureHandlers {
            handler(message)
        }
    }

    // MARK: - Event pump

    nonisolated private func drainEvents() {
        events.async { [weak self] in
            guard let self, let handle = self.handle else { return }

            while true {
                guard let event = mpv_wait_event(handle, 0),
                      event.pointee.event_id != MPV_EVENT_NONE
                else { return }

                self.process(event.pointee)
            }
        }
    }

    nonisolated private func process(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            Task { @MainActor in
                self.isFileOpen = true
                self.notifyState()
            }

        // mpv's answer to AVPlayer's seek completion — the position is only
        // trustworthy once playback restarts.
        case MPV_EVENT_PROPERTY_CHANGE, MPV_EVENT_PLAYBACK_RESTART:
            Task { @MainActor in self.notifyState() }

        case MPV_EVENT_END_FILE:
            guard let ending = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.data))?.pointee,
                  ending.reason == MPV_END_FILE_REASON_ERROR
            else { return }

            let message = String(cString: mpv_error_string(ending.error))
            Task { @MainActor in self.reportFailure(message) }

        case MPV_EVENT_LOG_MESSAGE:
            guard let message = UnsafePointer<mpv_event_log_message>(OpaquePointer(event.data))?.pointee else { return }
            logger.debug("mpv [\(String(cString: message.prefix))] \(String(cString: message.text))")

        default:
            break
        }
    }

    // MARK: - Property helpers

    private func double(_ name: String) -> Double {
        guard let handle else { return 0 }

        var value = Double()
        mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        return value
    }

    /// mpv allocates the returned string, so it has to be handed back.
    private func string(_ name: String) -> String? {
        guard let handle, let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        return String(cString: raw)
    }

    private func flag(_ name: String) -> Bool {
        guard let handle else { return false }

        var value = Int64()
        mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value)
        return value > 0
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let handle else { return }

        var raw = Int32(value ? 1 : 0)
        check(mpv_set_property(handle, name, MPV_FORMAT_FLAG, &raw), "set \(name)")
    }

    /// Options are only settable before `mpv_initialize`; anything changed
    /// while playing has to go through the property interface instead.
    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        check(mpv_set_option_string(handle, name, value), "set option \(name)")
    }

    private func setProperty(_ name: String, _ value: String) {
        guard let handle else { return }
        check(mpv_set_property_string(handle, name, value), "set \(name)")
    }

    /// For properties the video output has to reconfigure for.
    ///
    /// mpv's setters are synchronous and block until the core has applied
    /// them. Anything that makes the VO rebuild its render passes blocks on
    /// the VO thread, which needs the main thread to present — so setting one
    /// from the main thread hangs the two against each other. Cheap properties
    /// stay synchronous, since answering immediately is what lets a track
    /// selection be read straight back.
    private func setPropertyOffMain(_ name: String, _ value: String) {
        guard let handle else { return }

        events.async {
            let status = mpv_set_property_string(handle, name, value)
            guard status < 0 else { return }
            logger.error("mpv set \(name, privacy: .public): \(String(cString: mpv_error_string(status)))")
        }
    }

    private func command(_ name: String, _ arguments: String...) {
        guard let handle else { return }

        var argv: [UnsafePointer<CChar>?] = ([name] + arguments).map { UnsafePointer(strdup($0)) }
        argv.append(nil)
        defer {
            for argument in argv where argument != nil {
                free(UnsafeMutablePointer(mutating: argument))
            }
        }

        check(mpv_command(handle, &argv), name)
    }

    private func check(_ status: Int32, _ operation: String) {
        guard status < 0 else { return }
        logger.error("mpv \(operation): \(String(cString: mpv_error_string(status)))")
    }
}

private final class MPVMetalLayer: CAMetalLayer {

    /// Works around MoltenVK dropping the drawable to 1x1 to force a
    /// presentation, which otherwise leaves the picture flickering or stuck at
    /// that size. See https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            guard newValue.width > 1, newValue.height > 1 else { return }
            super.drawableSize = newValue
        }
    }

    /// mpv flips this from its render thread, but the screen only actually
    /// enters EDR mode when the change is made on the main thread — off it,
    /// HDR content silently plays back tone-mapped.
    ///
    /// Dispatched rather than waited on: mpv's render thread must never block
    /// on the main thread, which tears playback down and waits on mpv while
    /// doing so. Blocking here deadlocks the two against each other. EDR
    /// engaging a frame later is not something anyone can see.
    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.async {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}

/// The view mpv renders into.
///
/// Backing the view with the Metal layer rather than adding a sublayer to it
/// means UIKit maintains the layer's bounds and `contentsScale` itself. Doing
/// that by hand left mpv rendering against a mis-scaled surface, which sized
/// the subtitle overlay against the wrong resolution.
private final class MPVRenderView: UIView {

    /// Reports the render size and scale after each layout, so the engine can
    /// hold them up against what mpv thinks its window is.
    var onLayout: ((_ renderSize: CGSize, _ scale: CGFloat) -> Void)?

    override class var layerClass: AnyClass { MPVMetalLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true

        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.framebufferOnly = true
        }
        applyContentsScale()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MPVRenderView is not loaded from a nib")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyContentsScale()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Bounds animate through a rotation, and mpv presents continuously into
        // the layer while they do. Without this the picture tears and lands
        // mid-animation, at a size neither orientation agrees with.
        //
        // `drawableSize` is deliberately left alone. MoltenVK assigns it while
        // building a swapchain, on mpv's render thread; writing it from here as
        // well raced that, and a render pass sized for one drawable would run
        // against another. mpv reads bounds and scale instead, and MoltenVK
        // stays the only writer.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyContentsScale()
        CATransaction.commit()

        // The size mpv derives for itself, which is not the drawable's: those
        // are two different things now, and this is the one driving the resize.
        let scale = layer.contentsScale
        onLayout?(CGSize(width: bounds.width * scale, height: bounds.height * scale), scale)
    }

    /// mpv renders at bounds times `contentsScale`, and builds its swapchain
    /// the moment it's handed the layer — before the view has a window, while
    /// UIKit still has the scale at 1. Left alone the video renders at point
    /// resolution and Core Animation upscales it, which is the difference
    /// between sharp and soft.
    ///
    /// `nativeScale` rather than `scale`: they differ on the models that render
    /// above panel resolution, and the panel's is what decides how many pixels
    /// actually reach the glass.
    private func applyContentsScale() {
        let scale = window?.screen.nativeScale ?? traitCollection.displayScale
        guard scale > 0, layer.contentsScale != scale else { return }
        layer.contentsScale = scale
    }
}
