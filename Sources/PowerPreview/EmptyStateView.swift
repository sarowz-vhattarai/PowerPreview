import SwiftUI

struct EmptyStateView: View {
    let message: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .frame(width: 88, height: 88)

                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.88))
            }

            VStack(spacing: 6) {
                Text("PowerPreview")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                Button(action: action) {
                    Label("Open", systemImage: "folder")
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.92))
                .foregroundStyle(.black)
            }
        }
        .padding(40)
    }
}
