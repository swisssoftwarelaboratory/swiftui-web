// Metal shaders as SwiftUI names them (`ShaderLibrary`, `Shader`, `colorEffect`, `layerEffect`,
// `distortionEffect`). A page has no Metal and no compiled `.metallib`, so the functions are
// names with their arguments and nothing runs them: a view under `colorEffect` or `layerEffect`
// is not drawn (its colours are the shader's, which cannot be computed here), and one under
// `distortionEffect` is drawn undistorted. Accepted for source compatibility.
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
            case floats([Double]), color(Color), colors([Color]), image(Image), data(Data), boundingRect
        }
        package let kind: Kind

        public static func float<T: BinaryFloatingPoint>(_ x: T) -> Argument { Argument(kind: .floats([Double(x)])) }
        public static func float2<T: BinaryFloatingPoint>(_ x: T, _ y: T) -> Argument { Argument(kind: .floats([Double(x), Double(y)])) }
        public static func float3<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T) -> Argument { Argument(kind: .floats([Double(x), Double(y), Double(z)])) }
        public static func float4<T: BinaryFloatingPoint>(_ x: T, _ y: T, _ z: T, _ w: T) -> Argument { Argument(kind: .floats([Double(x), Double(y), Double(z), Double(w)])) }
        public static func float2(_ point: CGPoint) -> Argument { .float2(point.x, point.y) }
        public static func float2(_ size: CGSize) -> Argument { .float2(size.width, size.height) }
        public static func float2(_ vector: CGVector) -> Argument { .float2(vector.dx, vector.dy) }
        public static func floatArray(_ array: [Float]) -> Argument { Argument(kind: .floats(array.map(Double.init))) }
        public static func color(_ color: Color) -> Argument { Argument(kind: .color(color)) }
        public static func colorArray(_ array: [Color]) -> Argument { Argument(kind: .colors(array)) }
        public static func image(_ image: Image) -> Argument { Argument(kind: .image(image)) }
        public static func data(_ data: Data) -> Argument { Argument(kind: .data(data)) }
        public static var boundingRect: Argument { Argument(kind: .boundingRect) }

        public static func == (a: Argument, b: Argument) -> Bool {
            switch (a.kind, b.kind) {
            case (.floats(let x), .floats(let y)): return x == y
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

extension View {
    /// Fills the view's pixels with the shader's colours: not drawn on the web (no Metal).
    nonisolated public func colorEffect(_ shader: Shader, isEnabled: Bool = true) -> some View {
        opacity(isEnabled ? 0 : 1)
    }

    /// Runs the shader over the view's layer: not drawn on the web (no Metal).
    nonisolated public func layerEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View {
        opacity(isEnabled ? 0 : 1)
    }

    /// Moves the view's pixels by the shader: drawn undistorted on the web (no Metal).
    nonisolated public func distortionEffect(_ shader: Shader, maxSampleOffset: CGSize, isEnabled: Bool = true) -> some View { self }
}
