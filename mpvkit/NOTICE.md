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

The numbers are apply order, not decoration: the build sorts the directory by
filename and applies in that order, and each of ours builds on the one before.
Upstream's keep the low numbers and ours start at 0100, so pulling a new patch
from upstream cannot collide with or reorder ours.

| Patch | Origin | License |
|---|---|---|
| `0002-revert-build-static` | Upstream [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit) | LGPLv2.1+ |
| `0003-enable-avfoundation-ao-tvos` | Upstream [mpvkit/MPVKit](https://github.com/mpvkit/MPVKit) | LGPLv2.1+ |
| `0100-vo-add-host-layer-output` | Plankton | LGPLv2.1+ |
| `0101-vo-upload-software-frames` | Plankton | LGPLv2.1+ |
| `0102-vo-composite-osd` | Plankton | LGPLv2.1+ |
| `0103-vo-register-videotoolbox-hwdec` | Plankton | LGPLv2.1+ |

### 0101, software frame upload

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

### 0102, OSD compositing

Subtitles. Drawn into the frame at video resolution rather than over the layer,
so this output still does not need to know how large the layer is, and so they
appear in the Picture in Picture window, which shows the enqueued frames and
nothing else.

The frame is copied only when there is something to draw, so a hardware frame
with no subtitles on screen stays a straight handoff. A decoder owned frame is
duplicated rather than drawn on, since it may still be referenced for
prediction; an uploaded frame is already ours and is drawn on in place.

### 0100, host layer video output

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

### 0103, VideoToolbox hwdec registration

mpv only hands a non-copying hwdec a device that came from the video output.
The VideoToolbox registration already in mpv is a `ra_hwdec` belonging to the
GPU outputs: loaded only by `vo_gpu` and `vo_gpu_next`, and it refuses to load
without an OpenGL or Vulkan interop to map into. This output is neither, so
before this patch the decoder found no device and skipped hardware decoding
entirely.

Nothing looked wrong, because 0101 uploads the software frames and renders them
correctly. It only cost CPU, battery and headroom at high resolutions. The
engine now logs `hwdec:` on file load so this cannot hide again.

This is also what makes dropping Vulkan safe. Disabling `videotoolbox-pl`
removes `hwdec_vt.c`, which was the only thing registering VideoToolbox at all,
so doing that before this patch would have been fatal rather than cosmetic.

## What is deliberately not built

`vulkan` and `videotoolbox-pl` are disabled and the MoltenVK context patch is
gone. Playback goes through `vo=avfoundation`, which takes `CVPixelBuffer`s,
needs no GPU context, and registers the decode device itself, so mpv's Vulkan
backend, its MoltenVK windowing context and the GPU side of VideoToolbox all
built code nothing could reach. Dropping the MoltenVK patch is what retires the
fork this directory replaced: it existed to carry that one fix.

libplacebo cannot go with them, and neither can the Vulkan and shaderc
libraries behind it. mpv 0.41 requires libplacebo unconditionally — no
`required:` guard, in the mandatory dependency array, with the feature
hard-coded true — and the prebuilt libplacebo is compiled against both. So this
removes code paths rather than binary size.

## Rebuilding

```sh
cd mpvkit && make build platform=ios,isimulator
```

LGPL variant only. Hours, mostly FFmpeg. Needs `meson ninja nasm cmake
automake pkg-config` from Homebrew.

**Patches are applied once, on a fresh clone.** `beforeBuild()` returns early
if the source directory is already there, so editing a patch and rebuilding
silently reuses the previously patched tree and rebuilds identical code. After
changing anything under `patch/libmpv`, delete the extracted source and the
build output for that library first:

```sh
rm -rf dist/libmpv-v0.41.0 dist/libmpv
```

Everything else in `dist/` can stay, which keeps FFmpeg and the other
dependencies out of the rebuild.

## LGPL

libmpv, FFmpeg and the rest are LGPL and statically linked. The patch series
and build scripts here are what let a user rebuild those libraries from
modified sources and relink them, which is the condition that makes static
linking permissible.

Only ever build the LGPL variant. `make build enable-gpl` and the `-GPL`
targets pull in GPL components and change what the app may be distributed
under.
