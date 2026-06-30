import Foundation

public enum MediaKind: Equatable, Sendable {
    case image
    case video
}

public struct MediaItem: Identifiable, Equatable, Sendable {
    public let id: URL
    public let url: URL
    public let kind: MediaKind

    public var displayName: String {
        url.lastPathComponent
    }

    public init(url: URL, kind: MediaKind) {
        self.id = url
        self.url = url
        self.kind = kind
    }
}

public enum SupportedMedia {
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "heic", "heif",
        "bmp", "webp", "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2"
    ]

    public static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "webm", "avi", "mpeg", "mpg",
        "wmv", "flv", "3gp", "3g2", "ts", "mts", "m2ts", "ogv"
    ]

    public static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            return .image
        }

        if videoExtensions.contains(ext) {
            return .video
        }

        return nil
    }
}
