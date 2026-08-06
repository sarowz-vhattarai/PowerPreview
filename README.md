# PowerPreview

PowerPreview is a lightweight macOS media browser for photos and videos, powered by an embedded **libmpv / FFmpeg** engine (MPVKit) for broad format support.

## Features

- Open a folder or a single media file
- Navigate with arrow keys, toolbar, or mouse wheel
- MX Master–friendly wheel navigation
- Pinch zoom + trackpad pan for zoomed media
- Hands-off slideshow (photos 2s, videos play through)
- Double-click fullscreen
- Embedded mpv playback for MP4, MOV, MKV, WebM, AVI, HDR, 4K, and more
- Hover-only clean menubar and video scrubber

## Requirements

- macOS 13+
- Xcode 15+ (for building)

Point the active developer directory at Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Or for a single shell session:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build

```bash
make build
```

## Package DMG

```bash
make dmg
```

Output:

```text
dist/PowerPreview-0.2.1.dmg
```

## Engine notes

Playback uses **MPVKit-GPL** (embedded libmpv + FFmpeg + MoltenVK), statically linked into the app:

- Hardware decode via VideoToolbox when available
- HDR via `target-colorspace-hint` + EDR Metal layer
- `gpu-next` + Vulkan/MoltenVK for high-quality rendering
- Broad container/codec support (MP4, MOV, MKV, WebM, AVI, TS, and more)

Turn off **Metal API Validation** in the Xcode scheme when debugging HDR content.

Install the built app from:

```text
dist/PowerPreview-0.2.1.dmg
```
