The packaging script copies a self-contained macOS `mpv` executable into this resource directory inside `PowerPreview.app`.

Preferred source path:

```text
Vendor/mpv/mpv
```

During development, PowerPreview also checks `POWERPREVIEW_MPV_PATH`, `/opt/homebrew/bin/mpv`, and `/usr/local/bin/mpv`.
