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
| `0005-avfoundation-software-frame-upload` | Plankton | LGPLv2.1+ |
| `0006-avfoundation-osd-compositing` | Plankton | LGPLv2.1+ |

### 0001, MoltenVK resize

MPVKit's MoltenVK context never told mpv when its layer changed size, so
rotating the device left the video laid out for the previous orientation. The
patch derives the size from the layer's own `bounds` and `contentsScale` and
raises `VO_EVENT_RESIZE` from `VOCTRL_CHECK_EVENTS`.

Only relevant to the `gpu-next` path. If `vo=avfoundation` becomes the only
output Plankton uses, this patch stops being load bearing.

### 0005, software frame upload

VideoToolbox has no hardware path for VP9, MPEG-2, VC-1 or MPEG-4 ASP, and none
for AV1 before A17 Pro. A hardware only output shows nothing at all for a
broadcast stream or an older file, and the server does not step in because the
device profile claims those codecs are playable. Broadcast Live TV is largely
MPEG-2, so this is not an edge case.

Only NV12 and P010 are accepted, so mpv converts anything else on the way in
rather than this output growing a conversion of its own. Buffers come from a
pool and are IOSurface backed, which the display layer requires, and uploads
are tagged with the stream's colour since unlike hardware frames they arrive as
bytes with no such history.

### 0006, OSD compositing

Subtitles. Drawn into the frame at video resolution rather than over the layer,
so this output still does not need to know how large the layer is, and so they
appear in the Picture in Picture window, which shows the enqueued frames and
nothing else.

The frame is copied only when there is something to draw, so a hardware frame
with no subtitles on screen stays a straight handoff. A decoder owned frame is
duplicated rather than drawn on, since it may still be referenced for
prediction; an uploaded frame is already ours and is drawn on in place.

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

Deliberate limits:

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
