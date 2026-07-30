Place a self-contained macOS mpv runtime here:

```text
Vendor/mpv/mpv
Vendor/mpv/lib/
```

Fetch automatically:

```bash
./Scripts/fetch-mpv.sh
```

The packaging script copies this runtime into `PowerPreview.app/Contents/Resources/mpv-runtime/` so MKV, AVI, WebM, HDR, and other ffmpeg-backed formats work without Homebrew.
