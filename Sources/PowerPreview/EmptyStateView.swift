import SwiftUI

struct EmptyStateView: View {
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("PowerPreview")
                .font(.largeTitle.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Folder...", action: action)
                .keyboardShortcut("o", modifiers: [.command])
        }
        .padding(40)
    }
}
