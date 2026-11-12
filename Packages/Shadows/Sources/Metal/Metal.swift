// Apple's `Metal` module for wasm. A page has no Metal device (WebGPU is not driven from here),
// so `MTLCreateSystemDefaultDevice()` is nil and an app takes its no-GPU path; the protocols,
// descriptors and enums are declared so that code written against a device compiles. No value
// of the object protocols is ever made, so their members are extension stubs. Accepted for
// source compatibility.
#if os(WASI)
import WebFoundation

/// The system's default GPU: none on the web.
public func MTLCreateSystemDefaultDevice() -> (any MTLDevice)? { nil }
public func MTLCopyAllDevices() -> [any MTLDevice] { [] }

// MARK: - Values

public enum MTLPixelFormat: UInt, Sendable {
    case invalid = 0, a8Unorm = 1, r8Unorm = 10, r16Float = 25, rg8Unorm = 30, r32Float = 55, rgba8Unorm = 70, rgba8Unorm_srgb = 71,
         bgra8Unorm = 80, bgra8Unorm_srgb = 81, rgb10a2Unorm = 90, rg32Float = 105, rgba16Float = 115, rgba32Float = 125,
         depth16Unorm = 250, depth32Float = 252, stencil8 = 253, depth32Float_stencil8 = 260
}
public enum MTLTextureType: UInt, Sendable { case type1D = 0, type1DArray, type2D, type2DArray, type2DMultisample, typeCube, typeCubeArray, type3D, type2DMultisampleArray, typeTextureBuffer }
public enum MTLStorageMode: UInt, Sendable { case shared = 0, managed, `private`, memoryless }
public enum MTLCPUCacheMode: UInt, Sendable { case defaultCache = 0, writeCombined }
public enum MTLCompareFunction: UInt, Sendable { case never = 0, less, equal, lessEqual, greater, notEqual, greaterEqual, always }
public enum MTLLoadAction: UInt, Sendable { case dontCare = 0, load, clear }
public enum MTLStoreAction: UInt, Sendable { case dontCare = 0, store, multisampleResolve, storeAndMultisampleResolve, unknown, customSampleDepthStore }
public enum MTLPrimitiveType: UInt, Sendable { case point = 0, line, lineStrip, triangle, triangleStrip }
public enum MTLIndexType: UInt, Sendable { case uint16 = 0, uint32 }
public enum MTLCullMode: UInt, Sendable { case none = 0, front, back }
public enum MTLWinding: UInt, Sendable { case clockwise = 0, counterClockwise }
public enum MTLBlendFactor: UInt, Sendable { case zero = 0, one, sourceColor, oneMinusSourceColor, sourceAlpha, oneMinusSourceAlpha }
public enum MTLBlendOperation: UInt, Sendable { case add = 0, subtract, reverseSubtract, min, max }
public enum MTLSamplerMinMagFilter: UInt, Sendable { case nearest = 0, linear }
public enum MTLSamplerMipFilter: UInt, Sendable { case notMipmapped = 0, nearest, linear }
public enum MTLSamplerAddressMode: UInt, Sendable { case clampToEdge = 0, mirrorClampToEdge, `repeat`, mirrorRepeat, clampToZero, clampToBorderColor }
public enum MTLCommandBufferStatus: UInt, Sendable { case notEnqueued = 0, enqueued, committed, scheduled, completed, error }

public struct MTLTextureUsage: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let unknown = MTLTextureUsage([])
    public static let shaderRead = MTLTextureUsage(rawValue: 1)
    public static let shaderWrite = MTLTextureUsage(rawValue: 2)
    public static let renderTarget = MTLTextureUsage(rawValue: 4)
    public static let pixelFormatView = MTLTextureUsage(rawValue: 16)
}

public struct MTLResourceOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let storageModeShared = MTLResourceOptions([])
    public static let cpuCacheModeWriteCombined = MTLResourceOptions(rawValue: 1)
    public static let storageModePrivate = MTLResourceOptions(rawValue: 32)
    public static let storageModeMemoryless = MTLResourceOptions(rawValue: 48)
}

