// Apple's `QuartzCore` (Core Animation) module for wasm: UIKitWeb's layers, display link and
// media time, which Apple's UIKit re-exports, and `CAMetalLayer`, a layer for Metal drawables.
// A Metal layer draws into a canvas with the page's WebGPU (the Metal module, new-website#746):
// each drawable is the canvas's current texture, and the canvas is painted into the frame at the
// layer's place as a surface, so views above the layer stay above it. Without a GPU device the
// layer hands out no drawable and shows its background.
#if os(WASI)
@_exported import UIKitWebCore
import Metal
import WebFoundation

/// A drawable of a Metal layer: the texture to render into, and the layer it shows in.
public protocol CAMetalDrawable: MTLDrawable {
    var texture: any MTLTexture { get }
    var layer: CAMetalLayer { get }
}

/// A layer that Metal renders into.
open class CAMetalLayer: CALayer {
    open var device: (any MTLDevice)?
    open var preferredDevice: (any MTLDevice)? { MTLCreateSystemDefaultDevice() }
    open var pixelFormat: MTLPixelFormat = .bgra8Unorm
    open var framebufferOnly = true
    open var drawableSize: CGSize = .zero
    open var maximumDrawableCount = 3
    open var presentsWithTransaction = false
    open var allowsNextDrawableTimeout = true
    open var displaySyncEnabled = true

    /// The canvas behind the drawables, made with the first one.
    private var canvas: _WebGPUCanvas?
    /// Whether a drawable has been presented, so the canvas has a picture to show.
    private var presentedOnce = false

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }

    /// The next drawable to render into: the canvas's texture for this frame, sized to
    /// `drawableSize` (the bounds at `contentsScale` when it is zero); nil without a device.
    open func nextDrawable() -> (any CAMetalDrawable)? {
        let size = drawableSize.width > 0 && drawableSize.height > 0
            ? drawableSize : CGSize(width: bounds.width * contentsScale, height: bounds.height * contentsScale)
        let canvas = self.canvas ?? _WebGPUCanvas()
        self.canvas = canvas
        guard let texture = canvas.nextTexture(device: device, width: Int(size.width.rounded()), height: Int(size.height.rounded()),
                                               pixelFormat: pixelFormat, opaque: isOpaque) else { return nil }
        return _MetalLayerDrawable(texture: texture, layer: self)
    }

    /// A presented drawable's picture is painted with the next frame.
    func _drawablePresented() {
        presentedOnce = true
        setNeedsDisplay()
    }

    open override var _surface: (id: Int, fit: SurfaceFit)? {
        guard presentedOnce, let canvas else { return nil }
        return (canvas.surface, .fill)
    }
}

final class _MetalLayerDrawable: NSObject, CAMetalDrawable, _WebGPUPresentable, @unchecked Sendable {
    let texture: any MTLTexture
    private let owner: CAMetalLayer
    var layer: CAMetalLayer { owner }
    init(texture: any MTLTexture, layer: CAMetalLayer) {
        self.texture = texture
        owner = layer
    }
    func _presented() { MainActor.assumeIsolated { owner._drawablePresented() } }
}
#endif
