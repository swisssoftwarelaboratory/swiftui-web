// Scroll position, targets, geometry and phases (Docs/elements/ScrollView.md, "Scroll position,
// targets and geometry"). `ScrollNode` applies them in Runtime/ScrollNodes.swift: the modifiers
// with closures or bindings become transparent nodes the scroll view finds above itself; the
// value-typed ones (margins, behaviours, anchor roles) travel through the environment.

// MARK: - Geometry and phases

/// A type that defines the geometry of a scroll view.
public struct ScrollGeometry: Equatable, Sendable {
    /// The content offset of the scroll view: the point of the content at the top-leading corner
    /// of the viewport (negative at rest under a content inset).
    public var contentOffset: CGPoint
    /// The size of the content of the scroll view.
    public var contentSize: CGSize
    /// The content insets of the scroll view (safe area and content margins).
    public var contentInsets: EdgeInsets
    /// The size of the container of the scroll view, inset by the content insets.
    public var containerSize: CGSize

    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets, containerSize: CGSize) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    /// The visible rect of the scroll view: the whole viewport in content coordinates, the
    /// content insets included (`scroll/geometry`: origin −20 and 150 tall for a 150 pt viewport
    /// with a 20 pt top margin).
    public var visibleRect: CGRect {
        CGRect(x: contentOffset.x, y: contentOffset.y,
               width: containerSize.width + contentInsets.leading + contentInsets.trailing,
               height: containerSize.height + contentInsets.top + contentInsets.bottom)
    }

    /// The bounds rect of the scroll view: the content offset and the inset container size.
    public var bounds: CGRect { CGRect(origin: contentOffset, size: containerSize) }
}

/// A type that describes the state of a scroll gesture of a scrollable view like a scroll view.
public enum ScrollPhase: Hashable, Sendable, CaseIterable {
    /// The scroll view is not scrolling.
    case idle
    /// The user is touching the scroll view but has not moved it yet.
    case tracking
    /// The user is dragging the content.
    case interacting
    /// The content is decelerating after the user let go.
    case decelerating
    /// The scroll view is animating to a target (a scroll target behaviour settling).
    case animating

    /// Whether the phase is anything but idle.
    public var isScrolling: Bool { self != .idle }
}

/// Context provided to a scroll phase change action.
public struct ScrollPhaseChangeContext {
    /// The geometry of the scroll view at the time of the phase change.
    public let geometry: ScrollGeometry
    /// The velocity of the content (points per second), nil when the content is not moving.
    public let velocity: CGVector?

    package init(geometry: ScrollGeometry, velocity: CGVector?) {
        self.geometry = geometry
        self.velocity = velocity
    }
}

/// A node above a scroll view told about its geometry (`onScrollGeometryChange`).
@MainActor
package protocol _ScrollGeometryObserving: AnyObject {
    func scrollGeometryDidChange(_ geometry: ScrollGeometry)
}

/// A node above a scroll view told about its phase changes (`onScrollPhaseChange`).
@MainActor
package protocol _ScrollPhaseObserving: AnyObject {
    func scrollPhaseDidChange(from old: ScrollPhase, to new: ScrollPhase, context: ScrollPhaseChangeContext)
}

/// `onScrollGeometryChange`: a value derived from the geometry, and an action on its changes.
public struct _ScrollGeometryChangeModifier<Value: Equatable> {
    public var transform: (ScrollGeometry) -> Value
    public var action: (Value, Value) -> Void

    public init(transform: @escaping (ScrollGeometry) -> Value, action: @escaping (Value, Value) -> Void) {
        self.transform = transform
        self.action = action
    }
}

extension _ScrollGeometryChangeModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScrollGeometryChangeNode(context)
    }
}

/// `onScrollPhaseChange`: an action on the phase changes of the scroll views within.
public struct _ScrollPhaseChangeModifier {
    public var action: (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void

    public init(action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void) {
        self.action = action
    }
}

extension _ScrollPhaseChangeModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScrollPhaseChangeNode(context)
    }
}

