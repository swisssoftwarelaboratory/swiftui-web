// Metal shaders as SwiftUI names them (`ShaderLibrary`, `Shader`, `colorEffect`, `layerEffect`,
// `distortionEffect`). A page has no Metal and no compiled `.metallib`. A `colorEffect` runs on
// the page's GPU when the app's browser build ships the function's WGSL twin
// (`Shaders/<function>.wgsl`, new-website#746): the host renders it at the view's size and the
// frame paints it at the view's place; the view's own colours don't reach it yet (`color` is
// opaque black), which shaders that paint whole fills don't read. Without a twin or a GPU the view
// is not drawn, as before. `layerEffect` views are not drawn, and `distortionEffect` views are
// drawn undistorted. Accepted for source compatibility.
import WebFoundation

/// A Metal shader library: functions are looked up by name (`ShaderLibrary.default.wave`).
@dynamicMemberLookup
public struct ShaderLibrary: Equatable, @unchecked Sendable {
    package let source: String

    /// The default library of the main bundle.
    public static let `default` = ShaderLibrary(source: "main")
    /// The default library of a bundle.
    public static func bundle(_ bundle: Bundle) -> ShaderLibrary { ShaderLibrary(source: "\(bundle.bundleURL)") }
    /// A library from a `.metallib` file.
    public init(url: URL) { source = url.absoluteString }
    /// A library from a `.metallib`'s data.
    public init(data: Data) { source = "data:\(data.count)" }
    package init(source: String) { self.source = source }

    /// The function `name` of the library.
    public subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: self, name: name) }
    /// The function `name` of the default library.
    public static subscript(dynamicMember name: String) -> ShaderFunction { ShaderFunction(library: .default, name: name) }
}

/// A function of a shader library; calling it with arguments makes a shader.
@dynamicCallable
public struct ShaderFunction: Equatable, Sendable {
    public var library: ShaderLibrary
    public var name: String

    public init(library: ShaderLibrary, name: String) {
        self.library = library
        self.name = name
    }

    public func dynamicallyCall(withArguments arguments: [Shader.Argument]) -> Shader {
        Shader(function: self, arguments: arguments)
    }
}

/// A shader function with its arguments.
public struct Shader: Equatable, Sendable {
    /// One argument of a shader function.
    public struct Argument: Equatable, Sendable {
        package enum Kind: Equatable, Sendable {
            case floats([Double]), floatArray([Double]), color(Color), colors([Color]), image(Image), data(Data), boundingRect
        }
        package let kind: Kind

        public static func float<T: BinaryFloatingPoint>(_ x: T) -> Argument { Argument(kind: .floats([Double(x)])) }
        public static func float2<T: BinaryFloatingPoint>(_ x: T, _ y: T) -> Argument { Argument(kind: .floats([Double(x), Double(y)])) }
        public static func float3<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T) -> Argument { Argument(kind: .floats([Double(x), Double(y), Double(z)])) }
        public static func float4<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T, _ w: T) -> Argument { Argument(kind: .floats([Double(x), Double(y), Double(z), Double(w)])) }
        public static func float2(_ point: CGPoint) -> Argument { .float2(point.x, point.y) }
        public static func float2(_ size: CGSize) -> Argument { .float2(size.width, size.height) }
        public static func float2(_ vector: CGVector) -> Argument { .float2(vector.dx, vector.dy) }
        public static func floatArray(_ array: [Float]) -> Argument { Argument(kind: .floatArray(array.map(Double.init))) }
        public static func color(_ color: Color) -> Argument { Argument(kind: .color(color)) }
        public static func colorArray(_ array: [Color]) -> Argument { Argument(kind: .colors(array)) }
        public static func image(_ image: Image) -> Argument { Argument(kind: .image(image)) }
        public static func data(_ data: Data) -> Argument { Argument(kind: .data(data)) }
        public static var boundingRect: Argument { Argument(kind: .boundingRect) }

        public static func == (a: Argument, b: Argument) -> Bool {
            switch (a.kind, b.kind) {
            case (.floats(let x), .floats(let y)): return x == y
            case (.floatArray(let x), .floatArray(let y)): return x == y
            case (.color(let x), .color(let y)): return x == y
            case (.colors(let x), .colors(let y)): return x == y
            case (.data(let x), .data(let y)): return x == y
            case (.boundingRect, .boundingRect): return true
            default: return false
            }
        }
    }

    public var function: ShaderFunction
    public var arguments: [Argument]
    /// Whether the shader dithers its colours (no shader runs here).
    public var dithersColor = false

    public init(function: ShaderFunction, arguments: [Argument]) {
        self.function = function
        self.arguments = arguments
    }

    /// Compiles the shader ahead of use: nothing to compile on the web.
    public func compile(as type: ShaderType) async throws {}

    public enum ShaderType: Sendable { case colorEffect, layerEffect, distortionEffect }
}

