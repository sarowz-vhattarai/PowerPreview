import AppKit
import SwiftUI

struct KeyboardNavigationView: NSViewRepresentable {
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSpace: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onSpace = onSpace

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.onPrevious = onPrevious
        nsView.onNext = onNext
        nsView.onSpace = onSpace

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyCatcherView: NSView {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onSpace: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            onPrevious?()
        case 124:
            onNext?()
        case 49:
            onSpace?()
        default:
            super.keyDown(with: event)
        }
    }
}
