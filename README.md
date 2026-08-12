# Plankton

A native Jellyfin client for iPhone and iPad, built with SwiftUI. Plankton focuses on a clean, glassy interface that feels right at home on iOS 26, with first-class support for downloading media for offline viewing.

## Features

- Connect to your Jellyfin server by address or automatic discovery on your local network
- Browse your movie and TV show libraries with a fluid, Liquid Glass UI
- Play the original file untouched — Matroska, HEVC, AV1, DTS, TrueHD — so the server copies bytes instead of re-encoding, and playback starts sooner
- Picture in Picture, and full lock screen and Control Center controls, on the direct engine as well as on AVPlayer
- Embedded subtitles, including styled ASS/SSA and image-based PGS, with a size control in the player
- Live TV: browse the channel line-up with what's on now, and change channel without leaving the player
- Download movies and episodes at their original quality, playable offline
- Cap the bitrate separately for Wi-Fi and cellular, uncapped by default
- Offline mode: when your server can't be reached, land straight on your downloads — they always play from disk, even once you're back online
- Secure sign-in with the session stored in the Keychain

## Playback engines

Plankton ships two, chosen in Settings:

**Direct** (the default) decodes on the device with a bundled [mpv](https://mpv.io), using VideoToolbox. The server hands over the file as it is, so nothing is transcoded and nothing waits on the server's CPU.

mpv renders through a video output written for Plankton, which hands decoded frames straight to an `AVSampleBufferDisplayLayer`. That is what buys back Picture in Picture: the system only composites video it owns, and reads from that layer or an `AVPlayerLayer` and from nothing else. Since VideoToolbox already produces `CVPixelBuffer`s, this is a handoff rather than a conversion. Software decoded frames, for the codecs VideoToolbox has no hardware path for, are uploaded instead, and subtitles are composited into the frame so they survive into the Picture in Picture window.

**Server** uses AVPlayer over the HLS stream Jellyfin produces. It transcodes far more, but keeps AirPlay and the native track menus that come with AVKit.

Live TV always plays directly: it's an unbounded MPEG-TS stream, and AVPlayer plays progressive HTTP by asking for byte ranges that a stream with no end can't answer.

## Requirements

- Xcode 26 or later
- An iOS 26 device or simulator
- A [Jellyfin](https://jellyfin.org) server (10.9+)

## Building

Plankton is a standard Xcode project.


```sh
xcodebuild -project Plankton/Plankton.xcodeproj -scheme Plankton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Testing

```sh
xcodebuild -project Plankton/Plankton.xcodeproj -scheme Plankton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Project Structure

```
mpvkit/          Vendored MPVKit build: manifest, build scripts and the patch
                 series applied to libmpv. The xcframeworks are fetched from
                 this repository's releases rather than committed.
Plankton/Plankton/
├── Core/        Jellyfin service, playback engines, downloads, session & Keychain,
│                server discovery, device profiles, item helpers
├── Design/      Reusable UI: poster tiles & grids, media shelves, async images
└── Features/    Connect, Home, Library, Detail, Player, LiveTV, Downloads, Settings
```

## Dependencies

- [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) for all server communication
- [MPVKit](https://github.com/mpvkit/MPVKit) for libmpv and FFmpeg, vendored into `mpvkit/`

MPVKit lives in this repository rather than being consumed as a package, because
libmpv carries patches written for Plankton. `mpvkit/NOTICE.md` lists each one
with its origin and licence; in short they add the AVFoundation video output
described above, software frame upload, subtitle compositing, and registration
of the VideoToolbox decode device, which mpv otherwise only accepts from a GPU
video output.

The patched `Libmpv` is built from `mpvkit/` and published to this repository's
releases, so the patch and the binary it produced stay together. Everything else
resolves to upstream MPVKit. To rebuild:

```sh
cd mpvkit && make build platform=ios,isimulator
```

Patches are applied only on a fresh clone, so delete the extracted source first
if you change one. See `mpvkit/NOTICE.md`.

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a branch from `main`
2. Keep the code style consistent with the existing codebase (SwiftUI, `@Observable` services, feature folders)
3. Make sure the project builds and tests pass
4. Open a pull request with a clear description of the change

Bug reports and feature requests can go in [GitHub Issues](https://github.com/schembora/plankton/issues).

## License

Plankton is released under the [Apache License 2.0](LICENSE).

It bundles mpv and FFmpeg under the LGPL v3.0, without the optional GPL components. The app credits them in Settings → About → Acknowledgements. The source the binaries were built from, the patches applied to it and the scripts that build it are all in `mpvkit/`, which is what makes the static linking permissible: anyone can rebuild those libraries from modified sources and relink them.
