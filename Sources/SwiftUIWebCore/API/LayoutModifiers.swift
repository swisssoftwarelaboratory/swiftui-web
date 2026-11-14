// Layout-affecting modifiers. Each is a primitive `ViewModifier` (Body == Never) with its own
// node in Runtime/LayoutNodes.swift.

/// Positions the content in an invisible frame with fixed dimensions.
@frozen
public struct _FrameLayout: Equatable {
    package let width: CGFloat?
    package let height: CGFloat?
    package let alignment: Alignment

    package init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }
}

extension _FrameLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FrameNode(context)
    }
}

/// Positions the content in an invisible frame with flexible dimensions.
@frozen
public struct _FlexFrameLayout: Equatable {
    package let minWidth: CGFloat?
    package let idealWidth: CGFloat?
    package let maxWidth: CGFloat?
    package let minHeight: CGFloat?
    package let idealHeight: CGFloat?
    package let maxHeight: CGFloat?
    package let alignment: Alignment

    package init(minWidth: CGFloat?, idealWidth: CGFloat?, maxWidth: CGFloat?,
                 minHeight: CGFloat?, idealHeight: CGFloat?, maxHeight: CGFloat?, alignment: Alignment) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }
}

extension _FlexFrameLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FlexFrameNode(context)
    }
}

/// Pads the content by the given insets.
@frozen
public struct _PaddingLayout: Equatable {
    package var edges: Edge.Set
    package var insets: EdgeInsets?

    package init(edges: Edge.Set, insets: EdgeInsets?) {
        self.edges = edges
        self.insets = insets
    }
}

extension _PaddingLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PaddingNode(context)
    }
}

/// Fixes the content at its ideal size along the given axes.
@frozen
public struct _FixedSizeLayout: Equatable {
    package let horizontal: Bool
    package let vertical: Bool

    package init(horizontal: Bool, vertical: Bool) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

extension _FixedSizeLayout: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FixedSizeNode(context)
    }
}

/// Sets the layout priority of the content.
@frozen
public struct _LayoutPriorityModifier: Equatable {
    package let priority: Double

    package init(priority: Double) {
        self.priority = priority
    }
}

extension _LayoutPriorityModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        LayoutPriorityNode(context)
    }
}

/// Overrides one alignment guide of the content.
public struct _AlignmentGuideModifier {
    package let key: AlignmentKey
    package let computeValue: (ViewDimensions) -> CGFloat

    package init(key: AlignmentKey, computeValue: @escaping (ViewDimensions) -> CGFloat) {
        self.key = key
        self.computeValue = computeValue
    }
}

extension _AlignmentGuideModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AlignmentGuideNode(context)
    }
}

/// Stores a value for a `LayoutValueKey` on the content.
public struct _LayoutValueModifier<K: LayoutValueKey> {
    package let value: K.Value

    package init(value: K.Value) {
        self.value = value
    }
}

extension _LayoutValueModifier: Equatable where K.Value: Equatable {}

extension _LayoutValueModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        LayoutValueNode(context)
    }
}

extension View {
    /// Positions this view within an invisible frame with the specified size.
    nonisolated public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        modifier(_FrameLayout(width: width, height: height, alignment: alignment))
    }

    /// Positions this view within an invisible frame having the specified size constraints.
    nonisolated public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        modifier(_FlexFrameLayout(minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
                                  minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
                                  alignment: alignment))
    }

    /// Positions this view within an invisible frame. Deprecated no-argument form kept for
    /// source compatibility.
    @available(*, deprecated, message: "Please pass one or more parameters.")
    nonisolated public func frame() -> some View {
        modifier(_FrameLayout(width: nil, height: nil, alignment: .center))
    }

    /// Adds a different padding amount to each edge of this view.
    nonisolated public func padding(_ insets: EdgeInsets) -> some View {
        modifier(_PaddingLayout(edges: .all, insets: insets))
    }

    /// Adds an equal padding amount to specific edges of this view.
    nonisolated public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        modifier(_PaddingLayout(edges: edges, insets: length.map { EdgeInsets(edges, $0) }))
    }

    /// Adds a specific padding amount to each edge of this view.
    nonisolated public func padding(_ length: CGFloat) -> some View {
        padding(.all, length)
    }

    /// Fixes this view at its ideal size in the specified dimensions.
    nonisolated public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        modifier(_FixedSizeLayout(horizontal: horizontal, vertical: vertical))
    }

    /// Fixes this view at its ideal size.
    nonisolated public func fixedSize() -> some View {
        fixedSize(horizontal: true, vertical: true)
    }

    /// Sets the priority by which a parent layout should apportion space to this child.
    nonisolated public func layoutPriority(_ value: Double) -> some View {
        modifier(_LayoutPriorityModifier(priority: value))
    }

    /// Sets the view's horizontal alignment.
    @preconcurrency nonisolated public func alignmentGuide(_ g: HorizontalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        modifier(_AlignmentGuideModifier(key: g.key, computeValue: computeValue))
    }

    /// Sets the view's vertical alignment.
    @preconcurrency nonisolated public func alignmentGuide(_ g: VerticalAlignment, computeValue: @escaping @Sendable (ViewDimensions) -> CGFloat) -> some View {
        modifier(_AlignmentGuideModifier(key: g.key, computeValue: computeValue))
    }

    /// Associates a value with a custom layout property.
    nonisolated public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        modifier(_LayoutValueModifier<K>(value: value))
    }
}
