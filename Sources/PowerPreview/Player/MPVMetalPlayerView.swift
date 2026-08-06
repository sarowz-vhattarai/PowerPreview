import SwiftUI

/// SwiftUI host for the embedded Metal/libmpv player surface.
struct MPVMetalPlayerView: NSViewControllerRepresentable {
    @ObservedObject var model: EmbeddedMpvModel

    func makeNSViewController(context: Context) -> MPVMetalViewController {
        let controller = MPVMetalViewController()
        controller.playDelegate = model
        controller.playUrl = model.url
        model.attach(player: controller)
        return controller
    }

    func updateNSViewController(_ nsViewController: MPVMetalViewController, context: Context) {
        model.attach(player: nsViewController)
        nsViewController.playDelegate = model
        if let url = model.url, url != nsViewController.playUrl {
            nsViewController.loadFile(url)
        }
    }
}
