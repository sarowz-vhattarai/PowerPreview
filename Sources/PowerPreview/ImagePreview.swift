import AppKit
import SwiftUI

struct ImagePreview: View {
    let url: URL

    var body: some View {
        ZStack {
            Color.black

            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                Text("Could not load \(url.lastPathComponent)")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}
