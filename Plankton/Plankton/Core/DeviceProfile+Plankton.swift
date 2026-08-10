//
//  DeviceProfile+Plankton.swift
//  Plankton
//
//  What each playback engine can decode, in the shape Jellyfin negotiates with.
//

import JellyfinAPI

/// A device profile is the app's side of the transcoding negotiation: it tells
/// the server what the decoder handles, and the server re-encodes whatever
/// isn't on the list. Describing the wrong decoder is how a library ends up
/// transcoding everything, so these track the engines rather than the app.
///
/// Kept out of the engines themselves on purpose — an engine has no business
/// knowing Jellyfin exists. The mapping keys off `PlaybackEngineKind`, which is
/// a plain enum, so the coupling stays on this side of the line.
extension DeviceProfile {

    /// `maxBitrate` is nil when uncapped. Anything above it gets re-encoded, so
    /// a cap is the one setting that can undo direct play — it's left off
    /// unless the user asked for it.
    static func plankton(for engine: PlaybackEngineKind, maxBitrate: Int? = nil) -> DeviceProfile {
        var profile = switch engine {
        case .server: avPlayer
        case .direct: mpv
        }
        profile.maxStreamingBitrate = maxBitrate
        return profile
    }

    /// What AVPlayer can demux, which is very little — no Matroska at all, so
    /// most libraries fall straight through to the transcoding profile.
    private static var avPlayer: DeviceProfile {
        var profile = DeviceProfile()
        profile.name = "Plankton AVPlayer"
        profile.directPlayProfiles = [
            DirectPlayProfile(
                audioCodec: "aac,ac3,eac3,mp3,alac",
                container: "mp4,m4v,mov",
                type: .video,
                videoCodec: "h264,hevc"
            ),
        ]

        var hlsProfile = TranscodingProfile()
        hlsProfile.protocol = .hls
        hlsProfile.container = "fmp4"
        hlsProfile.type = .video
        hlsProfile.videoCodec = "h264"
        hlsProfile.audioCodec = "aac"
        hlsProfile.maxAudioChannels = "2"
        hlsProfile.enableSubtitlesInManifest = true
        profile.transcodingProfiles = [hlsProfile]

        profile.subtitleProfiles = [
            SubtitleProfile(format: "vtt", method: .hls),
        ]
        return profile
    }

    /// What mpv decodes, which is close to everything. Listing it honestly is
    /// the entire point of the engine: the server stops re-encoding and starts
    /// handing over the original file.
    private static var mpv: DeviceProfile {
        var profile = DeviceProfile()
        profile.name = "Plankton mpv"
        profile.directPlayProfiles = [
            DirectPlayProfile(
                audioCodec: "aac,ac3,eac3,dts,dtshd,truehd,flac,alac,opus,vorbis,mp3,mp2,pcm_s16le,pcm_s24le,wavpack",
                container: "mkv,mp4,m4v,mov,avi,webm,ts,m2ts,mpegts,flv,ogv,wmv,asf,3gp",
                type: .video,
                videoCodec: "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1,theora,prores"
            ),
        ]

        // Embedded rather than HLS or burned in: mpv rasterises ASS/SSA through
        // libass and decodes PGS bitmaps itself, so subtitles stay in the
        // container instead of being baked into the picture — which is what
        // forced a full video transcode before.
        profile.subtitleProfiles = [
            SubtitleProfile(format: "ass", method: .embed),
            SubtitleProfile(format: "ssa", method: .embed),
            SubtitleProfile(format: "srt", method: .embed),
            SubtitleProfile(format: "subrip", method: .embed),
            SubtitleProfile(format: "vtt", method: .embed),
            SubtitleProfile(format: "webvtt", method: .embed),
            SubtitleProfile(format: "pgssub", method: .embed),
            SubtitleProfile(format: "dvdsub", method: .embed),
            SubtitleProfile(format: "dvbsub", method: .embed),
        ]

        // A floor, not a fallback anyone should hit: something mpv genuinely
        // can't decode should still play rather than fail outright.
        var hlsProfile = TranscodingProfile()
        hlsProfile.protocol = .hls
        hlsProfile.container = "fmp4"
        hlsProfile.type = .video
        hlsProfile.videoCodec = "h264"
        hlsProfile.audioCodec = "aac"
        hlsProfile.enableSubtitlesInManifest = true
        profile.transcodingProfiles = [hlsProfile]

        return profile
    }
}
