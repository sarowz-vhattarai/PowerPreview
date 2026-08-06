import SwiftUI

struct VideoPreview: View {
    let url: URL
    @ObservedObject var zoomState: MediaZoomState
    /// Shared across next/prev so we reuse one libmpv / Metal surface.
    @ObservedObject var model: EmbeddedMpvModel
    @State private var controlsVisible = false
    @State private var hideControlsWorkItem: DispatchWorkItem?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Metal is attached under the SwiftUI hosting view; this clear
                // region keeps layout + gestures while chrome stays clickable.
                Color.clear
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(MPVMetalPlayerView(model: model))
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = (value - 1) * 0.05
                                zoomState.magnify(by: delta, at: .center)
                                model.applyZoom(zoomState)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                zoomState.pan(
                                    by: CGSize(
                                        width: value.translation.width * 0.05,
                                        height: value.translation.height * 0.05
                                    ),
                                    in: proxy.size
                                )
                                model.applyZoom(zoomState)
                            }
                    )

                VStack {
                    HStack {
                        Spacer()
                        VideoFormatBadges(model: model, compact: true)
                            .padding(.top, 56)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

                if model.isBuffering {
                    ProgressView()
                        .controlSize(.large)
                        .allowsHitTesting(false)
                }
            }
        }
        .background(
            MouseMovementReader(
                onMove: showControls,
                onExit: {}
            )
        )
        .onAppear {
            model.play(url: url)
            model.applyZoom(zoomState)
            showControls()
            FloatingChrome.layout()
        }
        .onChange(of: url) { newURL in
            // Replace file on the same mpv instance — do not recreate Metal/mpv.
            model.play(url: newURL)
            model.applyZoom(zoomState)
            showControls()
            FloatingChrome.layout()
        }
        .onChange(of: zoomState.scale) { _ in
            model.applyZoom(zoomState)
        }
        .onChange(of: zoomState.offset.width) { _ in
            model.applyZoom(zoomState)
        }
        .onChange(of: zoomState.offset.height) { _ in
            model.applyZoom(zoomState)
        }
        .onDisappear {
            // Leaving video entirely (e.g. to a photo) — soft-stop, tear down on VC deinit.
            model.stop(keepingPlayer: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleVideoPlayback)) { _ in
            model.togglePlayback()
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopVideoPlayback)) { _ in
            model.stop(keepingPlayer: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewShowVideoControls)) { _ in
            showControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewHideVideoControls)) { _ in
            hideControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: .powerPreviewWindowGeometryChanged)) { _ in
            FloatingChrome.layout()
        }
    }

    private func showControls() {
        controlsVisible = true
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
    }

    private func hideControls() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        controlsVisible = false
    }
}

struct EmbeddedMpvControlOverlay: View {
    @ObservedObject var model: EmbeddedMpvModel
    @State private var scrubProgress = 0.0
    @State private var isScrubbing = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Text(model.currentTimeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubProgress : model.progress },
                    set: { newValue in
                        scrubProgress = newValue
                        if isScrubbing {
                            model.seek(to: newValue)
                        }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubProgress = model.progress
                    } else {
                        model.seek(to: scrubProgress)
                    }
                }
            )
            .disabled(!model.canSeek)

            Text(model.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)

            VideoFormatBadges(model: model, compact: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

struct VideoFormatBadges: View {
    @ObservedObject var model: EmbeddedMpvModel
    var compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            if model.is4K {
                MediaFormatBadge(
                    title: "4K",
                    tint: Color(white: 0.22),
                    compact: compact
                )
                .help("UHD / 4K resolution")
            }

            if let title = model.signalFormat.badgeTitle {
                MediaFormatBadge(
                    title: title,
                    tint: model.signalFormat.tint,
                    compact: compact
                )
                .help(badgeHelp)
            }
        }
    }

    private var badgeHelp: String {
        if model.hdrDisplayActive {
            return "\(model.signalFormat.helpText). Display EDR/HDR path active."
        }
        return model.signalFormat.helpText
    }
}
