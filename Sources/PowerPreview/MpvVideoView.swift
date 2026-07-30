import AppKit
import SwiftUI

struct MpvVideoView: View {
    let url: URL
    @ObservedObject var zoomState: MediaZoomState
    @StateObject private var model = MpvPlayerModel()
    @State private var controlsVisible = false
    @State private var hideControlsWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            MpvHostRepresentable(model: model)
                .background(Color.black)

            if controlsVisible {
                MpvControlOverlay(model: model)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear {
            model.load(url)
            model.onMouseActivity = { showControlsBriefly() }
        }
        .onDisappear {
            model.onMouseActivity = nil
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
        let workItem = DispatchWorkItem { controlsVisible = false }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }
}

struct MpvHostRepresentable: NSViewRepresentable {
    @ObservedObject var model: MpvPlayerModel

    func makeNSView(context: Context) -> MpvHostView {
        let view = MpvHostView()
        view.model = model
        model.attach(hostView: view)
        return view
    }

    func updateNSView(_ nsView: MpvHostView, context: Context) {
        nsView.model = model
        model.attach(hostView: nsView)
        model.syncWindowGeometry()
    }
}

final class MpvHostView: NSView {
    weak var model: MpvPlayerModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            model?.stop()
        } else {
            model?.syncWindowGeometry()
        }
    }

    override func layout() {
        super.layout()
        model?.syncWindowGeometry()
    }
}