extension View {
    /// Adds an action to be performed when a value, created from a scroll geometry, changes.
    /// The geometry is that of the scroll views within this view; the action runs once when
    /// the scroll view appears (with the value of an empty geometry, then the first real one if
    /// it differs) and then whenever the value changes.
    nonisolated public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T,
                                                                 action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        modifier(_ScrollGeometryChangeModifier(transform: transform, action: action))
    }

    /// Adds an action to perform when the scroll phase of the scroll views within this view
    /// changes (once at appearance with `.idle` twice).
    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase) -> Void) -> some View {
        modifier(_ScrollPhaseChangeModifier(action: { old, new, _ in action(old, new) }))
    }

    /// Adds an action to perform when the scroll phase of the scroll views within this view
    /// changes, with the geometry and velocity at that moment.
    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase, _ context: ScrollPhaseChangeContext) -> Void) -> some View {
        modifier(_ScrollPhaseChangeModifier(action: action))
    }
}

// MARK: - Scroll position

/// The position of a scroll view: an identity, an edge or a point to scroll to, and whether the
/// user has since scrolled elsewhere.
public struct ScrollPosition: Equatable, @unchecked Sendable {
    package enum Request: Equatable, @unchecked Sendable {
        case none
        case id(AnyHashable, UnitPoint?)
        case edge(Edge)
        case point(x: CGFloat?, y: CGFloat?)
    }

    package var request: Request = .none
    package var positionedByUser = false

    /// A position with no target.
    public init() {}

    /// Creates a new scroll position to be scrolled to the given edge.
    public init(edge: Edge) { request = .edge(edge) }

    /// Creates a new scroll position to be scrolled to the given point.
    public init(point: CGPoint) { request = .point(x: point.x, y: point.y) }

    /// Creates a new scroll position to be scrolled to the given x offset, the y offset kept.
    public init(x: CGFloat) { request = .point(x: x, y: nil) }

    /// Creates a new scroll position to be scrolled to the given y offset, the x offset kept.
    public init(y: CGFloat) { request = .point(x: nil, y: y) }

    /// Creates a new scroll position to be scrolled to the given offsets.
    public init(x: CGFloat, y: CGFloat) { request = .point(x: x, y: y) }

    /// Creates a new scroll position to be scrolled to the view with the given identity.
    public init<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) { request = .id(AnyHashable(id), anchor) }

    /// Creates a new scroll position to be scrolled to the given edge, the identity type named.
    public init<ID: Hashable>(idType: ID.Type, edge: Edge) { request = .edge(edge) }

    /// Creates a new scroll position to be scrolled to the given point, the identity type named.
    public init<ID: Hashable>(idType: ID.Type, point: CGPoint) { request = .point(x: point.x, y: point.y) }

    package init(user id: AnyHashable?) {
        request = id.map { .id($0, nil) } ?? .none
        positionedByUser = true
    }

    /// The identity of the view the scroll view is positioned on, if any.
    public func viewID<T: Hashable>(type: T.Type) -> T? {
        if case .id(let id, _) = request { return id.base as? T }
        return nil
    }

    /// The identity of the view the scroll view is positioned on, if any.
    public var viewID: (any Hashable)? {
        if case .id(let id, _) = request { return id.base as? any Hashable }
        return nil
    }

    /// The edge the scroll view was scrolled to, if any (nil after the user scrolls).
    public var edge: Edge? {
        if case .edge(let edge) = request { return edge }
        return nil
    }

    /// The point the scroll view was scrolled to, if any (nil after the user scrolls).
    public var point: CGPoint? {
        if case .point(let x, let y) = request, let x, let y { return CGPoint(x: x, y: y) }
        return nil
    }

    /// Whether the scroll view is positioned by the user's scrolling rather than a request.
    public var isPositionedByUser: Bool { positionedByUser }

    /// Scrolls to the view with the given identity.
    public mutating func scrollTo<ID: Hashable>(id: ID, anchor: UnitPoint? = nil) { self = ScrollPosition(id: id, anchor: anchor) }
    /// Scrolls to the given edge.
    public mutating func scrollTo(edge: Edge) { self = ScrollPosition(edge: edge) }
    /// Scrolls to the given point.
    public mutating func scrollTo(point: CGPoint) { self = ScrollPosition(point: point) }
    /// Scrolls to the given offsets.
    public mutating func scrollTo(x: CGFloat, y: CGFloat) { self = ScrollPosition(x: x, y: y) }
    /// Scrolls to the given x offset, the y offset kept.
    public mutating func scrollTo(x: CGFloat) { self = ScrollPosition(x: x) }
    /// Scrolls to the given y offset, the x offset kept.
    public mutating func scrollTo(y: CGFloat) { self = ScrollPosition(y: y) }
}

