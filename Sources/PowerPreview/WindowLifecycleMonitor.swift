import AppKit
import SwiftUI

struct WindowLifecycleMonitor: NSViewRepresentable {
    let onSuspend: () -> Void

    func makeNSView(context: Context) -> WindowLifecycleView {
        let view = WindowLifecycleView()
        view.onSuspend = onSuspend
        return view
    }

    func updateNSView(_ nsView: WindowLifecycleView, context: Context) {
        nsView.onSuspend = onSuspend
    }
}

final class WindowLifecycleView: NSView {
    var onSuspend: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()

        guard let window else {
            return
        }

        let names: [Notification.Name] = [
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification
        ]

        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onSuspend?()
            }
            observers.append(observer)
        }
    }

    deinit {
        removeObservers()
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
