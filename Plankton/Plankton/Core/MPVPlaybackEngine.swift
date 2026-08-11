//
//  MPVPlaybackEngine.swift
//  Plankton
//
//  Playback through a bundled mpv, decoding the original file on the device.
//

import AVKit
import Foundation
import Libmpv
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "Player")

/// mpv draws into an `AVSampleBufferDisplayLayer` we hand it and decodes with
/// VideoToolbox, so the server can hand over its original file untouched — no
/// transcode, no remux, no HLS.
///
/// The layer is what buys back Picture in Picture. The system only composites
/// video it owns, and a `CAMetalLayer` is not that however good the picture
/// drawn into it: PiP reads from a sample buffer layer or an `AVPlayerLayer`
/// and from nothing else. Our own `vo=avfoundation` puts decoded frames into
/// one, which is a handoff rather than a conversion, since VideoToolbox has
/// already produced `CVPixelBuffer`s.
///
/// AirPlay and the native track picker are still AVKit's alone.
@MainActor
final class MPVPlaybackEngine: PlaybackEngine {

    private let url: URL
    private let renderView = MPVSampleBufferView()

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

    /// Drives Picture in Picture's transport. Held because PiP reads the
    /// position from it and there is nothing else to read.
    private var timebase: CMTimebase?
    private var pictureInPicture: AVPictureInPictureController?
    private let pictureInPictureDelegate = PictureInPictureDelegate()

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
        static let trackList = "track-list"
        static let subtitleTrack = "sid"
        static let audioTrack = "aid"
        static let subtitleScale = "sub-scale"
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
        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(renderView.displayLayer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &windowID)

        // Our own video output, which enqueues frames into the layer above.
        // Nothing to configure beyond the name: it takes no GPU context,
        // because it never renders anything itself.
        setOption("vo", "avfoundation")

        // The entire point of this engine — VideoToolbox decodes on device, so
        // the server never re-encodes.
        setOption("hwdec", "videotoolbox")

        // `target-colorspace-hint` stays off, but for a different reason than
        // it used to: there is no GPU output left to hint at. Colour reaches
        // the layer as attachments on each frame, which is where AVFoundation
        // reads it from.

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

        configurePictureInPicture()
    }

    /// Picture in Picture, which is the whole reason this engine renders into a
    /// sample buffer layer.
    ///
    /// Started automatically on the way out of the app rather than from a
    /// button: leaving mid-episode is exactly when it is wanted, and a button
    /// would be one more thing drawn over the video. The layer's control
    /// timebase is set here too, since PiP's own transport reads the position
    /// from it and mpv has no way to tell it anything.
    private func configurePictureInPicture() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            logger.info("Picture in Picture is unavailable on this device")
            return
        }

        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let timebase {
            CMTimebaseSetRate(timebase, rate: 0)
            renderView.displayLayer.controlTimebase = timebase
            self.timebase = timebase
        }

        pictureInPictureDelegate.engine = self
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: renderView.displayLayer,
            playbackDelegate: pictureInPictureDelegate
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPicture = controller
    }

    /// Keeps PiP's scrubber honest. The timebase is the only thing it reads a
    /// position from, and nothing else moves it.
    func syncTimebase() {
        guard let timebase else { return }

        CMTimebaseSetTime(timebase, time: CMTime(seconds: currentTime, preferredTimescale: 1000))
        CMTimebaseSetRate(timebase, rate: isPlaying ? 1 : 0)
        pictureInPicture?.invalidatePlaybackState()
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

    /// Set on the layer rather than through mpv's `panscan` and `keepaspect`.
    /// Those make the video output scale the picture itself, which on this
    /// output means a full re-render of every frame through Core Image, and
    /// costs HDR passthrough on the way. `videoGravity` is the layer doing the
    /// same job in the compositor for nothing.
    func setVideoFill(_ fill: VideoFill) {
        switch fill {
        case .fit:
            renderView.displayLayer.videoGravity = .resizeAspect
        case .fill:
            renderView.displayLayer.videoGravity = .resizeAspectFill
        case .stretch:
            renderView.displayLayer.videoGravity = .resize
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

        pictureInPicture?.stopPictureInPicture()
        pictureInPicture = nil
        timebase = nil
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
        syncTimebase()
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

/// The view mpv renders into.
///
/// Backed by an `AVSampleBufferDisplayLayer` rather than hosting one, so UIKit
/// maintains its bounds and the compositor scales the picture according to
/// `videoGravity`. Nothing here sizes a drawable or tracks `contentsScale`: the
/// layer takes frames at their own resolution and fits them to itself, which is
/// what makes a rotation something this engine no longer has to notice.
private final class MPVSampleBufferView: UIView {

    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        displayLayer.videoGravity = .resizeAspect

        // Unlike the Metal path, this is a plain main-thread property on a
        // layer we own, set once. mpv never touches it, so there is no render
        // thread to race and no reason to defer it.
        if #available(iOS 17.0, *) {
            displayLayer.wantsExtendedDynamicRangeContent = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MPVSampleBufferView is not loaded from a nib")
    }
}

// MARK: - Picture in Picture

/// PiP drives the player through this while its window is up: the on-screen
/// controls are gone, and its own transport is all there is.
///
/// A separate object because the delegate protocol demands an `NSObject`, and
/// the engine is not one. Forwarding costs a few lines and keeps PiP from
/// dictating the engine's inheritance.
private final class PictureInPictureDelegate: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {

    /// Weak: the engine owns this, and PiP outliving it would mean driving a
    /// player that has already torn its mpv handle down.
    weak var engine: MPVPlaybackEngine?

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        MainActor.assumeIsolated {
            guard let engine else { return }
            if playing {
                engine.play()
            } else {
                engine.pause()
            }
            engine.syncTimebase()
        }
    }

    /// The whole file, so PiP's scrubber spans what can actually be reached. A
    /// live stream has no such range, and positive infinity is how that is
    /// stated here.
    func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        MainActor.assumeIsolated {
            guard let duration = engine?.duration, duration > 0 else {
                return CMTimeRange(start: .zero, duration: .positiveInfinity)
            }
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 1000)
            )
        }
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        MainActor.assumeIsolated { !(engine?.isPlaying ?? false) }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // The layer fits the picture to whatever size it is given, so there is
        // nothing to reconfigure.
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            guard let engine else { return }
            engine.seek(to: engine.currentTime + skipInterval.seconds)
            engine.syncTimebase()
        }
        completionHandler()
    }
}
