import AppKit
import Foundation
import Libmpv

/// NSView whose backing layer is the CAMetalLayer mpv/MoltenVK renders into.
final class MPVMetalHostView: NSView {
    let metalLayer = MetalLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Let SwiftUI chrome above receive all mouse interaction.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func makeBackingLayer() -> CALayer {
        metalLayer.contentsScale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        return metalLayer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncDrawableSize()
    }

    override func layout() {
        super.layout()
        syncDrawableSize()
    }

    func syncDrawableSize() {
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        var size = bounds.size
        if size.width <= 1 || size.height <= 1 {
            size = CGSize(width: 960, height: 540)
        }
        metalLayer.contentsScale = scale
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(width: size.width * scale, height: size.height * scale)
    }
}

/// Embedded libmpv Metal player. Metal API Validation should stay off for HDR.
final class MPVMetalViewController: NSViewController {
    private(set) var hostView: MPVMetalHostView!
    var metalLayer: MetalLayer { hostView.metalLayer }
    var mpv: OpaquePointer!
    weak var playDelegate: MPVPlayerDelegate?
    lazy var queue = DispatchQueue(label: "com.powerpreview.mpv", qos: .userInitiated)
    private var wakeupContext: UnsafeMutableRawPointer?
    private var didSetupMpv = false

    var playUrl: URL?
    private(set) var loadedURL: URL?

    var hdrAvailable = false
    var signalFormat: VideoSignalFormat = .sdr
    var is4K = false
    private var geometryObserver: NSObjectProtocol?