/// A node above a scroll view holding its position binding (`scrollPosition`).
@MainActor
package protocol _ScrollPositioning: AnyObject {
    /// The anchor the modifier was given.
    var positionAnchor: UnitPoint? { get }
    /// The binding's current value.
    var currentPosition: ScrollPosition { get }
    /// The user scrolled: the binding takes the identity of the positioned view (nil for none).
    func userScrolled(to id: AnyHashable?)
}

/// `scrollPosition(id:anchor:)` and `scrollPosition(_:anchor:)`: the binding, type-erased.
public struct _ScrollPositionModifier {
    package let anchor: UnitPoint?
    package let read: () -> ScrollPosition
    package let write: (AnyHashable?) -> Void

    public init<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint?) {
        self.anchor = anchor
        read = { id.wrappedValue.map { ScrollPosition(id: $0, anchor: anchor) } ?? ScrollPosition() }
        write = { id.wrappedValue = $0?.base as? ID }
    }

    public init(position: Binding<ScrollPosition>, anchor: UnitPoint?) {
        self.anchor = anchor
        read = { position.wrappedValue }
        write = { position.wrappedValue = ScrollPosition(user: $0) }
    }
}

extension _ScrollPositionModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScrollPositionNode(context)
    }
}

/// `scrollTargetLayout`: the layout's children are the scroll targets of the scroll view around it.
public struct _ScrollTargetLayoutModifier {
    public var isEnabled: Bool
    public init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

extension _ScrollTargetLayoutModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScrollTargetLayoutNode(context)
    }
}

extension View {
    /// Associates a binding to be updated when a scroll view within this view scrolls. The
    /// binding's identity is scrolled to when it changes (with the smallest offset change
    /// without an anchor); the view positioned at the anchor is written back as the user scrolls.
    /// The initial value does not scroll (`scroll/position`), nor do programmatic scrolls update it.
    nonisolated public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View {
        modifier(_ScrollPositionModifier(id: id, anchor: anchor))
    }

    /// Associates a binding to be updated when a scroll view within this view scrolls: a
    /// `ScrollPosition` can name an identity, an edge or a point.
    nonisolated public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        modifier(_ScrollPositionModifier(position: position, anchor: anchor))
    }

    /// Configures the outermost layout as a scroll target layout: its children are the targets
    /// of `scrollPosition` and of the view-aligned scroll target behaviour.
    nonisolated public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        modifier(_ScrollTargetLayoutModifier(isEnabled: isEnabled))
    }
}

// MARK: - Scroll target behaviours

/// A type defining the target in which a scroll view should try and scroll to.
public struct ScrollTarget {
    /// The rect that a scrollable view should try and have contained (content coordinates).
    public var rect: CGRect
    /// The anchor to which the rect should be aligned within the visible region.
    public var anchor: UnitPoint?

    public init(rect: CGRect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }
}

