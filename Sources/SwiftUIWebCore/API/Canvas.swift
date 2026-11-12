/// A view type that supports immediate mode drawing (`Docs/elements/Canvas.md`).
///
/// The renderer draws into a `GraphicsContext` that records display-list commands in the
/// canvas's coordinate space: paths are filled and stroked with colours, text is laid out with
/// the environment's font, and the context's transform, opacity and clip apply to what follows.
public struct Canvas<Symbols: View>: View {
    package let renderer: _CanvasRenderer
    package let opaque: Bool
    package let colorMode: ColorRenderingMode
    package let rendersAsynchronously: Bool
    package let symbols: Symbols
    /// Whether the drawing is clipped to the canvas's bounds (a chart's axis labels spill over
    /// its edges, as Swift Charts' do).
    package var clipsToBounds = true

    /// Creates and configures a canvas.
    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void, @ViewBuilder symbols: () -> Symbols) {
        self.renderer = _CanvasRenderer(renderer)
        self.opaque = opaque
        self.colorMode = colorMode
        self.rendersAsynchronously = rendersAsynchronously
        self.symbols = symbols()
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Canvas<Symbols>>) -> TypedNode<Canvas<Symbols>> {
        CanvasNode(context)
    }
}

extension Canvas {
    /// A canvas whose drawing is not clipped to its bounds (Charts).
    package func _unclipped() -> Canvas { var c = self; c.clipsToBounds = false; return c }
}

extension Canvas where Symbols == EmptyView {
    /// Creates and configures a canvas without symbols.
    public init(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.init(opaque: opaque, colorMode: colorMode, rendersAsynchronously: rendersAsynchronously, renderer: renderer) { EmptyView() }
    }
}

/// The working color space and storage format used to render a canvas.
public enum ColorRenderingMode: Hashable, Sendable {
    case nonLinear, linear, extendedLinear
}

/// Holds a canvas renderer (a class so the runtime's field reflection ignores it).
package final class _CanvasRenderer {
    package let draw: (inout GraphicsContext, CGSize) -> Void
    package init(_ draw: @escaping (inout GraphicsContext, CGSize) -> Void) { self.draw = draw }
}

/// The records a `GraphicsContext` appends to (shared by copies of the context).
@MainActor
package final class _GraphicsRecorder {
    package var list = DisplayList()
    package let environment: EnvironmentValues
    package let textEngine: any TextEngine
    package let scale: CGFloat
    /// The canvas node: images and symbols paint through nodes made under it.
    package weak var node: ViewNode?
    /// The `symbols` views, by their tags (`resolveSymbol`).
    package var symbols: [(id: AnyHashable, node: ViewNode)] = []

    package init(environment: EnvironmentValues, textEngine: any TextEngine, scale: CGFloat) {
        self.environment = environment
        self.textEngine = textEngine
        self.scale = scale
    }
}

/// An immediate-mode drawing destination, and its current state. Its drawing methods are
/// nonisolated, as Apple's are (an app draws from free functions and nonisolated helpers); a page
/// has one thread, so they run the main-actor recorder in place, and the context is
/// `@unchecked Sendable` for that hand-over.
public struct GraphicsContext: @unchecked Sendable {
    package let recorder: _GraphicsRecorder
    /// The current transform from the context's space to the canvas's.
    public var transform: CGAffineTransform = .identity
    /// The opacity of drawing that follows.
    public var opacity: Double = 1
    /// The blend mode of drawing that follows: each operation composites with it.
    public var blendMode: BlendMode = .normal
    /// Clips accumulated on this context, in the canvas's space.
    package var clips: [(Path, Bool)] = []
    /// Filters applied to each operation that follows (`addFilter`), in order.
    package var filters: [Filter] = []
    /// The environment of the canvas view.
    public var environment: EnvironmentValues { _readOnMainActor { recorder.environment } }

    package init(recorder: _GraphicsRecorder) { self.recorder = recorder }

