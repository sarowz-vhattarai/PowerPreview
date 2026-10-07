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

    func toggleZoom(at anchor: UnitPoint) {
        if scale > 1 {
            reset()
            return
        }

        self.anchor = anchor
        offset = .zero
        scale = 2.6
    }

    func reset() {
        scale = 1
        anchor = .center
        offset = .zero
    }
}

struct ZoomableMediaView<Content: View>: View {
    @ObservedObject var zoomState: MediaZoomState
    let onDoubleClick: (UnitPoint) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                content
                    .scaleEffect(zoomState.scale, anchor: zoomState.anchor)
                    .offset(zoomState.offset)

                ZoomGestureReader(
                    onMagnify: { delta, anchor in
                        zoomState.magnify(by: delta, at: anchor)
                    },
                    onDoubleClick: onDoubleClick,
                    onPan: { delta in
                        zoomState.pan(by: delta, in: proxy.size)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
        }
    }
}

struct ZoomGestureReader: NSViewRepresentable {
    let onMagnify: (CGFloat, UnitPoint) -> Void
    let onDoubleClick: (UnitPoint) -> Void
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> ZoomGestureView {
        let view = ZoomGestureView()
        view.onMagnify = onMagnify
        view.onDoubleClick = onDoubleClick
        view.onPan = onPan
        return view
    }

    func updateNSView(_ nsView: ZoomGestureView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onDoubleClick = onDoubleClick
        nsView.onPan = onPan
    }
}

final class ZoomGestureView: NSView {
    var onMagnify: ((CGFloat, UnitPoint) -> Void)?
    var onDoubleClick: ((UnitPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?

    override var acceptsFirstResponder: Bool {
        false
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification, unitPoint(for: event))
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?(unitPoint(for: event))
            return
        }

        super.mouseDown(with: event)
    }

    private func unitPoint(for event: NSEvent) -> UnitPoint {
        let location = convert(event.locationInWindow, from: nil)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let y = bounds.height - location.y
        return UnitPoint(
            x: min(max(location.x / width, 0), 1),
            y: min(max(y / height, 0), 1)
        )
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        onPan?(CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
    }
}
