import AppKit
import Combine
import Foundation
import PowerPreviewCore

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [MediaItem] = []
    @Published var currentIndex = 0
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private var loadGeneration = 0

    var currentItem: MediaItem? {
        guard items.indices.contains(currentIndex) else {
            return nil
        }

        return items[currentIndex]
    }

    var positionText: String {
        guard !items.isEmpty else {
            return ""
        }

        return "\(currentIndex + 1) / \(items.count)"
    }

    var windowTitle: String {
        if let currentItem {
            return currentItem.displayName
        }

        if let folderURL {
            return folderURL.lastPathComponent
        }

        return "PowerPreview"
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Open"

        if panel.runModal() == .OK {
            open(panel.urls)
        }
    }

    func open(_ url: URL) {
        open([url])
    }

    func open(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let first = existing.first else {
            return
        }

        if existing.count == 1, isDirectory(first) {
            loadFolder(first, selecting: nil)
            return
        }

        let files = existing.filter { !isDirectory($0) }
        guard let file = files.first else {
            loadFolder(first, selecting: nil)
            return
        }

        loadFolder(file.deletingLastPathComponent(), selecting: file)
    }

    func showNext() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = min(currentIndex + 1, items.count - 1)
    }

    func showNextWrapping() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = currentIndex >= items.count - 1 ? 0 : currentIndex + 1
    }

    func showPrevious() {
        guard !items.isEmpty else {
            return
        }

        currentIndex = max(currentIndex - 1, 0)
    }

    func select(_ index: Int) {
        guard items.indices.contains(index) else {
            return
        }

        currentIndex = index
    }

    private func loadFolder(_ url: URL, selecting selected: URL?) {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        Task {
            let result: Result<[MediaItem], Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try MediaScanner().scan(folder: url))
                } catch {
                    return .failure(error)
                }
            }.value

            guard generation == loadGeneration else {
                return
            }

            isLoading = false

            switch result {
            case let .success(scanned):
                folderURL = url
                items = scanned
                if let selected {
                    currentIndex = scanned.firstIndex {
                        $0.url.standardizedFileURL == selected.standardizedFileURL
                    } ?? 0
                } else {
                    currentIndex = 0
                }
                errorMessage = scanned.isEmpty ? "No supported photos or videos in this folder." : nil
            case let .failure(error):
                folderURL = nil
                items = []
                currentIndex = 0
                errorMessage = "Could not open that folder. \(error.localizedDescription)"
            }
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