@MainActor
final class MpvPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var currentTimeText = "0:00"
    @Published var durationText = "0:00"
    @Published var canSeek = false

    var onMouseActivity: (() -> Void)?

    private weak var hostView: MpvHostView?
    private var process: Process?
    private var currentURL: URL?
    private var ipcPath: String?
    private var progressTimer: Timer?
    private var geometryTimer: Timer?
    private var mouseTimer: Timer?
    private var durationSeconds = 0.0
    private var isSeeking = false
    private var lastMousePoint: NSPoint = .zero

    func attach(hostView: MpvHostView) {
        self.hostView = hostView
    }

    func load(_ url: URL) {
        if currentURL == url, process?.isRunning == true {
            send(["set_property", "pause", false])
            isPlaying = true
            return
        }

        stop(clearURL: false)
        currentURL = url
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
        canSeek = false
        durationSeconds = 0
        startProcess(for: url)
    }

    func togglePlayback() {
        if isPlaying {
            send(["set_property", "pause", true])
            isPlaying = false
        } else {
            send(["set_property", "pause", false])
            isPlaying = true
        }
    }

    func seek(to newProgress: Double) {
        guard durationSeconds > 0 else { return }
        isSeeking = true
        let clamped = min(max(newProgress, 0), 1)
        progress = clamped
        let seconds = durationSeconds * clamped
        currentTimeText = formatTime(seconds)
        send(["seek", seconds, "absolute"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isSeeking = false
        }
    }

    func stop() {
        stop(clearURL: true)
    }

    private func stop(clearURL: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        geometryTimer?.invalidate()
        geometryTimer = nil
        mouseTimer?.invalidate()
        mouseTimer = nil

        if process?.isRunning == true {
            send(["quit"])
            usleep(50_000)
            if process?.isRunning == true {
                process?.terminate()
            }
        }
        process = nil
        if clearURL {
            currentURL = nil
        }
        isPlaying = false
        progress = 0
        canSeek = false
        durationSeconds = 0

        if let ipcPath {
            try? FileManager.default.removeItem(atPath: ipcPath)
            self.ipcPath = nil
        }
    }

    func syncWindowGeometry() {
        guard let hostView, let window = hostView.window, process?.isRunning == true else { return }

        // Keep a bottom strip in our window so the slider stays clickable.
        let bottomChrome: CGFloat = 64
        var viewRect = hostView.convert(hostView.bounds, to: nil)
        viewRect.size.height = max(viewRect.height - bottomChrome, 40)
        viewRect.origin.y += bottomChrome

        let screenRect = window.convertToScreen(viewRect)
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let x = Int((screenRect.minX - visible.minX).rounded())
        let y = Int((visible.maxY - screenRect.maxY).rounded())
        let w = max(Int(screenRect.width.rounded()), 1)
        let h = max(Int(screenRect.height.rounded()), 1)
        send(["set_property", "geometry", "\(w)x\(h)+\(x)+\(y)"])
    }

    private func startProcess(for url: URL) {
        guard let executable = MpvExecutableLocator.executableURL else { return }

        let socket = FileManager.default.temporaryDirectory
            .appendingPathComponent("powerpreview-mpv-\(UUID().uuidString).sock")
            .path
        ipcPath = socket

        let inputConf = FileManager.default.temporaryDirectory
            .appendingPathComponent("powerpreview-mpv-input-\(UUID().uuidString).conf")
        try? """
        MOUSE_BTN0_DBL cycle fullscreen
        SPACE cycle pause
        LEFT seek -5
        RIGHT seek 5
        """.write(to: inputConf, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.arguments = [
            "--no-config",
            "--no-terminal",
            "--force-window=immediate",
            "--no-border",
            "--ontop",
            "--ontop-level=window",
            "--keepaspect=yes",
            "--keepaspect-window=no",
            "--osc=no",
            "--input-conf=\(inputConf.path)",
            "--keep-open=no",
            "--idle=no",
            "--hwdec=auto-safe",
            "--vo=gpu",
            "--gpu-hwdec-interop=auto",
            "--hdr-compute-peak=auto",
            "--target-colorspace-hint=yes",
            "--input-ipc-server=\(socket)",
            url.path
        ]

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if status == 0 {
                    NotificationCenter.default.post(name: .videoDidFinishPlaying, object: nil)
                }
                self.isPlaying = false
            }
        }

        do {
            try process.run()
            self.process = process
            isPlaying = true
            startTimers()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.syncWindowGeometry()
                NSApp.activate(ignoringOtherApps: true)
                self?.hostView?.window?.makeKeyAndOrderFront(nil)
            }
        } catch {
            self.process = nil
            isPlaying = false
        }
    }

    private func startTimers() {
        progressTimer?.invalidate()
        geometryTimer?.invalidate()
        mouseTimer?.invalidate()

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.pollProgress() }
        }
        geometryTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.syncWindowGeometry() }
        }
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.pollMouse() }
        }
    }

    private func pollMouse() {
        let point = NSEvent.mouseLocation
        guard point != lastMousePoint else { return }
        lastMousePoint = point

        guard let hostView, let window = hostView.window else { return }
        let frame = window.convertToScreen(hostView.convert(hostView.bounds, to: nil))
        if frame.contains(point) {
            onMouseActivity?()
        }
    }

    private func pollProgress() {
        guard !isSeeking else { return }

        if let duration = requestDouble(["get_property", "duration"]), duration > 0 {
            durationSeconds = duration
            durationText = formatTime(duration)
            canSeek = true
        }

        if let timePos = requestDouble(["get_property", "time-pos"]) {
            currentTimeText = formatTime(timePos)
            if durationSeconds > 0 {
                progress = min(max(timePos / durationSeconds, 0), 1)
            }
        }

        if let paused = requestBool(["get_property", "pause"]) {
            isPlaying = !paused
        }

        if let eof = requestBool(["get_property", "eof-reached"]), eof {
            NotificationCenter.default.post(name: .videoDidFinishPlaying, object: nil)
            isPlaying = false
        }
    }

    private func send(_ command: [Any]) {
        guard let ipcPath else { return }
        let payload: [String: Any] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        writeIPC(line, to: ipcPath)
    }

    private func requestDouble(_ command: [Any]) -> Double? {
        guard let response = request(command) else { return nil }
        if let value = response["data"] as? Double { return value }
        if let value = response["data"] as? NSNumber { return value.doubleValue }
        return nil
    }

    private func requestBool(_ command: [Any]) -> Bool? {
        guard let response = request(command) else { return nil }
        if let value = response["data"] as? Bool { return value }
        if let value = response["data"] as? NSNumber { return value.boolValue }
        return nil
    }

    private func request(_ command: [Any]) -> [String: Any]? {
        guard let ipcPath else { return nil }
        let payload: [String: Any] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return nil }
        line.append("\n")

        let fd = open(ipcPath, O_RDWR)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        line.withCString { ptr in
            _ = write(fd, ptr, strlen(ptr))
        }

        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return nil }

        // mpv may return multiple JSON lines; use the first complete object.
        let raw = Data(buffer.prefix(count))
        if let text = String(data: raw, encoding: .utf8),
           let firstLine = text.split(separator: "\n").first,
           let lineData = firstLine.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
            return object
        }
        return nil
    }

    private func writeIPC(_ line: String, to path: String) {
        let fd = open(path, O_WRONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        defer { close(fd) }
        line.withCString { ptr in
            _ = write(fd, ptr, strlen(ptr))
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    deinit {
        progressTimer?.invalidate()
        geometryTimer?.invalidate()
        mouseTimer?.invalidate()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

struct MpvControlOverlay: View {
    @ObservedObject var model: MpvPlayerModel
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

enum MpvExecutableLocator {
    static var executableURL: URL? {
        if let override = ProcessInfo.processInfo.environment["POWERPREVIEW_MPV_PATH"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        if let resourceRoot = Bundle.main.resourceURL {
            let runtime = resourceRoot.appendingPathComponent("mpv-runtime/mpv")
            if FileManager.default.isExecutableFile(atPath: runtime.path) {
                return runtime
            }
        }

        if let bundled = Bundle.main.url(forResource: "mpv", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let cwdVendor = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Vendor/mpv/mpv")
        if FileManager.default.isExecutableFile(atPath: cwdVendor.path) {
            return cwdVendor
        }

        for path in [
            NSString("~/PowerPreview/Vendor/mpv/mpv").expandingTildeInPath,
            "/opt/homebrew/bin/mpv",
            "/usr/local/bin/mpv",
            "/usr/bin/mpv"
        ] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}
