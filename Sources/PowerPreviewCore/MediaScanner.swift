import Foundation

public struct MediaScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(folder url: URL) throws -> [MediaItem] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        let urls = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
        )

        return urls.compactMap { candidate -> MediaItem? in
            guard isVisibleRegularFile(candidate, keys: resourceKeys),
                  let kind = SupportedMedia.kind(for: candidate) else {
                return nil
            }

            return MediaItem(url: candidate, kind: kind)
        }
        .sorted { lhs, rhs in
            lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func isVisibleRegularFile(_ url: URL, keys: Set<URLResourceKey>) -> Bool {
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return false
        }

        return values.isRegularFile == true && values.isHidden != true
    }
}
