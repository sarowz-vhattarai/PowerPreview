import AppKit

/// Workaround for MoltenVK drawable-size flicker and HDR activation threading.
/// https://github.com/mpv-player/mpv/pull/13651
///
/// IMPORTANT: never `main.sync` from the mpv/VO thread — that deadlocks against
/// main-thread libmpv calls and freezes playback at startup.
final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.async {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}
