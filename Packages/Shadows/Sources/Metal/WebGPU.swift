// Metal drawn with the browser's WebGPU (new-website#746). The page asks for a GPU device while it
// loads when the app's build ships WGSL (`window.__swiftuiwebGPU`, WebGraphicsCanvas's host);
// `MTLCreateSystemDefaultDevice()` hands it out. The objects keep what WebGPU needs and call a
// small script (`gpu`) for each GPU step, so a frame costs a few dozen calls into the page.
//
// How Metal maps onto WebGPU here:
// - Buffers live on the GPU and, for `contents()`, in memory; a buffer whose memory was handed out
//   is uploaded again when it is next bound. `set…Bytes` goes through a ring of uniform memory.
// - Pipeline state that Metal sets on the encoder (depth test, culling, winding) is part of a
//   WebGPU pipeline, so each pipeline state makes its WebGPU pipelines as draws ask for them.
// - The WGSL twin declares its resources in group 0 at fixed bindings (`Binding`), and the
//   samplers MSL makes inline (`constexpr sampler`) at the standard bindings 100 to 105.
// - Command buffers record into a GPU command encoder and submit on `commit`; nothing waits.
// - A `CAMetalLayer`'s drawable is a canvas's current texture, painted into the frame as a surface.
#if os(WASI)
import WebFoundation
import JavaScriptKit

/// Where a Metal resource index lands in the WGSL twin's group 0.
public enum _MTLWGSLBinding {
    public static func vertexBuffer(_ index: Int) -> Int { index }
    public static func fragmentBuffer(_ index: Int) -> Int { 16 + index }
    public static func vertexTexture(_ index: Int) -> Int { 32 + index }
    public static func fragmentTexture(_ index: Int) -> Int { 48 + index }
    public static func fragmentSampler(_ index: Int) -> Int { 80 + index }
    /// The samplers an MSL source makes inline: 100 linear, 101 linear with mipmaps, 102 that with
    /// 8x anisotropy, 103 linear comparison (less or equal), 104 nearest, 105 linear repeating; all
    /// others clamp to the edge.
    public static let standardSamplers = 100...105
}

/// The page's script for each GPU step (see the file's note).
enum _GPU {
    nonisolated(unsafe) static let script: JSObject? = {
        guard let make = JSObject.global.Function.function?.new(source) else { return nil }
        return make().object
    }()

