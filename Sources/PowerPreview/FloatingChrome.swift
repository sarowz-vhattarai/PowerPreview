import AppKit
import SwiftUI

/// Shared playback HUD values so the floating AppKit chrome can render the scrubber
/// even when Metal sits under the main SwiftUI hosting view.
@MainActor
final class PlaybackHUDState: ObservableObject {
    static let shared = PlaybackHUDState()

    @Published var isActiveVideo = false
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var currentTimeText = "0:00"
    @Published var durationText = "0:00"
    @Published var canSeek = false

    var seekHandler: ((Double) -> Void)?
    var toggleHandler: (() -> Void)?

    func reset() {
        isActiveVideo = false
        isPlaying = false
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
        canSeek = false
        seekHandler = nil
        toggleHandler = nil
    }
}

/// NSHostingView that only captures hits on real controls; empty areas pass through
/// to the window underneath (Metal / main SwiftUI).
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === self { return nil }
        return hit
    }
}

/// Transparent child panel so chrome stays above SwiftUI and receives real clicks.
final class ChromePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws hover chrome in a dedicated child window above Metal + SwiftUI.
@MainActor
enum FloatingChrome {
    private static var panel: ChromePanel?
    private static var overlay: PassThroughHostingView<FloatingChromeRoot>?
    private static let model = FloatingChromeModel()
    private static var resizeObservers: [NSObjectProtocol] = []

    /// Exposed so Metal attach can skip this view when finding the main hosting root.
    static var overlayView: NSView? { overlay }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            window !== panel
                && !(window is ChromePanel)
                && window.isVisible
                && window.frame.height > 100
                && window.contentView != nil
        }
    }

    static func installIfNeeded(appState: AppState) {
        model.appState = appState
        guard panel == nil else {
            layout()
            return
        }
        guard let window = mainWindow() else { return }

        let host = PassThroughHostingView(
            rootView: FloatingChromeRoot(model: model, hud: PlaybackHUDState.shared)
        )
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = ChromePanel(
            contentRect: NSRect(origin: .zero, size: window.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        self.panel = panel
        overlay = host
        installWindowObservers(for: window)
        layout()
    }

    static func layout() {
        guard let panel, let overlay, let window = mainWindow(),
              let content = window.contentView else { return }

        let rectInWindow = content.convert(content.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        panel.setFrame(screenRect, display: true)
        overlay.frame = CGRect(origin: .zero, size: screenRect.size)

        if panel.parent !== window {
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    static func setVisible(_ visible: Bool) {
        if let appState = model.appState {
            installIfNeeded(appState: appState)
        }
        layout()
        withAnimation(.easeInOut(duration: 0.12)) {
            model.chromeVisible = visible
        }
        // Hidden chrome → full click-through so video gestures still work.
        panel?.ignoresMouseEvents = !visible
    }

    static func teardown() {
        for observer in resizeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        resizeObservers.removeAll()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        overlay = nil
        model.chromeVisible = false
    }

    private static func installWindowObservers(for window: NSWindow) {
        guard resizeObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didMoveNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: window, queue: .main) { _ in
                Task { @MainActor in
                    FloatingChrome.layout()
                    NotificationCenter.default.post(name: .powerPreviewWindowGeometryChanged, object: nil)
                }
            }
            resizeObservers.append(token)
        }
    }
}

@MainActor
final class FloatingChromeModel: ObservableObject {
    @Published var chromeVisible = false
    weak var appState: AppState?
}

private struct FloatingChromeRoot: View {
    @ObservedObject var model: FloatingChromeModel
    @ObservedObject var hud: PlaybackHUDState
    @AppStorage("trackpadScrollNavigates") private var trackpadScrollNavigates = false

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)

            if model.chromeVisible, let appState = model.appState {
                VStack(spacing: 0) {
                    floatingToolbar(appState: appState)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                        .allowsHitTesting(true)

                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    if hud.isActiveVideo {
                        floatingScrubber
                            .padding(.horizontal, 18)
                            .padding(.bottom, 16)
                            .allowsHitTesting(true)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(model.chromeVisible)
    }

    private func floatingToolbar(appState: AppState) -> some View {
        FloatingToolbarBody(appState: appState, trackpadScrollNavigates: $trackpadScrollNavigates)
    }

    private var floatingScrubber: some View {
        HStack(spacing: 12) {
            Button {
                hud.toggleHandler?()
            } label: {
                Image(systemName: hud.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Text(hud.currentTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { hud.progress },
                    set: { hud.seekHandler?($0) }
                ),
                in: 0...1
            )
            .disabled(!hud.canSeek)

            Text(hud.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Separate view so `@ObservedObject appState` refreshes status / index.
private struct FloatingToolbarBody: View {
    @ObservedObject var appState: AppState
    @Binding var trackpadScrollNavigates: Bool

    var body: some View {
        HStack(spacing: 10) {
            chromeButton("folder") { appState.openFolder() }
            chromeToggle(
                systemName: appState.isSlideshowEnabled ? "play.rectangle.fill" : "play.rectangle",
                isOn: appState.isSlideshowEnabled
            ) {
                appState.setSlideshowEnabled(!appState.isSlideshowEnabled)
            }
            chromeToggle(
                systemName: trackpadScrollNavigates ? "laptopcomputer" : "laptopcomputer.slash",
                isOn: trackpadScrollNavigates
            ) {
                trackpadScrollNavigates.toggle()
            }

            Spacer(minLength: 8)

            chromeButton("chevron.left") { appState.showPrevious() }
                .opacity(appState.currentIndex == 0 ? 0.35 : 1)

            Text(appState.statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 160, maxWidth: 360)

            chromeButton("chevron.right") { appState.showNext() }
                .opacity(appState.items.isEmpty || appState.currentIndex == appState.items.count - 1 ? 0.35 : 1)

            Spacer(minLength: 8)

            chromeButton("arrow.up.left.and.arrow.down.right") {
                let target = FloatingChrome.mainWindowForFullscreen() ?? NSApp.keyWindow
                target?.toggleFullScreen(nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chromeButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chromeToggle(systemName: String, isOn: Bool, action: @escaping () -> Void) -> some View {
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
    }
}

extension FloatingChrome {
    /// Fullscreen must target the media window, not the chrome panel.
    @MainActor
    static func mainWindowForFullscreen() -> NSWindow? {
        NSApp.windows.first { window in
            !(window is ChromePanel) && window.isVisible && window.frame.height > 100
        }
    }
}
