/// Layout-specific properties of a layout container.
public struct LayoutProperties: Sendable {
    /// The orientation of the containing stack-like container, if any.
    public var stackOrientation: Axis?

    public init() {}
}

/// A key for accessing a layout value of a layout container's subviews.
public protocol LayoutValueKey {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

/// A type that defines the geometry of a collection of views. Like SwiftUI's, it isn't tied to the
/// main actor, so a Swift 6 layout can implement it with `nonisolated` methods; the runtime still
/// calls it on the main actor, and `LayoutSubview` steps back onto it.
public protocol Layout: Animatable {
    /// Cached values computed by the layout container.
    associatedtype Cache = Void

    /// Properties of a layout container.
    static var layoutProperties: LayoutProperties { get }

    /// Creates and initializes a cache for a layout instance.
    func makeCache(subviews: Self.Subviews) -> Self.Cache

    /// Updates the layout's cache when something changes.
    func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews)

    /// Returns the preferred spacing values of the composite view.
    func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing

    /// Returns the size of the composite view, given a proposed size and the view's subviews.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache) -> CGSize

    /// Assigns positions to each of the layout's subviews.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Self.Subviews, cache: inout Self.Cache)

    /// Returns the position of the specified horizontal alignment guide along the x axis.
    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    /// Returns the position of the specified vertical alignment guide along the y axis.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat?

    /// A collection of proxies for the subviews of a layout view.
    typealias Subviews = LayoutSubviews
}

extension Layout {
    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    public func updateCache(_ cache: inout Self.Cache, subviews: Self.Subviews) {
        cache = makeCache(subviews: subviews)
    }

    public func spacing(subviews: Self.Subviews, cache: inout Self.Cache) -> ViewSpacing {
        var spacing = ViewSpacing.zero
        for subview in subviews { spacing.formUnion(subview.spacing) }
        return spacing
    }

    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? {
        nil
    }

    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Self.Subviews, cache: inout Self.Cache) -> CGFloat? {
        nil
    }
}

extension Layout where Cache == Void {
    public func makeCache(subviews: Self.Subviews) -> Void {}
}

extension Layout {
    /// Combines the specified views into a single composite view using the layout algorithms of
    /// the custom layout container.
    nonisolated public func callAsFunction<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        _LayoutView(layout: self, content: content())
    }
}

/// Runs `body` on the main actor, where layout always runs, and hands back its result, which
/// needn't be `Sendable` since it never leaves the main thread.
package func onMain<T>(_ body: @MainActor () -> T) -> T {
    nonisolated(unsafe) var result: T?
    // Swift 5 mode (decision 0027): a `@MainActor` closure isn't `Sendable` by itself.
    withoutActuallyEscaping(body) { body in
        nonisolated(unsafe) let body = body
        MainActor.assumeIsolated { result = body() }
    }
    return result!
}

/// A proxy that represents one subview of a layout.
public struct LayoutSubview: Equatable, Sendable {
    package let node: ViewNode
    package let container: ViewNode
    package let index: Int

    package init(node: ViewNode, container: ViewNode, index: Int) {
        self.node = node
        self.container = container
        self.index = index
    }

    /// The layout priority of the subview.
    public var priority: Double { onMain { node.layoutPriority } }
    /// Whether the subview is a `Spacer` (stacks size spacers from the leftover).
    package var isSpacer: Bool { onMain { node.isSpacer } }

    /// The view's preferred spacing values.
    public var spacing: ViewSpacing { onMain { node.layoutSpacing } }

    /// Gets the value of a layout value key.
    public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
        onMain { node.layoutValue(for: K.self) }
    }

    /// Asks the subview for its size.
    public func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        onMain { node.sizeThatFits(proposal) }
    }

    /// Asks the subview for its dimensions and alignment guides.
    public func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        onMain { node.dimensions(in: proposal) }
    }

    /// Assigns a position and proposed size to the subview.
    public func place(at position: CGPoint, anchor: UnitPoint = .topLeading, proposal: ProposedViewSize) {
        onMain { node.place(at: position, anchor: anchor, proposal: proposal, by: container) }
    }

    public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
        lhs.node === rhs.node
    }
}

/// A collection of proxy values that represent the subviews of a layout view.
public struct LayoutSubviews: RandomAccessCollection, Equatable, Sendable {
    public typealias Element = LayoutSubview
    public typealias Index = Int
    public typealias SubSequence = LayoutSubviews

    package let elements: [LayoutSubview]

    /// The layout direction inherited by the container view.
    public let layoutDirection: LayoutDirection

    package init(_ elements: [LayoutSubview], layoutDirection: LayoutDirection = .leftToRight) {
        self.elements = elements
        self.layoutDirection = layoutDirection
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { elements.count }
    public subscript(index: Int) -> LayoutSubview { elements[index] }
    public subscript(bounds: Range<Int>) -> LayoutSubviews {
        LayoutSubviews(Array(elements[bounds]), layoutDirection: layoutDirection)
    }
    public subscript<S: Sequence>(indices: S) -> LayoutSubviews where S.Element == Int {
        LayoutSubviews(indices.map { elements[$0] }, layoutDirection: layoutDirection)
    }
}

/// A direction in which SwiftUI can lay out content.
public enum LayoutDirection: Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft
}

