import AVKit
import SwiftUI

struct VideoPreview: View {
    let url: URL
    @ObservedObject var zoomState: MediaZoomState

    var body: some View {
        Group {
            if MpvExecutableLocator.executableURL != nil {
                MpvVideoView(url: url)
            } else {
                NativeVideoView(url: url, zoomState: zoomState)
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
    @ObservedObject var zoomState: MediaZoomState
    @StateObject private var model = NativeVideoModel()
    @State private var controlsVisible = false
    @State private var hideControlsWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            ZoomableMediaView(zoomState: zoomState) {
                NativePlayerLayerView(player: model.player)
                    .background(Color.black)
            }

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
    @Published var canSeek = false

    let player = AVPlayer()
    private var currentURL: URL?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var isSeeking = false
    private var durationSeconds = 0.0

    func load(_ url: URL) {
        guard currentURL != url else {
            player.play()
            isPlaying = true
            return
        }

        removeObservers()
        currentURL = url
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
        canSeek = false
        durationSeconds = 0

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observeItem(item)
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
        removeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentURL = nil
        isPlaying = false
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
        canSeek = false
        durationSeconds = 0
    }

    func seek(to newProgress: Double) {
        guard durationSeconds > 0 else {
            return
        }

        isSeeking = true
        let clamped = min(max(newProgress, 0), 1)
        progress = clamped
        currentTimeText = formatTime(durationSeconds * clamped)

        let seconds = durationSeconds * clamped
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            Task { @MainActor [weak self] in
                self?.refreshDuration(from: observedItem)
            }
        }
    }

    private func refreshDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        guard item.status == .readyToPlay, seconds.isFinite, seconds > 0 else {
            canSeek = false
            durationSeconds = 0
            return
        }

        durationSeconds = seconds
        durationText = formatTime(seconds)
        canSeek = true
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

        if let item = player.currentItem {
            refreshDuration(from: item)
        }

        currentTimeText = formatTime(currentTime)

        if durationSeconds > 0 {
            progress = min(max(currentTime / durationSeconds, 0), 1)
        } else {
            progress = 0
        }
    }

    private func removeObservers() {
        removeTimeObserver()
        statusObservation = nil
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
    @State private var scrubProgress = 0.0
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Text(model.currentTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubProgress : model.progress },
                    set: { newValue in
                        scrubProgress = newValue
                        if isScrubbing {
                            model.seek(to: newValue)
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubProgress = model.progress
                    } else {
                        model.seek(to: scrubProgress)
                    }
                }
            )
            .disabled(!model.canSeek)

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

    private var mouseMonitor: Any?
    private var lastMouseLocation: NSPoint?
    private var isInside = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else {
            return
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)
            let inside = self.bounds.contains(location)

            if inside {
                if location != self.lastMouseLocation {
                    self.lastMouseLocation = location
                    self.onMove?()
                }
                self.isInside = true
            } else if self.isInside {
                self.isInside = false
                self.lastMouseLocation = nil
                self.onExit?()
            }

            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    deinit {
        removeMouseMonitor()
    }
}
