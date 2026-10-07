import AVFoundation
import SwiftUI

struct VideoPreview: View {
    let url: URL

    var body: some View {
        NativeVideoView(url: url)
            .id(url)
    }
}

struct NativeVideoView: View {
    let url: URL
    @StateObject private var model = NativeVideoModel()

    var body: some View {
        NativePlayerLayerView(player: model.player)
            .onAppear {
                model.load(url)
            }
            .onChange(of: url) { newURL in
                model.load(newURL)
            }
            .onDisappear {
                model.stop()
            }
    }
}

@MainActor
final class NativeVideoModel: ObservableObject {
    let player = AVPlayer()

    private var currentURL: URL?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var isSeeking = false

    func load(_ url: URL) {
        let session = PlaybackSession.shared
        session.isVideo = true
        session.failureMessage = nil
        session.toggleHandler = { [weak self] in
            self?.togglePlayback()
        }
        session.seekHandler = { [weak self] progress in
            self?.seek(to: progress)
        }

        guard currentURL != url else {
            player.play()
            session.isPlaying = true
            return
        }

        removeObservers()
        currentURL = url
        session.progress = 0
        session.currentTimeText = "0:00"
        session.durationText = "0:00"

        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    PlaybackSession.shared.failureMessage = item.error?.localizedDescription
                        ?? "This video could not be played."
                    PlaybackSession.shared.isPlaying = false
                }
            }
        }

        player.replaceCurrentItem(with: item)
        observeEnd(of: item)
        addTimeObserver()
        player.play()
        session.isPlaying = true
    }

    func stop() {
        player.pause()
        removeObservers()
        currentURL = nil
        PlaybackSession.shared.reset()
    }

    func togglePlayback() {
        if PlaybackSession.shared.isPlaying {
            player.pause()
            PlaybackSession.shared.isPlaying = false
        } else {
            player.play()
            PlaybackSession.shared.isPlaying = true
        }
    }

    func seek(to newProgress: Double) {
        guard let duration = finiteDuration, duration > 0 else {
            return
        }

        isSeeking = true
        let seconds = duration * min(max(newProgress, 0), 1)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.updateProgress(currentTime: time.seconds)
            }
        }
    }

    private func updateProgress(currentTime: Double) {
        guard !isSeeking, currentTime.isFinite else {
            return
        }

        let duration = finiteDuration ?? 0
        let session = PlaybackSession.shared
        session.currentTimeText = formatTime(currentTime)
        session.durationText = formatTime(duration)
        session.progress = duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    private var finiteDuration: Double? {
        guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else {
            return nil
        }

        return seconds
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "0:00"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainder = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%d:%02d", minutes, remainder)
    }

    private func observeEnd(of item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PlaybackSession.shared.isPlaying = false
                PlaybackSession.shared.noteEnded()
            }
        }
    }

    private func removeObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation = nil
    }

    deinit {
        let player = self.player
        let observer = self.timeObserver
        let endObserver = self.endObserver
        DispatchQueue.main.async {
            if let observer {
                player.removeTimeObserver(observer)
            }
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            player.pause()
        }
    }
}

struct NativePlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerHostView, context: Context) {
        nsView.player = player
    }
}

final class PlayerLayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }
}