    static let source = """
        const U = { MAP_READ: 1, COPY_SRC: 4, COPY_DST: 8, INDEX: 16, VERTEX: 32, UNIFORM: 64, STORAGE: 128 };
        const mipCode = `
          @group(0) @binding(0) var src: texture_2d<f32>;
          @group(0) @binding(1) var smp: sampler;
          struct O { @builtin(position) p: vec4f, @location(0) uv: vec2f };
          @vertex fn v(@builtin(vertex_index) i: u32) -> O {
            var o: O; let x = f32((i << 1u) & 2u); let y = f32(i & 2u);
            o.p = vec4f(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0); o.uv = vec2f(x, y); return o;
          }
          @fragment fn f(i: O) -> @location(0) vec4f { return textureSample(src, smp, i.uv); }`;
        const view = (t, level, format) => level < 0 && !format ? t.createView()
          : t.createView({ baseMipLevel: Math.max(level, 0), mipLevelCount: level < 0 ? undefined : 1, format: format || undefined });
        return {
          buffer(dev, size, bytes) {
            const b = dev.createBuffer({ size: Math.max(16, Math.ceil(size / 4) * 4),
              usage: U.STORAGE | U.VERTEX | U.INDEX | U.UNIFORM | U.COPY_DST | U.COPY_SRC });
            if (bytes) dev.queue.writeBuffer(b, 0, bytes);
            return b;
          },
          write(dev, b, offset, bytes) { dev.queue.writeBuffer(b, offset, bytes); },
          texture(dev, w, h, format, mips, samples, usage) {
            return dev.createTexture({ size: [w, h], format, mipLevelCount: mips, sampleCount: samples, usage });
          },
          writeTexture(dev, t, level, x, y, w, h, bytes, bpr) {
            dev.queue.writeTexture({ texture: t, mipLevel: level, origin: [x, y, 0] }, bytes, { bytesPerRow: bpr, rowsPerImage: h }, [w, h, 1]);
          },
          sampler(dev, mag, min, mip, u, v, aniso, compare) {
            const d = { magFilter: mag, minFilter: min, mipmapFilter: mip, addressModeU: u, addressModeV: v, addressModeW: u, maxAnisotropy: aniso };
            if (compare) d.compare = compare;
            return dev.createSampler(d);
          },
          standardSamplers(dev) {
            const c = 'clamp-to-edge';
            return [
              dev.createSampler({ magFilter: 'linear', minFilter: 'linear', addressModeU: c, addressModeV: c }),
              dev.createSampler({ magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear', addressModeU: c, addressModeV: c }),
              dev.createSampler({ magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear', addressModeU: c, addressModeV: c, maxAnisotropy: 8 }),
              dev.createSampler({ magFilter: 'linear', minFilter: 'linear', addressModeU: c, addressModeV: c, compare: 'less-equal' }),
              dev.createSampler({ addressModeU: c, addressModeV: c }),
              dev.createSampler({ magFilter: 'linear', minFilter: 'linear', mipmapFilter: 'linear', addressModeU: 'repeat', addressModeV: 'repeat' }),
            ];
          },
          module(dev, code) { return dev.createShaderModule({ code }); },
          // The compile errors, one a line ('' when it compiled), when the browser says.
          errors(module, done) {
            if (!module.getCompilationInfo) { done(''); return; }
            module.getCompilationInfo().then(i => done(i.messages.filter(m => m.type === 'error')
              .map(m => m.lineNum + ':' + m.linePos + ' ' + m.message).join('\\n')), e => done(String(e)));
          },
          // The group 0 layout from the twin's declarations: [binding, kind] pairs.
          layout(dev, entries) {
            const v = 1 | 2;   // VERTEX | FRAGMENT
            const made = entries.map(([binding, kind]) => {
              switch (kind) {
                case 'uniform': return { binding, visibility: v, buffer: { type: 'uniform' } };
                case 'storage': return { binding, visibility: v, buffer: { type: 'read-only-storage' } };
                case 'depth': return { binding, visibility: v, texture: { sampleType: 'depth' } };
                case 'unfilterable': return { binding, visibility: v, texture: { sampleType: 'unfilterable-float' } };
                case 'multisampled': return { binding, visibility: v, texture: { sampleType: 'unfilterable-float', multisampled: true } };
                case 'comparison': return { binding, visibility: v, sampler: { type: 'comparison' } };
                case 'sampler': return { binding, visibility: v, sampler: { type: 'filtering' } };
                default: return { binding, visibility: v, texture: { sampleType: 'float' } };
              }
            });
            const group = dev.createBindGroupLayout({ entries: made });
            return { group, pipeline: dev.createPipelineLayout({ bindGroupLayouts: [group] }) };
          },
          pipeline(dev, layout, module, vs, fs, colors, depthFormat, samples, compare, depthWrite, cull, front, topology, blends) {
            const d = {
              layout: layout.pipeline,
              vertex: { module, entryPoint: vs },
              primitive: { topology, cullMode: cull, frontFace: front },
              multisample: { count: samples },
            };
            if (fs) d.fragment = { module, entryPoint: fs, targets: colors.map((format, i) => blends[i] ? { format, blend: blends[i] } : { format }) };
            if (depthFormat) d.depthStencil = { format: depthFormat, depthCompare: compare, depthWriteEnabled: depthWrite };
            return dev.createRenderPipeline(d);
          },
          encoder(dev) { return dev.createCommandEncoder(); },
          // A render pass: colours as [texture, level, viewFormat, resolveTexture, resolveFormat, load, store, r, g, b, a].
          pass(enc, colors, depth) {
            const d = { colorAttachments: colors.map(c => {
              const a = { view: view(c[0], c[1], c[2]), loadOp: c[5], storeOp: c[6], clearValue: { r: c[7], g: c[8], b: c[9], a: c[10] } };
              if (c[3]) a.resolveTarget = view(c[3], -1, c[4]);
              return a;
            }) };
            if (depth) d.depthStencilAttachment = { view: view(depth[0], depth[1], ''), depthLoadOp: depth[2], depthStoreOp: depth[3], depthClearValue: depth[4] };
            return enc.beginRenderPass(d);
          },
          // A bind group: [binding, resource, offset, size] (a buffer, a texture or a sampler).
          bindGroup(dev, layout, entries) {
            return dev.createBindGroup({ layout: layout.group, entries: entries.map(([binding, r, offset, size]) =>
              r instanceof GPUBuffer ? { binding, resource: { buffer: r, offset, size: size > 0 ? size : undefined } }
              : r instanceof GPUTexture ? { binding, resource: r.createView() }
              : { binding, resource: r }) });
          },
          draw(pass, pipeline, group, viewport, index, indexFormat, count, instances, first) {
            pass.setPipeline(pipeline);
            pass.setBindGroup(0, group);
            if (viewport) pass.setViewport(viewport[0], viewport[1], viewport[2], viewport[3], viewport[4], viewport[5]);
            if (index) { pass.setIndexBuffer(index, indexFormat); pass.drawIndexed(count, instances, first); }
            else pass.draw(count, instances, first);
          },
          // Each smaller level drawn from the one above it (WebGPU has no generateMipmaps).
          mips(dev, enc, t, format, levels) {
            const cache = (dev.__swiftuiwebMips ||= {});
            let p = cache[format];
            if (!p) {
              const module = dev.createShaderModule({ code: mipCode });
              p = cache[format] = { pipeline: dev.createRenderPipeline({ layout: 'auto', vertex: { module, entryPoint: 'v' },
                fragment: { module, entryPoint: 'f', targets: [{ format }] } }),
                sampler: dev.createSampler({ magFilter: 'linear', minFilter: 'linear' }) };
            }
            for (let level = 1; level < levels; level++) {
              const group = dev.createBindGroup({ layout: p.pipeline.getBindGroupLayout(0), entries: [
                { binding: 0, resource: view(t, level - 1, '') }, { binding: 1, resource: p.sampler }] });
              const pass = enc.beginRenderPass({ colorAttachments: [{ view: view(t, level, ''), loadOp: 'clear', storeOp: 'store' }] });
              pass.setPipeline(p.pipeline); pass.setBindGroup(0, group); pass.draw(3); pass.end();
            }
          },
          copy(enc, a, ao, b, bo, size) { enc.copyBufferToBuffer(a, ao, b, bo, size); },
          submit(dev, enc) { dev.queue.submit([enc.finish()]); },
          done(dev, f) { dev.queue.onSubmittedWorkDone().then(() => f(), () => f()); },
          // A layer's canvas, sized and configured, kept in the page's surfaces under its id.
          canvas(dev, id, w, h, format, viewFormat, alpha) {
            const surfaces = (globalThis.__swiftuiwebSurfaces ||= new Map());
            let c = surfaces.get(id);
            if (!c) { c = document.createElement('canvas'); c.__ctx = c.getContext('webgpu'); surfaces.set(id, c); }
            const key = [w, h, format, viewFormat, alpha].join();
            if (c.__key !== key) {
              c.width = Math.max(1, w); c.height = Math.max(1, h);
              c.__ctx.configure({ device: dev, format, viewFormats: viewFormat !== format ? [viewFormat] : [], alphaMode: alpha,
                usage: 0x10 | 0x01 });   // RENDER_ATTACHMENT | COPY_SRC
              c.__key = key;
            }
            return c.__ctx.getCurrentTexture();
          },
          // Stand-ins for what a pass doesn't bind (a shadow pass binds only its vertices).
          dummies(dev) {
            const t = (format) => dev.createTexture({ size: [1, 1], format, usage: 4 | 16 });
            return { buffer: dev.createBuffer({ size: 4096, usage: U.UNIFORM | U.STORAGE }), float: t('rgba8unorm'), depth: t('depth32float'),
                     sampler: dev.createSampler(), comparison: dev.createSampler({ compare: 'less-equal' }) };
          },
          dropCanvas(id) { const s = globalThis.__swiftuiwebSurfaces; if (s) s.delete(id); },
        };
        """