/// What the host is handed for one argument of a shader running on the GPU.
public enum _ShaderValue: Sendable {
    /// One to four floats (`float` to `float4`).
    case floats([Double])
    /// A float array (`floatArray`), which the Metal function takes as a pointer and a count.
    case floatArray([Double])
    /// A colour, its sRGB components and opacity.
    case color(red: Double, green: Double, blue: Double, alpha: Double)
}

/// The host that runs a `colorEffect` on the page's GPU (new-website#746).
public enum _ShaderHost {
    /// Renders `function` with `arguments` over `size` points at `scale` pixels a point into the
    /// frame's surface `surface`; false when it can't (no twin, no GPU), and nothing is drawn.
    @MainActor public static var render: ((_ function: String, _ arguments: [_ShaderValue], _ size: CGSize, _ scale: CGFloat, _ surface: Int) -> Bool)?
}

/// Where a `colorEffect`'s colours are painted: over the view, at its size.
struct _ColorEffectModifier: ViewModifier {
    let shader: Shader
    let isEnabled: Bool
    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 0 : 1).overlay {
            if isEnabled { _ShaderEffectSurface(shader: shader) }
        }
    }
}

/// The shader's picture at the view's place, as a surface of the frame.
public struct _ShaderEffectSurface: View {
    let shader: Shader
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ShaderEffectSurface>) -> TypedNode<_ShaderEffectSurface> {
        _ShaderEffectNode(context)
    }
}

@MainActor
package final class _ShaderEffectNode: LeafNode<_ShaderEffectSurface> {
    private let surface: Int

    package override init(_ context: _NodeContext<_ShaderEffectSurface>) {
        surface = 3_000_000 + context.runtime.nextHostElementIdentifier()
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        guard bounds.width > 0, bounds.height > 0, let render = _ShaderHost.render else { return }
        var values: [_ShaderValue] = []
        for argument in view.shader.arguments {
            switch argument.kind {
            case .floats(let floats): values.append(.floats(floats))
            case .floatArray(let floats): values.append(.floatArray(floats))
            case .color(let color):
                let rgba = color.resolve(in: environment)
                values.append(.color(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha))
            case .boundingRect: values.append(.floats([0, 0, Double(bounds.width), Double(bounds.height)]))
            case .colors, .image, .data: return   // not passed to a twin yet: nothing drawn, as before
            }
        }
        guard render(view.shader.function.name, values, bounds.size, context.scale, surface) else { return }
        list.append(.drawSurface(surface, rect: bounds, fit: .fill))
    }

    override package var nodeDescription: String { "ShaderEffect" }
}

extension View {
    /// Fills the view's pixels with the shader's colours: drawn on the page's GPU from the
    /// function's WGSL twin; not drawn without one (see the file's note).
    nonisolated public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View {
        modifier(_ColorEffectModifier(shader: shader, isEnabled: isEnabled))
    }

    /// Runs the shader over the view's layer: not drawn on the web (no Metal).
    nonisolated public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View {
        opacity(isEnabled ? 0 : 1)
    }

    /// Moves the view's pixels by the shader: drawn undistorted on the web (no Metal).
    nonisolated public func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View { self }
}
