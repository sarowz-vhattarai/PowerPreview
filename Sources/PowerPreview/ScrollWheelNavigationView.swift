import AppKit
import SwiftUI

struct ScrollWheelNavigationView: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void
    let allowTrackpadNavigation: Bool

    func makeNSView(context: Context) -> ScrollWheelCatcherView {
        let view = ScrollWheelCatcherView()
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.allowTrackpadNavigation = allowTrackpadNavigation
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCatcherView, context: Context) {
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.allowTrackpadNavigation = allowTrackpadNavigation
    }
}

final class ScrollWheelCatcherView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var allowTrackpadNavigation = false

    private var lastNavigationDate = Date.distantPast
    private var scrollMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installScrollMonitorIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        handleScroll(event)
    }

    private func installScrollMonitorIfNeeded() {
        guard scrollMonitor == nil else {
            return
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldHandle(event) else {
                return event
            }

            self.handleScroll(event)
            return nil
        }
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard event.window != nil else {
            return false
        }

        if event.hasPreciseScrollingDeltas && !allowTrackpadNavigation {
            return false
        }

        if let window, event.window === window {
            return true
        }

        return event.window?.isMainWindow == true || event.window === NSApp.keyWindow
    }

    private func handleScroll(_ event: NSEvent) {
        let verticalDelta = dominantVerticalDelta(from: event)
        guard verticalDelta != 0 else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastNavigationDate) > 0.18 else {
            return
        }

        if verticalDelta < 0 {
            onNext?()
        } else {
            onPrevious?()
        }

        NSCursor.setHiddenUntilMouseMoves(true)
        lastNavigationDate = now
    }

    private func dominantVerticalDelta(from event: NSEvent) -> CGFloat {
        let scrollY = event.scrollingDeltaY
        let scrollX = event.scrollingDeltaX

        if abs(scrollY) > 0, abs(scrollY) >= abs(scrollX) {
            return scrollY
        }

        let lineY = CGFloat(event.deltaY)
        let lineX = CGFloat(event.deltaX)

        if abs(lineY) > 0, abs(lineY) >= abs(lineX) {
            return lineY
        }

        return 0
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        removeScrollMonitor()
    }
}
