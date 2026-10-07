import AppKit
import SwiftUI

@main
struct PowerPreviewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        Window("PowerPreview", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
                .background(MainWindowMarker())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    AppState.shared.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Playback") {
                Button("Previous") {
                    AppState.shared.showPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Next") {
                    AppState.shared.showNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button("Play or Pause") {
                    PlaybackSession.shared.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Slideshow") {
                    NotificationCenter.default.post(name: .toggleSlideshow, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Enter Full Screen") {
                    NotificationCenter.default.post(name: .toggleFullScreen, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async {
            AppState.shared.open(urls)
            MainWindowMarker.focusExistingWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowMarker.focusExistingWindow()
        }
        return true
    }
}

struct MainWindowMarker: NSViewRepresentable {
    static let identifier = NSUserInterfaceItemIdentifier("powerpreview.main")

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            Self.claim(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.claim(nsView.window)
        }
    }

    static func claim(_ window: NSWindow?) {
        guard let window, !(window is NSPanel) else {
            return
        }

        window.identifier = identifier
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
    }

    static func focusExistingWindow() {
        NSApp.windows.first { $0.identifier == identifier || $0.canBecomeMain && !($0 is NSPanel) }?
            .makeKeyAndOrderFront(nil)
    }
}
