import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var zoomState = MediaZoomState()
    @AppStorage("trackpadScrollNavigates") private var trackpadScrollNavigates = false
    @State private var toolbarVisible = false
    @State private var hideToolbarWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer()

                if toolbarVisible {
                    toolbar
                        .transition(.opacity)
                }
            }
        }
        .focusable()
        .background(navigationEventViews)
        .background(
            MouseMovementReader(
                onMove: showToolbarBriefly,
                onExit: hideToolbar
            )
        )
        .background(
            WindowLifecycleMonitor {
                stopAllPlayback()
            }
        )
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onOpenURL { url in
            appState.open(url)
        }
        .onChange(of: appState.currentItem?.id) { _ in
            stopAllPlayback()
            zoomState.reset()
        }
    }

    private var navigationEventViews: some View {
        ZStack {
            KeyboardNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                onSpace: { toggleVideoPlaybackIfNeeded() }
            )

            ScrollWheelNavigationView(
                onPrevious: { appState.showPrevious() },
                onNext: { appState.showNext() },
                allowTrackpadNavigation: trackpadScrollNavigates
            )
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let item = appState.currentItem {
            ZoomableMediaView(zoomState: zoomState) {
                switch item.kind {
                case .image:
                    ImagePreview(url: item.url)
                case .video:
                    VideoPreview(url: item.url)
                }
            }
        } else {
            EmptyStateView(
                message: appState.errorMessage ?? "Open a folder of photos and videos.",
                action: appState.openFolder
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Button("Open Folder...") {
                appState.openFolder()
            }
                .keyboardShortcut("o", modifiers: [.command])

            Toggle("Trackpad Next", isOn: $trackpadScrollNavigates)
                .toggleStyle(.checkbox)
                .help("When off, trackpad scrolling pans zoomed media. Mouse wheel navigation still works.")

            Spacer()

            Button("Previous") {
                appState.showPrevious()
            }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(appState.currentIndex == 0)

            Text(appState.statusText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 280)

            Button("Next") {
                appState.showNext()
            }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(appState.items.isEmpty || appState.currentIndex == appState.items.count - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func showToolbarBriefly() {
        toolbarVisible = true
        hideToolbarWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            toolbarVisible = false
        }

        hideToolbarWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func hideToolbar() {
        hideToolbarWorkItem?.cancel()
        hideToolbarWorkItem = nil
        toolbarVisible = false
    }

    private func stopAllPlayback() {
        NotificationCenter.default.post(name: .stopVideoPlayback, object: nil)
    }

    private func toggleVideoPlaybackIfNeeded() {
        guard appState.currentItem?.kind == .video else {
            return
        }

        NotificationCenter.default.post(name: .toggleVideoPlayback, object: nil)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let droppedURL: URL?
            if let url = item as? URL {
                droppedURL = url
            } else if let data = item as? Data {
                droppedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                droppedURL = nil
            }

            guard let droppedURL else {
                return
            }

            DispatchQueue.main.async {
                appState.open(droppedURL)
            }
        }

        return true
    }
}
