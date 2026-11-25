// The Core Animation layers AVFoundation declares: a player's video and a capture session's
// preview, as layers a UIView names in `layerClass`. A player layer shows its player's video:
// the browser plays it and each frame is painted into the frame at the layer's place, so views
// above it stay above it (new-website#746). A page has no capture session, so the preview layer
// shows black.
import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// How a layer fits video into its bounds.
public struct AVLayerVideoGravity: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resize = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResize")
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
}

/// A layer showing a player's video, painted as a surface of the frame (see the file's note).
open class AVPlayerLayer: CALayer {
    open var player: AVPlayer? {
        didSet {
            guard player !== oldValue else { return }
            oldValue?.layers.removeAll { $0.layer === self || $0.layer == nil }
            if AVPlayer.repaint == nil { AVPlayer.repaint = { ($0 as? CALayer)?.setNeedsDisplay() } }
            player?.layers.append(.init(self))
            player?.syncVideo()
            setNeedsDisplay()
        }
    }
    open var videoGravity: AVLayerVideoGravity = .resizeAspect { didSet { setNeedsDisplay() } }
    open var pixelBufferAttributes: [String: Any]?
    open var isReadyForDisplay: Bool { player?.currentItem.map { $0._isLoaded && $0.status == .readyToPlay } ?? false }
    open var videoRect: CGRect {
        guard let size = player?.currentItem?.presentationSize, size.width > 0, size.height > 0, videoGravity != .resize else { return bounds }
        let k = videoGravity == .resizeAspect ? min(bounds.width / size.width, bounds.height / size.height)
                                              : max(bounds.width / size.width, bounds.height / size.height)
        let w = size.width * k, h = size.height * k
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    open override var _surface: (id: Int, fit: SurfaceFit)? {
        guard let surface = MainActor.assumeIsolated({ player?.currentItem?._video()?.surface }) else { return nil }
        let fit: SurfaceFit = videoGravity == .resize ? .fill : videoGravity == .resizeAspectFill ? .aspectFill : .aspect
        return (surface, fit)
    }

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }
    public convenience init(player: AVPlayer?) {
        self.init()
        self.player = player
    }
}

/// A layer showing a capture session's camera feed (a page has no capture session).
open class AVCaptureVideoPreviewLayer: CALayer {
    open var session: AVCaptureSession?
    open var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Black, as a camera's preview is before a frame arrives: the drawn iPhone's cameras
    /// (new-website#666) show no picture yet, and the view behind must not show through.
    public required init() {
        super.init()
        backgroundColor = CGColor(gray: 0, alpha: 1)
    }
    public override init(layer: Any) { super.init(layer: layer) }
    public convenience init(session: AVCaptureSession) {
        self.init()
        self.session = session
    }
}

// CoreVideo's pixel buffer keys, which AVFoundation re-exports (a player layer's
// `pixelBufferAttributes`).
#if os(WASI)
public typealias OSType = UInt32
public let kCVPixelBufferPixelFormatTypeKey = "PixelFormatType"
public let kCVPixelBufferWidthKey = "Width"
public let kCVPixelBufferHeightKey = "Height"
public let kCVPixelFormatType_32BGRA: OSType = 0x4247_5241
public let kCVPixelFormatType_32ARGB: OSType = 0x0000_0020
#endif