    static func call(_ name: String, _ arguments: [ConvertibleToJSValue]) -> JSValue {
        guard let script, let function = script[name].object else { return .undefined }
        return function.callAsFunction(this: script, arguments: arguments)
    }

    static func warn(_ message: String) {
        _ = JSObject.global.console.object?.warn?(message)
    }

    static func bytes(_ pointer: UnsafeRawPointer, _ length: Int) -> JSTypedArray<UInt8> {
        JSTypedArray<UInt8>(buffer: UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: length))
    }
}

// MARK: - Device

public final class _WebGPUDevice: NSObject, MTLDevice, @unchecked Sendable {
    /// The page's device, once its request finished (nil without WebGPU).
    public static var shared: _WebGPUDevice? {
        if let made { return made }
        guard _GPU.script != nil, let device = JSObject.global.__swiftuiwebGPU.object, device.queue.object != nil else { return nil }
        made = _WebGPUDevice(device)
        return made
    }
    nonisolated(unsafe) private static var made: _WebGPUDevice?

    let gpu: JSObject
    /// The samplers an MSL source makes inline (`_MTLWGSLBinding.standardSamplers`).
    let standardSamplers: [JSValue]
    /// Uniform memory for `set…Bytes`, used round from the start.
    let ring: JSObject
    /// What a draw binds where the app bound nothing, by kind (`_GPU` layout's kinds).
    let dummies: JSObject
    private var ringOffset = 0
    static let ringSize = 1 << 20

    init(_ gpu: JSObject) {
        self.gpu = gpu
        let samplers = _GPU.call("standardSamplers", [gpu]).object
        standardSamplers = (0..<6).map { samplers?[$0] ?? .undefined }
        ring = _GPU.call("buffer", [gpu, Self.ringSize, JSValue.null]).object!
        dummies = _GPU.call("dummies", [gpu]).object!
        super.init()
    }

    /// Copies `length` bytes into the ring: its offset (WebGPU binds uniforms at 256-byte steps).
    func ringWrite(_ pointer: UnsafeRawPointer, length: Int) -> Int {
        let size = (length + 255) & ~255
        if ringOffset + size > Self.ringSize { ringOffset = 0 }
        let offset = ringOffset
        _ = _GPU.call("write", [gpu, ring, offset, _GPU.bytes(pointer, length)])
        ringOffset += size
        return offset
    }

