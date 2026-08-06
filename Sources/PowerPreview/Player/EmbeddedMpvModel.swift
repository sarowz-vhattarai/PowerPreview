import SwiftUI

/// Playback state bridging SwiftUI chrome to the embedded libmpv Metal controller.
/// One instance is reused across next/prev so we never stack MoltenVK/mpv processes.
@MainActor
final class EmbeddedMpvModel: ObservableObject, MPVPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var currentTimeText = "0:00"
    @Published var durationText = "0:00"
    @Published var canSeek = false
    @Published var isBuffering = false
    @Published var signalFormat: VideoSignalFormat = .sdr
    @Published var is4K = false
    @Published var hdrDisplayActive = false

    private(set) var url: URL?
    private weak var player: MPVMetalViewController?
    private var durationSeconds = 0.0
    private var isSeeking = false

    init(url: URL? = nil) {
        self.url = url
    }

    func attach(player: MPVMetalViewController) {
        self.player = player
        let hud = PlaybackHUDState.shared
        hud.isActiveVideo = true
        hud.toggleHandler = { [weak self] in self?.togglePlayback() }
        hud.seekHandler = { [weak self] progress in self?.seek(to: progress) }
        syncHUD()
    }

    /// Load or replace the current file on the shared player (no new mpv instance).
    func play(url: URL) {
        let changed = self.url != url
        self.url = url
        if changed {
            progress = 0
            currentTimeText = "0:00"
            durationText = "0:00"
            canSeek = false
            durationSeconds = 0
            signalFormat = .sdr
            is4K = false
            hdrDisplayActive = false
        }
        let hud = PlaybackHUDState.shared
        hud.isActiveVideo = true
        hud.toggleHandler = { [weak self] in self?.togglePlayback() }
        hud.seekHandler = { [weak self] progress in self?.seek(to: progress) }
        syncHUD()
        player?.loadFile(url)
    }

    func applyZoom(_ zoomState: MediaZoomState) {
        player?.applyZoom(scale: zoomState.scale, offset: zoomState.offset)
    }

    func togglePlayback() {
        player?.togglePause()
    }

    /// Soft stop — keep mpv/Metal alive for the next file.
    func stop(keepingPlayer: Bool = false) {
        if keepingPlayer {
            player?.pause()
            commandStopOnly()
        } else {
            player?.stopPlayback()
        }
        isPlaying = false
        PlaybackHUDState.shared.reset()
    }

    private func commandStopOnly() {
        // Prefer unload via empty stop without detaching Metal when browsing videos.
        player?.pause()
    }

    func applyZoomReset() {
        player?.applyZoom(scale: 1, offset: .zero)
    }

    private func syncHUD() {
        let hud = PlaybackHUDState.shared
        hud.isActiveVideo = true
        hud.isPlaying = isPlaying
        hud.progress = progress
        hud.currentTimeText = currentTimeText
        hud.durationText = durationText
        hud.canSeek = canSeek
    }

    func seek(to newProgress: Double) {
        guard durationSeconds > 0 else { return }
        isSeeking = true
        let clamped = min(max(newProgress, 0), 1)
        progress = clamped
        let seconds = durationSeconds * clamped
        currentTimeText = formatTime(seconds)
        player?.seek(absolute: seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isSeeking = false
        }
    }

    nonisolated func propertyChange(mpv: OpaquePointer, propertyName: String, data: Any?) {
        Task { @MainActor in
            self.handlePropertyChange(propertyName: propertyName, data: data)
        }
    }

    private func handlePropertyChange(propertyName: String, data: Any?) {
        switch propertyName {
        case MPVProperty.duration:
            if let value = data as? Double, value.isFinite, value > 0 {
                durationSeconds = value
                durationText = formatTime(value)
                canSeek = true
                syncHUD()
            }
        case MPVProperty.timePos:
            guard !isSeeking, let value = data as? Double, value.isFinite else { return }
            currentTimeText = formatTime(value)
            if durationSeconds > 0 {
                progress = min(max(value / durationSeconds, 0), 1)
            }
            syncHUD()
        case MPVProperty.pause:
            if let paused = data as? Bool {
                isPlaying = !paused
                syncHUD()
            }
        case MPVProperty.pausedForCache:
            if let buffering = data as? Bool {
                isBuffering = buffering
            }
        case "powerpreview/signal-format":
            if let format = data as? VideoSignalFormat {
                signalFormat = format
            }
        case "powerpreview/is-4k":
            if let value = data as? Bool {
                is4K = value
            }
        case "powerpreview/hdr-display":
            if let value = data as? Bool {
                hdrDisplayActive = value
            }
        case MPVProperty.eofReached:
            if let eof = data as? Bool, eof {
                NotificationCenter.default.post(name: .videoDidFinishPlaying, object: nil)
                isPlaying = false
            }
        default:
            break
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