    override func loadView() {
        let host = MPVMetalHostView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        hostView = host
        view = host
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        ppLog("viewDidLoad bounds=\(view.bounds) playUrl=\(playUrl?.lastPathComponent ?? "nil")")
        hostView.syncDrawableSize()
        startMpvIfNeeded()
        if let url = playUrl {
            loadFile(url)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        hostView.syncDrawableSize()
        attachMetalUnderSwiftUIChrome()
        installGeometryObserver()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeGeometryObserver()
        detachMetalFromWindow()
    }

    /// Place Metal at the bottom of the content view; FloatingChrome stays topmost.
    private func attachMetalUnderSwiftUIChrome() {
        guard let window = view.window,
              let content = window.contentView else { return }

        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor

        // Prefer the main SwiftUI hosting view — never treat FloatingChrome as the root.
        let chrome = FloatingChrome.overlayView
        let hosting = content.subviews.first(where: { subview in
            guard subview !== chrome else { return false }
            let name = String(describing: type(of: subview))
            return name.contains("Hosting") || name.contains("NSHosting")
        })

        if let hosting {
            hosting.wantsLayer = true
            hosting.layer?.isOpaque = false
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if view.superview !== content {
            view.removeFromSuperview()
            // relativeTo: nil + .below → insert at bottom of the stack
            content.addSubview(view, positioned: .below, relativeTo: nil)
        }

        syncMetalToContentBounds()
        FloatingChrome.layout()
    }

    func syncMetalToContentBounds() {
        guard let content = view.window?.contentView ?? view.superview else {
            hostView.syncDrawableSize()
            return
        }
        if view.superview === content {
            let bounds = content.bounds
            if view.frame != bounds {
                view.frame = bounds
            }
            view.autoresizingMask = [.width, .height]
        }
        hostView.syncDrawableSize()
        FloatingChrome.layout()
    }

    private func installGeometryObserver() {
        removeGeometryObserver()
        geometryObserver = NotificationCenter.default.addObserver(
            forName: .powerPreviewWindowGeometryChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncMetalToContentBounds()
        }
        if let window = view.window {
            let center = NotificationCenter.default
            for name in [
                NSWindow.didResizeNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ] {
                center.addObserver(
                    self,
                    selector: #selector(windowGeometryChanged(_:)),
                    name: name,
                    object: window
                )
            }
        }
    }

    private func removeGeometryObserver() {
        if let geometryObserver {
            NotificationCenter.default.removeObserver(geometryObserver)
            self.geometryObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowGeometryChanged(_ notification: Notification) {
        syncMetalToContentBounds()
    }

    func detachMetalFromWindow() {
        if view.superview === view.window?.contentView {
            view.removeFromSuperview()
        }
    }

    /// Pinch/pan from SwiftUI — metal is reparented out of the representable, so
    /// scaleEffect on the placeholder does not apply; transform the host directly.
    func applyZoom(scale: CGFloat, offset: CGSize) {
        let clamped = max(scale, 1)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: offset.width, y: -offset.height)
        transform = transform.scaledBy(x: clamped, y: clamped)
        hostView.layer?.setAffineTransform(transform)
        hostView.syncDrawableSize()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let content = view.window?.contentView, view.superview === content {
            syncMetalToContentBounds()
            let chrome = FloatingChrome.overlayView
            if let hosting = content.subviews.first(where: {
                $0 !== chrome && String(describing: type(of: $0)).contains("Hosting")
            }) {
                hosting.wantsLayer = true
                hosting.layer?.isOpaque = false
                hosting.layer?.backgroundColor = NSColor.clear.cgColor
            }
        } else {
            hostView.syncDrawableSize()
        }
    }

    func startMpvIfNeeded() {
        guard !didSetupMpv else { return }
        didSetupMpv = true
        setupMpv()
    }

    func setupMpv() {
        setenv("LUA_PATH", ";", 1)
        setenv("LUA_CPATH", ";", 1)
        setenv("MVK_CONFIG_LOG_LEVEL", "2", 0)

        mpv = mpv_create()
        guard mpv != nil else {
            assertionFailure("mpv_create failed")
            return
        }

        checkError(mpv_request_log_messages(mpv, "warn"))
        checkError(mpv_set_option_string(mpv, "config", "no"))
        checkError(mpv_set_option_string(mpv, "load-scripts", "no"))
        checkError(mpv_set_option_string(mpv, "load-stats-overlay", "no"))
        checkError(mpv_set_option_string(mpv, "load-osd-console", "no"))
        checkError(mpv_set_option_string(mpv, "load-auto-profiles", "no"))
        checkError(mpv_set_option_string(mpv, "osc", "no"))
        checkError(mpv_set_option_string(mpv, "osd-level", "0"))
        checkError(mpv_set_option_string(mpv, "terminal", "no"))
        checkError(mpv_set_option_string(mpv, "input-media-keys", "no"))
        checkError(mpv_set_option_string(mpv, "input-default-bindings", "no"))
        checkError(mpv_set_option_string(mpv, "input-vo-keyboard", "no"))

        var wid = unsafeBitCast(metalLayer, to: Int64.self)
        checkError(mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid))
        checkError(mpv_set_option_string(mpv, "vo", "gpu-next"))
        checkError(mpv_set_option_string(mpv, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(mpv, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(mpv, "hwdec", "videotoolbox-copy"))
        checkError(mpv_set_option_string(mpv, "hwdec-codecs", "all"))
        checkError(mpv_set_option_string(mpv, "ao", "coreaudio"))
        checkError(mpv_set_option_string(mpv, "audio-fallback-to-null", "yes"))
        checkError(mpv_set_option_string(mpv, "audio-channels", "stereo"))
        checkError(mpv_set_option_string(mpv, "cache", "yes"))
        checkError(mpv_set_option_string(mpv, "cache-secs", "3"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-bytes", "64M"))
        checkError(mpv_set_option_string(mpv, "demuxer-max-back-bytes", "32M"))
        checkError(mpv_set_option_string(mpv, "demuxer-readahead-secs", "2"))
        checkError(mpv_set_option_string(mpv, "video-sync", "audio"))
        checkError(mpv_set_option_string(mpv, "interpolation", "no"))
        checkError(mpv_set_option_string(mpv, "hdr-compute-peak", "no"))
        checkError(mpv_set_option_string(mpv, "tone-mapping", "auto"))
        checkError(mpv_set_option_string(mpv, "gamut-mapping-mode", "auto"))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "ytdl", "no"))
        checkError(mpv_set_option_string(mpv, "sid", "no"))
        checkError(mpv_set_option_string(mpv, "keepaspect", "yes"))
        checkError(mpv_set_option_string(mpv, "force-window", "no"))

        ppLog("mpv_initialize…")
        checkError(mpv_initialize(mpv))
        ppLog("mpv_initialize done")

        mpv_observe_property(mpv, 0, MPVProperty.videoParamsSigPeak, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsGamma, MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsPrimaries, MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, MPVProperty.videoParamsDovi, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.videoFormat, MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, MPVProperty.width, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.height, MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, MPVProperty.eofReached, MPV_FORMAT_FLAG)

        wakeupContext = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let controller = Unmanaged<MPVMetalViewController>.fromOpaque(ctx).takeUnretainedValue()
            controller.readEvents()
        }, wakeupContext)
    }

    func loadFile(_ url: URL, time: Double? = nil) {
        playUrl = url
        ppLog("loadFile \(url.lastPathComponent)")
        startMpvIfNeeded()
        guard mpv != nil else {
            ppLog("loadFile aborted — mpv nil")
            return
        }

        if loadedURL == url, time == nil {
            play()
            return
        }

        hostView.syncDrawableSize()
        var args: [String?] = [url.absoluteString, "replace", "-1"]
        if let time, time > 0 {
            args.append("start=\(Int(time))")
        }
        command("loadfile", args: args)
        loadedURL = url
        play()
        ppLog("loadFile commanded path=\(url.path)")
    }

    func play() {
        setFlag(MPVProperty.pause, false)
    }

    func pause() {
        setFlag(MPVProperty.pause, true)
    }

    func togglePause() {
        setFlag(MPVProperty.pause, !getFlag(MPVProperty.pause))
    }

    func seek(absolute seconds: Double) {
        command("seek", args: [String(seconds), "absolute"])
    }

    func seek(relative seconds: Double) {
        command("seek", args: [String(seconds), "relative"])
    }

    func stopPlayback() {
        command("stop", checkForErrors: false)
        loadedURL = nil
        playUrl = nil
        detachMetalFromWindow()
    }

    /// Replace current media without tearing down Metal/mpv (used for next/prev).
    func replaceFile(_ url: URL) {
        loadFile(url)
    }

    func getDouble(_ name: String) -> Double {
        guard mpv != nil else { return 0 }
        var data = Double()
        mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        return data
    }

    func getInt(_ name: String) -> Int {
        guard mpv != nil else { return 0 }
        var data: Int64 = 0
        mpv_get_property(mpv, name, MPV_FORMAT_INT64, &data)
        return Int(data)
    }

    func getString(_ name: String) -> String? {
        guard mpv != nil else { return nil }
        guard let cstr = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(cstr) }
        return String(cString: cstr)
    }

    func getFlag(_ name: String) -> Bool {
        guard mpv != nil else { return false }
        var data: Int32 = 0
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data != 0
    }

    func refreshSignalFormat() {
        guard mpv != nil else { return }

        let gamma = getString(MPVProperty.videoParamsGamma)
        let primaries = getString(MPVProperty.videoParamsPrimaries)
        let format = getString(MPVProperty.videoFormat)?.lowercased() ?? ""
        let peak = getDouble(MPVProperty.videoParamsSigPeak)
        let doviFlag = getFlag(MPVProperty.videoParamsDovi)
        let looksDovi = doviFlag
            || format.contains("dovi")
            || format.contains("dvhe")
            || format.contains("dvh1")

        let detected = VideoSignalFormat.detect(
            gamma: gamma,
            primaries: primaries,
            sigPeak: peak,
            isDolbyVision: looksDovi
        )
        signalFormat = detected

        let width = getInt(MPVProperty.width)
        let height = getInt(MPVProperty.height)
        is4K = width >= 3840 || height >= 2160

        let maxEDR = NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0
        hdrAvailable = maxEDR > 1.0 && detected != .sdr

        playDelegate?.propertyChange(mpv: mpv, propertyName: "powerpreview/signal-format", data: detected)
        playDelegate?.propertyChange(mpv: mpv, propertyName: "powerpreview/is-4k", data: is4K)
        playDelegate?.propertyChange(mpv: mpv, propertyName: "powerpreview/hdr-display", data: hdrAvailable)
    }

    func setFlag(_ name: String, _ flag: Bool) {
        guard mpv != nil else { return }
        var data: Int32 = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    func command(
        _ command: String,
        args: [String?] = [],
        checkForErrors: Bool = true
    ) {
        guard mpv != nil else { return }
        var pointers: [UnsafeMutablePointer<CChar>?] = makeCArgs(command, args).map { value in
            value.map { strdup($0) }
        }
        defer {
            for ptr in pointers {
                free(ptr)
            }
        }
        let status = pointers.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return base.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) { rebound in
                mpv_command(mpv, rebound)
            }
        }
        if checkForErrors {
            checkError(status)
        }
    }

