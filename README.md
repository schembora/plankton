# Plankton

A native Jellyfin client for iPhone and iPad, built with SwiftUI. Plankton focuses on a clean, glassy interface that feels right at home on iOS 26, with first-class support for downloading media for offline viewing.

## Features

- Connect to your Jellyfin server by address or automatic discovery on your local network
- Browse your movie and TV show libraries with a fluid, Liquid Glass UI
- Play the original file untouched — Matroska, HEVC, AV1, DTS, TrueHD — so the server copies bytes instead of re-encoding, and playback starts sooner
- Embedded subtitles, including styled ASS/SSA and image-based PGS, with a size control in the player
- Live TV: browse the channel line-up with what's on now, and change channel without leaving the player
- Download movies and episodes at their original quality, playable offline
- Cap the bitrate separately for Wi-Fi and cellular, uncapped by default
- Offline mode: when your server can't be reached, land straight on your downloads — they always play from disk, even once you're back online
- Secure sign-in with the session stored in the Keychain

## Playback engines

Plankton ships two, chosen in Settings:

**Direct** (the default) decodes on the device with a bundled [mpv](https://mpv.io), using VideoToolbox for hardware decoding and libplacebo for rendering. The server hands over the file as it is, so nothing is transcoded and nothing waits on the server's CPU.

**Server** uses AVPlayer over the HLS stream Jellyfin produces. It transcodes far more, but keeps Picture in Picture, AirPlay and the native track menus that come with AVKit.

Live TV always plays directly: it's an unbounded MPEG-TS stream, and AVPlayer plays progressive HTTP by asking for byte ranges that a stream with no end can't answer.

## Requirements

- Xcode 26.3 or later
- An iOS 26.3+ device or simulator
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
Plankton/Plankton/
├── Core/        Jellyfin service, playback engines, downloads, session & Keychain,
│                server discovery, device profiles, item helpers
├── Design/      Reusable UI: poster tiles & grids, media shelves, async images
└── Features/    Connect, Home, Library, Detail, Player, LiveTV, Downloads, Settings
```

## Dependencies

- [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) for all server communication
- [MPVKit](https://github.com/mpvkit/MPVKit) for libmpv and FFmpeg

`Libmpv` resolves to a [fork](https://github.com/schembora/MPVKit) carrying one patch: MPVKit's MoltenVK context never tells mpv that its layer has resized, so rotating the device leaves the video laid out for the previous orientation. Everything else comes from upstream MPVKit. The patch is not yet upstreamed.

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a branch from `main`
2. Keep the code style consistent with the existing codebase (SwiftUI, `@Observable` services, feature folders)
3. Make sure the project builds and tests pass
4. Open a pull request with a clear description of the change

Bug reports and feature requests can go in [GitHub Issues](https://github.com/schembora/plankton/issues).

## License

Plankton is released under the [Apache License 2.0](LICENSE).

It bundles mpv and FFmpeg under the LGPL v3.0, without the optional GPL components, via MPVKit. The app credits them in Settings → About → Acknowledgements, and the source the binaries were built from is in the [MPVKit fork](https://github.com/schembora/MPVKit) above.