public struct MTLClearColor: Sendable, Equatable {
    public var red, green, blue, alpha: Double
    public init() { red = 0; green = 0; blue = 0; alpha = 0 }
    public init(red: Double, green: Double, blue: Double, alpha: Double) { self.red = red; self.green = green; self.blue = blue; self.alpha = alpha }
}
public func MTLClearColorMake(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> MTLClearColor { MTLClearColor(red: red, green: green, blue: blue, alpha: alpha) }

public struct MTLOrigin: Sendable, Equatable {
    public var x, y, z: Int
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Int, y: Int, z: Int) { self.x = x; self.y = y; self.z = z }
}
public struct MTLSize: Sendable, Equatable {
    public var width, height, depth: Int
    public init() { width = 0; height = 0; depth = 0 }
    public init(width: Int, height: Int, depth: Int) { self.width = width; self.height = height; self.depth = depth }
}
public struct MTLRegion: Sendable, Equatable {
    public var origin: MTLOrigin
    public var size: MTLSize
    public init() { origin = MTLOrigin(); size = MTLSize() }
    public init(origin: MTLOrigin, size: MTLSize) { self.origin = origin; self.size = size }
}
public func MTLRegionMake1D(_ x: Int, _ width: Int) -> MTLRegion { MTLRegion(origin: MTLOrigin(x: x, y: 0, z: 0), size: MTLSize(width: width, height: 1, depth: 1)) }
public func MTLRegionMake2D(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> MTLRegion {
    MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0), size: MTLSize(width: width, height: height, depth: 1))
}
public func MTLRegionMake3D(_ x: Int, _ y: Int, _ z: Int, _ width: Int, _ height: Int, _ depth: Int) -> MTLRegion {
    MTLRegion(origin: MTLOrigin(x: x, y: y, z: z), size: MTLSize(width: width, height: height, depth: depth))
}
public struct MTLViewport: Sendable, Equatable {
    public var originX, originY, width, height, znear, zfar: Double
    public init(originX: Double, originY: Double, width: Double, height: Double, znear: Double, zfar: Double) {
        self.originX = originX; self.originY = originY; self.width = width; self.height = height; self.znear = znear; self.zfar = zfar
    }
}

// MARK: - Descriptors

open class MTLCompileOptions: NSObject, @unchecked Sendable {
    public override init() {}
    open var preprocessorMacros: [String: NSObject]?
    open var fastMathEnabled = true
}

open class MTLTextureDescriptor: NSObject, @unchecked Sendable {
    open var textureType: MTLTextureType = .type2D
    open var pixelFormat: MTLPixelFormat = .rgba8Unorm
    open var width = 1, height = 1, depth = 1, mipmapLevelCount = 1, sampleCount = 1, arrayLength = 1
    open var usage: MTLTextureUsage = .shaderRead
    open var storageMode: MTLStorageMode = .shared
    open var cpuCacheMode: MTLCPUCacheMode = .defaultCache
    open var resourceOptions: MTLResourceOptions = []
    public override init() {}
    open class func texture2DDescriptor(pixelFormat: MTLPixelFormat, width: Int, height: Int, mipmapped: Bool) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor()
        d.pixelFormat = pixelFormat; d.width = width; d.height = height
        if mipmapped { var n = 1, s = max(width, height); while s > 1 { s /= 2; n += 1 }; d.mipmapLevelCount = n }
        return d
    }
}

open class MTLRenderPipelineColorAttachmentDescriptor: NSObject, @unchecked Sendable {
    open var pixelFormat: MTLPixelFormat = .invalid
    open var isBlendingEnabled = false
    open var sourceRGBBlendFactor: MTLBlendFactor = .one, destinationRGBBlendFactor: MTLBlendFactor = .zero
    open var sourceAlphaBlendFactor: MTLBlendFactor = .one, destinationAlphaBlendFactor: MTLBlendFactor = .zero
    open var rgbBlendOperation: MTLBlendOperation = .add, alphaBlendOperation: MTLBlendOperation = .add
}

/// An array of attachment descriptors, made on first use of an index (as Metal's are).
open class _MTLAttachmentArray<Element: NSObject>: NSObject, @unchecked Sendable {
    private var items: [Int: Element] = [:]
    private let make: () -> Element
    init(_ make: @escaping () -> Element) { self.make = make }
    public subscript(index: Int) -> Element! {
        get { if let item = items[index] { return item }; let item = make(); items[index] = item; return item }
        set { items[index] = newValue }
    }
}
public typealias MTLRenderPipelineColorAttachmentDescriptorArray = _MTLAttachmentArray<MTLRenderPipelineColorAttachmentDescriptor>
public typealias MTLRenderPassColorAttachmentDescriptorArray = _MTLAttachmentArray<MTLRenderPassColorAttachmentDescriptor>

