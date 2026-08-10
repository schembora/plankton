# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Plankton is a native Jellyfin client for iPhone/iPad, built with SwiftUI. It targets iOS 26+ and uses the Liquid Glass UI style. Core features: server discovery/connect, library browsing, two selectable playback engines (a bundled mpv that plays the original file, or AVPlayer over the server's HLS), Live TV, subtitle selection and sizing, and offline downloads.

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

**Do not add `JellyfinAPI` (or any package product) to the `PlanktonTests` target.** `PlanktonTests` is a hosted bundle — it loads `Plankton.app`, so it already has every symbol the app links. Listing `JellyfinAPI` as a package product dependency of *both* targets makes Xcode rebuild it as a dynamic framework in `PackageFrameworks/`, and that framework fails to link its own transitive SwiftNIO dependencies (`symbol(s) not found` for `NIOCore`/`NIOPosix`). The failure is reported against the `JellyfinAPI` target, not the test target, which makes it look like a missing NIO dependency — adding NIO doesn't help. Test files still `import JellyfinAPI` normally; the module is found via the built products directory.

## Architecture

### Dependency: jellyfin-sdk-swift

All server communication goes through the [jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift) package (`JellyfinAPI` module, built on `Get`), pinned in `project.pbxproj`. Requests are built as `Paths.*` request values and sent through `JellyfinClient`/`JellyfinService.send(_:)`. Model types like `BaseItemDto`, `MediaSourceInfo`, `DeviceProfile` come from this package — check it before hand-rolling request/response types.

### Dependency: MPVKit (forked)

libmpv and FFmpeg come from [MPVKit](https://github.com/mpvkit/MPVKit), except `Libmpv`, which resolves to [a fork](https://github.com/schembora/MPVKit) pinned at `1.0.0-resize.1`. The fork carries one patch to MPVKit's MoltenVK context, which never reported layer resizes to mpv — rotating left the video laid out for the previous orientation.

Things to know before touching it:

- The patch lives in `Sources/BuildScripts/patch/libmpv/`, and rebuilding means `make build platform=ios,isimulator` in the fork: a full source build of FFmpeg and its dependencies, measured in hours. It needs `meson ninja nasm cmake automake` from Homebrew.
- The built `Libmpv.xcframework.zip` is published as a GitHub release on the fork, and `Package.swift` points at that URL with a checksum. `dist/` is not committed, so a clean checkout depends on the release existing.
- Only ever build the LGPL variant. `make build enable-gpl` and the `-GPL` targets pull in GPL components, which changes what the app can be distributed under.

### Core services (`Plankton/Core`)

Three `@Observable` classes, constructed once in `PlanktonApp.init()` and injected via `.environment(_:)` for the whole app to read with `@Environment(...)`:

- **`JellyfinService`** — owns the `JellyfinClient`, server URL, and signed-in user. Restores the cached session (Keychain token + `UserDefaults` server/user info) *synchronously* on launch so the UI never blocks on network, then validates it in the background (`validateSession()`). Distinguishes connectivity failures from auth rejections (`isNetworkError` / `isAuthFailure`) — only a definitive 401/403 signs the user out; anything else (unreachable host, timeout, 5xx) drops into **offline mode** (`isOffline`) while keeping the session so downloads stay playable. Also tracks `hasLiveTV` (cached like the session) and `isOnExpensiveNetwork` from the same `NWPathMonitor` that drives offline mode. Resolves what to play via `playbackSource(for:engine:maxBitrate:)`, returning a `PlaybackSource` that says whether the server handed over the original file, whether the stream is unbounded, and which live stream to release afterwards.
- **`DownloadService`** — runs **two** background sessions: an `AVAssetDownloadURLSession` for HLS, and a plain `URLSession` for original files, because the former only vends asset tasks and the latter can't fetch a playlist. Which one is used follows what the server actually returned, not the engine setting. Persists a `[DownloadedMedia]` index as JSON (`metadata.json` in Application Support) plus locally cached poster/backdrop JPEGs (episodes share their series' art). Downloaded file locations are stored as security-scoped bookmarks and re-resolved (and refreshed if stale) on each access via `localURL(forItemID:)`. `PlanktonAppDelegate` (in `PlanktonApp.swift`) hands background-session completion callbacks to this service when iOS relaunches the app after a transfer finishes while suspended.
- **`PlaybackSettings`** — the engine choice, subtitle scale, and per-network bitrate caps, persisted to `UserDefaults` and written through on change.

### Playback engines (`Plankton/Core`)

`PlaybackEngine` is the seam between the app and whatever decodes video: a clock, a play/pause state, a surface, track selection, and observation hooks for time, state and failure. `PlaybackReporter` and `NowPlayingCenter` talk to the protocol, never to a concrete player, so swapping the decoder doesn't reach into progress reporting or the lock screen.

- **`AVPlaybackEngine`** — `AVPlayer` inside `AVPlayerViewController`. Brings its own transport, PiP, AirPlay and track menus (`providesControls == true`), so the app draws nothing over it.
- **`MPVPlaybackEngine`** — libmpv rendering with `vo=gpu-next` through MoltenVK into a layer-backed `UIView`, decoding with VideoToolbox. Draws only frames, so the app supplies every control.

`DeviceProfile+Plankton.swift` maps an engine to the profile sent to Jellyfin. **The profile is what decides whether the server transcodes**, so it has to describe the decoder that will actually play: telling the server about AVPlayer while mpv does the playing is how a library ends up transcoding for no reason.

