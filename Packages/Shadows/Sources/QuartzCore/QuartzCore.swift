// Apple's `QuartzCore` (Core Animation) module for wasm: UIKitWeb's layers, display link and
// media time, which Apple's UIKit re-exports, and `CAMetalLayer`, a layer for Metal drawables.
// There is no Metal device on the web (see the Metal module), so a Metal layer hands out no
// drawable and shows its background. Accepted for source compatibility.
#if os(WASI)
@_exported import UIKitWebCore
import Metal

/// A drawable of a Metal layer (none are made on the web).
public protocol CAMetalDrawable: MTLDrawable {}

extension CAMetalDrawable {
    public var texture: any MTLTexture { fatalError("No Metal drawable exists on the web") }
    public var layer: CAMetalLayer { fatalError("No Metal drawable exists on the web") }
}

/// A layer that Metal renders into (nothing is rendered on the web).
open class CAMetalLayer: CALayer {
    open var device: (any MTLDevice)?
    open var preferredDevice: (any MTLDevice)? { nil }
    open var pixelFormat: MTLPixelFormat = .bgra8Unorm
    open var framebufferOnly = true
    open var drawableSize: CGSize = .zero
    open var maximumDrawableCount = 3
    open var presentsWithTransaction = false
    open var allowsNextDrawableTimeout = true
    open var displaySyncEnabled = true

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }

    /// The next drawable to render into: none without a device.
    open func nextDrawable() -> (any CAMetalDrawable)? { nil }
}
#endif
