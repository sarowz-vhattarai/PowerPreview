import AVKit
import SwiftUI

struct VideoPreview: View {
    let url: URL

    var body: some View {
        Group {
            if MpvExecutableLocator.executableURL != nil {
                MpvVideoView(url: url)
            } else {
                NativeVideoView(url: url)
            }
        }
        .id(url)
    }
}

enum MpvExecutableLocator {
    static var executableURL: URL? {
        if let override = ProcessInfo.processInfo.environment["POWERPREVIEW_MPV_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        if let bundled = Bundle.main.url(forResource: "mpv", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv", "/usr/bin/mpv"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}

struct NativeVideoView: View {
    let url: URL
    @StateObject private var model = NativeVideoModel()
    @State private var controlsVisible = false
    @State private var hideControlsWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            NativePlayerLayerView(player: model.player)
                .background(Color.black)

            MouseMovementReader(
                onMove: showControlsBriefly,
                onExit: hideControls
            )

            if controlsVisible {
                VideoControlOverlay(model: model)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear {
            model.load(url)
        }
        .onDisappear {
            model.stop()
        }
        .onChange(of: url) { newURL in
            controlsVisible = false
            model.load(newURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleVideoPlayback)) { _ in
            model.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopVideoPlayback)) { _ in
            model.stop()
        }
    }

    private func showControlsBriefly() {
        controlsVisible = true
        hideControlsWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            controlsVisible = false
        }

        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func hideControls() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        controlsVisible = false
    }
}

@MainActor
final class NativeVideoModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var currentTimeText = "0:00"
    @Published var durationText = "0:00"

    let player = AVPlayer()
    private var currentURL: URL?
    private var timeObserver: Any?
    private var isSeeking = false

    func load(_ url: URL) {
        guard currentURL != url else {
            player.play()
            isPlaying = true
            return
        }

        removeTimeObserver()
        currentURL = url
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        addTimeObserver()
        player.play()
        isPlaying = true
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        removeTimeObserver()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        isPlaying = false
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
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
        currentTimeText = formatTime(currentTime)
        durationText = formatTime(duration)

        if duration > 0 {
            progress = min(max(currentTime / duration, 0), 1)
        } else {
            progress = 0
        }
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
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func removeTimeObserver() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    deinit {
        let player = self.player
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
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
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
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
        layer?.addSublayer(playerLayer)
    }
}

struct VideoControlOverlay: View {
    @ObservedObject var model: NativeVideoModel

    var body: some View {
        HStack(spacing: 12) {
            Button(model.isPlaying ? "Pause" : "Play") {
                model.togglePlayback()
            }
            .buttonStyle(.borderedProminent)

            Text(model.currentTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { model.progress },
                    set: { newValue in
                        model.progress = newValue
                        model.seek(to: newValue)
                    }
                ),
                in: 0...1
            )

            Text(model.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MouseMovementReader: NSViewRepresentable {
    let onMove: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> MouseMovementView {
        let view = MouseMovementView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: MouseMovementView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }
}

final class MouseMovementView: NSView {
    var onMove: (() -> Void)?
    var onExit: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var lastMouseLocation: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        lastMouseLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseExited(with event: NSEvent) {
        lastMouseLocation = nil
        onExit?()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        defer {
            lastMouseLocation = location
        }

        guard location != lastMouseLocation else {
            return
        }

        onMove?()
    }
}