    /// A color or pattern that you can use to outline or fill paths and shapes.
    public struct Shading: Sendable {
        package enum Kind: Sendable {
            case color(Color), foreground, background
            /// Gradients in the context's space (transformed when drawn).
            case linear(Gradient, start: CGPoint, end: CGPoint)
            case radial(Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
            case conic(Gradient, center: CGPoint, angle: Angle)
            /// A shape style resolved against the drawn path's bounds.
            case style(any ShapeStyle)
            /// An image repeated across the filled area, in the context's space.
            case tiled(Image, origin: CGPoint, scale: CGFloat)
        }
        package let kind: Kind

        /// A shading that fills with an image repeated from `origin` at `scale`.
        public static func tiledImage(_ image: Image, origin: CGPoint = .zero, sourceRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), scale: CGFloat = 1) -> Shading {
            Shading(kind: .tiled(image, origin: origin, scale: scale))
        }

        public static func color(_ color: Color) -> Shading { Shading(kind: .color(color)) }
        public static var foreground: Shading { Shading(kind: .foreground) }
        public static var backgroundStyle: Shading { Shading(kind: .background) }
        public static func color(red: Double, green: Double, blue: Double, opacity: Double = 1) -> Shading {
            Shading(kind: .color(Color(red: red, green: green, blue: blue, opacity: opacity)))
        }
        public static func linearGradient(_ gradient: Gradient, startPoint: CGPoint, endPoint: CGPoint, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .linear(gradient, start: startPoint, end: endPoint))
        }
        public static func radialGradient(_ gradient: Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .radial(gradient, center: center, startRadius: startRadius, endRadius: endRadius))
        }
        public static func conicGradient(_ gradient: Gradient, center: CGPoint, angle: Angle = .zero, options: GradientOptions = GradientOptions()) -> Shading {
            Shading(kind: .conic(gradient, center: center, angle: angle))
        }
        public static func style<S: ShapeStyle>(_ style: S) -> Shading { Shading(kind: .style(style)) }

        /// The flat colour of a colour shading (gradients resolve through `gradient`).
        @MainActor package func resolve(in environment: EnvironmentValues) -> RGBA {
            switch kind {
            case .color(let color): return color.resolve(in: environment)
            case .foreground: return (environment.foregroundColor ?? .primary).resolve(in: environment)
            case .background: return Color.white.resolve(in: environment)
            case .style(let style): return style.resolveColor(in: environment)
            case .linear, .radial, .conic, .tiled: return Color.primary.resolve(in: environment)
            }
        }

        /// The gradient a gradient shading paints, in the canvas's absolute space: the
        /// context's points through `transform`, a style against the path's `bounds`.
        @MainActor package func gradient(bounds: CGRect, transform: CGAffineTransform, environment: EnvironmentValues) -> DisplayGradient? {
            let magnitude = (transform.a * transform.a + transform.b * transform.b).squareRoot()
            switch kind {
            case .linear(let gradient, let start, let end):
                return DisplayGradient(kind: .linear(start: start.applying(transform), end: end.applying(transform)), stops: gradient.resolvedStops(in: environment))
            case .radial(let gradient, let center, let r0, let r1):
                return DisplayGradient(kind: .radial(center: center.applying(transform), startRadius: r0 * magnitude, endRadius: r1 * magnitude),
                                       stops: gradient.resolvedStops(in: environment))
            case .conic(let gradient, let center, let angle):
                return DisplayGradient(kind: .angular(center: center.applying(transform), startAngle: angle.radians + _atan2(Double(transform.b), Double(transform.a))),
                                       stops: gradient.resolvedStops(in: environment))
            case .style(let style):
                // An erased flat style stays a colour: a one-stop gradient paints nothing in Canvas2D.
                let base = (style as? AnyShapeStyle)?.base ?? style
                guard !(base is Color), !(base is HierarchicalShapeStyle), let gradient = base as? any _GradientStyle else { return nil }
                return gradient._resolveGradient(in: bounds, environment: environment)
            case .color, .foreground, .background, .tiled:
                return nil
            }
        }
    }

    /// Options for gradient shadings (accepted; gradients neither mirror nor repeat here).
    public struct GradientOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let `repeat` = GradientOptions(rawValue: 1)
        public static let mirror = GradientOptions(rawValue: 2)
        public static let linearColor = GradientOptions(rawValue: 4)
    }

    // MARK: Transforms

    public mutating func translateBy(x: CGFloat, y: CGFloat) { transform = transform.translatedBy(x: x, y: y) }
    public mutating func scaleBy(x: CGFloat, y: CGFloat) { transform = transform.scaledBy(x: x, y: y) }
    public mutating func rotate(by angle: Angle) { transform = transform.rotated(by: CGFloat(angle.radians)) }
    public mutating func concatenate(_ matrix: CGAffineTransform) { transform = matrix.concatenating(transform) }

    // MARK: Clipping

    /// Adds a clip to the context, in the context's current space.
    public mutating func clip(to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()) {
        clips.append((path.applying(transform), style.isEOFilled))
    }

    /// Options that affect the use of clip shapes.
    public struct ClipOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let inverse = ClipOptions(rawValue: 1)
    }

    /// The bounding rectangle of the intersection of all current clip shapes.
    public var clipBoundingRect: CGRect {
        var result: CGRect? = nil
        for (path, _) in clips { result = result.map { $0.intersection(path.boundingRect) } ?? path.boundingRect }
        return result ?? CGRect(x: -CGFloat.infinity, y: -CGFloat.infinity, width: CGFloat.infinity, height: CGFloat.infinity)
    }

    // MARK: Drawing

    /// Records one operation inside the context's state: its opacity group, its clips, and the
    /// filters and blend mode as effect groups over `bounds` (each operation on its own, as
    /// SwiftUI applies them).
    @MainActor private func withState(bounds: CGRect = .zero, _ body: (inout DisplayList) -> Void) {
        let needsGroup = opacity < 1
        let needsClip = !clips.isEmpty
        if needsGroup { recorder.list.append(.beginGroup(opacity: opacity)) }
        if needsClip {
            recorder.list.append(.save)
            for (path, eo) in clips { recorder.list.append(.clipPath(path, eoFill: eo)) }
        }
        var effects: [PendingEffect] = filters.map { $0.effect(in: environment) }
        if blendMode != .normal { effects.append(.blend(blendMode)) }
        var context = PaintContext(origin: .zero, scale: recorder.scale)
        context.effects = effects
        context.withEffects(bounds, into: &recorder.list, body)
        if needsClip { recorder.list.append(.restore) }
        if needsGroup { recorder.list.append(.endGroup) }
    }

    /// Fills a path with the given shading.
    public func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
        _readOnMainActor {
            guard opacity > 0 else { return }
            let transformed = path.applying(transform)
            if case .tiled(let image, let origin, let scale) = shading.kind {
                // The image repeated over the path: a clip to the path, then the image tiled across
                // the clip's bounds from the origin.
                guard let draw = resolvedImage(image, in: CGRect(origin: origin, size: .zero), scale: scale, tiling: transformed.boundingRect) else { return }
                withState(bounds: transformed.boundingRect) { list in
                    list.append(.save)
                    list.append(.clipPath(transformed, eoFill: style.isEOFilled))
                    list.append(.drawImage(draw))
                    list.append(.restore)
                }
                return
            }
            if let gradient = shading.gradient(bounds: transformed.boundingRect, transform: transform, environment: environment) {
                withState(bounds: transformed.boundingRect) { $0.append(.fillGradient(transformed, gradient, eoFill: style.isEOFilled)) }
                return
            }
            let color = shading.resolve(in: environment)
            withState(bounds: transformed.boundingRect) { $0.append(.fillPath(transformed, color, eoFill: style.isEOFilled)) }
        }
    }

    /// Strokes a path with the given shading and line width.
    public func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
        _readOnMainActor {
            stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
        }
    }

    /// Strokes a path with the given shading and stroke style.
    public func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
        _readOnMainActor {
            guard opacity > 0 else { return }
            let color = shading.resolve(in: environment)
            let scale = (transform.a * transform.a + transform.b * transform.b).squareRoot()
            var scaled = style
            scaled.lineWidth = style.lineWidth * (scale > 0 ? scale : 1)
            let transformed = path.applying(transform)
            let bounds = transformed.boundingRect.insetBy(dx: -scaled.lineWidth, dy: -scaled.lineWidth)
            if let gradient = shading.gradient(bounds: transformed.boundingRect, transform: transform, environment: environment) {
                withState(bounds: bounds) { $0.append(.strokeGradient(transformed, style: scaled, gradient)) }
                return
            }
            withState(bounds: bounds) { $0.append(.strokePath(transformed, style: scaled, color)) }
        }
    }

    /// Draws a text view, positioned by an anchor point.
    public func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
        _readOnMainActor {
            let resolved = resolve(text)
            let size = resolved.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            draw(resolved, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
        }
    }

    /// Draws a text view, wrapped and positioned at the top leading corner of a rectangle.
    public func draw(_ text: Text, in rect: CGRect) {
        _readOnMainActor {
            draw(resolve(text), in: rect)
        }
    }

    public func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
        _readOnMainActor {
            let size = text.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            draw(text, in: CGRect(x: point.x - size.width * anchor.x, y: point.y - size.height * anchor.y, width: size.width, height: size.height))
        }
    }

    /// Draws resolved text into a rectangle (wrapped at its width, from its top leading corner).
    public func draw(_ text: ResolvedText, in rect: CGRect) {
        _readOnMainActor {
            guard opacity > 0 else { return }
            let layout = text.layout(width: rect.width.isFinite ? rect.width : nil)
            let isTranslation = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1
            withState(bounds: rect.applying(transform)) { list in
                if !isTranslation { list.append(.save); list.append(.concat(transform)) }
                let origin = isTranslation ? CGPoint(x: rect.minX + transform.tx, y: rect.minY + transform.ty) : rect.origin
                for line in layout.lines {
                    for fragment in line.fragments where !fragment.text.isEmpty {
                        let run = min(max(fragment.run, 0), max(text.runs.count - 1, 0))
                        list.append(.drawText(fragment.text, DisplayFont(text.runs[run].font),
                                              origin: CGPoint(x: origin.x + fragment.x, y: origin.y + line.baseline), text.colors[run]))
                    }
                }
                if !isTranslation { list.append(.restore) }
            }
        }
    }

    /// Resolves a text view for measuring and repeated drawing.
    public func resolve(_ text: Text) -> ResolvedText {
        return _readOnMainActor {
            let environment = recorder.environment
            let parts = text.parts()
            let runs = parts.map { part -> StyledRun in
                let font = part.modifiers.font ?? environment.font ?? environment.platformProfile.defaultFont
                var resolved = font.resolve(in: environment)
                if let weight = part.modifiers.weight { resolved.weight = weight; resolved.weightOverridden = true }
                else if part.modifiers.bold { resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true }
                if part.modifiers.italic { resolved.italic = true }
                return StyledRun(part.string, font: resolved)
            }
            let inherited = environment.foregroundColor ?? .primary
            let colors = parts.map { ($0.modifiers.foregroundColor ?? inherited).resolve(in: environment) }
            return ResolvedText(runs: runs, colors: colors, engine: recorder.textEngine, options: environment.textLayoutOptions)
        }
    }

    /// Draws a nested layer with a copy of the context (the layer's drawing goes through this
    /// context's opacity and clip).
    @MainActor public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        var layer = self
        try content(&layer)
    }

    // MARK: Images

    /// An image resolved for measuring and repeated drawing.
    public struct ResolvedImage: @unchecked Sendable {
        package let image: Image
        /// The image's size in points (zero when the name did not resolve).
        public let size: CGSize
        /// The image's baseline from its top (a symbol's; the bottom otherwise).
        public let baseline: CGFloat
        /// A shading to draw the image with instead of its own colours (a tint).
        public var shading: Shading?
    }

    /// Resolves an image to its size at the canvas's environment.
    public func resolve(_ image: Image) -> ResolvedImage {
        return _readOnMainActor {
            guard let node = makeNode(for: image) else { return ResolvedImage(image: image, size: .zero, baseline: 0, shading: nil) }
            let size = node.sizeThatFits(.unspecified)
            let baseline = node.dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
            node.unmount()
            return ResolvedImage(image: image, size: size, baseline: baseline.isFinite ? baseline : size.height, shading: nil)
        }
    }

    /// Draws an image, resized into a rectangle.
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        _readOnMainActor {
            draw(resolve(image), in: rect)
        }
    }

    /// Draws an image at its own size, positioned by an anchor point.
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        _readOnMainActor {
            draw(resolve(image), at: point, anchor: anchor)
        }
    }

    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        _readOnMainActor {
            draw(image, in: CGRect(x: point.x - image.size.width * anchor.x, y: point.y - image.size.height * anchor.y,
                                   width: image.size.width, height: image.size.height))
        }
    }

    /// Draws a resolved image into a rectangle: the image's node, resizable, painted through
    /// the context's transform (a translation moves the rect; anything else wraps the paint).
    public func draw(_ image: ResolvedImage, in rect: CGRect) {
        _readOnMainActor {
            guard opacity > 0, rect.width > 0, rect.height > 0 else { return }
            var resized = image.image.resizable()
            var tint: Color?
            if let shading = image.shading, case .color(let color) = shading.kind {
                resized = resized.renderingMode(.template)
                tint = color
            }
            guard let node = makeNode(for: resized, tint: tint) else { return }
            paint(node, in: rect)
            node.unmount()
        }
    }

    /// Paints a node into a rectangle of the context's space.
    @MainActor private func paint(_ node: ViewNode, in rect: CGRect) {
        guard let owner = recorder.node else { return }
        node.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(rect.size), by: owner)
        let isTranslation = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1
        let absolute = rect.applying(transform)
        withState(bounds: absolute) { list in
            if isTranslation {
                node.paint(into: &list, context: PaintContext(origin: CGPoint(x: rect.minX + transform.tx, y: rect.minY + transform.ty), scale: recorder.scale))
            } else {
                list.append(.save)
                list.append(.concat(transform))
                node.paint(into: &list, context: PaintContext(origin: rect.origin, scale: recorder.scale))
                list.append(.restore)
            }
        }
    }

    @MainActor private func makeNode(for image: Image, tint: Color? = nil) -> ViewNode? {
        guard let owner = recorder.node else { return nil }
        var environment = environment
        if let tint { environment.foregroundColor = tint }
        return Image._makeNode(_NodeContext(view: image, parent: owner, environment: environment))
    }

    /// The image's draw command for a tiled shading, or nil when it did not resolve.
    @MainActor private func resolvedImage(_ image: Image, in rect: CGRect, scale: CGFloat, tiling bounds: CGRect) -> ImageDraw? {
        guard let node = makeNode(for: image.resizable()) as? any _ImageDrawProviding else { return nil }
        defer { (node as? ViewNode)?.unmount() }
        guard var draw = node._imageDraw(scale: recorder.scale) else { return nil }
        let size = CGSize(width: draw.pixelSize.width / draw.scale * scale, height: draw.pixelSize.height / draw.scale * scale)
        guard size.width > 0, size.height > 0 else { return nil }
        // The tiles start at the origin: the drawn rect spans the bounds from the tile grid's
        // first cell before them.
        let start = rect.origin.applying(transform)
        let dx = ((bounds.minX - start.x) / size.width).rounded(.down) * size.width
        let dy = ((bounds.minY - start.y) / size.height).rounded(.down) * size.height
        let width = (((bounds.maxX - (start.x + dx)) / size.width).rounded(.up)) * size.width
        let height = (((bounds.maxY - (start.y + dy)) / size.height).rounded(.up)) * size.height
        draw.rect = CGRect(x: start.x + dx, y: start.y + dy, width: width, height: height)
        draw.tiles = true
        // The painters tile at pixelSize / scale points: the shading's scale divides the file's.
        draw.scale = draw.scale / scale
        return draw
    }

    // MARK: Symbols

    /// A symbol view resolved for drawing.
    public struct ResolvedSymbol: @unchecked Sendable {
        package let node: ViewNode
        /// The symbol's ideal size.
        public let size: CGSize
    }

    /// Finds the `symbols` child tagged `id` and resolves it to its ideal size.
    public func resolveSymbol<ID: Hashable>(id: ID) -> ResolvedSymbol? {
        nonisolated(unsafe) let id = id
        return _readOnMainActor {
            guard let entry = recorder.symbols.first(where: { $0.id == AnyHashable(id) }) else { return nil }
            return ResolvedSymbol(node: entry.node, size: entry.node.sizeThatFits(.unspecified))
        }
    }

    /// Draws a symbol at its ideal size, positioned by an anchor point.
    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        _readOnMainActor {
            draw(symbol, in: CGRect(x: point.x - symbol.size.width * anchor.x, y: point.y - symbol.size.height * anchor.y,
                                    width: symbol.size.width, height: symbol.size.height))
        }
    }

    /// Draws a symbol resized into a rectangle.
    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        _readOnMainActor {
            guard opacity > 0, rect.width > 0, rect.height > 0 else { return }
            paint(symbol.node, in: rect)
        }
    }

    // MARK: Filters

    /// An effect applied to each drawing operation that follows (`addFilter`).
    public struct Filter: Sendable {
        package enum Kind: Sendable {
            case blur(radius: CGFloat, opaque: Bool)
            case shadow(Color, radius: CGFloat, offset: CGSize)
            case matrix(ColorMatrix)
            case none
        }
        package let kind: Kind

        @MainActor package func effect(in environment: EnvironmentValues) -> PendingEffect {
            switch kind {
            case .blur(let radius, let opaque): return .filter(.blur(radius: radius, opaque: opaque))
            case .shadow(let color, let radius, let offset): return .shadow(color.resolve(in: environment), radius: radius, offset: offset)
            case .matrix(let matrix): return .filter(.colorMatrix(matrix))
            case .none: return .opacity(1)
            }
        }

        public static func blur(radius: CGFloat, options: BlurOptions = BlurOptions()) -> Filter {
            Filter(kind: .blur(radius: radius, opaque: options.contains(.opaque)))
        }
        public static func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
                                  blendMode: BlendMode = .normal, options: ShadowOptions = ShadowOptions()) -> Filter {
            Filter(kind: .shadow(color, radius: radius, offset: CGSize(width: x, height: y)))
        }
        public static func colorMatrix(_ matrix: ColorMatrix) -> Filter { Filter(kind: .matrix(matrix)) }
        public static func colorMultiply(_ color: Color) -> Filter {
            // Resolved against sRGB without an environment: a plain colour's components.
            let c = color.resolve(in: EnvironmentValues())
            return Filter(kind: .matrix(ColorMatrix([c.red, 0, 0, 0, 0, 0, c.green, 0, 0, 0, 0, 0, c.blue, 0, 0, 0, 0, 0, c.alpha, 0])))
        }
        public static func grayscale(_ amount: Double) -> Filter { Filter(kind: .matrix(_ColorFilters.saturation(1 - min(max(amount, 0), 1)))) }
        public static func saturation(_ amount: Double) -> Filter { Filter(kind: .matrix(_ColorFilters.saturation(amount))) }
        public static func brightness(_ amount: Double) -> Filter {
            Filter(kind: .matrix(ColorMatrix([1, 0, 0, 0, amount, 0, 1, 0, 0, amount, 0, 0, 1, 0, amount, 0, 0, 0, 1, 0])))
        }
        public static func contrast(_ amount: Double) -> Filter {
            let t = (1 - amount) / 2
            return Filter(kind: .matrix(ColorMatrix([amount, 0, 0, 0, t, 0, amount, 0, 0, t, 0, 0, amount, 0, t, 0, 0, 0, 1, 0])))
        }
        public static func colorInvert(_ amount: Double = 1) -> Filter {
            let a = 1 - 2 * amount
            return Filter(kind: .matrix(ColorMatrix([a, 0, 0, 0, amount, 0, a, 0, 0, amount, 0, 0, a, 0, amount, 0, 0, 0, 1, 0])))
        }
        public static func hueRotation(_ angle: Angle) -> Filter { Filter(kind: .matrix(_ColorFilters.hueRotation(angle.radians))) }
        public static var luminanceToAlpha: Filter {
            Filter(kind: .matrix(ColorMatrix([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.2125, 0.7154, 0.0721, 0, 0])))
        }
        /// Accepted without effect.
        public static func alphaThreshold(min: Double, max: Double = 1, color: Color = .black) -> Filter { Filter(kind: .none) }
    }

    public struct BlurOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let opaque = BlurOptions(rawValue: 1)
        public static let dithersResult = BlurOptions(rawValue: 2)
    }

    public struct ShadowOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let shadowAbove = ShadowOptions(rawValue: 1)
        public static let shadowOnly = ShadowOptions(rawValue: 2)
        public static let invertsAlpha = ShadowOptions(rawValue: 4)
        public static let disablesGroup = ShadowOptions(rawValue: 8)
    }

    public struct FilterOptions: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let linearColor = FilterOptions(rawValue: 1)
    }

    /// Adds a filter to the context: every drawing operation that follows runs through it.
    public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) {
        filters.append(filter)
    }

    #if canImport(CoreGraphics) && !os(WASI)
    /// Runs `content` with a scratch Core Graphics context the canvas's size. The web has no
    /// Core Graphics, so what is drawn into it is not shown (accepted for source compatibility).
    @MainActor public func withCGContext(content: (CGContext) throws -> Void) rethrows {
        let size = recorder.node?.frame.size ?? CGSize(width: 1, height: 1)
        guard let context = CGContext(data: nil, width: max(Int(size.width * recorder.scale), 1), height: max(Int(size.height * recorder.scale), 1),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        try content(context)
    }
    #endif
}

