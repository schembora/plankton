# Plankton

A native Jellyfin client for iPhone and iPad, built with SwiftUI. Plankton focuses on a clean, glassy interface that feels right at home on iOS 26, with first-class support for downloading media for offline viewing (in progress).

## Features

- Connect to your Jellyfin server by address or automatic discovery on your local network
- Browse your movie and TV show libraries with a fluid, Liquid Glass UI
- Stream with the native player, the server transcodes to HLS when needed
- Secure sign-in with the session stored in the Keychain

**Coming soon:** offline downloads, Picture in Picture, and subtitles.

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
├── Core/        Jellyfin service, session & Keychain, item helpers
├── Design/      Reusable UI: poster cards, media shelves, async images
└── Features/    Connect, Home, Library, Detail, Player, Settings
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
