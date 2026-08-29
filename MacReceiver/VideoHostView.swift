// The NSView that shows the streamed desktop.
//
// Port of the iOS VideoView (iOS/OpenSidecarPhoneApp.swift:808-908). Three
// AppKit differences matter and each one is a silent-wrong-render if missed:
//
//  1. isFlipped = true — AppKit is bottom-left origin. With this, the aspect-fit
//     and normalize math ports across unchanged and the cursor is not mirrored.
//  2. contentsScale must be set by hand on every sublayer we add. On iOS it is
//     inherited; on AppKit it is not, and the symptom (everything renders at 1x,
//     i.e. soft and half-resolution) looks exactly like an encoder problem.
//  3. layout(), not layoutSubviews().

import AppKit
import AVFoundation
import CoreVideo

final class VideoHostView: NSView {

    private let displayLayer: AVSampleBufferDisplayLayer
    private let cursorLayer = CALayer()
    private var cursorNormSize = CGSize(width: 0.02, height: 0.02)
    private var cursorAnchor = CGPoint.zero
    private var cursorPosition = CGPoint(x: 0.5, y: 0.5)
    private var cursorVisible = false

    /// Decoded video size, taken from the SPS — never from `hello`
    /// (PROTOCOL.md section 5.2 makes this normative).
    var videoSize: CGSize = .zero {
        didSet { if videoSize != oldValue { needsLayout = true } }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Opt-in alternative to AVSampleBufferDisplayLayer. Its only advantage here
    /// is that we own the fragment shader, so we can sharpen while upscaling —
    /// the system layer only offers bilinear, which is what makes a stream
    /// smaller than the panel look soft at full screen.
    private(set) var metalRenderer: MetalVideoRenderer?

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        wantsLayer = true                      // must precede adding sublayers
        layer?.backgroundColor = NSColor.black.cgColor

        if UserDefaults.standard.bool(forKey: "metalRenderer"),
           let renderer = MetalVideoRenderer() {
            metalRenderer = renderer
            renderer.metalLayer.frame = bounds
            layer?.addSublayer(renderer.metalLayer)
        } else {
            displayLayer.videoGravity = .resizeAspect
            layer?.addSublayer(displayLayer)
        }

        cursorLayer.isHidden = true
        cursorLayer.zPosition = 10
        cursorLayer.magnificationFilter = .nearest
        layer?.addSublayer(cursorLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Geometry

    /// The letterboxed rect the video actually occupies inside our bounds.
    func videoRect() -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0 else { return bounds }
        let fit = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let w = videoSize.width * fit, h = videoSize.height * fit
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2,
                      width: w, height: h)
    }

    /// Scale factor from video pixels to view points — the divisor for scroll
    /// deltas, which travel in video pixels (PROTOCOL.md section 7).
    var videoFitScale: CGFloat {
        guard videoSize.width > 0, videoSize.height > 0 else { return 1 }
        return min(bounds.width / videoSize.width, bounds.height / videoSize.height)
    }

    /// View point -> normalized [0,1] video space, origin top-left.
    func normalized(_ point: CGPoint) -> CGPoint {
        let r = videoRect()
        guard r.width > 0, r.height > 0 else { return .zero }
        return CGPoint(x: min(max((point.x - r.minX) / r.width, 0), 1),
                       y: min(max((point.y - r.minY) / r.height, 0), 1))
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)     // no implicit animation on resize
        if let metal = metalRenderer {
            let rect = videoRect()                // aspect-fit; CAMetalLayer does
                                                  // not letterbox for us
            let scale = window?.backingScaleFactor ?? 2
            let drawable = CGSize(width: rect.width * scale, height: rect.height * scale)
            // nextDrawable() returns nil forever on a zero-sized layer, which
            // shows up as a permanently black window rather than an error.
            if rect.width > 1, rect.height > 1 {
                metal.metalLayer.frame = rect
                metal.metalLayer.drawableSize = drawable
            }
        } else {
            displayLayer.frame = bounds
        }
        updateCursorLayout()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyContentsScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyContentsScale()
    }

    /// A manually created CALayer defaults to contentsScale 1.0 and does NOT
    /// inherit the window's backing factor the way iOS layers do. Left at 1 on a
    /// Retina panel, the video is rasterised at point resolution and then
    /// stretched to the physical pixels — which reads as "sharp in a small
    /// window, blurry at full screen", because a small window downscales (sharp)
    /// while full screen upscales (soft).
    ///
    /// viewDidChangeBackingProperties alone is not enough: it fires on *changes*,
    /// so a view whose scale never changes after creation can keep 1.0 forever.
    /// Hence also viewDidMoveToWindow, and a screen-derived fallback.
    private func applyContentsScale() {
        let scale = window?.backingScaleFactor
            ?? window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        guard scale > 0 else { return }
        layer?.contentsScale = scale
        displayLayer.contentsScale = scale
        cursorLayer.contentsScale = scale
        metalRenderer?.metalLayer.contentsScale = scale
        if scale != lastLoggedScale {
            lastLoggedScale = scale
            Log.info("backing scale \(scale) — layer renders at "
                     + "\(Int(bounds.width * scale))x\(Int(bounds.height * scale)) px")
        }
        needsLayout = true
    }

    private var lastLoggedScale: CGFloat = 0

    // MARK: - Cursor echo

    func setCursor(x: Double, y: Double, visible: Bool) {
        cursorPosition = CGPoint(x: x, y: y)
        cursorVisible = visible
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.isHidden = !visible
        updateCursorLayout()
        CATransaction.commit()
    }

    func setCursorSprite(_ image: CGImage, anchor: CGPoint, normSize: CGSize) {
        cursorAnchor = anchor
        cursorNormSize = normSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.contents = image
        updateCursorLayout()
        CATransaction.commit()
    }

    private func updateCursorLayout() {
        let r = videoRect()
        guard r.width > 0 else { return }
        let w = cursorNormSize.width * r.width
        let h = cursorNormSize.height * r.height
        let x = r.minX + cursorPosition.x * r.width - cursorAnchor.x * w
        let y = r.minY + cursorPosition.y * r.height - cursorAnchor.y * h
        cursorLayer.frame = CGRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
    }
}
