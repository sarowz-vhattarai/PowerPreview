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

    private let scanner: MediaScanner

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

    init(scanner: MediaScanner = MediaScanner()) {
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
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            loadFolder(url)
        } else {
            loadFile(url)
        }
    }

    func loadFolder(_ url: URL) {
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
        guard SupportedMedia.kind(for: url) != nil else {
            folderURL = nil
            items = []
            currentIndex = 0
            errorMessage = "Unsupported media file: \(url.lastPathComponent)"
            return
        }

        let parentFolder = url.deletingLastPathComponent()

        do {
            let scannedItems = try scanner.scan(folder: parentFolder)
            folderURL = parentFolder
            items = scannedItems
            currentIndex = scannedItems.firstIndex { $0.url.standardizedFileURL == url.standardizedFileURL } ?? 0
            errorMessage = scannedItems.isEmpty ? "No supported photos or videos found in this folder." : nil
        } catch {
            folderURL = nil
            items = []
            currentIndex = 0
            errorMessage = "Could not open file: \(error.localizedDescription)"
        }
    }

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
}
