import AppKit
import SwiftUI

@MainActor
enum AppModel {
    static let shared = AppState()
}

@main
struct PowerPreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Single named window — WindowGroup was spawning a second empty player on open.
        Window("PowerPreview \(AppVersion.display)", id: "main") {
            ContentView()
                .environmentObject(AppModel.shared)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    appDelegate.noteMainWindowAppeared()
                }
                .onOpenURL { url in
                    appDelegate.openMedia(url)
                }
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    AppModel.shared.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didConsumeLaunchArguments = false
    private var lastOpenKey: String?
    private var lastOpenAt: TimeInterval = 0
    private var mainViewReady = false
    private var pendingOpenURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowEventBridge.shared.start()
        consumeLaunchOpenDocumentsEvent()
        openLaunchArgumentsIfNeeded()

        // Safety: if the SwiftUI window never signals ready, still open the file.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if self.pendingOpenURL != nil {
                self.mainViewReady = true
                self.flushPendingOpen()
            }
            self.centerMainWindowIfNeeded()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        openMedia(url)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openMedia(URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            centerMainWindowIfNeeded()
        }
        return true
    }

    func noteMainWindowAppeared() {
        mainViewReady = true
        Task { @MainActor in
            self.centerMainWindowIfNeeded()
            self.flushPendingOpen()
        }
    }

    @discardableResult
    func openMedia(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let key = resolved.path
        let now = ProcessInfo.processInfo.systemUptime
        if key == lastOpenKey, now - lastOpenAt < 2.0 {
            return true
        }
        lastOpenKey = key
        lastOpenAt = now

        // Hold the path until ContentView is in the hierarchy and observing AppState.
        // Opening earlier updated state while the UI still showed the empty screen.
        if !mainViewReady {
            pendingOpenURL = resolved
            return true
        }

        applyOpen(resolved)
        return true
    }

    private func flushPendingOpen() {
        guard let url = pendingOpenURL else { return }
        pendingOpenURL = nil
        applyOpen(url)
    }

    private func applyOpen(_ url: URL) {
        Task { @MainActor in
            AppModel.shared.open(url)
            self.centerMainWindowIfNeeded()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func consumeLaunchOpenDocumentsEvent() {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenDocuments),
              let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            return
        }

        for index in 1...max(list.numberOfItems, 0) {
            guard let item = list.atIndex(index) else { continue }
            if let url = item.fileURLValue {
                openMedia(url)
            } else if let path = item.stringValue {
                openMedia(URL(fileURLWithPath: path))
            }
        }
    }

    private func openLaunchArgumentsIfNeeded() {
        guard !didConsumeLaunchArguments else { return }
        didConsumeLaunchArguments = true

        for arg in CommandLine.arguments.dropFirst() {
            if arg.hasPrefix("-") { continue }
            let url = URL(fileURLWithPath: arg)
            if FileManager.default.fileExists(atPath: url.path) {
                openMedia(url)
                break
            }
        }
    }

    @MainActor
    private func centerMainWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 100 })
                ?? NSApp.keyWindow
                ?? NSApp.windows.first,
              let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        var frame = window.frame
        let intersects = frame.intersects(visible.insetBy(dx: 40, dy: 40))
        if !intersects || frame.width < 200 || frame.height < 200 {
            frame.size = CGSize(width: max(frame.width, 900), height: max(frame.height, 548))
            frame.origin.x = visible.midX - frame.width / 2
            frame.origin.y = visible.midY - frame.height / 2
            window.setFrame(frame, display: true)
        }
        window.makeKeyAndOrderFront(nil)
    }
}