open class MTLRenderPipelineDescriptor: NSObject, @unchecked Sendable {
    open var label: String?
    open var vertexFunction: (any MTLFunction)?
    open var fragmentFunction: (any MTLFunction)?
    open var vertexDescriptor: MTLVertexDescriptor?
    open var rasterSampleCount = 1
    open var sampleCount: Int { get { rasterSampleCount } set { rasterSampleCount = newValue } }
    open var isAlphaToCoverageEnabled = false
    open var depthAttachmentPixelFormat: MTLPixelFormat = .invalid
    open var stencilAttachmentPixelFormat: MTLPixelFormat = .invalid
    public let colorAttachments = MTLRenderPipelineColorAttachmentDescriptorArray { MTLRenderPipelineColorAttachmentDescriptor() }
    public override init() {}
}

open class MTLVertexDescriptor: NSObject, @unchecked Sendable {
    public override init() {}
}

open class MTLDepthStencilDescriptor: NSObject, @unchecked Sendable {
    open var depthCompareFunction: MTLCompareFunction = .always
    open var isDepthWriteEnabled = false
    open var label: String?
    public override init() {}
}

open class MTLSamplerDescriptor: NSObject, @unchecked Sendable {
    open var minFilter: MTLSamplerMinMagFilter = .nearest, magFilter: MTLSamplerMinMagFilter = .nearest
    open var mipFilter: MTLSamplerMipFilter = .notMipmapped
    open var sAddressMode: MTLSamplerAddressMode = .clampToEdge, tAddressMode: MTLSamplerAddressMode = .clampToEdge
    public override init() {}
}

open class MTLRenderPassAttachmentDescriptor: NSObject, @unchecked Sendable {
    open var texture: (any MTLTexture)?
    open var resolveTexture: (any MTLTexture)?
    open var level = 0, slice = 0
    open var loadAction: MTLLoadAction = .dontCare
    open var storeAction: MTLStoreAction = .store
}
open class MTLRenderPassColorAttachmentDescriptor: MTLRenderPassAttachmentDescriptor, @unchecked Sendable {
    open var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
}
open class MTLRenderPassDepthAttachmentDescriptor: MTLRenderPassAttachmentDescriptor, @unchecked Sendable {
    open var clearDepth: Double = 1
}
open class MTLRenderPassStencilAttachmentDescriptor: MTLRenderPassAttachmentDescriptor, @unchecked Sendable {
    open var clearStencil: UInt32 = 0
}

open class MTLRenderPassDescriptor: NSObject, @unchecked Sendable {
    public let colorAttachments = MTLRenderPassColorAttachmentDescriptorArray { MTLRenderPassColorAttachmentDescriptor() }
    open var depthAttachment: MTLRenderPassDepthAttachmentDescriptor! = MTLRenderPassDepthAttachmentDescriptor()
    open var stencilAttachment: MTLRenderPassStencilAttachmentDescriptor! = MTLRenderPassStencilAttachmentDescriptor()
    public override init() {}
}

// MARK: - Objects (never made on the web)

public protocol MTLResource: NSObjectProtocol, Sendable {}
public protocol MTLFunction: NSObjectProtocol, Sendable {}
public protocol MTLRenderPipelineState: NSObjectProtocol, Sendable {}
public protocol MTLDepthStencilState: NSObjectProtocol, Sendable {}
public protocol MTLSamplerState: NSObjectProtocol, Sendable {}
public protocol MTLBuffer: MTLResource {}
public protocol MTLTexture: MTLResource {}
public protocol MTLLibrary: NSObjectProtocol, Sendable {}
public protocol MTLCommandQueue: NSObjectProtocol, Sendable {}
public protocol MTLCommandBuffer: NSObjectProtocol, Sendable {}
public protocol MTLCommandEncoder: NSObjectProtocol, Sendable {}
public protocol MTLRenderCommandEncoder: MTLCommandEncoder {}
public protocol MTLBlitCommandEncoder: MTLCommandEncoder {}
public protocol MTLComputeCommandEncoder: MTLCommandEncoder {}
public protocol MTLDrawable: NSObjectProtocol, Sendable {}
public protocol MTLDevice: NSObjectProtocol, Sendable {}