/// The context in which a scroll target behavior updates its scroll target.
@dynamicMemberLookup
public struct ScrollTargetBehaviorContext {
    /// The original target when the scrollable view's scrolling ended: the projected rest
    /// position of the content.
    public let originalTarget: ScrollTarget
    /// The current velocity of the scrollable view's scroll gesture (points per second).
    public let velocity: CGVector
    /// The size of the content of the scrollable view.
    public let contentSize: CGSize
    /// The size of the container of the scrollable view (inset by the content insets).
    public let containerSize: CGSize
    /// The axes in which the scrollable view is scrollable.
    public let axes: Axis.Set

    package let environment: EnvironmentValues
    /// The frames of the scroll targets (content coordinates), in layout order.
    package let targets: [CGRect]
    /// The content offset when the gesture began.
    package let startOffset: CGPoint
    /// The content insets: target offsets are in the geometry's coordinates (negative at rest).
    package let contentInsets: EdgeInsets
    /// Where the content is as the finger lifts (the geometry's coordinates, like `startOffset`).
    package var currentOffset: CGPoint?

    package init(originalTarget: ScrollTarget, velocity: CGVector, contentSize: CGSize, containerSize: CGSize, axes: Axis.Set,
                 environment: EnvironmentValues, targets: [CGRect], startOffset: CGPoint, contentInsets: EdgeInsets,
                 currentOffset: CGPoint? = nil) {
        self.currentOffset = currentOffset
        self.originalTarget = originalTarget
        self.velocity = velocity
        self.contentSize = contentSize
        self.containerSize = containerSize
        self.axes = axes
        self.environment = environment
        self.targets = targets
        self.startOffset = startOffset
        self.contentInsets = contentInsets
    }

    /// The environment of the scrollable view.
    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T { environment[keyPath: keyPath] }
}

/// A type that defines the scroll behavior of a scrollable view.
public protocol ScrollTargetBehavior {
    /// Updates the proposed target that a scrollable view should scroll to.
    func updateTarget(_ target: inout ScrollTarget, context: ScrollTargetBehaviorContext)
}

/// The scroll behavior that aligns scroll targets to container-based geometry: the content
/// settles on a page the size of the container, at most one page from where the gesture began.
public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {}

    /// The speed (points per second) from which a lift turns the page the finger was going,
    /// however little it moved. Measured on iOS 27 in the simulator (new-website#216): 60 pt at
    /// 400 pt/s and 30 pt at 800 pt/s turn a page, 100 pt at 360 pt/s and 60 pt at 330 pt/s
    /// spring back; slower than that the nearer page wins (150 pt of 361 at 200 pt/s springs
    /// back, 220 pt turns).
    package static let flickSpeed: CGFloat = 380

    public func updateTarget(_ target: inout ScrollTarget, context: ScrollTargetBehaviorContext) {
        for axis in Axis.allCases where context.axes.contains(Axis.Set(axis)) {
            let length = context.containerSize[axis]
            guard length > 0 else { continue }
            let inset = axis == .horizontal ? context.contentInsets.leading : context.contentInsets.top
            let startPage = ((context.startOffset[axis] + inset) / length).rounded()
            var page: CGFloat
            if let current = context.currentOffset {
                // As iOS pages: a flick turns one page its way; otherwise the nearer page.
                let position = (current[axis] + inset) / length
                let speed = axis == .horizontal ? context.velocity.dx : context.velocity.dy
                if speed >= Self.flickSpeed { page = position.rounded(.down) + 1 }
                else if speed <= -Self.flickSpeed { page = position.rounded(.up) - 1 }
                else { page = position.rounded() }
            } else {
                page = ((target.rect.origin[axis] + inset) / length).rounded()
            }
            page = min(max(page, startPage - 1), startPage + 1)
            target.rect.origin[axis] = page * length - inset
        }
    }
}

