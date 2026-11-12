// The Core Animation layers AVFoundation declares: a player's video and a capture session's
// preview, as layers a UIView names in `layerClass`. Neither draws on the web yet (the video
// plays only through SwiftUI's `VideoPlayer`, and a page has no capture session), so the layer
// keeps its properties and shows its background. Accepted for source compatibility.
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

/// A layer showing a player's video (not drawn on the web: see the file's note).
open class AVPlayerLayer: CALayer {
    open var player: AVPlayer?
    open var videoGravity: AVLayerVideoGravity = .resizeAspect
    open var pixelBufferAttributes: [String: Any]?
    open var isReadyForDisplay: Bool { false }
    open var videoRect: CGRect { bounds }

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

    public required init() { super.init() }
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
