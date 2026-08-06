import AppKit
import Foundation

extension Notification.Name {
    static let powerPreviewGoPrevious = Notification.Name("PowerPreview.goPrevious")
    static let powerPreviewGoNext = Notification.Name("PowerPreview.goNext")
    static let powerPreviewTogglePlayback = Notification.Name("PowerPreview.togglePlaybackFromKey")
    static let powerPreviewPointerActivity = Notification.Name("PowerPreview.pointerActivity")
    static let powerPreviewPointerExit = Notification.Name("PowerPreview.pointerExit")
}

/// App-wide key/mouse bridge that does not depend on SwiftUI first-responder.
/// Metal reparenting was stealing key focus and breaking arrow navigation / hover.
@MainActor
final class WindowEventBridge {
    static let shared = WindowEventBridge()

    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var pollTimer: Timer?
    private var pointerWasInside = false

    private init() {}

    func start() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }

            switch event.keyCode {
            case 123: // left arrow
                NotificationCenter.default.post(name: .powerPreviewGoPrevious, object: nil)
                return nil
            case 124: // right arrow
                NotificationCenter.default.post(name: .powerPreviewGoNext, object: nil)
                return nil
            case 49: // space
                NotificationCenter.default.post(name: .powerPreviewTogglePlayback, object: nil)
                return nil
            default:
                return event
            }
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            DispatchQueue.main.async {
                WindowEventBridge.shared.handlePointerSample()
            }
            return event
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            DispatchQueue.main.async {
                WindowEventBridge.shared.handlePointerSample()
            }
        }
    }

    func stop() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func handlePointerSample() {
        let point = NSEvent.mouseLocation
        let inside = NSApp.windows.contains { window in
            window.isVisible && window.frame.height > 100 && window.frame.contains(point)
        }

        if inside {
            NotificationCenter.default.post(name: .powerPreviewPointerActivity, object: nil)
            pointerWasInside = true
        } else if pointerWasInside {
            pointerWasInside = false
            NotificationCenter.default.post(name: .powerPreviewPointerExit, object: nil)
        }
    }
}