/// The scroll behavior that aligns scroll targets to view-based geometry: the content settles
/// with a child of the scroll target layout aligned to the leading edge of the visible region.
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    /// A type that defines the amount of views that can be scrolled at a time.
    public struct LimitBehavior: Hashable, Sendable {
        package enum Role: Hashable, Sendable { case automatic, always, alwaysByFew, alwaysByOne, never }
        package let role: Role

        /// One view at a time in a compact horizontal size class, unlimited otherwise.
        public static let automatic = LimitBehavior(role: .automatic)
        /// One view at a time.
        public static let always = LimitBehavior(role: .always)
        /// A few views at a time (three).
        public static let alwaysByFew = LimitBehavior(role: .alwaysByFew)
        /// One view at a time.
        public static let alwaysByOne = LimitBehavior(role: .alwaysByOne)
        /// Any number of views.
        public static let never = LimitBehavior(role: .never)
    }

    public var limitBehavior: LimitBehavior
    /// The anchor of the visible region the views align to (leading and top when nil).
    public var anchor: UnitPoint?

    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
    }

    public init(limitBehavior: LimitBehavior = .automatic, anchor: UnitPoint?) {
        self.limitBehavior = limitBehavior
        self.anchor = anchor
    }

    public func updateTarget(_ target: inout ScrollTarget, context: ScrollTargetBehaviorContext) {
        guard !context.targets.isEmpty else { return }
        let limit: Int?
        switch limitBehavior.role {
        case .automatic: limit = context.environment.horizontalSizeClass == .compact ? 1 : nil
        case .always, .alwaysByOne: limit = 1
        case .alwaysByFew: limit = 3
        case .never: limit = nil
        }
        for axis in Axis.allCases where context.axes.contains(Axis.Set(axis)) {
            let inset = axis == .horizontal ? context.contentInsets.leading : context.contentInsets.top
            let fraction = anchor.map { axis == .horizontal ? $0.x : $0.y } ?? 0
            let container = context.containerSize[axis]
            // Where the content would sit with each target aligned, in the geometry's coordinates.
            let candidates = context.targets.map { $0.origin[axis] + fraction * $0.size[axis] - fraction * container - inset }
            func nearest(to value: CGFloat) -> Int {
                var best = 0
                for (index, candidate) in candidates.enumerated() where abs(candidate - value) < abs(candidates[best] - value) { best = index }
                return best
            }
            let start = nearest(to: context.startOffset[axis])
            var chosen = nearest(to: target.rect.origin[axis])
            if let limit { chosen = min(max(chosen, start - limit), start + limit) }
            target.rect.origin[axis] = candidates[chosen]
        }
    }
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    /// The scroll behavior that aligns scroll targets to container-based geometry.
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    /// The scroll behavior that aligns scroll targets to view-based geometry.
    public static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }

    /// The scroll behavior that aligns scroll targets to view-based geometry, limiting how many
    /// views a gesture scrolls past.
    public static func viewAligned(limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior) -> ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }

    /// The scroll behavior that aligns scroll targets to view-based geometry at the given anchor.
    public static func viewAligned(anchor: UnitPoint?) -> ViewAlignedScrollTargetBehavior {
        ViewAlignedScrollTargetBehavior(anchor: anchor)
    }
}

package struct ScrollTargetBehaviorKey: EnvironmentKey {
    nonisolated(unsafe) package static let defaultValue: (any ScrollTargetBehavior)? = nil
}

extension EnvironmentValues {
    /// The scroll target behaviour of the scroll views within (`scrollTargetBehavior`).
    package var _scrollTargetBehavior: (any ScrollTargetBehavior)? {
        get { self[ScrollTargetBehaviorKey.self] }
        set { self[ScrollTargetBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets the scroll behavior of views scrollable in the provided axes.
    nonisolated public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        environment(\._scrollTargetBehavior, behavior)
    }
}

// MARK: - Content margins

/// The placement of margins.
public struct ContentMarginPlacement: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case automatic, scrollContent, scrollIndicators }
    package let role: Role

