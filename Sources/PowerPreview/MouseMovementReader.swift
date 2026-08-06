import AppKit
import SwiftUI

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
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self, let window = self.window else {
                return event
            }

            // Prefer window-frame hit testing — more reliable than 0×0 background views.
            let mouse = NSEvent.mouseLocation
            let inside = window.frame.contains(mouse)

            if inside {
                if mouse != self.lastMouseLocation {
                    self.lastMouseLocation = mouse
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