    public var name: String { "WebGPU" }
    public func makeCommandQueue() -> (any MTLCommandQueue)? { _WebGPUQueue(device: self) }
    public func makeBuffer(length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? { _WebGPUBuffer(device: self, length: length, bytes: nil) }
    public func makeBuffer(bytes pointer: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> (any MTLBuffer)? {
        _WebGPUBuffer(device: self, length: length, bytes: pointer)
    }
    public func makeTexture(descriptor: MTLTextureDescriptor) -> (any MTLTexture)? { _WebGPUTexture(device: self, descriptor: descriptor) }
    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> (any MTLSamplerState)? { _WebGPUSampler(device: self, descriptor: descriptor) }
    public func makeDepthStencilState(descriptor: MTLDepthStencilDescriptor) -> (any MTLDepthStencilState)? {
        _WebGPUDepthState(compare: descriptor.depthCompareFunction, writes: descriptor.isDepthWriteEnabled)
    }

    /// The WGSL twin of an MSL source, from the app's browser build (`Shaders/<fingerprint>.wgsl`).
    public func makeLibrary(source: String, options: MTLCompileOptions?) throws -> any MTLLibrary { try twin(source) }

    private func twin(_ source: String) throws -> _WebGPULibrary {
        let name = _WebGPULibrary.fingerprint(source)
        guard let url = Bundle.main.url(forResource: name, withExtension: "wgsl", subdirectory: "Shaders"),
              let data = try? Data(contentsOf: url), let code = String(data: data, encoding: .utf8) else {
            _GPU.warn("SwiftUIWeb: no WGSL twin for a Metal library: the app's browser build needs Shaders/\(name).wgsl (new-website#746)")
            throw _MTLUnavailable()
        }
        return _WebGPULibrary(device: self, code: code)
    }

    /// The same, after the browser says it compiled: a twin with errors throws, as a failed compile does.
    public func makeLibrary(source: String, options: MTLCompileOptions?) async throws -> any MTLLibrary {
        let library = try twin(source)
        let errors: String = await withCheckedContinuation { continuation in
            let done = JSOneshotClosure { arguments in
                continuation.resume(returning: arguments.first?.string ?? "")
                return .undefined
            }
            _ = _GPU.call("errors", [library.module, done])
        }
        if !errors.isEmpty {
            _GPU.warn("SwiftUIWeb: a WGSL twin did not compile:\n\(errors)")
            throw _MTLUnavailable()
        }
        return library
    }

    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> any MTLRenderPipelineState {
        guard let vertex = descriptor.vertexFunction as? _WebGPUFunction else { throw _MTLUnavailable() }
        return _WebGPUPipelineState(device: self, descriptor: descriptor, vertex: vertex, fragment: descriptor.fragmentFunction as? _WebGPUFunction)
    }

    /// A Metal pixel format's WebGPU name.
    static func format(_ format: MTLPixelFormat) -> String {
        switch format {
        case .a8Unorm, .r8Unorm: "r8unorm"
        case .r16Float: "r16float"
        case .rg8Unorm: "rg8unorm"
        case .r32Float: "r32float"
        case .rgba8Unorm: "rgba8unorm"
        case .rgba8Unorm_srgb: "rgba8unorm-srgb"
        case .bgra8Unorm: "bgra8unorm"
        case .bgra8Unorm_srgb: "bgra8unorm-srgb"
        case .rgb10a2Unorm: "rgb10a2unorm"
        case .rg32Float: "rg32float"
        case .rgba16Float: "rgba16float"
        case .rgba32Float: "rgba32float"
        case .depth16Unorm: "depth16unorm"
        case .depth32Float: "depth32float"
        case .stencil8: "stencil8"
        case .depth32Float_stencil8: "depth32float-stencil8"
        case .invalid: ""
        }
    }

    static func compare(_ function: MTLCompareFunction) -> String {
        switch function {
        case .never: "never"
        case .less: "less"
        case .equal: "equal"
        case .lessEqual: "less-equal"
        case .greater: "greater"
        case .notEqual: "not-equal"
        case .greaterEqual: "greater-equal"
        case .always: "always"
        }
    }
}

// MARK: - Resources

final class _WebGPUBuffer: NSObject, MTLBuffer, @unchecked Sendable {
    let device: _WebGPUDevice
    let buffer: JSObject
    let length: Int
    private let memory: UnsafeMutableRawPointer
    /// Set when `contents()` handed out the memory: it is uploaded again when next bound.
    private var handedOut = false

    init(device: _WebGPUDevice, length: Int, bytes: UnsafeRawPointer?) {
        self.device = device
        self.length = length
        memory = UnsafeMutableRawPointer.allocate(byteCount: max(length, 1), alignment: 16)
        if let bytes { memory.copyMemory(from: bytes, byteCount: length) } else { memory.initializeMemory(as: UInt8.self, repeating: 0, count: max(length, 1)) }
        buffer = _GPU.call("buffer", [device.gpu, length, bytes == nil ? JSValue.null : _GPU.bytes(memory, length).jsValue]).object!
        super.init()
    }
    deinit {
        memory.deallocate()
        _ = buffer.destroy?()
    }

    func contents() -> UnsafeMutableRawPointer { handedOut = true; return memory }
    func didModifyRange(_ range: Range<Int>) { upload() }
    /// The GPU's copy, brought up to date with the memory the app may have written.
    var current: JSObject {
        if handedOut { upload() }
        return buffer
    }
    private func upload() {
        _ = _GPU.call("write", [device.gpu, buffer, 0, _GPU.bytes(memory, (length + 3) & ~3)])
    }
}

final class _WebGPUTexture: NSObject, MTLTexture, @unchecked Sendable {
    let texture: JSObject
    let width: Int, height: Int, mipmapLevelCount: Int, sampleCount: Int
    let pixelFormat: MTLPixelFormat, textureType: MTLTextureType, usage: MTLTextureUsage
    let device: _WebGPUDevice?
    /// How a render pass sees it (a canvas texture rendered as sRGB), "" for its own format.
    let viewFormat: String
    var format: String { _WebGPUDevice.format(pixelFormat) }

    init?(device: _WebGPUDevice, descriptor d: MTLTextureDescriptor) {
        let format = _WebGPUDevice.format(d.pixelFormat)
        guard !format.isEmpty else { return nil }
        let depth = d.pixelFormat == .depth16Unorm || d.pixelFormat == .depth32Float || d.pixelFormat == .stencil8 || d.pixelFormat == .depth32Float_stencil8
        let samples = d.textureType == .type2DMultisample ? max(d.sampleCount, 4) : 1
        // TEXTURE_BINDING 4, RENDER_ATTACHMENT 16, COPY_DST 2, COPY_SRC 1
        var flags = 0
        if d.usage.contains(.shaderRead) || d.usage.isEmpty || samples == 1 && !depth { flags |= 4 }
        if d.usage.contains(.renderTarget) || d.mipmapLevelCount > 1 || depth { flags |= 16 }
        if samples == 1 && !depth { flags |= 2 | 1 }
        guard let made = _GPU.call("texture", [device.gpu, d.width, d.height, format, d.mipmapLevelCount, samples, flags]).object else { return nil }
        texture = made
        width = d.width; height = d.height; mipmapLevelCount = d.mipmapLevelCount; sampleCount = samples
        pixelFormat = d.pixelFormat; textureType = d.textureType; usage = d.usage
        self.device = device
        viewFormat = ""
        super.init()
    }

    /// A drawable's texture: the canvas's current one.
    init(canvasTexture: JSObject, width: Int, height: Int, pixelFormat: MTLPixelFormat, viewFormat: String) {
        texture = canvasTexture
        self.width = width; self.height = height; mipmapLevelCount = 1; sampleCount = 1
        self.pixelFormat = pixelFormat; textureType = .type2D; usage = .renderTarget
        device = nil
        self.viewFormat = viewFormat
        super.init()
    }

    func replace(region: MTLRegion, mipmapLevel level: Int, withBytes pixelBytes: UnsafeRawPointer, bytesPerRow: Int) {
        guard let device else { return }
        let length = bytesPerRow * region.size.height
        _ = _GPU.call("writeTexture", [device.gpu, texture, level, region.origin.x, region.origin.y, region.size.width, region.size.height,
                                       _GPU.bytes(pixelBytes, length), bytesPerRow])
    }
}

final class _WebGPUSampler: NSObject, MTLSamplerState, @unchecked Sendable {
    let sampler: JSObject
    init?(device: _WebGPUDevice, descriptor d: MTLSamplerDescriptor) {
        func filter(_ f: MTLSamplerMinMagFilter) -> String { f == .linear ? "linear" : "nearest" }
        func address(_ a: MTLSamplerAddressMode) -> String {
            switch a {
            case .repeat: "repeat"
            case .mirrorRepeat: "mirror-repeat"
            default: "clamp-to-edge"
            }
        }
        let mip = d.mipFilter == .linear ? "linear" : "nearest"
        let aniso = d.minFilter == .linear && d.magFilter == .linear && d.mipFilter == .linear ? max(1, d.maxAnisotropy) : 1
        let compare = d.compareFunction.map(_WebGPUDevice.compare) ?? ""
        guard let made = _GPU.call("sampler", [device.gpu, filter(d.magFilter), filter(d.minFilter), mip, address(d.sAddressMode), address(d.tAddressMode),
                                               aniso, compare]).object else { return nil }
        sampler = made
        super.init()
    }
}

final class _WebGPUDepthState: NSObject, MTLDepthStencilState, @unchecked Sendable {
    let compare: MTLCompareFunction, writes: Bool
    init(compare: MTLCompareFunction, writes: Bool) { self.compare = compare; self.writes = writes }
}

// MARK: - Shaders and pipelines

final class _WebGPULibrary: NSObject, MTLLibrary, @unchecked Sendable {
    let device: _WebGPUDevice
    let module: JSObject
    /// The entry points by name, each with its stage.
    let entries: [String: String]
    /// Group 0's resources as the twin declares them: binding and kind (`_GPU` layout's kinds).
    let bindings: [(binding: Int, kind: String)]
    lazy var layout: JSObject = _GPU.call("layout", [device.gpu, bindings.map { [$0.binding.jsValue, $0.kind.jsValue].jsValue }]).object!

    init(device: _WebGPUDevice, code: String) {
        self.device = device
        module = _GPU.call("module", [device.gpu, code]).object!
        entries = Self.entryPoints(code)
        bindings = Self.declarations(code)
        super.init()
    }

    var functionNames: [String] { entries.keys.sorted() }
    func makeFunction(name functionName: String) -> (any MTLFunction)? {
        entries[functionName].map { _WebGPUFunction(library: self, name: functionName, stage: $0) }
    }

    /// The MSL source's name for its twin: FNV-1a (64 bits) of its UTF-8, in hex.
    static func fingerprint(_ source: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in source.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    /// `@vertex fn name` and `@fragment fn name`.
    static func entryPoints(_ code: String) -> [String: String] {
        var found: [String: String] = [:]
        let words = code.split(whereSeparator: { $0.isWhitespace || $0 == "(" })
        for (index, word) in words.enumerated() where (word == "@vertex" || word == "@fragment") {
            var next = index + 1
            while next < words.count, words[next].hasPrefix("@") { next += 1 }
            if next + 1 < words.count, words[next] == "fn" { found[String(words[next + 1])] = word == "@vertex" ? "vertex" : "fragment" }
        }
        return found
    }

    /// `@group(0) @binding(N) var<…> name: type;` declarations.
    static func declarations(_ code: String) -> [(binding: Int, kind: String)] {
        var found: [(Int, String)] = []
        for line in code.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("@group(0)"), let b = text.range(of: "@binding("), let close = text[b.upperBound...].firstIndex(of: ")"),
                  let binding = Int(text[b.upperBound..<close]), let colon = text[close...].firstIndex(of: ":") else { continue }
            let head = text[close..<colon], type = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let kind: String
            if head.contains("var<uniform") { kind = "uniform" }
            else if head.contains("var<storage") { kind = "storage" }
            else if type.hasPrefix("sampler_comparison") { kind = "comparison" }
            else if type.hasPrefix("sampler") { kind = "sampler" }
            else if type.hasPrefix("texture_depth") { kind = "depth" }
            else if type.hasPrefix("texture_multisampled") { kind = "multisampled" }
            else { kind = "float" }
            found.append((binding, kind))
        }
        return found
    }
}

final class _WebGPUFunction: NSObject, MTLFunction, @unchecked Sendable {
    let library: _WebGPULibrary, name: String, stage: String
    init(library: _WebGPULibrary, name: String, stage: String) { self.library = library; self.name = name; self.stage = stage }
}

final class _WebGPUPipelineState: NSObject, MTLRenderPipelineState, @unchecked Sendable {
    let device: _WebGPUDevice
    let vertex: _WebGPUFunction, fragment: _WebGPUFunction?
    let colors: [String]
    let blends: [JSValue]
    let depthFormat: String
    let samples: Int
    /// The WebGPU pipelines made so far, by the encoder state they bake in.
    private var made: [String: JSObject] = [:]

    init(device: _WebGPUDevice, descriptor d: MTLRenderPipelineDescriptor, vertex: _WebGPUFunction, fragment: _WebGPUFunction?) {
        self.device = device
        self.vertex = vertex
        self.fragment = fragment
        var colors: [String] = [], blends: [JSValue] = []
        for index in 0..<8 {
            guard let attachment = d.colorAttachments[index], attachment.pixelFormat != .invalid else { break }
            colors.append(_WebGPUDevice.format(attachment.pixelFormat))
            blends.append(attachment.isBlendingEnabled ? Self.blend(attachment) : .null)
        }
        self.colors = colors
        self.blends = blends
        depthFormat = _WebGPUDevice.format(d.depthAttachmentPixelFormat)
        samples = d.rasterSampleCount
        super.init()
    }

    static func blend(_ a: MTLRenderPipelineColorAttachmentDescriptor) -> JSValue {
        func factor(_ f: MTLBlendFactor) -> String {
            switch f {
            case .zero: "zero"
            case .one: "one"
            case .sourceColor: "src"
            case .oneMinusSourceColor: "one-minus-src"
            case .sourceAlpha: "src-alpha"
            case .oneMinusSourceAlpha: "one-minus-src-alpha"
            }
        }
        func operation(_ o: MTLBlendOperation) -> String {
            switch o {
            case .add: "add"
            case .subtract: "subtract"
            case .reverseSubtract: "reverse-subtract"
            case .min: "min"
            case .max: "max"
            }
        }
        let object = JSObject.global.Object.function!.new()
        let color = JSObject.global.Object.function!.new(), alpha = JSObject.global.Object.function!.new()
        color.srcFactor = .string(factor(a.sourceRGBBlendFactor)); color.dstFactor = .string(factor(a.destinationRGBBlendFactor))
        color.operation = .string(operation(a.rgbBlendOperation))
        alpha.srcFactor = .string(factor(a.sourceAlphaBlendFactor)); alpha.dstFactor = .string(factor(a.destinationAlphaBlendFactor))
        alpha.operation = .string(operation(a.alphaBlendOperation))
        object.color = .object(color); object.alpha = .object(alpha)
        return .object(object)
    }

    func pipeline(depth: _WebGPUDepthState?, cull: MTLCullMode, front: MTLWinding, topology: MTLPrimitiveType) -> JSObject? {
        let compare = depth.map { _WebGPUDevice.compare($0.compare) } ?? "always"
        let writes = depth?.writes ?? false
        let cullName = cull == .front ? "front" : cull == .back ? "back" : "none"
        // Metal's front faces wind clockwise unless told otherwise.
        let frontName = front == .clockwise ? "cw" : "ccw"
        let topologyName: String
        switch topology {
        case .point: topologyName = "point-list"
        case .line: topologyName = "line-list"
        case .lineStrip: topologyName = "line-strip"
        case .triangle: topologyName = "triangle-list"
        case .triangleStrip: topologyName = "triangle-strip"
        }
        let key = [compare, String(writes), cullName, frontName, topologyName].joined(separator: " ")
        if let found = made[key] { return found }
        let library = vertex.library
        guard let created = _GPU.call("pipeline", [device.gpu, library.layout, library.module, vertex.name, fragment?.name ?? JSValue.null,
                                                   colors.jsValue, depthFormat.isEmpty ? JSValue.null : depthFormat.jsValue, samples, compare, writes,
                                                   cullName, frontName, topologyName, blends.jsValue]).object else { return nil }
        made[key] = created
        return created
    }
}

// MARK: - Commands

final class _WebGPUQueue: NSObject, MTLCommandQueue, @unchecked Sendable {
    let device: _WebGPUDevice
    init(device: _WebGPUDevice) { self.device = device }
    func makeCommandBuffer() -> (any MTLCommandBuffer)? { _WebGPUCommandBuffer(device: device) }
}

/// A drawable the command buffer presents: told when its frame is submitted.
public protocol _WebGPUPresentable: AnyObject {
    func _presented()
}

final class _WebGPUCommandBuffer: NSObject, MTLCommandBuffer, @unchecked Sendable {
    let device: _WebGPUDevice
    let encoder: JSObject
    private(set) var status: MTLCommandBufferStatus = .notEnqueued
    private var presented: [any _WebGPUPresentable] = []
    private var completed: [@Sendable (any MTLCommandBuffer) -> Void] = []

    init(device: _WebGPUDevice) {
        self.device = device
        encoder = _GPU.call("encoder", [device.gpu]).object!
    }

    func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> (any MTLRenderCommandEncoder)? {
        _WebGPURenderEncoder(buffer: self, descriptor: descriptor)
    }
    func makeBlitCommandEncoder() -> (any MTLBlitCommandEncoder)? { _WebGPUBlitEncoder(buffer: self) }
    func present(_ drawable: any MTLDrawable) {
        if let presentable = drawable as? any _WebGPUPresentable { presented.append(presentable) }
    }
    func commit() {
        guard status == .notEnqueued else { return }
        _ = _GPU.call("submit", [device.gpu, encoder])
        status = .committed
        for drawable in presented { drawable._presented() }
        presented = []
        let handlers = completed
        completed = []
        let done = JSOneshotClosure { [self] _ in
            status = .completed
            for handler in handlers { handler(self) }
            return .undefined
        }
        _ = _GPU.call("done", [device.gpu, done])
    }
    /// A page can't wait for the GPU; later work is queued after this anyway.
    func waitUntilCompleted() {}
    func addCompletedHandler(_ block: @escaping @Sendable (any MTLCommandBuffer) -> Void) { completed.append(block) }
}

final class _WebGPURenderEncoder: NSObject, MTLRenderCommandEncoder, @unchecked Sendable {
    let buffer: _WebGPUCommandBuffer
    let pass: JSObject?
    private var pipelineState: _WebGPUPipelineState?
    private var depthState: _WebGPUDepthState?
    private var cull: MTLCullMode = .none
    private var front: MTLWinding = .clockwise
    private var viewport: JSValue = .null
    /// The resources bound so far, by WGSL binding: a buffer (with offset and size), a texture or a sampler.
    private var bound: [Int: (resource: JSValue, offset: Int, size: Int)] = [:]
    private var device: _WebGPUDevice { buffer.device }

    init(buffer: _WebGPUCommandBuffer, descriptor d: MTLRenderPassDescriptor) {
        self.buffer = buffer
        func load(_ action: MTLLoadAction) -> String { action == .load ? "load" : "clear" }
        func store(_ action: MTLStoreAction) -> String { action == .store || action == .storeAndMultisampleResolve ? "store" : "discard" }
        var colors: [JSValue] = []
        for index in 0..<8 {
            guard let attachment = d.colorAttachments[index], let texture = attachment.texture as? _WebGPUTexture else { continue }
            let resolve = attachment.resolveTexture as? _WebGPUTexture
            let c = attachment.clearColor
            colors.append([texture.texture.jsValue, attachment.level.jsValue, texture.viewFormat.jsValue,
                           resolve.map { $0.texture.jsValue } ?? .null, (resolve?.viewFormat ?? "").jsValue,
                           load(attachment.loadAction).jsValue, store(attachment.storeAction).jsValue,
                           c.red.jsValue, c.green.jsValue, c.blue.jsValue, c.alpha.jsValue].jsValue)
        }
        var depth: JSValue = .null
        if let attachment = d.depthAttachment, let texture = attachment.texture as? _WebGPUTexture {
            depth = [texture.texture.jsValue, attachment.level.jsValue, load(attachment.loadAction).jsValue,
                     store(attachment.storeAction).jsValue, attachment.clearDepth.jsValue].jsValue
        }
        pass = _GPU.call("pass", [buffer.encoder, colors.jsValue, depth]).object
        super.init()
    }

    func endEncoding() { _ = pass?.end?() }
    func setRenderPipelineState(_ pipelineState: any MTLRenderPipelineState) { self.pipelineState = pipelineState as? _WebGPUPipelineState }
    func setDepthStencilState(_ depthStencilState: (any MTLDepthStencilState)?) { depthState = depthStencilState as? _WebGPUDepthState }
    func setCullMode(_ cullMode: MTLCullMode) { cull = cullMode }
    func setFrontFacing(_ frontFacingWinding: MTLWinding) { front = frontFacingWinding }
    func setViewport(_ v: MTLViewport) {
        viewport = [v.originX, v.originY, v.width, v.height, v.znear, v.zfar].jsValue
    }

    private func bind(_ binding: Int, _ b: (any MTLBuffer)?, offset: Int) {
        guard let b = b as? _WebGPUBuffer else { bound[binding] = nil; return }
        bound[binding] = (b.current.jsValue, offset, b.length - offset)
    }
    private func bindBytes(_ binding: Int, _ bytes: UnsafeRawPointer, _ length: Int) {
        let offset = device.ringWrite(bytes, length: length)
        bound[binding] = (device.ring.jsValue, offset, (length + 15) & ~15)
    }
    func setVertexBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) { bind(_MTLWGSLBinding.vertexBuffer(index), buffer, offset: offset) }
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { bindBytes(_MTLWGSLBinding.vertexBuffer(index), bytes, length) }
    func setFragmentBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: Int) { bind(_MTLWGSLBinding.fragmentBuffer(index), buffer, offset: offset) }
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { bindBytes(_MTLWGSLBinding.fragmentBuffer(index), bytes, length) }
    func setVertexTexture(_ texture: (any MTLTexture)?, index: Int) {
        bound[_MTLWGSLBinding.vertexTexture(index)] = (texture as? _WebGPUTexture).map { ($0.texture.jsValue, 0, 0) }
    }
    func setFragmentTexture(_ texture: (any MTLTexture)?, index: Int) {
        bound[_MTLWGSLBinding.fragmentTexture(index)] = (texture as? _WebGPUTexture).map { ($0.texture.jsValue, 0, 0) }
    }
    func setFragmentSamplerState(_ sampler: (any MTLSamplerState)?, index: Int) {
        bound[_MTLWGSLBinding.fragmentSampler(index)] = (sampler as? _WebGPUSampler).map { ($0.sampler.jsValue, 0, 0) }
    }