    /// The automatic placement: the content and the indicators.
    public static let automatic = ContentMarginPlacement(role: .automatic)
    /// The scroll content placement: the content only.
    public static let scrollContent = ContentMarginPlacement(role: .scrollContent)
    /// The scroll indicators placement: the indicators only.
    public static let scrollIndicators = ContentMarginPlacement(role: .scrollIndicators)
}

/// The content margins of the scroll views within a view, for the content and the indicators.
package struct _ContentMargins: Equatable, Sendable {
    package var content = EdgeInsets()
    package var indicators = EdgeInsets()

    package mutating func set(_ edges: Edge.Set, _ insets: EdgeInsets, for placement: ContentMarginPlacement) {
        if placement.role != .scrollIndicators { content.replace(edges, with: insets) }
        if placement.role != .scrollContent { indicators.replace(edges, with: insets) }
    }
}

extension EdgeInsets {
    /// Replaces the given edges with those of `insets`.
    package mutating func replace(_ edges: Edge.Set, with insets: EdgeInsets) {
        if edges.contains(.top) { top = insets.top }
        if edges.contains(.leading) { leading = insets.leading }
        if edges.contains(.bottom) { bottom = insets.bottom }
        if edges.contains(.trailing) { trailing = insets.trailing }
    }

    package static func + (lhs: EdgeInsets, rhs: EdgeInsets) -> EdgeInsets {
        EdgeInsets(top: lhs.top + rhs.top, leading: lhs.leading + rhs.leading, bottom: lhs.bottom + rhs.bottom, trailing: lhs.trailing + rhs.trailing)
    }
}

package struct ContentMarginsKey: EnvironmentKey {
    package static let defaultValue = _ContentMargins()
}

extension EnvironmentValues {
    /// The content margins of the scroll views within (`contentMargins`).
    package var _contentMargins: _ContentMargins {
        get { self[ContentMarginsKey.self] }
        set { self[ContentMarginsKey.self] = newValue }
    }
}

extension View {
    /// Configures the content margin for the scrollable views within this view: the content is
    /// inset (and the scroll view grows across its axis by the margins, `scroll/margins`).
    nonisolated public func contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for placement: ContentMarginPlacement = .automatic) -> some View {
        _transformEnvironment("contentMargins", key: [AnyHashable(edges.rawValue), AnyHashable(insets), AnyHashable(placement)]) { $0._contentMargins.set(edges, insets, for: placement) }
    }

    /// Configures the content margin for the scrollable views within this view.
    nonisolated public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat?, for placement: ContentMarginPlacement = .automatic) -> some View {
        let value = length ?? 0
        return contentMargins(edges, EdgeInsets(top: value, leading: value, bottom: value, trailing: value), for: placement)
    }

    /// Configures the content margin for the scrollable views within this view.
    nonisolated public func contentMargins(_ length: CGFloat, for placement: ContentMarginPlacement = .automatic) -> some View {
        contentMargins(.all, length, for: placement)
    }
}

// MARK: - Anchor roles, indicator flashes, keyboard dismissal

/// A type defining the role of a scroll anchor.
public struct ScrollAnchorRole: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case initialOffset, sizeChanges, alignment }
    package let role: Role

    /// The anchor determines the initial content offset.
    public static let initialOffset = ScrollAnchorRole(role: .initialOffset)
    /// The anchor is kept when the content size changes (when the content sits at it).
    public static let sizeChanges = ScrollAnchorRole(role: .sizeChanges)
    /// The anchor aligns content smaller than the viewport.
    public static let alignment = ScrollAnchorRole(role: .alignment)
}

package struct DefaultScrollAnchorSizeChangesKey: EnvironmentKey { package static let defaultValue: UnitPoint? = nil }
package struct DefaultScrollAnchorAlignmentKey: EnvironmentKey { package static let defaultValue: UnitPoint? = nil }
package struct ScrollIndicatorsFlashOnAppearKey: EnvironmentKey { package static let defaultValue = false }

