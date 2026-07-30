import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var zoomState = MediaZoomState()
    @AppStorage("trackpadScrollNavigates") private var trackpadScrollNavigates = false
    @State private var toolbarVisible = false
    @State private var hideToolbarWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                if toolbarVisible {
                    topMenuBar
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .focusable()
        .background(navigationEventViews)
        .background(
            MouseMovementReader(
                onMove: showToolbarBriefly,
                onExit: hideToolbar
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
                onMove: showToolbarBriefly,
                onExit: hideToolbar
            )
        )
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onOpenURL { url in
            appState.open(url)
        }
        .onChange(of: appState.currentItem?.id) { _ in
            stopAllPlayback()
            zoomState.reset()
            appState.scheduleSlideshowStep()
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
                VideoPreview(url: item.url, zoomState: zoomState)
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
                .foregroundStyle(.primary.opacity(0.9))
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
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func menuIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
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
                .foregroundStyle(isOn ? Color.accentColor : Color.primary.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func showToolbarBriefly() {
        toolbarVisible = true
        hideToolbarWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            toolbarVisible = false
        }

        hideToolbarWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func hideToolbar() {
        hideToolbarWorkItem?.cancel()
        hideToolbarWorkItem = nil
        toolbarVisible = false
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
            if point != lastPoint {
                lastPoint = point
                onMove?()
            }
            wasInside = true
        } else if wasInside {
            wasInside = false
            onExit?()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
