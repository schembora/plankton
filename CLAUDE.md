# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Plankton is a native Jellyfin client for iPhone/iPad, built with SwiftUI. It targets iOS 26+ and uses the Liquid Glass UI style. Core features: server discovery/connect, library browsing, native HLS/direct-play streaming, Picture in Picture, subtitle selection, and offline downloads (saved via the same HLS stream the player negotiates).

## Commands

Build:
```sh
xcodebuild -project Plankton/Plankton.xcodeproj -scheme Plankton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Test (all):
```sh
xcodebuild -project Plankton/Plankton.xcodeproj -scheme Plankton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Run a single test (Swift Testing `@Test` functions, not XCTest — use `-only-testing` with the suite/test name):
```sh
xcodebuild -project Plankton/Plankton.xcodeproj -scheme Plankton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:PlanktonTests/JellyfinServiceTests/bareHostDefaultsToHTTP test
```

There is only one scheme (`Plankton`), covering the app, `PlanktonTests` (unit, Swift Testing), and `PlanktonUITests`.

**Known issue:** the test targets currently fail to *link* — `PlanktonTests` pulls in `JellyfinAPI` but not its transitive SwiftNIO dependencies, so `xcodebuild test` dies with `symbol(s) not found` for `NIOPosix.MultiThreadedEventLoopGroup`. This predates any recent work; the app target itself builds fine. Fixing it means adding the NIO products to the test target's link phase.

## Architecture

### Dependency: jellyfin-sdk-swift

All server communication goes through the [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) package (`JellyfinAPI` module, built on `Get`), pinned in `project.pbxproj`. Requests are built as `Paths.*` request values and sent through `JellyfinClient`/`JellyfinService.send(_:)`. Model types like `BaseItemDto`, `MediaSourceInfo`, `DeviceProfile` come from this package — check it before hand-rolling request/response types.

### Core services (`Plankton/Core`)

Two `@Observable` classes, constructed once in `PlanktonApp.init()` and injected via `.environment(_:)` for the whole app to read with `@Environment(...)`:

- **`JellyfinService`** — owns the `JellyfinClient`, server URL, and signed-in user. Restores the cached session (Keychain token + `UserDefaults` server/user info) *synchronously* on launch so the UI never blocks on network, then validates it in the background (`validateSession()`). Distinguishes connectivity failures from auth rejections (`isNetworkError` / `isAuthFailure`) — only a definitive 401/403 signs the user out; anything else (unreachable host, timeout, 5xx) drops into **offline mode** (`isOffline`) while keeping the session so downloads stay playable. Also resolves the actual playable URL for an item (`playbackURL(for:)`) by negotiating `PlaybackInfo` with a device profile, returning transcoded HLS or a direct-play URL.
- **`DownloadService`** — wraps `AVAssetDownloadURLSession` (a background `URLSession`) to download the same HLS stream the player would use, so anything streamable is downloadable. Persists a `[DownloadedMedia]` index as JSON (`metadata.json` in Application Support) plus locally cached poster/backdrop JPEGs (episodes share their series' art). Downloaded file locations are stored as security-scoped bookmarks and re-resolved (and refreshed if stale) on each access via `localURL(forItemID:)`. `PlanktonAppDelegate` (in `PlanktonApp.swift`) hands background-session completion callbacks to this service when iOS relaunches the app after a transfer finishes while suspended.

`PlaybackReporter` posts playback to `/Sessions/Playing*` — start, progress every 30s via an `AVPlayer` periodic time observer, and stop on teardown — so watch position is shared with every other Jellyfin client. This is what keeps Continue Watching honest; without it, watching in Plankton would never advance the resume point. Note `JellyfinService` has a second `send` overload for `Request<Void>`, since the reporting endpoints return no body.

Other Core pieces: `KeychainStore` (minimal Keychain wrapper for the access token and a persistent per-install device ID), `ServerDiscovery` (raw UDP broadcast on port 7359 to find LAN servers — deliberately bypasses higher-level networking APIs since an unconnected socket is needed to receive replies from any sender), `BaseItemDto+Plankton.swift` (display/formatting helpers — episode labels, runtime text, poster/backdrop image resolution with series fallback — that mirror the same formatting logic in `DownloadedMedia`).

### App shell (`RootView.swift`)

Gates the whole app on `jellyfin.isSignedIn || jellyfin.isOffline`: signed-out and non-offline shows `ConnectView`; otherwise the tab UI. Offline mode forces the initial tab to Downloads and disables Home/Library (they need the server). The offline state is stated by `OfflineHeader` at the top of the Downloads tab rather than floating over the UI.

### Design (`Plankton/Design`)

Shared, reusable presentation components with no feature-specific logic: `PosterTile` is the common 2:3 tile (artwork + title/subtitle + optional `DownloadBadge` + optional `WatchedProgressBar`) used by both `PosterCard` (server artwork) and `DownloadCard` (on-device artwork) so server-backed and downloaded media render identically. `ResumeCard` is the wide 16:9 variant for Continue Watching — episodes use their own still there, but their *series* poster in a 2:3 tile, since a 16:9 still crops badly in a poster frame (see `posterImageSource` vs `wideImageSource`). `JellyfinImage` wraps `AsyncImage` with a placeholder. `MediaRow`/`PosterGrid` lay out shelves and grids; `PosterGrid` has header/content/footer slots.

### Features (`Plankton/Features`)

One folder per feature area — `Connect`, `Home`, `Library`, `Detail`, `Player`, `Downloads`, `Settings`.

- **Player** — `PlayerView` wraps `AVPlayerViewController` via `UIViewControllerRepresentable` (not a pure SwiftUI player) to get native PiP, native subtitle track menus, and HLS/direct-play. It takes a `PlaybackItem` (url + optional `itemID`/`startTicks`) rather than a bare URL, so it can seek to the resume point and report progress.
- **Library** — one unified browse grid: glass filter chips (All/Movies/Shows), a genre menu, and a sort menu, with the nav bar hidden so the pinned filter bar acts as the header. Note `refreshable` is applied *before* the `safeAreaInset` — it propagates through the environment, and if the filter bar sits inside its subtree the horizontal chip strip grows its own pull-to-refresh.
- **Detail** — a series renders its title over the backdrop, then a resume banner, season chips, a season-download row, and episode rows. Movies keep the poster/title block and Play row.
- **Downloads** — `DownloadStrip` collapses every active transfer into one glass strip (it replaced a stack of tall per-item rows that pushed the grid below the fold), `DownloadScopeSheet` scopes a series download to a season or the whole show with approximate sizes from `MediaSourceInfo.size`, and `SeriesDownloadsView` shows a series' downloaded episodes since episodes group by `DownloadedMedia.seriesGroupID`.

## Conventions

- SwiftUI throughout; app-wide state lives in `@Observable` services injected via `.environment(_:)`, not singletons.
- Files carry a short header comment naming the file and its one-line purpose — follow this pattern for new files.
- Comments explain *why*, not what — e.g. why offline mode is entered, why a socket is raw, why a bookmark gets refreshed. Keep new comments to that bar.
- Duplication between `BaseItemDto+Plankton.swift` and `DownloadedMedia` (episode labels, runtime formatting) is intentional: `DownloadedMedia` is a plain, `Codable`-only snapshot that must not depend on `BaseItemDto` or network types.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest.
- `enableUserData` has no documented default on the Jellyfin API — set it explicitly on any request whose results drive watched progress or resume, or it silently returns nothing on some servers.
- Prefer omitting a control to shipping one that does nothing. The Downloads redesign deliberately left out pause, a "Queued" state, and quality/cellular toggles because none of the underlying behavior exists yet.