    private func makeCArgs(_ command: String, _ args: [String?]) -> [String?] {
        var strArgs = args
        strArgs.insert(command, at: 0)
        strArgs.append(nil)
        return strArgs
    }

    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while self.mpv != nil {
                let event = mpv_wait_event(self.mpv, 0)
                guard let event, event.pointee.event_id != MPV_EVENT_NONE else { break }

                switch event.pointee.event_id {
                case MPV_EVENT_FILE_LOADED, MPV_EVENT_PLAYBACK_RESTART:
                    DispatchQueue.main.async { [weak self] in
                        self?.hostView.syncDrawableSize()
                        self?.play()
                        self?.refreshSignalFormat()
                    }
                case MPV_EVENT_PROPERTY_CHANGE:
                    let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data))?.pointee
                    guard let property else { break }
                    let name = String(cString: property.name)

                    DispatchQueue.main.async { [weak self] in
                        guard let self, let mpv = self.mpv else { return }
                        switch name {
                        case MPVProperty.videoParamsSigPeak,
                             MPVProperty.videoParamsGamma,
                             MPVProperty.videoParamsPrimaries,
                             MPVProperty.videoParamsDovi,
                             MPVProperty.videoFormat,
                             MPVProperty.width,
                             MPVProperty.height:
                            self.refreshSignalFormat()
                        case MPVProperty.pausedForCache:
                            let buffering = (UnsafePointer<Int32>(OpaquePointer(property.data))?.pointee ?? 0) != 0
                            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: buffering)
                        case MPVProperty.duration:
                            let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee ?? 0
                            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: value)
                            self.refreshSignalFormat()
                        case MPVProperty.timePos:
                            let value = UnsafePointer<Double>(OpaquePointer(property.data))?.pointee ?? 0
                            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: value)
                        case MPVProperty.pause:
                            let paused = (UnsafePointer<Int32>(OpaquePointer(property.data))?.pointee ?? 0) != 0
                            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: paused)
                        case MPVProperty.eofReached:
                            let eof = (UnsafePointer<Int32>(OpaquePointer(property.data))?.pointee ?? 0) != 0
                            self.playDelegate?.propertyChange(mpv: mpv, propertyName: name, data: eof)
                        default:
                            break
                        }
                    }
                case MPV_EVENT_SHUTDOWN:
                    mpv_terminate_destroy(self.mpv)
                    self.mpv = nil
                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafeMutablePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data)) {
                        print("[mpv] \(String(cString: msg.pointee.text))", terminator: "")
                    }
                default:
                    break
                }
            }
        }
    }

    deinit {
        if mpv != nil {
            mpv_set_wakeup_callback(mpv, nil, nil)
            queue.sync {
                if self.mpv != nil {
                    mpv_terminate_destroy(self.mpv)
                    self.mpv = nil
                }
            }
        }
        if let wakeupContext {
            Unmanaged<MPVMetalViewController>.fromOpaque(wakeupContext).release()
            self.wakeupContext = nil
        }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            let message = String(cString: mpv_error_string(status))
            ppLog("MPV API error: \(message)")
            print("MPV API error: \(message)")
        }
    }
}

private func ppLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/pp-mpv.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    } else {
        try? data.write(to: url)
    }
}