    /// The bind group for a draw: every binding the twin declares, from what is bound, and a
    /// stand-in for what isn't (a pass that uses only some of the twin's resources).
    private func group(_ state: _WebGPUPipelineState) -> JSObject? {
        var entries: [JSValue] = []
        for (binding, kind) in state.vertex.library.bindings {
            let entry: (resource: JSValue, offset: Int, size: Int)
            if _MTLWGSLBinding.standardSamplers.contains(binding) {
                entry = (device.standardSamplers[binding - _MTLWGSLBinding.standardSamplers.lowerBound], 0, 0)
            } else if let found = bound[binding] {
                entry = found
            } else {
                let stand = kind == "uniform" || kind == "storage" ? "buffer" : kind == "unfilterable" || kind == "multisampled" ? "float" : kind
                entry = (device.dummies[stand], 0, 0)
            }
            entries.append([binding.jsValue, entry.resource, entry.offset.jsValue, entry.size.jsValue].jsValue)
        }
        return _GPU.call("bindGroup", [device.gpu, state.vertex.library.layout, entries.jsValue]).object
    }

    private func draw(_ type: MTLPrimitiveType, index: JSValue, format: String, count: Int, instances: Int, first: Int) {
        guard let pass, let state = pipelineState, let pipeline = state.pipeline(depth: depthState, cull: cull, front: front, topology: type),
              let group = group(state) else { return }
        _ = _GPU.call("draw", [pass, pipeline, group, viewport, index, format, count, instances, first])
    }
    func drawPrimitives(type primitiveType: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) {
        draw(primitiveType, index: .null, format: "", count: vertexCount, instances: instanceCount, first: vertexStart)
    }
    func drawIndexedPrimitives(type primitiveType: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType, indexBuffer: any MTLBuffer,
                               indexBufferOffset: Int, instanceCount: Int) {
        guard let indices = indexBuffer as? _WebGPUBuffer else { return }
        let size = indexType == .uint32 ? 4 : 2
        draw(primitiveType, index: indices.current.jsValue, format: indexType == .uint32 ? "uint32" : "uint16", count: indexCount,
             instances: instanceCount, first: indexBufferOffset / size)
    }
}

