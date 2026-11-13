/// Layers a view behind the content.
public struct _BackgroundModifier<Background: View> {
    public var background: Background
    public var alignment: Alignment

    public init(background: Background, alignment: Alignment) {
        self.background = background
        self.alignment = alignment
    }
}

extension _BackgroundModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        LayeredNode(context, layer: \.modifier.background, alignment: \.modifier.alignment, isOverlay: false)
    }
}

/// Layers a view in front of the content.
public struct _OverlayModifier<Overlay: View> {
    public var overlay: Overlay
    public var alignment: Alignment

    public init(overlay: Overlay, alignment: Alignment) {
        self.overlay = overlay
        self.alignment = alignment
    }
}

extension _OverlayModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        LayeredNode(context, layer: \.modifier.overlay, alignment: \.modifier.alignment, isOverlay: true)
    }
}

/// Multiplies the content's opacity.
@frozen
public struct _OpacityEffect: Equatable {
    public var opacity: Double
    public init(opacity: Double) { self.opacity = opacity }
}

extension _OpacityEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OpacityNode(context)
    }
}

/// Draws a shadow of the content's rendering behind it.
@frozen
public struct _ShadowEffect: Equatable {
    public var color: Color
    public var radius: CGFloat
    public var offset: CGSize

    public init(color: Color, radius: CGFloat, offset: CGSize) {
        self.color = color
        self.radius = radius
        self.offset = offset
    }
}

extension _ShadowEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ShadowNode(context)
    }
}

/// Clips the content to a shape.
public struct _ClipEffect<ClipShape: Shape> {
    public var shape: ClipShape
    public var style: FillStyle

    public init(shape: ClipShape, style: FillStyle) {
        self.shape = shape
        self.style = style
    }
}

extension _ClipEffect: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ClipNode(context)
    }
}

extension View {
    /// Layers the given view behind this view. Apple soft-deprecates this form in favour of
    /// `background(alignment:content:)`, which is also what makes `.background(Color.blue)`
    /// pick the `ShapeStyle` overload; disfavouring it here has the same effect.
    @_disfavoredOverload
    nonisolated public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> some View {
        modifier(_BackgroundModifier(background: background, alignment: alignment))
    }

    /// Layers the views that you specify behind this view.
    nonisolated public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        modifier(_BackgroundModifier(background: content(), alignment: alignment))
    }

    /// Sets the view's background to a style.
    nonisolated public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        // The fill reaches into the safe area on `edges` where this view touches it (a screen's
        // ground colour under the status bar and the home indicator), as Apple's does.
        modifier(_BackgroundModifier(background: FillShapeView(shape: Rectangle(), style: style, fillStyle: FillStyle(), background: EmptyView())
            .modifier(_IgnoresSafeAreaModifier(regions: .container, edges: edges)), alignment: .center))
    }

    /// Sets the view's background to a shape filled with a style.
    nonisolated public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(_BackgroundModifier(background: FillShapeView(shape: shape, style: style, fillStyle: fillStyle, background: EmptyView()), alignment: .center))
    }

    /// Sets the view's background to a shape filled with the foreground style.
    nonisolated public func background<T: Shape>(in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(_BackgroundModifier(background: FillShapeView(shape: shape, style: ForegroundStyle(), fillStyle: fillStyle, background: EmptyView()), alignment: .center))
    }

    /// Layers a secondary view in front of this view (soft-deprecated by Apple; see `background`).
    @_disfavoredOverload
    nonisolated public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> some View {
        modifier(_OverlayModifier(overlay: overlay, alignment: alignment))
    }

    /// Layers the views that you specify in front of this view.
    nonisolated public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        modifier(_OverlayModifier(overlay: content(), alignment: alignment))
    }

    /// Layers a style in front of this view.
    nonisolated public func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        // The fill reaches into the safe area on `edges` where this view touches it (a screen's
        // ground colour under the status bar and the home indicator), as Apple's does.
        modifier(_OverlayModifier(overlay: FillShapeView(shape: Rectangle(), style: style, fillStyle: FillStyle(), background: EmptyView())
            .modifier(_IgnoresSafeAreaModifier(regions: .container, edges: edges)), alignment: .center))
    }

    /// Layers a shape filled with a style in front of this view.
    nonisolated public func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        modifier(_OverlayModifier(overlay: FillShapeView(shape: shape, style: style, fillStyle: fillStyle, background: EmptyView()), alignment: .center))
    }

    /// Adds a border to this view with the specified style and width, inside the view's bounds.
    nonisolated public func border<S: ShapeStyle>(_ content: S, width: CGFloat = 1) -> some View {
        overlay(Rectangle().strokeBorder(content, lineWidth: width))
    }

    /// Sets the transparency of this view.
    nonisolated public func opacity(_ opacity: Double) -> some View {
        modifier(_OpacityEffect(opacity: opacity))
    }

    /// Adds a shadow to this view: the content's rendering, blurred by `radius` and moved by
    /// `x`/`y`, painted behind it. The default colour is a third-opaque black.
    nonisolated public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(_ShadowEffect(color: color, radius: radius, offset: CGSize(width: x, height: y)))
    }

    /// Sets a clipping shape for this view.
    nonisolated public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        modifier(_ClipEffect(shape: shape, style: style))
    }

    /// Clips this view to its bounding rectangular frame.
    nonisolated public func clipped(antialiased: Bool = false) -> some View {
        clipShape(Rectangle(), style: FillStyle(antialiased: antialiased))
    }

    /// Clips this view to its bounding frame, with the specified corner radius.
    @available(*, deprecated, message: "Use `clipShape` or `fill` instead.")
    nonisolated public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius), style: FillStyle(antialiased: antialiased))
    }
}