/// How a view's drawing responds to the layout direction (`Shape.layoutDirectionBehavior`).
public enum LayoutDirectionBehavior: Hashable, Sendable {
    /// Drawn the same way in both directions.
    case fixed
    /// Mirrored horizontally when the layout direction is `direction`.
    case mirrors(in: LayoutDirection)
    /// Mirrored in a right-to-left layout (the default for shapes).
    public static var mirrors: LayoutDirectionBehavior { .mirrors(in: .rightToLeft) }

    /// Whether drawing mirrors in `direction`.
    package func flips(in direction: LayoutDirection) -> Bool {
        if case .mirrors(let flipped) = self { return flipped == direction }
        return false
    }
}

/// The view produced by calling a `Layout` as a function.
public struct _LayoutView<L: Layout, Content: View> {
    public var layout: L
    public var content: Content

    public init(layout: L, content: Content) {
        self.layout = layout
        self.content = content
    }
}

extension _LayoutView: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_LayoutView<L, Content>>) -> TypedNode<_LayoutView<L, Content>> {
        LayoutContainerNode(context, layout: \.layout, content: \.content)
    }
}

// MARK: - AnyLayout

/// A type-erased instance of the layout protocol: switching between layouts keeps the subviews.
public struct AnyLayout: Layout {
    package let base: any Layout
    private let makeCacheBox: (LayoutSubviews) -> Any
    private let updateCacheBox: (inout Any, LayoutSubviews) -> Void
    private let spacingBox: (LayoutSubviews, inout Any) -> ViewSpacing
    private let sizeBox: (ProposedViewSize, LayoutSubviews, inout Any) -> CGSize
    private let placeBox: (CGRect, ProposedViewSize, LayoutSubviews, inout Any) -> Void
    private let horizontalGuideBox: (HorizontalAlignment, CGRect, ProposedViewSize, LayoutSubviews, inout Any) -> CGFloat?
    private let verticalGuideBox: (VerticalAlignment, CGRect, ProposedViewSize, LayoutSubviews, inout Any) -> CGFloat?

    /// Creates an instance that type-erases `layout`.
    public init<L: Layout>(_ layout: L) {
        base = layout
        makeCacheBox = { layout.makeCache(subviews: $0) }
        updateCacheBox = { cache, subviews in
            var typed = cache as! L.Cache
            layout.updateCache(&typed, subviews: subviews)
            cache = typed
        }
        spacingBox = { subviews, cache in
            var typed = cache as! L.Cache
            defer { cache = typed }
            return layout.spacing(subviews: subviews, cache: &typed)
        }
        sizeBox = { proposal, subviews, cache in
            var typed = cache as! L.Cache
            defer { cache = typed }
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &typed)
        }
        placeBox = { bounds, proposal, subviews, cache in
            var typed = cache as! L.Cache
            defer { cache = typed }
            layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &typed)
        }
        horizontalGuideBox = { guide, bounds, proposal, subviews, cache in
            var typed = cache as! L.Cache
            defer { cache = typed }
            return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &typed)
        }
        verticalGuideBox = { guide, bounds, proposal, subviews, cache in
            var typed = cache as! L.Cache
            defer { cache = typed }
            return layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &typed)
        }
    }

    /// The erased layout's cache, plus the type it was made for so a swapped layout starts afresh.
    public struct Cache {
        package var value: Any
        package let type: ObjectIdentifier
    }

    private var typeIdentifier: ObjectIdentifier { ObjectIdentifier(Swift.type(of: base)) }

    public static var layoutProperties: LayoutProperties { LayoutProperties() }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(value: makeCacheBox(subviews), type: typeIdentifier)
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.type != typeIdentifier { cache = makeCache(subviews: subviews); return }
        updateCacheBox(&cache.value, subviews)
    }

    private func withFreshCache<R>(_ cache: inout Cache, subviews: Subviews, _ body: (inout Any) -> R) -> R {
        if cache.type != typeIdentifier { cache = makeCache(subviews: subviews) }
        return body(&cache.value)
    }

    public func spacing(subviews: Subviews, cache: inout Cache) -> ViewSpacing {
        withFreshCache(&cache, subviews: subviews) { spacingBox(subviews, &$0) }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        withFreshCache(&cache, subviews: subviews) { sizeBox(proposal, subviews, &$0) }
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        withFreshCache(&cache, subviews: subviews) { placeBox(bounds, proposal, subviews, &$0) }
    }

    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        withFreshCache(&cache, subviews: subviews) { horizontalGuideBox(guide, bounds, proposal, subviews, &$0) }
    }

    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGFloat? {
        withFreshCache(&cache, subviews: subviews) { verticalGuideBox(guide, bounds, proposal, subviews, &$0) }
    }

    public typealias AnimatableData = EmptyAnimatableData
}