final class _WebGPUBlitEncoder: NSObject, MTLBlitCommandEncoder, @unchecked Sendable {
    let buffer: _WebGPUCommandBuffer
    init(buffer: _WebGPUCommandBuffer) { self.buffer = buffer }
    func endEncoding() {}
    func generateMipmaps(for texture: any MTLTexture) {
        guard let texture = texture as? _WebGPUTexture, texture.mipmapLevelCount > 1 else { return }
        _ = _GPU.call("mips", [buffer.device.gpu, buffer.encoder, texture.texture, texture.format, texture.mipmapLevelCount])
    }
    func copy(from sourceBuffer: any MTLBuffer, sourceOffset: Int, to destinationBuffer: any MTLBuffer, destinationOffset: Int, size: Int) {
        guard let a = sourceBuffer as? _WebGPUBuffer, let b = destinationBuffer as? _WebGPUBuffer else { return }
        _ = _GPU.call("copy", [buffer.encoder, a.current, sourceOffset, b.current, destinationOffset, size])
    }
}

// MARK: - Layers

/// A Metal layer's canvas (QuartzCore's `CAMetalLayer`): its current texture each frame, shown as
/// a surface of the frame.
public final class _WebGPUCanvas: @unchecked Sendable {
    public let surface: Int
    nonisolated(unsafe) private static var next = 0
    public init() {
        Self.next += 1
        surface = 2_000_000 + Self.next
    }
    deinit { _ = _GPU.call("dropCanvas", [surface]) }

    /// The texture to draw this frame into, sized in pixels; nil without a device.
    public func nextTexture(device: (any MTLDevice)?, width: Int, height: Int, pixelFormat: MTLPixelFormat, opaque: Bool) -> (any MTLTexture)? {
        guard let device = device as? _WebGPUDevice, width > 0, height > 0 else { return nil }
        let viewFormat = _WebGPUDevice.format(pixelFormat)
        // A canvas holds bgra8unorm or rgba8unorm; the sRGB form is how passes see it.
        let format = viewFormat.hasPrefix("rgba8") ? "rgba8unorm" : "bgra8unorm"
        guard let texture = _GPU.call("canvas", [device.gpu, surface, width, height, format, viewFormat, opaque ? "opaque" : "premultiplied"]).object else { return nil }
        return _WebGPUTexture(canvasTexture: texture, width: width, height: height, pixelFormat: pixelFormat, viewFormat: viewFormat == format ? "" : viewFormat)
    }
}
#endif
