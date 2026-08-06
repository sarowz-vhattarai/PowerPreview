import Foundation

extension Notification.Name {
    static let toggleVideoPlayback = Notification.Name("PowerPreview.toggleVideoPlayback")
    static let stopVideoPlayback = Notification.Name("PowerPreview.stopVideoPlayback")
    static let videoDidFinishPlaying = Notification.Name("PowerPreview.videoDidFinishPlaying")
    static let powerPreviewShowVideoControls = Notification.Name("PowerPreview.showVideoControls")
    static let powerPreviewHideVideoControls = Notification.Name("PowerPreview.hideVideoControls")
    static let powerPreviewWindowGeometryChanged = Notification.Name("PowerPreview.windowGeometryChanged")
}
