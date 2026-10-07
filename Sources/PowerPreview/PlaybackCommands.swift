import Foundation

extension Notification.Name {
    static let toggleSlideshow = Notification.Name("PowerPreview.toggleSlideshow")
    static let toggleFullScreen = Notification.Name("PowerPreview.toggleFullScreen")
}

@MainActor
final class PlaybackSession: ObservableObject {
    static let shared = PlaybackSession()

    @Published var isVideo = false
    @Published var isPlaying = false
    @Published var progress = 0.0
    @Published var currentTimeText = "0:00"
    @Published var durationText = "0:00"
    @Published var failureMessage: String?
    @Published private(set) var endCount = 0

    var toggleHandler: (() -> Void)?
    var seekHandler: ((Double) -> Void)?

    func toggle() {
        guard isVideo else {
            return
        }

        toggleHandler?()
    }

    func seek(to progress: Double) {
        seekHandler?(progress)
    }

    func noteEnded() {
        endCount += 1
    }

    func reset() {
        isVideo = false
        isPlaying = false
        progress = 0
        currentTimeText = "0:00"
        durationText = "0:00"
        failureMessage = nil
        toggleHandler = nil
        seekHandler = nil
    }
}
