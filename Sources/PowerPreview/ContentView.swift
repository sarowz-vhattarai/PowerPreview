import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var zoomState = MediaZoomState()
    /// One shared player for all videos — next/prev only loadfile, never a second mpv.
    @StateObject private var videoModel = EmbeddedMpvModel()
    @AppStorage("trackpadScrollNavigates") private var trackpadScrollNavigates = false
    @State private var toolbarVisible = false
    @State private var hideToolbarWorkItem: DispatchWorkItem?

    var body: some View {
        let showingVideo = appState.currentItem?.kind == .video

        ZStack {
            // For video, leave this clear so the Metal layer under the hosting
            // view is visible. Photos / empty state still need a black plate.
            if !showingVideo {
                Color.black
                    .ignoresSafeArea()
            }

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                // Top/bottom chrome is drawn by FloatingChrome above Metal.
                Spacer()
            }
        }
        .focusable()
        .background(navigationEventViews)
        .background(
            MouseMovementReader(
                onMove: showChrome,
                onExit: hideChrome
            )
        )
        .background(
            WindowLifecycleMonitor {
                stopAllPlayback()
            }
        )
        .background(
            DoubleClickFullscreenReader()
        )
        .background(
            WindowMouseActivityReader(
                onMove: showChrome,
                onExit: hideChrome
            )
        )
        .onAppear {
            NSApp.windows.first?.backgroundColor = .black
            NSApp.windows.first?.title = "PowerPreview \(AppVersion.marketing)"
            showChrome()
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onChange(of: appState.currentItem?.id) { _ in
            zoomState.reset()
            appState.scheduleSlideshowStep()
            NSApp.windows.first?.backgroundColor = .black
            showChrome()
        }
        .onChange(of: appState.isSlideshowEnabled) { enabled in
            if enabled {
                appState.scheduleSlideshowStep()
            } else {
                appState.cancelSlideshowStep()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .videoDidFinishPlaying)) { _ in
            appState.onVideoFinished()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewGoPrevious)) { _ in
            appState.showPrevious()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewGoNext)) { _ in
            appState.showNext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewTogglePlayback)) { _ in
            toggleVideoPlaybackIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewPointerActivity)) { _ in
            showChrome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewPointerExit)) { _ in
            hideChrome()
        }
    }

    private var navigationEventViews: some View {
        ZStack {
            KeyboardNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                onSpace: { toggleVideoPlaybackIfNeeded() }
            )

            ScrollWheelNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                allowTrackpadNavigation: trackpadScrollNavigates
            )
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let item = appState.currentItem {
            switch item.kind {
            case .image:
                ZoomableMediaView(zoomState: zoomState) {
                    ImagePreview(url: item.url)
                }
            case .video:
                VideoPreview(url: item.url, zoomState: zoomState, model: videoModel)
            }
        } else {
            EmptyStateView(
                message: appState.errorMessage ?? "Open a folder of photos and videos.",
                action: appState.openFolder
            )
        }
    }

    private var topMenuBar: some View {
        HStack(spacing: 10) {
            menuIconButton("folder", help: "Open folder or file") {
                appState.openFolder()
            }

            menuToggleButton(
                systemName: appState.isSlideshowEnabled ? "play.rectangle.fill" : "play.rectangle",
                isOn: appState.isSlideshowEnabled,
                help: "Slideshow: photos 2s, videos play through"
            ) {
                appState.setSlideshowEnabled(!appState.isSlideshowEnabled)
            }

            menuToggleButton(
                systemName: trackpadScrollNavigates ? "laptopcomputer" : "laptopcomputer.slash",
                isOn: trackpadScrollNavigates,
                help: "Trackpad scroll changes media"
            ) {
                trackpadScrollNavigates.toggle()
            }

            Spacer(minLength: 8)

            menuIconButton("chevron.left", help: "Previous") {
                appState.showPrevious()
            }
            .disabled(appState.currentIndex == 0)
            .opacity(appState.currentIndex == 0 ? 0.35 : 1)

            Text(appState.statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, maxWidth: 360)

            menuIconButton("chevron.right", help: "Next") {
                appState.showNext()
            }
            .disabled(appState.items.isEmpty || appState.currentIndex == appState.items.count - 1)
            .opacity(appState.items.isEmpty || appState.currentIndex == appState.items.count - 1 ? 0.35 : 1)

            Spacer(minLength: 8)

            menuIconButton("arrow.up.left.and.arrow.down.right", help: "Toggle fullscreen") {
                toggleFullscreen()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(.white)
    }

    private func menuIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func menuToggleButton(systemName: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func showChrome() {
        toolbarVisible = true
        hideToolbarWorkItem?.cancel()
        hideToolbarWorkItem = nil
        FloatingChrome.installIfNeeded(appState: appState)
        FloatingChrome.setVisible(true)
        FloatingChrome.layout()
        NotificationCenter.default.post(name: .powerPreviewShowVideoControls, object: nil)
    }

    private func hideChrome() {
        hideToolbarWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            toolbarVisible = false
            FloatingChrome.setVisible(false)
            NotificationCenter.default.post(name: .powerPreviewHideVideoControls, object: nil)
        }
        hideToolbarWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func showToolbarBriefly() {
        showChrome()
    }

    private func hideToolbar() {
        hideChrome()
    }

    private func stopAllPlayback() {
        NotificationCenter.default.post(name: .stopVideoPlayback, object: nil)
    }

    private func toggleVideoPlaybackIfNeeded() {
        guard appState.currentItem?.kind == .video else {
            return
        }

        NotificationCenter.default.post(name: .toggleVideoPlayback, object: nil)
    }

    private func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let droppedURL: URL?
            if let url = item as? URL {
                droppedURL = url
            } else if let data = item as? Data {
                droppedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                droppedURL = nil
            }

            guard let droppedURL else {
                return
            }

            DispatchQueue.main.async {
                appState.open(droppedURL)
            }
        }

        return true
    }
}

struct DoubleClickFullscreenReader: NSViewRepresentable {
    func makeNSView(context: Context) -> DoubleClickView {
        DoubleClickView()
    }

    func updateNSView(_ nsView: DoubleClickView, context: Context) {}
}

final class DoubleClickView: NSView {
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitor()
        }
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        // Local + global so double-click still works while the mpv window is focused.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2, let window = NSApp.keyWindow ?? NSApp.mainWindow {
                let mouse = NSEvent.mouseLocation
                if window.frame.contains(mouse) {
                    window.toggleFullScreen(nil)
                    return nil
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}

struct WindowMouseActivityReader: NSViewRepresentable {
    let onMove: () -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> WindowMouseActivityView {
        let view = WindowMouseActivityView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: WindowMouseActivityView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }
}

final class WindowMouseActivityView: NSView {
    var onMove: (() -> Void)?
    var onExit: (() -> Void)?

    private var timer: Timer?
    private var lastPoint = NSPoint.zero
    private var wasInside = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let window else { return }
        let point = NSEvent.mouseLocation
        let inside = window.frame.contains(point)

        if inside {
            if !wasInside || point != lastPoint {
                lastPoint = point
                onMove?()
            }
            wasInside = true
        } else if wasInside {
            wasInside = false
            lastPoint = .zero
            onExit?()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
