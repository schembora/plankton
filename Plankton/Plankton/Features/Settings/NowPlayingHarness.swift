//
//  NowPlayingHarness.swift
//  Plankton
//
//  A now playing entry with no player behind it, for isolating why ours is
//  ignored.
//

#if DEBUG

import AVFoundation
import MediaPlayer
import Observation
import OSLog

private let logger = Logger(subsystem: "com.schembor.Plankton", category: "NowPlaying")

/// Publishes a lock screen entry backed by a plain `AVAudioPlayer` looping
/// silence, with no mpv, no Picture in Picture and no custom video output
/// anywhere near it.
///
/// The app publishes a complete and correct entry — eight fields, rate 1,
/// audio still running once backgrounded — and iOS shows it neither on the
/// lock screen nor in Control Center, while other apps on the same device work
/// fine. That rules out the presentation and the device, and leaves two
/// possibilities this separates: something specific to how mpv drives audio,
/// or something about the app itself that would defeat any player.
///
/// If this appears, the difference is mpv. If it does not, the difference is
/// the app, and every fix aimed at the player was aimed at the wrong layer.
@MainActor
@Observable
final class NowPlayingHarness {

    private(set) var isRunning = false

    @ObservationIgnored private var player: AVAudioPlayer?

    func start() {
        guard !isRunning else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            // Silence rather than a tone, since this runs on a real device and
            // has to be lockable without being unpleasant. Silence still counts
            // as playing: what the system tracks is an active session with a
            // running player, not the samples in it.
            player = try AVAudioPlayer(data: Self.silentWAV())
            player?.numberOfLoops = -1
            player?.volume = 1
            player?.play()
        } catch {
            logger.error("harness failed to start: \(error.localizedDescription)")
            return
        }

        MPRemoteCommandCenter.shared().playCommand.isEnabled = true
        MPRemoteCommandCenter.shared().pauseCommand.isEnabled = true
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let info: [String: Any] = [
            MPMediaItemPropertyTitle: "Harness",
            MPMediaItemPropertyArtist: "No player behind this",
            MPMediaItemPropertyPlaybackDuration: 600.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing

        isRunning = true
        logger.info("harness started: fields=\(MPNowPlayingInfoCenter.default().nowPlayingInfo?.count ?? -1, privacy: .public)")
    }

    func stop() {
        player?.stop()
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        UIApplication.shared.endReceivingRemoteControlEvents()
        isRunning = false
    }

    /// A second of silence, built rather than shipped so there is no asset to
    /// add and nothing to go stale.
    private static func silentWAV() -> Data {
        let sampleRate = 44100
        let samples = sampleRate
        let dataBytes = samples * 2

        var wav = Data()
        func append(_ string: String) { wav.append(contentsOf: string.utf8) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + dataBytes))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)                          // PCM
        append16(1)                          // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))     // byte rate
        append16(2)                          // block align
        append16(16)                         // bits per sample
        append("data")
        append32(UInt32(dataBytes))
        wav.append(Data(count: dataBytes))

        return wav
    }
}

#endif