/// Colour matrices for the filters that are not a plain product.
package enum _ColorFilters {
    package static func saturation(_ s: Double) -> ColorMatrix {
        let (lr, lg, lb) = (0.2126, 0.7152, 0.0722)
        return ColorMatrix([lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0,
                            lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0,
                            lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0,
                            0, 0, 0, 1, 0])
    }

    package static func hueRotation(_ radians: Double) -> ColorMatrix {
        let c = _cos(radians), sn = _sin(radians)
        return ColorMatrix([0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715, 0.072 - c * 0.072 + sn * 0.928, 0, 0,
                            0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140, 0.072 - c * 0.072 - sn * 0.283, 0, 0,
                            0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715, 0.072 + c * 0.928 + sn * 0.072, 0, 0,
                            0, 0, 0, 1, 0])
    }
}

/// A node that can hand out its image draw command (tiled shadings).
@MainActor
package protocol _ImageDrawProviding: AnyObject {
    func _imageDraw(scale: CGFloat) -> ImageDraw?
}

/// A text view resolved for drawing in a graphics context.
public struct ResolvedText: @unchecked Sendable {
    package let runs: [StyledRun]
    package let colors: [RGBA]
    package let engine: any TextEngine
    package let options: TextLayoutOptions

    @MainActor package func layout(width: CGFloat?) -> TextLayout {
        engine.layout(runs, options: options, width: width)
    }

    /// The size of the text when drawn in the given amount of space.
    public func measure(in size: CGSize) -> CGSize {
        return _readOnMainActor {
            layout(width: size.width.isFinite ? size.width : nil).size
        }
    }

    /// The first baseline of the text when drawn in the given amount of space.
    public func firstBaseline(in size: CGSize) -> CGFloat {
        return _readOnMainActor {
            layout(width: size.width.isFinite ? size.width : nil).firstBaseline
        }
    }
}

