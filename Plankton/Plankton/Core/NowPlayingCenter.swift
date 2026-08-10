//
//  NowPlayingCenter.swift
//  Plankton
//
//  Publishes what's playing to the lock screen and Control Center.
//

import Foundation
import JellyfinAPI
import MediaPlayer
import OSLog

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "NowPlaying")

/// What the lock screen shows for a playing item. Built by whoever starts
/// playback, since only they know whether it came from the server or from disk.
struct NowPlayingMetadata {

    /// The episode or movie name — not the series, which reads as the artist.
    var title: String
    var subtitle: String?
    var artwork: Artwork?
}

extension NowPlayingMetadata {

    /// Server-backed playback. An episode leads with its own name and puts the
    /// series underneath, the way a track sits under its artist — the reverse of
    /// a poster tile, where the series is what you're scanning for.
    init(_ item: BaseItemDto) {
        // A channel leads with itself and puts the programme underneath. The
        // channel is what was chosen and what stays put; the programme is
        // whatever happens to be on it.
        if item.isLiveChannel {
            title = [item.channelNumber, item.name].metadataLine ?? item.displayTitle
            subtitle = item.currentProgram?.name
            artwork = item.artwork(.primary, maxWidth: 600)
            return
        }

        title = item.name ?? item.displayTitle
        if item.type == .episode {
            subtitle = [item.seriesName, item.episodeLabel].metadataLine
        } else {
            subtitle = item.productionYear.map(String.init)
        }
        artwork = item.artwork(.poster, maxWidth: 600)
    }

    /// Offline playback. The poster is passed in rather than read from
    /// `DownloadService`, so `DownloadedMedia` stays a plain snapshot.
    init(_ media: DownloadedMedia, poster: URL) {
        title = media.title
        subtitle = [media.seriesName, media.episodeLabel].metadataLine
        artwork = .local(poster)
    }
}

/// Mirrors a `PlaybackEngine` into `MPNowPlayingInfoCenter` and wires the lock
/// screen's transport controls back to it.
///
/// `AVPlayerViewController` can populate the info center itself, but only from
/// metadata embedded in the asset — a Jellyfin HLS stream carries no title or
/// artwork, so the lock screen would offer bare transport controls with nothing
/// to identify what's playing. Its automatic updating is switched off in
/// `AVPlaybackEngine`, because it replaces the whole info dictionary and would
/// drop the fields filled in here.
@MainActor
final class NowPlayingCenter {

    /// How far the lock screen's skip buttons jump, in seconds.
    private static let skipInterval: TimeInterval = 15

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()

    /// The item's fixed fields. Position and duration are merged in on publish,
    /// so each value has one source of truth.
    private var staticInfo: [String: Any] = [:]

    private weak var engine: (any PlaybackEngine)?
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var artworkTask: Task<Void, Never>?

    func start(_ metadata: NowPlayingMetadata, for engine: any PlaybackEngine, artwork cache: ImageCache) {
        self.engine = engine

        staticInfo[MPMediaItemPropertyTitle] = metadata.title
        if let subtitle = metadata.subtitle {
            staticInfo[MPMediaItemPropertyArtist] = subtitle
        }
        staticInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        staticInfo[MPNowPlayingInfoPropertyIsLiveStream] = false

        publish()
        observe(engine)
        registerCommands(for: engine)
        loadArtwork(metadata.artwork, from: cache)
    }

    /// Leaves nothing behind. A stale entry would keep the lock screen offering
    /// transport controls for a player that has already been torn down.
    func stop() {
        artworkTask?.cancel()
        artworkTask = nil

        for (command, target) in commandTargets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        commandTargets.removeAll()

        staticInfo.removeAll()
        engine = nil
        infoCenter.nowPlayingInfo = nil
    }

    /// Position goes out as a timestamp plus a rate rather than a ticking
    /// value — the system extrapolates between updates, so this only needs
    /// calling when playback state changes, not on every frame.
    private func publish() {
        guard let engine else { return }

        var info = staticInfo
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.currentTime
        // Derived from `isPlaying` rather than read off the player: a stalled
        // or seeking AVPlayer still reports a rate of 1, which would leave the
        // lock screen's extrapolated clock running ahead of the video.
        info[MPNowPlayingInfoPropertyPlaybackRate] = engine.isPlaying ? 1.0 : 0.0

        // Indefinite until the HLS playlist loads; publishing a NaN duration
        // leaves the lock screen scrubber pinned at zero for the whole item.
        if let duration = engine.duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        infoCenter.nowPlayingInfo = info
    }

    /// Play/pause moves the clock the lock screen extrapolates from, and an
    /// HLS duration resolves after playback starts — both have to be republished.
    private func observe(_ engine: any PlaybackEngine) {
        engine.observeState { [weak self] in
            self?.publish()
        }
    }

    private func registerCommands(for engine: any PlaybackEngine) {
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]

        add(commandCenter.playCommand) { [weak self] _ in
            engine.play()
            self?.publish()
            return .success
        }

        add(commandCenter.pauseCommand) { [weak self] _ in
            engine.pause()
            self?.publish()
            return .success
        }

        add(commandCenter.togglePlayPauseCommand) { [weak self] _ in
            if engine.isPlaying {
                engine.pause()
            } else {
                engine.play()
            }
            self?.publish()
            return .success
        }

        add(commandCenter.skipForwardCommand) { [weak self] _ in
            self?.seek(to: engine.currentTime + Self.skipInterval)
            return .success
        }

        add(commandCenter.skipBackwardCommand) { [weak self] _ in
            self?.seek(to: engine.currentTime - Self.skipInterval)
            return .success
        }

        add(commandCenter.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        // Remote command targets are delivered on the main thread, and the
        // handler has to answer synchronously, so there is nowhere to hop to.
        let target = command.addTarget { event in
            MainActor.assumeIsolated { handler(event) }
        }
        commandTargets.append((command, target))
    }

    /// The engine republishes through `observeState` once the seek lands, so
    /// there's nothing to do here but ask.
    private func seek(to seconds: TimeInterval) {
        engine?.seek(to: seconds)
    }

    /// Artwork lands after everything else: it may need a round trip, and the
    /// title should appear immediately rather than wait on an image.
    private func loadArtwork(_ artwork: Artwork?, from cache: ImageCache) {
        guard let artwork else { return }

        artworkTask = Task { [weak self] in
            guard let image = await cache.image(for: artwork) else {
                logger.info("No artwork for the now playing item")
                return
            }
            guard !Task.isCancelled, let self else { return }

            staticInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in
                image
            }
            publish()
        }
    }
}