extension MTLDevice {
    public var name: String { "" }
    public func makeCommandQueue() -> (any MTLCommandQueue)? { nil }
    public func makeBuffer(length: Int, options: MTLResourceOptions = []) -> (any MTLBuffer)? { nil }
    public func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions = []) -> (any MTLBuffer)? { nil }
    public func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)? { nil }
    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)? { nil }
    public func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)? { nil }
    public func makeDefaultLibrary() -> (any MTLLibrary)? { nil }
    public func makeDefaultLibrary(bundle: Bundle) throws -> any MTLLibrary { throw _MTLUnavailable() }
    public func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary { throw _MTLUnavailable() }
    public func makeLibrary(source: String, options: MTLCompileOptions?) async throws -> any MTLLibrary { throw _MTLUnavailable() }
    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState { throw _MTLUnavailable() }
}

/// What a Metal call throws on the web: there is no device.
struct _MTLUnavailable: Error {}

extension MTLResource {
    public var label: String? { nil }
    public var storageMode: MTLStorageMode { .shared }
}

extension MTLBuffer {
    public var length: Int { 0 }
    public func contents() -> UnsafeMutableRawPointer { fatalError("No Metal buffer exists on the web") }
}

extension MTLTexture {
    public var width: Int { 0 }
    public var height: Int { 0 }
    public var depth: Int { 0 }
    public var mipmapLevelCount: Int { 1 }
    public var sampleCount: Int { 1 }
    public var pixelFormat: MTLPixelFormat { .invalid }
    public var textureType: MTLTextureType { .type2D }
    public var usage: MTLTextureUsage { [] }
    public func replace(region: MTLRegion, mipmapLevel level: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int) {}
    public func replace(region: MTLRegion, mipmapLevel level: Int, slice: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {}
    public func getBytes(_ pixelBytes: UnsafeMutableRawPointer, bytesPerRow: Int, from region: MTLRegion, mipmapLevel level: Int) {}
}

extension MTLLibrary {
    public var functionNames: [String] { [] }
    public func makeFunction(name functionName: String) -> (any MTLFunction)? { nil }
}

extension MTLCommandQueue {
    public func makeCommandBuffer() -> (any MTLCommandBuffer)? { nil }
}

extension MTLCommandBuffer {
    public var status: MTLCommandBufferStatus { .notEnqueued }
    public var gpuStartTime: CFTimeInterval { 0 }
    public var gpuEndTime: CFTimeInterval { 0 }
    public var error: (any Error)? { nil }
    public func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)? { nil }
    public func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)? { nil }
    public func makeComputeCommandEncoder() -> (any MTLComputeCommandEncoder)? { nil }
    public func present(_ drawable: any MTLDrawable) {}
    public func commit() {}
    public func enqueue() {}
    public func waitUntilCompleted() {}
    public func waitUntilScheduled() {}
    public func addCompletedHandler(_ block: @escaping @Sendable (any MTLCommandBuffer) -> Void) {}
    public func addScheduledHandler(_ block: @escaping @Sendable (any MTLCommandBuffer) -> Void) {}
}

extension MTLCommandEncoder {
    public func endEncoding() {}
    public func pushDebugGroup(_ string: String) {}
    public func popDebugGroup() {}
}

extension MTLRenderCommandEncoder {
    public func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState) {}
    public func setDepthStencilState(_ depthStencilState: (any MTLDepthStencilState)?) {}
    public func setCullMode(_ cullMode: MTLCullMode) {}
    public func setFrontFacing(_ frontFacingWinding: MTLWinding) {}
    public func setViewport(_ viewport: MTLViewport) {}
    public func setVertexBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) {}
    public func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {}
    public func setFragmentBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) {}
    public func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) {}
    public func setVertexTexture(_ texture: (any MTLTexture)?, index: Int) {}
    public func setFragmentTexture(_ texture: (any MTLTexture)?, index: Int) {}
    public func setFragmentSamplerState(_ sampler: (any MTLSamplerState)?, index: Int) {}
    public func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) {}
    public func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {}
    public func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int) {}
    public func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer, indexBufferOffset: Int, instanceCount: Int) {}
}

extension MTLBlitCommandEncoder {
    public func generateMipmaps(for texture: any MTLTexture) {}
    public func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, to destinationBuffer: any MTLBuffer, destinationOffset: Int, size: Int) {}
}
#endif
