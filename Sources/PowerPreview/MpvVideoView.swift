import AppKit
import SwiftUI

struct MpvVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> MpvHostView {
        let view = MpvHostView()
        view.videoURL = url
        return view
    }

    func updateNSView(_ nsView: MpvHostView, context: Context) {
        nsView.videoURL = url
        nsView.playWhenReady()
    }
}

final class MpvHostView: NSView {
    var videoURL: URL? {
        didSet {
            if oldValue != videoURL {
                playWhenReady()
            }
        }
    }

    private let controller = MpvProcessController()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playWhenReady()
    }

    func playWhenReady() {
        guard let videoURL, let windowID = window?.windowNumber else {
            return
        }

        controller.play(url: videoURL, windowID: windowID)
    }

    deinit {
        controller.stop()
    }
}

final class MpvProcessController {
    private var process: Process?
    private var currentURL: URL?

    func play(url: URL, windowID: Int) {
        guard currentURL != url || process?.isRunning != true else {
            return
        }

        stop()

        guard let executableURL = MpvExecutableLocator.executableURL else {
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--no-config",
            "--no-terminal",
            "--force-window=immediate",
            "--keep-open=no",
            "--idle=no",
            "--autofit=100%x100%",
            "--geometry=100%x100%",
            "--wid=\(windowID)",
            url.path
        ]

        do {
            try process.run()
            self.process = process
            currentURL = url
        } catch {
            self.process = nil
            currentURL = nil
        }
    }

    func stop() {
        if process?.isRunning == true {
            process?.terminate()
        }

        process = nil
        currentURL = nil
    }

    deinit {
        stop()
    }
}
