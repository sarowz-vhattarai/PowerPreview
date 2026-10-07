import AppKit
import AVFoundation
import ImageIO
import PowerPreviewCore
import SwiftUI

struct FilmstripView: View {
    let items: [MediaItem]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        FilmstripCell(item: item, isSelected: index == currentIndex)
                            .id(item.id)
                            .onTapGesture {
                                onSelect(index)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: currentIndex) { _ in
                guard items.indices.contains(currentIndex) else {
                    return
                }

                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(items[currentIndex].id, anchor: .center)
                }
            }
        }
        .frame(height: 84)
    }
}

private struct FilmstripCell: View {
    let item: MediaItem
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: item.kind == .video ? "film" : "photo")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }

            if item.kind == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.55), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
            }
        }
        .frame(width: 86, height: 58)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .opacity(isSelected ? 1 : 0.72)
        .task(id: item.id) {
            thumbnail = await ThumbnailStore.shared.thumbnail(for: item)
        }
    }
}

actor ThumbnailStore {
    static let shared = ThumbnailStore()

    private var cache: [URL: NSImage] = [:]

    func thumbnail(for item: MediaItem) async -> NSImage? {
        if let cached = cache[item.url] {
            return cached
        }

        let image: NSImage?
        switch item.kind {
        case .image:
            image = DisplayImage.make(from: item.url, maxPixelSize: 240)
        case .video:
            image = videoFrame(at: item.url)
        }

        if let image {
            cache[item.url] = image
        }

        return image
    }

    private func videoFrame(at url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)

        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