/// The ways that scrollable content can interact with the software keyboard.
public struct ScrollDismissesKeyboardMode: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case automatic, immediately, interactively, never }
    package let role: Role

    /// Determine the mode automatically: scrolling dismisses the keyboard.
    public static let automatic = ScrollDismissesKeyboardMode(role: .automatic)
    /// Dismiss the keyboard as soon as scrolling starts.
    public static let immediately = ScrollDismissesKeyboardMode(role: .immediately)
    /// Dismiss the keyboard as the finger scrolls (here: as soon as scrolling starts).
    public static let interactively = ScrollDismissesKeyboardMode(role: .interactively)
    /// Never dismiss the keyboard automatically as a result of scrolling.
    public static let never = ScrollDismissesKeyboardMode(role: .never)
}

package struct ScrollDismissesKeyboardModeKey: EnvironmentKey { package static let defaultValue = ScrollDismissesKeyboardMode.automatic }

extension EnvironmentValues {
    /// The anchor kept as the content size changes (`defaultScrollAnchor(_:for: .sizeChanges)`).
    package var _defaultScrollAnchorForSizeChanges: UnitPoint? {
        get { self[DefaultScrollAnchorSizeChangesKey.self] }
        set { self[DefaultScrollAnchorSizeChangesKey.self] = newValue }
    }

    /// The anchor aligning short content (`defaultScrollAnchor(_:for: .alignment)`).
    package var _defaultScrollAnchorForAlignment: UnitPoint? {
        get { self[DefaultScrollAnchorAlignmentKey.self] }
        set { self[DefaultScrollAnchorAlignmentKey.self] = newValue }
    }

    /// Whether scroll views flash their indicators when they appear.
    package var _scrollIndicatorsFlashOnAppear: Bool {
        get { self[ScrollIndicatorsFlashOnAppearKey.self] }
        set { self[ScrollIndicatorsFlashOnAppearKey.self] = newValue }
    }

    /// The way scrollable content interacts with the software keyboard.
    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode {
        get { self[ScrollDismissesKeyboardModeKey.self] }
        set { self[ScrollDismissesKeyboardModeKey.self] = newValue }
    }
}

/// `scrollIndicatorsFlash(trigger:)`: flashes the indicators of the scroll views within when
/// the value changes.
public struct _ScrollIndicatorsFlashModifier<Value: Equatable> {
    public var trigger: Value
    public init(trigger: Value) { self.trigger = trigger }
}

extension _ScrollIndicatorsFlashModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ScrollIndicatorsFlashNode(context)
    }
}

extension View {
    /// Associates an anchor to control the position of a scroll view in a particular
    /// circumstance: the initial offset, the content size changing, or the alignment of content
    /// smaller than the viewport.
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        _transformEnvironment("defaultScrollAnchor", key: [AnyHashable(anchor), AnyHashable(role)]) { environment in
            switch role.role {
            case .initialOffset: environment.defaultScrollAnchor = anchor
            case .sizeChanges: environment._defaultScrollAnchorForSizeChanges = anchor
            case .alignment: environment._defaultScrollAnchorForAlignment = anchor
            }
        }
    }

    /// Flashes the scroll indicators of scrollable views when they appear.
    nonisolated public func scrollIndicatorsFlash(onAppear: Bool) -> some View {
        environment(\._scrollIndicatorsFlashOnAppear, onAppear)
    }

    /// Flashes the scroll indicators of scrollable views when a value changes.
    nonisolated public func scrollIndicatorsFlash(trigger value: some Equatable) -> some View {
        modifier(_ScrollIndicatorsFlashModifier(trigger: value))
    }

    /// Configures the behavior in which scrollable content interacts with the software keyboard
    /// (iOS: a pan in a scroll view drops keyboard focus unless the mode is `never`).
    nonisolated public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View {
        environment(\.scrollDismissesKeyboardMode, mode)
    }
}
