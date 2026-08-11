# Notice

Attribution and license obligations for the vendored build.

This directory is a vendored copy of [MPVKit](https://github.com/mpvkit/MPVKit),
carrying Plankton's own patches to libmpv. It holds the package manifest, the
build scripts and the patch series only. The built `.xcframework`s are far too
large to commit and are fetched by `Package.swift` from GitHub releases.

Vendored rather than kept as a separate fork so that the patches, the scripts
that apply them and the releases that carry the result all live in one repo.
Before this, `main` resolved `Libmpv` to a personal fork whose release had to
keep existing for a clean checkout to build.

## libmpv (v0.41.0)

Each patch also carries a DEP-3 header stating its own origin.

| Patch | Origin | License |
|---|---|---|
| `0001-player-add-moltenvk-context` | Upstream [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit), plus Plankton's fix to report layer resizes to mpv | LGPLv2.1+ |
| `0002-revert-build-static` | Upstream [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit) | LGPLv2.1+ |
| `0003-enable-avfoundation-ao-tvos` | Upstream [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit) | LGPLv2.1+ |
| `0004-avfoundation-video-output` | Plankton | LGPLv2.1+ |

### 0001, MoltenVK resize

MPVKit's MoltenVK context never told mpv when its layer changed size, so
rotating the device left the video laid out for the previous orientation. The
patch derives the size from the layer's own `bounds` and `contentsScale` and
raises `VO_EVENT_RESIZE` from `VOCTRL_CHECK_EVENTS`.

Only relevant to the `gpu-next` path. If `vo=avfoundation` becomes the only
output Plankton uses, this patch stops being load bearing.

### 0004, AVFoundation video output

Written for Plankton. Adds `vo=avfoundation`, which hands VideoToolbox frames
to an `AVSampleBufferDisplayLayer` passed in as `--wid`.

It exists because the system only composites video it owns: Picture in Picture
and the lock screen's now playing surface both read from an
`AVSampleBufferDisplayLayer` or an `AVPlayerLayer`, and neither can be fed from
a `CAMetalLayer` however good the picture drawn into it is. With `hwdec` set to
videotoolbox the decoder is already producing `CVPixelBuffer`s, so the output is
a handoff rather than a conversion.

The approach — a patched video output writing into a host supplied sample
buffer layer — is the one taken by several other iOS mpv clients, among them
[mpv-ios](https://github.com/mpv-ios/mpv-ios),
[Streamyfin](https://github.com/streamyfin/streamyfin) and
[pippin-player](https://github.com/lmor152/pippin-player). Their patches were
read to understand the shape of the problem. This implementation is our own and
shares no code with them.

Deliberate limits, each of which is a thing to add rather than a thing that is
broken:

- **Hardware frames only.** `query_format` accepts `IMGFMT_VIDEOTOOLBOX` and
  nothing else. Software decoded output would have to be uploaded into a
  `CVPixelBuffer` first, and the point of this output is that VideoToolbox has
  already made one. A file that falls back to software decoding will not play
  on this output.
- **No OSD.** mpv's rendered overlays, subtitles included, are not composited.
  Subtitles need the frame and the overlay combined before the layer sees it.
- **Timing stays with mpv.** Samples carry invalid timestamps and the
  `DisplayImmediately` attachment, so mpv's clock paces playback and the layer
  schedules nothing. The layer's control timebase is the host's to set, since
  Picture in Picture's transport UI needs one and this output does not know the
  playback state it would describe.
- **Geometry stays with the host.** The layer is placed and sized by the UI
  framework and scales by `videoGravity`, so this output never sets a drawable
  size and never has to notice a rotation.

## LGPL

libmpv, FFmpeg and the rest are LGPL and statically linked. The patch series
and build scripts here are what let a user rebuild those libraries from
modified sources and relink them, which is the condition that makes static
linking permissible.

Only ever build the LGPL variant. `make build enable-gpl` and the `-GPL`
targets pull in GPL components and change what the app may be distributed
under.
