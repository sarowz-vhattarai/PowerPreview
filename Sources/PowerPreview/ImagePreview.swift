import AppKit
import ImageIO
import SwiftUI

struct ImagePreview: View {
    let url: URL

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if failed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text("Could not display \(url.lastPathComponent)")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: "\(url.path)|\(Int(proxy.size.width))x\(Int(proxy.size.height))") {
                await load(fitting: proxy.size)
            }
        }
    }

    private func load(fitting size: CGSize) async {
        let maxPixelSize = DisplayImage.maxPixelSize(fitting: size)
        let loaded = await Task.detached(priority: .userInitiated) {
            DisplayImage.make(from: url, maxPixelSize: maxPixelSize)
        }.value

        image = loaded
        failed = loaded == nil
    }
}

enum DisplayImage {
    static func maxPixelSize(fitting size: CGSize) -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let longestEdge = max(size.width, size.height) * scale
        return Int(min(max(longestEdge, 512), 4096))
    }

    static func make(from url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