`PlaybackReporter` posts playback to `/Sessions/Playing*` — start, progress every 30s via an `AVPlayer` periodic time observer, and stop on teardown — so watch position is shared with every other Jellyfin client. This is what keeps Continue Watching honest; without it, watching in Plankton would never advance the resume point. Note `JellyfinService` has a second `send` overload for `Request<Void>`, since the reporting endpoints return no body.

Other Core pieces: `KeychainStore` (minimal Keychain wrapper for the access token and a persistent per-install device ID), `ServerDiscovery` (raw UDP broadcast on port 7359 to find LAN servers — deliberately bypasses higher-level networking APIs since an unconnected socket is needed to receive replies from any sender), `BaseItemDto+Plankton.swift` (display/formatting helpers — episode labels, runtime text, poster/backdrop image resolution with series fallback — that mirror the same formatting logic in `DownloadedMedia`).

### App shell (`RootView.swift`)

Gates the whole app on `jellyfin.isSignedIn || jellyfin.isOffline`: signed-out and non-offline shows `ConnectView`; otherwise the tab UI. Offline mode forces the initial tab to Downloads and disables Home/Library (they need the server). The offline state is stated by `OfflineHeader` at the top of the Downloads tab rather than floating over the UI.

### Design (`Plankton/Design`)

Shared, reusable presentation components with no feature-specific logic: `PosterTile` is the common 2:3 tile (artwork + title/subtitle + optional `DownloadBadge` + optional `WatchedProgressBar`) used by both `PosterCard` (server artwork) and `DownloadCard` (on-device artwork) so server-backed and downloaded media render identically. `ResumeCard` is the wide 16:9 variant for Continue Watching — episodes use their own still there, but their *series* poster in a 2:3 tile, since a 16:9 still crops badly in a poster frame (see `posterImageSource` vs `wideImageSource`). `JellyfinImage` wraps `AsyncImage` with a placeholder. `MediaRow`/`PosterGrid` lay out shelves and grids; `PosterGrid` has header/content/footer slots.

### Features (`Plankton/Features`)

One folder per feature area — `Connect`, `Home`, `Library`, `Detail`, `Player`, `LiveTV`, `Downloads`, `Settings`.

- **Player** — `PlayerContainerView` composes a playthrough: the engine's surface, the controls it doesn't bring itself, and the failure alert. `PlaybackSession` owns one playthrough — engine, reporter, lock screen, and a sampled snapshot of the clock for SwiftUI to read, since the engine deliberately isn't `@Observable` (its position changes constantly and reading it is a synchronous call into AVFoundation or libmpv). `PlayerControls` draws the chrome for engines that have none, and `PlaybackTimeline` holds the one place live and recorded playback genuinely differ. The subtitle and audio pickers are only ever populated by mpv: AVKit brings its own menus, so both track lists on `AVPlaybackEngine` are deliberately empty. Audio is worth picking from mostly on the direct path anyway, since a server transcode collapses the file to a single stream.
- **LiveTV** — the channel line-up with what's on each channel now. Channels come back as ordinary `BaseItemDto`s, so the artwork helpers and `PlaybackLauncher` apply unchanged. The tab only exists where the server reports Live TV enabled *and* a service configured.
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

### Playback and downloads: the non-obvious parts

- **The file decides the engine, not the setting.** A downloaded `.movpkg` is an HLS bundle only AVPlayer can open; anything else is an original container only mpv can. `DownloadService.requiredEngine(forItemID:)` reads that off the file rather than a stored flag, because a stored claim and the bytes on disk can disagree — and did. The same rule overrides the preference for Live TV.
- `PlaybackItem.engine` has a default, and two call sites in the Downloads tab silently took it and handed Matroska files to AVPlayer. When adding a construction site, choose the engine deliberately.
- **The queue is source-neutral.** `PlaybackQueueEntry` is either a `BaseItemDto` or a `DownloadedMedia`, because a queue of server items can't be built offline and that is exactly where the Downloads tab needs one. `PlaybackSession.resolve(_:)` prefers a download for *both* cases, so a part-downloaded season keeps moving with no server. An entry whose file needs the other engine is dropped from the queue rather than offered, since the surface is built once per playthrough.
- **A bitrate cap is a transcode trigger, not a quality dial.** Jellyfin re-encodes anything above it even when the codec and container would have played untouched, so capping below a file's own bitrate causes the transcoding the direct engine exists to avoid. It defaults to uncapped for that reason.
- **Live sources arrive unopened.** Until the server opens the stream it has no codec details to match against the profile, so it assumes unsupported and answers with a transcode URL for a stream it never inspected, which then fails. Set `isAutoOpenLiveStream` for channels, carry the returned `liveStreamID` on the stream URL, and close it on teardown — an open stream holds a tuner and nothing else releases it.
- **Never write `CAMetalLayer.drawableSize` from the app.** MoltenVK assigns it while building a swapchain, on mpv's render thread; a second writer on the UI thread races it, and a render pass sized for one drawable ends up executing against another. mpv derives its size from the layer's `bounds` and `contentsScale` instead. `contentsScale` *is* ours to maintain, and must be set before mpv builds its swapchain or the video renders at point resolution.
- **mpv's render thread must never block on the main thread.** Teardown runs on the main actor and waits on mpv's own threads, so a `DispatchQueue.main.sync` from the render thread deadlocks the two. Everything crossing that boundary is `async`.
- `target-colorspace-hint` is deliberately off: it makes MoltenVK set a colorspace on the layer off the main thread, which UIKit raises on, and the setter is private so it can't be funnelled to main. HDR plays tone-mapped as a result.
