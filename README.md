# PowerPreview

PowerPreview is a lightweight macOS media preview app for browsing photos and videos in a folder.

## Features

- Open a folder or single media file.
- Navigate media with arrow keys, buttons, or mouse wheel.
- MX Master-style wheel scrolling changes media immediately.
- Video autoplay with spacebar play/pause.
- Clean video UI with custom controls shown only on mouse movement.
- Pinch zoom for images and videos.
- Pan zoomed media with trackpad scrolling.
- Optional `Trackpad Next` toggle for trackpad scroll navigation.
- Finder/Open With registration for common media types.

## Build

This project can build with Apple Command Line Tools and does not require full Xcode.

```bash
make build
```

## Package DMG

```bash
make dmg
```

The DMG is written to:

```text
dist/PowerPreview-0.1.0.dmg
```

Without a bundled `mpv`, PowerPreview uses native macOS video playback. To bundle `mpv`, place a self-contained macOS executable at:

```text
Vendor/mpv/mpv
```
