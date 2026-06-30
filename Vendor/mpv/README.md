Place a self-contained macOS `mpv` executable here as:

```text
Vendor/mpv/mpv
```

The DMG packaging script copies that binary into `PowerPreview.app/Contents/Resources/mpv`.

For a fully independent app, use an `mpv` build that does not depend on Homebrew libraries. A Homebrew `mpv` binary can work on your machine, but the packaged app may fail on another Mac unless its dependent libraries are bundled too.
