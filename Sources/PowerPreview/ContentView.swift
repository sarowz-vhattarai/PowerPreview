import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var zoomState = MediaZoomState()
    @StateObject private var playback = PlaybackSession.shared
    @AppStorage("trackpadScrollNavigates") private var trackpadScrollNavigates = false
    @State private var dropTargeted = false
    @State private var isFullscreen = false
    @State private var isSlideshow = false
    @State private var slideshowPaused = false
    @State private var slideshowTask: Task<Void, Never>?
    @State private var topBarHovered = false

    private let stage = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let slideshowImageDuration: UInt64 = 4_000_000_000

    private var showsLowerBar: Bool {
        !isFullscreen && appState.currentItem != nil
    }

    var body: some View {
        ZStack {
            stage.ignoresSafeArea()

            VStack(spacing: 0) {
                if !isFullscreen {
                    topBar
                }

                stageContent

                if showsLowerBar {
                    footer
                    if !appState.items.isEmpty {
                        FilmstripView(
                            items: appState.items,
                            currentIndex: appState.currentIndex,
                            onSelect: appState.select
                        )
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: showsLowerBar)
        }
        .overlay(alignment: .top) {
            if isFullscreen {
                ZStack(alignment: .top) {
                    if topBarHovered {
                        topBar
                            .frame(maxWidth: .infinity)
                            .background(.black.opacity(0.72))
                            .transition(.opacity)
                    }

                    TopHoverReveal(isHovering: $topBarHovered)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .animation(.easeOut(duration: 0.16), value: topBarHovered)
            }
        }
        .background(navigationEventViews)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .onOpenURL { url in
            appState.open(url)
            MainWindowMarker.focusExistingWindow()
        }
        .onChange(of: appState.currentItem?.id) { _ in
            zoomState.reset()
            syncWindowTitle()
            armSlideshow()
        }
        .onChange(of: playback.endCount) { _ in
            guard isSlideshow, !slideshowPaused else {
                return
            }
            appState.showNextWrapping()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard isMainWindow(note.object) else { return }
            isFullscreen = true
            topBarHovered = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard isMainWindow(note.object) else { return }
            isFullscreen = false
            topBarHovered = false
            zoomState.reset()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSlideshow)) { _ in
            toggleSlideshow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFullScreen)) { _ in
            toggleFullscreen()
        }
        .onAppear(perform: syncWindowTitle)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
    }

    private var navigationEventViews: some View {
        ZStack {
            KeyboardNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                onSpace: handleSpace,
                onEscape: handleEscape
            )

            ScrollWheelNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                allowTrackpadNavigation: trackpadScrollNavigates
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: appState.openFolder) {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(ChromeButtonStyle())
            .help("Open a folder or files")
            .padding(.leading, 68)

            Text(appState.folderURL?.lastPathComponent ?? "No folder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 12)

            if zoomState.scale > 1 {
                Button(action: zoomState.reset) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(ChromeButtonStyle())
                .help("Fit to window")
            }

            Button(action: toggleSlideshow) {
                Image(systemName: isSlideshow ? "stop.fill" : "play.rectangle.on.rectangle")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(ChromeButtonStyle(isOn: isSlideshow))
            .disabled(appState.items.isEmpty)
            .help(isSlideshow ? "Stop slideshow" : "Play a slideshow")

            Button(action: toggleFullscreen) {
                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(ChromeButtonStyle(isOn: isFullscreen))
            .help(isFullscreen ? "Leave full screen" : "Full screen")

            Button {
                trackpadScrollNavigates.toggle()
            } label: {
                Image(systemName: trackpadScrollNavigates ? "hand.point.up.left.fill" : "hand.draw")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(ChromeButtonStyle(isOn: trackpadScrollNavigates))
            .help(trackpadScrollNavigates ? "Trackpad scrolls to the next file" : "Trackpad pans a zoomed photo")
        }
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var stageContent: some View {
        ZStack {
            if let item = appState.currentItem {
                ZoomableMediaView(zoomState: zoomState, onDoubleClick: handleDoubleClick) {
                    switch item.kind {
                    case .image:
                        ImagePreview(url: item.url)
                    case .video:
                        VideoPreview(url: item.url)
                    }
                }

                if let failure = playback.failureMessage {
                    Text(failure)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(16)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } else {
                EmptyStateView(
                    message: appState.errorMessage ?? "Open a folder, or drop photos and videos here.",
                    isLoading: appState.isLoading,
                    action: appState.openFolder
                )
            }

            if appState.isLoading && appState.currentItem != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if playback.isVideo {
                HStack(spacing: 12) {
                    Button(action: playback.toggle) {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(ChromeButtonStyle())

                    Text(playback.currentTimeText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 58, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { playback.progress },
                            set: { playback.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .tint(.white)

                    Text(playback.durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 64, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Button(action: appState.showPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ChromeButtonStyle())
                .disabled(appState.currentIndex == 0)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appState.currentItem?.displayName ?? "")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(appState.positionText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 8)

                Button(action: appState.showNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ChromeButtonStyle())
                .disabled(appState.items.isEmpty || appState.currentIndex == appState.items.count - 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func toggleSlideshow() {
        if isSlideshow {
            stopSlideshow()
            return
        }

        guard appState.currentItem != nil else {
            return
        }

        isSlideshow = true
        slideshowPaused = false
        if !isFullscreen {
            toggleFullscreen()
        }
        if appState.currentItem?.kind == .video, !playback.isPlaying {
            playback.toggle()
        }
        armSlideshow()
    }

    private func stopSlideshow() {
        isSlideshow = false
        slideshowPaused = false
        slideshowTask?.cancel()
        slideshowTask = nil
    }

    private func armSlideshow() {
        slideshowTask?.cancel()
        guard isSlideshow, !slideshowPaused, appState.currentItem?.kind == .image else {
            return
        }

        slideshowTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: slideshowImageDuration)
            guard !Task.isCancelled, isSlideshow, !slideshowPaused else {
                return
            }
            appState.showNextWrapping()
        }
    }

    private func handleSpace() {
        if isSlideshow {
            slideshowPaused.toggle()
            if appState.currentItem?.kind == .video {
                playback.toggle()
            }
            if slideshowPaused {
                slideshowTask?.cancel()
            } else {
                armSlideshow()
            }
            return
        }

        playback.toggle()
    }

    private func handleEscape() {
        if isSlideshow {
            stopSlideshow()
        }
        if isFullscreen {
            toggleFullscreen()
        } else {
            zoomState.reset()
        }
    }

    private func handleDoubleClick(_ anchor: UnitPoint) {
        if isFullscreen {
            withAnimation(.easeInOut(duration: 0.22)) {
                zoomState.toggleZoom(at: anchor)
            }
        } else {
            toggleFullscreen()
        }
    }

    private func toggleFullscreen() {
        NSApp.windows.first { $0.identifier == MainWindowMarker.identifier }?.toggleFullScreen(nil)
    }

    private func isMainWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else {
            return false
        }
        return window.identifier == MainWindowMarker.identifier
    }

    private func syncWindowTitle() {
        NSApp.windows.first { $0.identifier == MainWindowMarker.identifier }?.title = appState.windowTitle
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let urls = FileDropCollector()

        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            appState.open(urls.items)
        }

        return true
    }
}

private final class FileDropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var items: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

struct TopHoverReveal: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TopHoverView {
        let view = TopHoverView()
        view.onHover = { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: TopHoverView, context: Context) {
        nsView.onHover = { hovering in
            if isHovering != hovering {
                isHovering = hovering
            }
        }
    }
}

final class TopHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

struct ChromeButtonStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.55 : 0.92))
            .padding(7)
            .background(
                Circle().fill(isOn ? Color.white.opacity(0.22) : Color.white.opacity(configuration.isPressed ? 0.08 : 0.12))
            )
    }
}
