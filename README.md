# Plankton

A native Jellyfin client for iPhone and iPad, built with SwiftUI. Plankton focuses on a clean, glassy interface that feels right at home on iOS 26, with first-class support for downloading media for offline viewing.

## Features

- Connect to your Jellyfin server by address or automatic discovery on your local network
- Browse your movie and TV show libraries with a fluid, Liquid Glass UI
- Stream with the native player, the server transcodes to HLS when needed
- Keep watching in Picture in Picture while using other apps
- Pick subtitles right in the player's native track menu
- Download movies and episodes for offline viewing — saved via the same HLS the player negotiates, so anything that streams can be saved
- Offline mode: when your server can't be reached, land straight on your downloads — they always play from disk, even once you're back online
- Secure sign-in with the session stored in the Keychain

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
├── Core/        Jellyfin service, downloads, session & Keychain, server discovery, item helpers
├── Design/      Reusable UI: poster tiles & grids, media shelves, async images
└── Features/    Connect, Home, Library, Detail, Player, Downloads, Settings
```

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a branch from `main`
2. Keep the code style consistent with the existing codebase (SwiftUI, `@Observable` services, feature folders)
3. Make sure the project builds and tests pass
4. Open a pull request with a clear description of the change

Bug reports and feature requests can go in [GitHub Issues](https://github.com/schembora/plankton/issues).

## License

Plankton is released under the [Apache License 2.0](LICENSE).
