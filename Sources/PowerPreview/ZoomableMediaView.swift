import AppKit
import SwiftUI

final class MediaZoomState: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var anchor: UnitPoint = .center
    @Published var offset: CGSize = .zero

    func magnify(by delta: CGFloat, at anchor: UnitPoint) {
        self.anchor = anchor
        scale = min(max(scale + delta, 1), 6)

        if scale == 1 {
            offset = .zero
        }
    }

    func pan(by delta: CGSize, in containerSize: CGSize) {
        guard scale > 1 else {
            offset = .zero
            return
        }

        let maxX = containerSize.width * (scale - 1) / 2
        let maxY = containerSize.height * (scale - 1) / 2
        offset = CGSize(
            width: min(max(offset.width + delta.width, -maxX), maxX),
            height: min(max(offset.height + delta.height, -maxY), maxY)
        )
    }

    func reset() {
        scale = 1
        anchor = .center
        offset = .zero
    }
}

/// Used for photos. Restores trackpad pinch/pan via a transparent AppKit gesture
/// view (safe here because there is no Metal layer underneath).
struct ZoomableMediaView<Content: View>: View {
    @ObservedObject var zoomState: MediaZoomState
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(zoomState.scale, anchor: zoomState.anchor)
                    .offset(zoomState.offset)

                ZoomGestureReader(
                    onMagnify: { delta, location in
                        let anchor = UnitPoint(
                            x: max(0, min(1, location.x / max(proxy.size.width, 1))),
                            y: max(0, min(1, location.y / max(proxy.size.height, 1)))
                        )
                        zoomState.magnify(by: delta, at: anchor)
                    },
                    onPan: { delta in
                        zoomState.pan(by: delta, in: proxy.size)
                    }
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

struct ZoomGestureReader: NSViewRepresentable {
    let onMagnify: (CGFloat, CGPoint) -> Void
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> ZoomGestureView {
        let view = ZoomGestureView()
        view.onMagnify = onMagnify
        view.onPan = onPan
        return view
    }

    func updateNSView(_ nsView: ZoomGestureView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onPan = onPan
    }
}

final class ZoomGestureView: NSView {
    var onMagnify: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Participate in magnify/scroll but stay visually transparent.
        self
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification, convert(event.locationInWindow, from: nil))
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        onPan?(CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
    }
}
