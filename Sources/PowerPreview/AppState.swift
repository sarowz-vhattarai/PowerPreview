import AppKit
import Combine
import Foundation
import PowerPreviewCore

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [MediaItem] = []
    @Published var currentIndex = 0
    @Published var errorMessage: String?
    @Published var isSlideshowEnabled = false

    private let scanner: MediaScanner
    private var slideshowTask: Task<Void, Never>?
    private var siblingScanTask: Task<Void, Never>?

    var currentItem: MediaItem? {
        guard items.indices.contains(currentIndex) else {
            return nil
        }

        return items[currentIndex]
    }

    var statusText: String {
        guard let currentItem else {
            return "Open a folder to start previewing media"
        }

        return "\(currentItem.displayName)  \(currentIndex + 1) of \(items.count)"
    }

    nonisolated init(scanner: MediaScanner = MediaScanner()) {
        self.scanner = scanner
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    func open(_ url: URL) {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL

        // Same file already showing — do nothing (prevents dual decode / freeze).
        if let current = currentItem?.url, Self.sameFile(current, resolved) {
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue {
            loadFolder(resolved)
        } else {
            loadFile(resolved)
        }
    }

    func loadFolder(_ url: URL) {
        siblingScanTask?.cancel()
        do {
            let scannedItems = try scanner.scan(folder: url)
            folderURL = url
            items = scannedItems
            currentIndex = 0
            errorMessage = scannedItems.isEmpty ? "No supported photos or videos found in this folder." : nil
        } catch {
            folderURL = nil
            items = []
            currentIndex = 0
            errorMessage = "Could not open folder: \(error.localizedDescription)"
        }
    }

    func loadFile(_ url: URL) {
        siblingScanTask?.cancel()

        guard let kind = SupportedMedia.kind(for: url) else {
            folderURL = nil
            items = []
            currentIndex = 0
            errorMessage = "Unsupported media file: \(url.lastPathComponent)"
            return
        }

        // Always start playback on the chosen file immediately.
        let parentFolder = url.deletingLastPathComponent()
        folderURL = parentFolder
        items = [MediaItem(url: url, kind: kind)]
        currentIndex = 0
        errorMessage = nil
        objectWillChange.send()

        // Keep next/prev browsing for photos, small clips, and compact media folders.
        // Skip only for huge movies sitting in giant folders (e.g. Downloads).
        guard shouldScanSiblings(for: url, kind: kind) else {
            return
        }

        let target = url
        siblingScanTask = Task {
            let scannedItems = (try? scanner.scan(folder: parentFolder)) ?? []
            guard !Task.isCancelled, !scannedItems.isEmpty else { return }

            await MainActor.run {
                guard self.folderURL == parentFolder else { return }
                let previous = self.currentItem?.url
                self.items = scannedItems
                if let previous,
                   let idx = scannedItems.firstIndex(where: { Self.sameFile($0.url, previous) }) {
                    self.currentIndex = idx
                } else if let idx = scannedItems.firstIndex(where: { Self.sameFile($0.url, target) }) {
                    self.currentIndex = idx
                } else {
                    self.currentIndex = min(self.currentIndex, max(scannedItems.count - 1, 0))
                }
            }
        }
    }

    /// Photos always. Videos scan when the file is small OR the parent folder is compact.
    private func shouldScanSiblings(for url: URL, kind: MediaKind) -> Bool {
        if kind == .image {
            return true
        }

        let parent = url.deletingLastPathComponent()
        if isCompactMediaFolder(parent) {
            return true
        }

        let size: Int64
        if let number = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber {
            size = number.int64Value
        } else {
            return true
        }

        return size < Self.siblingScanMaxBytes
    }

    /// Folders with a modest entry count are treated as browseable albums.
    private func isCompactMediaFolder(_ url: URL) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return entries.count > 0 && entries.count <= 250
    }

    /// ~200 MB — short clips stay browsable even inside huge folders like Downloads.
    private static let siblingScanMaxBytes: Int64 = 200 * 1024 * 1024

    func showNext() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = min(currentIndex + 1, items.count - 1)
    }

    func showPrevious() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = max(currentIndex - 1, 0)
    }

    func setSlideshowEnabled(_ enabled: Bool) {
        isSlideshowEnabled = enabled
        if enabled {
            scheduleSlideshowStep()
        } else {
            cancelSlideshowStep()
        }
    }

    func scheduleSlideshowStep() {
        cancelSlideshowStep()

        guard isSlideshowEnabled, let item = currentItem, item.kind == .image else {
            return
        }

        slideshowTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, isSlideshowEnabled else {
                return
            }

            advanceSlideshow()
        }
    }

    func onVideoFinished() {
        guard isSlideshowEnabled else {
            return
        }

        advanceSlideshow()
    }

    func cancelSlideshowStep() {
        slideshowTask?.cancel()
        slideshowTask = nil
    }

    private func advanceSlideshow() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = currentIndex >= items.count - 1 ? 0 : currentIndex + 1
    }

    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.resolvingSymlinksInPath().standardizedFileURL
            == rhs.resolvingSymlinksInPath().standardizedFileURL
    }
}
