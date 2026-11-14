// ScrollView: layout (flexible along its axes, content-sized across them), clipping, content
// offset, programmatic scrolling and user scrolling (wheel, pan, momentum). Measured behaviours
// are in Docs/elements/ScrollView.md; every constant is in PlatformMetrics.

/// A node `ScrollViewProxy.scrollTo` can address.
@MainActor
package protocol _ScrollTarget: AnyObject {
    /// Scrolls so the descendant identified by `id` is visible; false when there is none.
    func scrollTo(id: AnyHashable, anchor: UnitPoint?) -> Bool
}

/// A node that carries a `View.id(_:)` identifier.
@MainActor
package protocol _IdentifiedNode: AnyObject {
    var identifier: AnyHashable { get }
}

/// A node with a user-scrollable viewport.
@MainActor
package protocol _Scrollable: AnyObject {
    var isMounted: Bool { get }
    var contentOffset: CGPoint { get }
    /// Applies `delta` (positive moves the content up and left) and returns the part it could not
    /// consume, so enclosing scroll views can take over at the edges.
    func scroll(by delta: CGSize) -> CGSize
    /// Makes the indicators visible and restarts their fade.
    func showIndicators()
    /// Starts decelerating from `velocity` (points per second).
    func beginMomentum(velocity: CGSize)
    /// Whether momentum is still carrying the content.
    var isDecelerating: Bool { get }
    /// A finger pulling the content down past its top: the scroll view takes the distance
    /// (`refreshable`); returns whether it did.
    func pull(by distance: CGFloat) -> Bool
    /// The finger lifted after a pull: a pull past the threshold starts the refresh.
    func endPull()
    /// Stops momentum where the content is (a finger landing on a decelerating scroll view).
    func stopMomentum()
    /// Advances momentum and indicator fading by `elapsed` seconds; true while still animating.
    func advance(elapsed: Double) -> Bool
    /// Whether a frame that only scrolled can move the content instead of laying out (nothing
    /// inside reads its own geometry, no programmatic target pending).
    var canMoveContentOnly: Bool { get }
    /// Moves the content to the current offset without laying it out again.
    func moveContent()
    /// A touch landed on the scroll view (phase `tracking`).
    func beginTracking()
    /// The touch lifted with `velocity` (points per second, zero for none): momentum, or a scroll
    /// target behaviour settling the content.
    func endTracking(velocity: CGSize)
    /// Whether a pan starting in the scroll view drops keyboard focus (`scrollDismissesKeyboard`).
    var dismissesKeyboardOnScroll: Bool { get }
    /// Whether the content settles somewhere when the finger lifts (a scroll target behaviour,
    /// paging): a trackpad swipe settles it as the momentum begins instead of riding the tail.
    var settlesOnRelease: Bool { get }
    /// The axes it scrolls along.
    var scrollAxes: Axis.Set { get }
    /// A new wheel gesture starts over it: a settle still running is stopped, and the gesture
    /// counts from where it was heading.
    func beginWheelGesture()
}

extension Axis.Set {
    package init(_ axis: Axis) { self.init(rawValue: 1 << axis.rawValue) }
}

/// A node that turns a trackpad's sideways scroll into a swipe (a list's rows with actions).
@MainActor
package protocol _SwipeWheelReceiving: AnyObject {
    /// `dx` over `point` (the node's coordinates); returns whether the node took it.
    func swipeWheel(by dx: CGFloat, at point: CGPoint) -> Bool
}

/// Node for `ScrollView`. The builder content is wrapped in an implicit centre-aligned `VStack`
/// (fixture `scroll/children`), which is the single content node placed at `-contentOffset`.
@MainActor
extension _Scrollable {
    package func pull(by distance: CGFloat) -> Bool { false }
    package func endPull() {}
    package func beginTracking() {}
    package func endTracking(velocity: CGSize) { beginMomentum(velocity: velocity) }
    package var dismissesKeyboardOnScroll: Bool { false }
    package var settlesOnRelease: Bool { false }
    package var scrollAxes: Axis.Set { [.horizontal, .vertical] }
    package func beginWheelGesture() {}
}

package final class ScrollNode<Content: View>: LayoutNode<ScrollView<Content>>, _ScrollTarget, _Scrollable, _RelativeFrameContainer {
    override package var clipsHitTesting: Bool { true }
    package private(set) var child: TypedNode<VStack<Content>>!

    /// The current offset of the content within the viewport, clamped to the content at layout.
    package private(set) var contentOffset: CGPoint = .zero {
        // An iOS navigation bar collapses its large title as the screen's content scrolls.
        didSet {
            if contentOffset.y != oldValue.y { environment._navigationContext?.stack?.scrollDidChange(self) }
            if contentOffset != oldValue { markPlacementStale() }
        }
    }

    /// The content's size for the most recent layout.
    package private(set) var contentSize: CGSize = .zero

    /// The visible size the content is laid out against, which `containerRelativeFrame` inside
    /// takes its lengths from; the views that read it forget their sizes when it changes.
    package private(set) var relativeFrameContainerSize: CGSize = .zero
    private var relativeFrameDependents: [WeakNode] = []

    package func addRelativeFrameDependent(_ node: ViewNode) {
        relativeFrameDependents.removeAll { $0.node == nil }
        relativeFrameDependents.append(WeakNode(node: node))
    }

    /// Notes the visible size for `proposal` (the frame's length where the proposal has none).
    private func noteRelativeFrameContainer(_ proposal: ProposedViewSize, insets: EdgeInsets) {
        let size = CGSize(width: max(0, (proposal.width ?? frame.width) - insets.leading - insets.trailing),
                          height: max(0, (proposal.height ?? frame.height) - insets.top - insets.bottom))
        guard size != relativeFrameContainerSize else { return }
        var changed: Axis.Set = []
        if size.width != relativeFrameContainerSize.width { changed.insert(.horizontal) }
        if size.height != relativeFrameContainerSize.height { changed.insert(.vertical) }
        relativeFrameContainerSize = size
        relativeFrameDependents.removeAll { $0.node == nil }
        // Only the views that read a changed length forget their sizes (a page as wide as its
        // pager ignores the heights the pager is measured for), and only the memos inside the
        // content: this node's and its ancestors' are keyed by the proposal the container size
        // came from, so they stay right. Forgetting more made a pager measured for several
        // heights in one pass re-measure its pages, and the window above them, on every frame
        // that touched it (new-website#216: a keystroke on another tab measured 12,900 views).
        for dependent in relativeFrameDependents {
            if let reader = dependent.node as? any _RelativeFrameDependent, reader.relativeFrameAxes.isDisjoint(with: changed) { continue }
            dependent.node?.noteMemoReset("relative frame \(changed)")
            var node = dependent.node
            while let current = node, current !== self {
                current.invalidateSizeMemo()
                node = current.parent
            }
        }
    }

    private var appliedDefaultAnchor = false
    private var pendingTarget: (id: AnyHashable, anchor: UnitPoint?)?
    private var lastContentSize: CGSize?

    /// The scroll phase, published to the `onScrollPhaseChange` nodes above.
    package private(set) var phase: ScrollPhase = .idle {
        didSet {
            guard phase != oldValue else { return }
            let context = ScrollPhaseChangeContext(geometry: scrollGeometry, velocity: velocity == .zero ? nil : CGVector(dx: velocity.width, dy: velocity.height))
            for observer in ancestors(of: _ScrollPhaseObserving.self) { observer.scrollPhaseDidChange(from: oldValue, to: phase, context: context) }
        }
    }
    private var hasPublished = false
    /// The content offset when the gesture began (behaviours limit how far a gesture settles).
    private var trackingStartOffset = CGPoint.zero
    /// A scroll target behaviour carrying the content to its target.
    private var settle: (from: CGPoint, to: CGPoint, elapsed: Double, velocity: CGSize)?
    /// Seconds of wheel quiet left before the wheel scroll counts as ended.
    private var wheelIdle = 0.0

    /// The scroll targets (`scrollTargetLayout`) in content coordinates, refreshed at layout.
    package private(set) var targets: [(id: AnyHashable?, rect: CGRect)] = []
    /// The position binding's last value seen, and the identity last written to it.
    private var lastPosition: ScrollPosition?
    private var lastPositionedID: AnyHashable?

    // Animation state, advanced by the host through `Runtime.advanceScrollAnimations`.
    package private(set) var indicatorOpacity: Double = 0
    private var indicatorHold: Double = 0
    package private(set) var velocity: CGSize = .zero

    package init(_ context: _NodeContext<ScrollView<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = VStack<Content>._makeNode(_NodeContext(view: Self.wrapped(context.view), parent: self, environment: Self.contentEnvironment(context.environment)))
    }

    private static func wrapped(_ view: ScrollView<Content>) -> VStack<Content> {
        VStack { view.content }
    }

    /// The content starts a lazy context of its own (a scroll view in a lazy stack's row).
    private static func contentEnvironment(_ environment: EnvironmentValues) -> EnvironmentValues {
        var environment = environment
        environment._lazyContainerAxis = nil
        return environment
    }

    override package func update(view: ScrollView<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: Self.wrapped(view), environment: Self.contentEnvironment(environment), force: force)
    }

    package var axes: Axis.Set { view.axes }
    package var scrollAxes: Axis.Set { axes }
    package var settlesOnRelease: Bool { environment._scrollTargetBehavior != nil }

    /// Where the next wheel sequence counts from, when a settle it interrupted was heading there.
    private var pendingWheelStart: CGPoint?
    /// Where the current trackpad gesture began (a settle it interrupted: where that was
    /// heading): a paging view keeps within a page of it for the whole gesture.
    private var wheelGestureStart: CGPoint?

    package func beginWheelGesture() {
        // A swipe that interrupts a settle counts from where the settle was heading; the page
        // rule measures from here too, even within the last swipe's quiet period.
        let start = settle?.to ?? contentOffset
        wheelGestureStart = start
        trackingStartOffset = start
        pendingWheelStart = nil
        settle = nil
        wheelIdle = 0
    }
    package var isScrollEnabled: Bool { environment.isScrollEnabled }
    override package var extendsIntoSafeArea: Bool { true }

    /// Safe-area insets from an enclosing `safeAreaInset`/`safeAreaPadding` or the host: the
    /// scroll view keeps its frame and insets the content (read at layout, kept for scrolling).
    package private(set) var contentInsets = EdgeInsets()

    /// Whether an indicator may show along each axis.
    package var showsIndicators: (horizontal: Bool, vertical: Bool) {
        guard view.showsIndicators else { return (false, false) }
        return (axes.contains(.horizontal) && environment.horizontalScrollIndicatorVisibility.showsIndicators,
                axes.contains(.vertical) && environment.verticalScrollIndicatorVisibility.showsIndicators)
    }

    // MARK: Layout

    /// Along a scroll axis the content is proposed nothing (its ideal length); across it, the
    /// proposal passes through.
    private func contentProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: axes.contains(.horizontal) ? nil : proposal.width,
                         height: axes.contains(.vertical) ? nil : proposal.height)
    }

    /// Along a scroll axis the scroll view takes the proposal (its content's length when there is
    /// none); across it, exactly the content's size (fixtures `scroll/narrow-content`,
    /// `scroll/wide-content`).
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let insets = safeAreaOverlap + environment._contentMargins.content
        noteRelativeFrameContainer(proposal, insets: insets)
        var size = child.sizeThatFits(contentProposal(proposal, insets: insets))
        size.width += insets.leading + insets.trailing
        size.height += insets.top + insets.bottom
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            if let length = proposal[axis] { size[axis] = length }
        }
        return size
    }

    /// The content proposal with the safe-area insets taken off across the scroll axes.
    private func contentProposal(_ proposal: ProposedViewSize, insets: EdgeInsets) -> ProposedViewSize {
        var result = contentProposal(proposal)
        if let width = result.width { result.width = max(0, width - insets.leading - insets.trailing) }
        if let height = result.height { result.height = max(0, height - insets.top - insets.bottom) }
        return result
    }

    /// The largest offset along each scroll axis for the current content and viewport.
    package var maximumOffset: CGPoint {
        let insets = contentInsets
        return CGPoint(x: axes.contains(.horizontal) ? max(0, contentSize.width + insets.leading + insets.trailing - frame.width) : 0,
                       y: axes.contains(.vertical) ? max(0, contentSize.height + insets.top + insets.bottom - frame.height) : 0)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let maximum = maximumOffset
        return CGPoint(x: min(max(0, offset.x), maximum.x), y: min(max(0, offset.y), maximum.y))
    }

    /// The offset and size the content was last placed for (see `layoutContents`).
    private var placedViewport: (offset: CGPoint, size: CGSize)?

    override package func layoutContents(proposal: ProposedViewSize) {
        // After a scroll, a resize or with a target to scroll to, the content is placed whole:
        // lazy elements follow the viewport, not their proposal. Otherwise unchanged parts of it
        // keep their placements like the rest of the window.
        let whole = pendingTarget != nil || placedViewport.map { $0.offset != contentOffset || $0.size != frame.size } ?? true
        if whole { runtime.wholePlacements += 1 }
        defer {
            if whole { runtime.wholePlacements -= 1 }
            placedViewport = (contentOffset, frame.size)
        }
        cachedLazyProviders = nil
        contentInsets = safeAreaOverlap + environment._contentMargins.content
        noteRelativeFrameContainer(proposal, insets: contentInsets)
        let contentProposal = contentProposal(proposal, insets: contentInsets)
        let size = child.sizeThatFits(contentProposal)
        if let old = lastContentSize, old != size, let anchor = environment._defaultScrollAnchorForSizeChanges {
            keepAnchor(anchor, oldSize: old, newSize: size)
        }
        contentSize = size
        lastContentSize = size
        if !appliedDefaultAnchor {
            appliedDefaultAnchor = true
            if let anchor = environment.defaultScrollAnchor {
                let maximum = maximumOffset
                contentOffset = CGPoint(x: maximum.x * anchor.x, y: maximum.y * anchor.y)
            }
            if environment._scrollIndicatorsFlashOnAppear { showIndicators() }
        }
        contentOffset = clamped(contentOffset)
        placeContent(proposal: contentProposal)
        materializeLazyContent(proposal: contentProposal)
        layoutRefreshIndicator()
        refreshTargets()
        applyPositionBinding()
        // A programmatic target needs the content's fresh frames, so it is resolved after the
        // first placement and the content placed again when the offset moves.
        if let target = pendingTarget {
            pendingTarget = nil
            // A lazy element not created yet is created where its placeholder sits.
            // The provider forgets the memos the new element changes (its own and its ancestors').
            if targetRect(id: target.id) == nil, lazyProviders.contains(where: { $0.materialize(id: target.id) }) {
                cachedLazyProviders = nil
                contentSize = child.sizeThatFits(contentProposal)
                lastContentSize = contentSize
                placeContent(proposal: contentProposal)
            }
            if let rect = targetRect(id: target.id) {
                let offset = offset(scrollingTo: rect, anchor: target.anchor)
                if offset != contentOffset {
                    contentOffset = offset
                    placeContent(proposal: contentProposal)
                    materializeLazyContent(proposal: contentProposal)
                }
            }
        }
        lastPositionedID = targets.isEmpty ? nil : positionedID(anchor: positioningNode()?.positionAnchor)
        publishGeometry()
        if !hasPublished {
            hasPublished = true
            // The phase observers hear `idle` once as the scroll view appears (`scroll/geometry`).
            let context = ScrollPhaseChangeContext(geometry: scrollGeometry, velocity: nil)
            for observer in ancestors(of: _ScrollPhaseObserving.self) { observer.scrollPhaseDidChange(from: .idle, to: .idle, context: context) }
        }
    }

    private func placeContent(proposal: ProposedViewSize) {
        var origin = contentOrigin
        if environment._scrollContentSnapsToPixels {
            // On the window's half-point grid (a table view's rows never sit at a quarter point).
            let absolute = frameInRoot.origin
            origin.x = ((absolute.x + origin.x) * 2).rounded() / 2 - absolute.x
            origin.y = ((absolute.y + origin.y) * 2).rounded() / 2 - absolute.y
        }
        child.place(at: origin, anchor: .topLeading, proposal: proposal, by: self)
    }

    // MARK: Lazy content (Runtime/LazyNodes.swift)

    /// The viewport in content coordinates, one viewport further along each scroll axis: the
    /// elements a lazy `ForEach` creates ahead of the scroll.
    private var lazyWindow: CGRect {
        var window = CGRect(x: contentOffset.x - contentInsets.leading, y: contentOffset.y - contentInsets.top, width: frame.width, height: frame.height)
        if axes.contains(.horizontal) { window = window.insetBy(dx: -frame.width, dy: 0) }
        if axes.contains(.vertical) { window = window.insetBy(dx: 0, dy: -frame.height) }
        return window
    }

    /// The lazy `ForEach`es in the content, found once per layout (every scrolled frame asks
    /// whether one needs an element; the walk over the content is the cost of a layout).
    private var cachedLazyProviders: [any _LazyMaterializing]?
    private var lazyProviders: [any _LazyMaterializing] {
        if let cachedLazyProviders { return cachedLazyProviders }
        let providers = child.descendants(where: { $0 is _LazyMaterializing }).map { $0 as! any _LazyMaterializing }
        cachedLazyProviders = providers
        return providers
    }

    /// Creates the lazy elements in the window and lays the content out again with them, a few
    /// times over when the new sizes bring more into view.
    private func materializeLazyContent(proposal: ProposedViewSize) {
        var passes = 0
        while passes < 3 {
            let origin = child.frameInRoot.origin
            let window = lazyWindow
            var changed = false
            for provider in lazyProviders where provider.materialize(visible: window, contentOrigin: origin) { changed = true }
            guard changed else { return }
            cachedLazyProviders = nil   // the new elements may hold lazy content of their own
            passes += 1
            contentSize = child.sizeThatFits(proposal)
            lastContentSize = contentSize
            contentOffset = clamped(contentOffset)
            placeContent(proposal: proposal)
        }
    }

    /// Whether the offset moved lazy placeholders into the window (a frame must lay out).
    private var lazyContentNeedsLayout: Bool {
        let origin = child.frameInRoot.origin
        let window = lazyWindow
        return lazyProviders.contains { $0.needsMaterialization(visible: window, contentOrigin: origin) }
    }

    /// Where the content's top-left sits: the safe-area inset, scrolled by the offset; content
    /// shorter than the viewport is placed by the alignment anchor (`scroll/anchor-roles`).
    private var contentOrigin: CGPoint {
        var origin = CGPoint(x: contentInsets.leading - contentOffset.x, y: contentInsets.top - contentOffset.y + refreshOffset)
        if let anchor = environment._defaultScrollAnchorForAlignment {
            for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
                let available = frame.size[axis] - insetsAlong(axis)
                if contentSize[axis] < available {
                    origin[axis] += (available - contentSize[axis]) * (axis == .horizontal ? anchor.x : anchor.y)
                }
            }
        }
        return origin
    }

    /// The content insets along `axis`, both ends.
    private func insetsAlong(_ axis: Axis) -> CGFloat {
        axis == .horizontal ? contentInsets.leading + contentInsets.trailing : contentInsets.top + contentInsets.bottom
    }

    /// `defaultScrollAnchor(_:for: .sizeChanges)`: content sitting at the anchor stays there as
    /// the size changes (a chat at its bottom stays at the bottom; content at the top does not
    /// move, `scroll/anchor-roles`).
    private func keepAnchor(_ anchor: UnitPoint, oldSize: CGSize, newSize: CGSize) {
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            let fraction = axis == .horizontal ? anchor.x : anchor.y
            let oldMaximum = max(0, oldSize[axis] + insetsAlong(axis) - frame.size[axis])
            guard abs(contentOffset[axis] - oldMaximum * fraction) < 0.5 else { continue }
            let newMaximum = max(0, newSize[axis] + insetsAlong(axis) - frame.size[axis])
            contentOffset[axis] = newMaximum * fraction
        }
    }

    // MARK: Geometry, position binding and targets (API/ScrollTargets.swift)

    /// The nodes of `type` between this scroll view and the scroll view enclosing it.
    private func ancestors<T>(of type: T.Type) -> [T] {
        var result: [T] = []
        var node = parent
        while let current = node {
            if current is _Scrollable { break }
            if let match = current as? T { result.append(match) }
            node = current.parent
        }
        return result
    }

    /// The geometry as `ScrollGeometry` reports it: the offset from the content's origin
    /// (negative at rest under an inset) and the inset container (`scroll/geometry`).
    package var scrollGeometry: ScrollGeometry {
        ScrollGeometry(contentOffset: CGPoint(x: contentOffset.x - contentInsets.leading, y: contentOffset.y - contentInsets.top),
                       contentSize: contentSize, contentInsets: contentInsets,
                       containerSize: CGSize(width: max(0, frame.width - insetsAlong(.horizontal)), height: max(0, frame.height - insetsAlong(.vertical))))
    }

    private func publishGeometry() {
        let observers = ancestors(of: _ScrollGeometryObserving.self)
        guard !observers.isEmpty else { return }
        let geometry = scrollGeometry
        for observer in observers { observer.scrollGeometryDidChange(geometry) }
    }

    private func positioningNode() -> _ScrollPositioning? { ancestors(of: _ScrollPositioning.self).first }

    /// The scroll targets below, in content coordinates.
    private func refreshTargets() {
        guard let provider = child.descendants(where: { ($0 as? _ScrollTargetLayoutProviding)?.isEnabled == true }).first as? _ScrollTargetLayoutProviding else {
            targets = []
            return
        }
        let origin = child.frameInRoot.origin
        targets = provider.scrollTargets().map { target in
            let frame = target.node.frameInRoot
            return (target.id, CGRect(x: frame.minX - origin.x, y: frame.minY - origin.y, width: frame.width, height: frame.height))
        }
    }

    /// The binding's value changed since the last layout: scroll to it. The initial value and
    /// programmatic scrolls leave the binding alone (`scroll/position`).
    private func applyPositionBinding() {
        guard let positioning = positioningNode() else { return }
        let current = _trackingObservation(for: self) { positioning.currentPosition }
        guard let last = lastPosition else {
            lastPosition = current
            return
        }
        guard current != last else { return }
        lastPosition = current
        switch current.request {
        case .none:
            break
        case .id(let id, let anchor):
            pendingTarget = (id, anchor ?? positioning.positionAnchor)
        case .edge(let edge):
            let maximum = maximumOffset
            switch edge {
            case .top: contentOffset.y = 0
            case .bottom: contentOffset.y = maximum.y
            case .leading: contentOffset.x = 0
            case .trailing: contentOffset.x = maximum.x
            }
            placeContent(proposal: contentProposal(ProposedViewSize(frame.size), insets: contentInsets))
        case .point(let x, let y):
            contentOffset = clamped(CGPoint(x: x.map { $0 + contentInsets.leading } ?? contentOffset.x,
                                            y: y.map { $0 + contentInsets.top } ?? contentOffset.y))
            placeContent(proposal: contentProposal(ProposedViewSize(frame.size), insets: contentInsets))
        }
    }

    /// The target the scroll view is positioned on: without an anchor the one showing the most
    /// (the first of equals); with one, the target under the anchor point of the visible region,
    /// else the nearest to it.
    package func positionedID(anchor: UnitPoint?) -> AnyHashable? {
        let container = scrollGeometry.containerSize
        let visible = CGRect(origin: contentOffset, size: container)
        if let anchor {
            let point = CGPoint(x: contentOffset.x + anchor.x * container.width, y: contentOffset.y + anchor.y * container.height)
            if let hit = targets.first(where: { $0.rect.minX <= point.x && point.x < $0.rect.maxX && $0.rect.minY <= point.y && point.y < $0.rect.maxY }) {
                return hit.id
            }
            var best: (id: AnyHashable?, distance: CGFloat)?
            for target in targets {
                let dx = target.rect.midX - point.x, dy = target.rect.midY - point.y
                let distance = dx * dx + dy * dy
                if best == nil || distance < best!.distance { best = (target.id, distance) }
            }
            return best?.id
        }
        var best: (id: AnyHashable?, area: CGFloat)?
        for target in targets {
            let overlap = target.rect.intersection(visible)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > 0, best == nil || area > best!.area { best = (target.id, area) }
        }
        return best?.id
    }

    /// After a user scroll: the positioned identity changed, so the binding takes it.
    private func updatePositionBinding() {
        guard let positioning = positioningNode(), !targets.isEmpty else { return }
        let id = positionedID(anchor: positioning.positionAnchor)
        guard id != lastPositionedID else { return }
        lastPositionedID = id
        positioning.userScrolled(to: id)
        lastPosition = positioning.currentPosition
    }

    override package func unmount() {
        refreshIndicator?.unmount()
        super.unmount()
    }

    // MARK: Pull to refresh (`refreshable`, iOS: Docs/elements/List.md)

    /// The resisted distance of a pull in progress, then the band's height while refreshing.
    private var pullDistance: CGFloat = 0
    package private(set) var isRefreshing = false
    private var refreshIndicator: TypedNode<AnyView>?
    private var refreshOffset: CGFloat { isRefreshing ? PlatformMetrics.refreshHeight : pullDistance }
    private var canRefresh: Bool { environment.refresh != nil && axes.contains(.vertical) && environment.platformProfile.isIOS }

    /// The finger's raw travel past the top; the content follows it through the rubber band.
    private var pullTravel: CGFloat = 0

    package func pull(by distance: CGFloat) -> Bool {
        guard canRefresh, !isRefreshing, contentOffset.y <= 0 else { return false }
        pullTravel = max(0, pullTravel + distance)
        // UIScrollView's rubber band: the content moves (1 − 1 / (x·c/d + 1)) · d for a pull of
        // x against a view d tall, c = 0.55 — half the finger at first, ever less after.
        let d = max(1, frame.height), c = environment.platformProfile.metrics.refreshRubberBandConstant
        pullDistance = CGFloat(RubberBand.offset(forOvershoot: Double(pullTravel), dimension: Double(d), constant: Double(c)))
        runtime.requestFullLayout()
        return true
    }

    package func endPull() {
        guard pullDistance > 0 else { return }
        let threshold = environment.platformProfile.metrics.refreshThreshold
        let triggered = pullDistance >= threshold
        pullDistance = 0
        pullTravel = 0
        if triggered { beginRefresh() }
        runtime.requestFullLayout()
    }

    /// Runs the environment's refresh action, the content moved down behind a spinner meanwhile.
    package func beginRefresh() {
        guard let action = environment.refresh, !isRefreshing else { return }
        isRefreshing = true
        runtime.requestFullLayout()
        Task { @MainActor [weak self] in
            await action()
            guard let self, self.isMounted else { return }
            self.isRefreshing = false
            self.runtime.requestFullLayout()
        }
    }

    /// The spinner in the band above the content while pulling or refreshing.
    private func layoutRefreshIndicator() {
        guard refreshOffset > 0 else {
            if let node = refreshIndicator { node.unmount(); refreshIndicator = nil }
            return
        }
        let view = AnyView(ProgressView().progressViewStyle(.circular).opacity(isRefreshing ? 1 : min(1, pullDistance / environment.platformProfile.metrics.refreshThreshold)))
        let node: TypedNode<AnyView>
        if let existing = refreshIndicator {
            existing.update(view: view, environment: environment, force: false)
            node = existing
        } else {
            node = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
            refreshIndicator = node
        }
        guard let target = node.layoutChildren.first else { return }
        let size = target.sizeThatFits(.unspecified)
        target.place(at: CGPoint(x: (frame.width - size.width) / 2, y: contentInsets.top + (refreshOffset - size.height) / 2), anchor: .topLeading,
                     proposal: ProposedViewSize(size), by: self)
    }

    private var geometryCheckGeneration: UInt64 = .max
    private var contentReadsGeometry = false

    package var canMoveContentOnly: Bool {
        guard pendingTarget == nil, hasBeenPlaced, !lazyContentNeedsLayout else { return false }
        if geometryCheckGeneration != runtime.fullLayoutCount {   // the content can change with every full layout
            geometryCheckGeneration = runtime.fullLayoutCount
            // Structural descendants: a geometry reader in a background or overlay layer (a
            // fixture probe) reads the scrolled frame too.
            contentReadsGeometry = !child.descendants(where: { $0.readsGeometry }).isEmpty
        }
        return !contentReadsGeometry
    }

    package func moveContent() {
        child.moveFrame(toOrigin: contentOrigin)
        publishGeometry()
    }

    /// The frame of the identified descendant in content coordinates, or `nil`: a scroll target
    /// (a `ForEach` element of the target layout) or a `View.id(_:)` descendant.
    private func targetRect(id: AnyHashable) -> CGRect? {
        if let target = targets.first(where: { $0.id == id }) { return target.rect }
        guard let node = identifiedNode(id) else { return nil }
        let frames = node.layoutChildren.map(\.frameInRoot)
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() { union = union.union(frame) }
        let origin = child.frameInRoot.origin
        return CGRect(x: union.minX - origin.x, y: union.minY - origin.y, width: union.width, height: union.height)
    }

    private func identifiedNode(_ id: AnyHashable) -> ViewNode? {
        child.descendants(where: { ($0 as? _IdentifiedNode)?.identifier == id }).first
    }

    /// The offset that shows `rect` (content coordinates): aligned on `anchor` in both the target
    /// and the viewport, or with the smallest change that brings it fully into view
    /// (fixture `scroll/scroll-to`).
    private func offset(scrollingTo rect: CGRect, anchor: UnitPoint?) -> CGPoint {
        var offset = contentOffset
        // Mirrored content: measure the target from the trailing end, where offset 0 lies.
        var rect = rect
        if mirrorsPlacements { rect.origin.x = contentSize.width - rect.maxX }
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            let viewport = frame.size[axis]
            let start = rect.origin[axis], length = rect.size[axis]
            if let anchor {
                let fraction = axis == .horizontal ? anchor.x : anchor.y
                offset[axis] = start + fraction * length - fraction * viewport
            } else if start < offset[axis] {
                offset[axis] = start
            } else if start + length > offset[axis] + viewport {
                offset[axis] = start + length - viewport
            }
        }
        return clamped(offset)
    }

    // MARK: Programmatic and user scrolling

    package func scrollTo(id: AnyHashable, anchor: UnitPoint?) -> Bool {
        guard targets.contains(where: { $0.id == id }) || identifiedNode(id) != nil || lazyProviders.contains(where: { $0.hasPlaceholder(id: id) }) else { return false }
        pendingTarget = (id, anchor)
        // The target is resolved in the next full layout (the fast path only moves frames).
        runtime.requestFullLayout()
        return true
    }

    package func scroll(by delta: CGSize) -> CGSize {
        guard isScrollEnabled else { return delta }
        // Right-to-left: offset 0 is the trailing end (the content is placed mirrored), so a
        // leftward swipe lowers the offset.
        let mirrored = mirrorsPlacements
        var delta = delta
        if mirrored { delta.width = -delta.width }
        var remaining = delta
        var offset = contentOffset
        let maximum = maximumOffset
        // A wheel over a paging view moves it at most one page from where the gesture began,
        // as a finger on the glass can: the OS's momentum tail, which a page cannot tell from
        // the finger, no longer carries it across the other pages before it settles back
        // (new-website#216: one swipe ran to the last page, then back to the second).
        let wheel = runtime.pan == nil && velocity == .zero && settle == nil
        let gestureStart = wheel && settlesOnRelease ? wheelGestureStart : nil
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            let target = offset[axis] + delta[axis]
            var low: CGFloat = 0, high = maximum[axis]
            if let start = gestureStart {
                let page = relativeFrameContainerSize[axis] > 0 ? relativeFrameContainerSize[axis] : frame.size[axis]
                low = max(low, start[axis] - page)
                high = min(high, start[axis] + page)
            }
            let clampedValue = min(max(low, target), high)
            // What the page limit holds back stays with this view (the gesture is its own).
            remaining[axis] = gestureStart != nil && clampedValue > 0 && clampedValue < maximum[axis] ? 0 : target - clampedValue
            offset[axis] = clampedValue
        }
        if mirrored { remaining.width = -remaining.width }
        if offset != contentOffset {
            contentOffset = offset
            runtime.noteScrolled(self)
            runtime.requestLayout(invalidatingSizes: false)
            if runtime.pan != nil {
                phase = .interacting
            } else if velocity == .zero, settle == nil {
                // A wheel: interacting until it goes quiet (there is no gesture end to hear).
                if wheelIdle == 0 {
                    trackingStartOffset = gestureStart ?? pendingWheelStart ?? CGPoint(x: offset.x - delta.width, y: offset.y - delta.height)
                    pendingWheelStart = nil
                }
                phase = .interacting
                wheelIdle = environment.platformProfile.metrics.scrollWheelIdleSeconds
                runtime.animate(self)
            }
            updatePositionBinding()
        } else if gestureStart != nil, delta != .zero {
            // Held at the page limit, the gesture goes on: its quiet period starts again with
            // every event, or it would settle and start counting afresh mid-swipe.
            wheelIdle = environment.platformProfile.metrics.scrollWheelIdleSeconds
            runtime.animate(self)
        }
        return remaining
    }

    package func beginTracking() {
        wheelGestureStart = nil
        settle = nil
        wheelIdle = 0
        trackingStartOffset = contentOffset
        phase = .tracking
    }

    package func endTracking(velocity: CGSize) {
        if environment._scrollTargetBehavior != nil {
            settleWithBehavior(velocity: velocity)
        } else if velocity != .zero {
            beginMomentum(velocity: velocity)
        } else {
            phase = .idle
        }
    }

    package var dismissesKeyboardOnScroll: Bool {
        environment.platformProfile.isIOS && environment.scrollDismissesKeyboardMode.role != .never
    }

    /// Hands the projected rest position to the scroll target behaviour and carries the content
    /// to the target it returns.
    private func settleWithBehavior(velocity: CGSize) {
        guard let behavior = environment._scrollTargetBehavior else { return }
        let metrics = environment.platformProfile.metrics
        // The distance momentum would cover: the geometric sum of the per-millisecond decays.
        let decay = DecayModel(rate: metrics.scrollDecelerationRate)
        let projected = clamped(CGPoint(x: contentOffset.x + decay.projectedOffset(velocity: velocity.width), y: contentOffset.y + decay.projectedOffset(velocity: velocity.height)))
        let geometry = scrollGeometry
        var target = ScrollTarget(rect: CGRect(origin: CGPoint(x: projected.x - contentInsets.leading, y: projected.y - contentInsets.top), size: geometry.containerSize))
        let context = ScrollTargetBehaviorContext(
            originalTarget: target, velocity: CGVector(dx: velocity.width, dy: velocity.height),
            contentSize: contentSize, containerSize: geometry.containerSize, axes: axes, environment: environment,
            targets: targets.map(\.rect), startOffset: CGPoint(x: trackingStartOffset.x - contentInsets.leading, y: trackingStartOffset.y - contentInsets.top),
            contentInsets: contentInsets,
            currentOffset: CGPoint(x: contentOffset.x - contentInsets.leading, y: contentOffset.y - contentInsets.top))
        behavior.updateTarget(&target, context: context)
        let destination = clamped(CGPoint(x: target.rect.minX + contentInsets.leading, y: target.rect.minY + contentInsets.top))
        self.velocity = .zero
        guard destination != contentOffset else {
            phase = .idle
            return
        }
        settle = (contentOffset, destination, 0, velocity)
        // The wheel is over: its quiet period must not settle again from mid-way.
        wheelIdle = 0
        phase = .decelerating
        runtime.animate(self)
    }

    package func showIndicators() {
        let shows = showsIndicators
        guard shows.horizontal || shows.vertical else { return }
        indicatorOpacity = 1
        indicatorHold = PlatformMetrics.scrollerHoldSeconds
        runtime.animate(self)
    }

    package func beginMomentum(velocity: CGSize) {
        guard velocity != .zero else { return }
        self.velocity = velocity
        phase = .decelerating
        runtime.animate(self)
    }

    package var isDecelerating: Bool { velocity != .zero || settle != nil }

    package func stopMomentum() {
        velocity = .zero
        settle = nil
        indicatorHold = PlatformMetrics.scrollerHoldSeconds
    }

    package func advance(elapsed: Double) -> Bool {
        var animating = false
        if var state = settle {
            state.elapsed += elapsed
            let omega = environment.platformProfile.metrics.scrollTargetSpring
            var progress: Double
            if omega > 0 {
                // x(t) = to + (d₀ + (v₀ + ω d₀) t) e^(−ωt): the finger's speed carries on into the
                // spring, which then eases the content onto its target (iOS paging).
                let t = state.elapsed, spring = SpringModel(omega: omega, zeta: 1)
                func axis(_ from: CGFloat, _ to: CGFloat, _ v: CGFloat) -> CGFloat {
                    let d0 = Double(from - to)
                    // A fast finger carries into the spring only up to 1.7 ω d₀ toward the target:
                    // iOS overshoots a page by about 4 pt after a 3,000 pt/s flick, not 20.
                    var v0 = Double(v)
                    if v0 * d0 < 0 { v0 = max(-1.7 * omega * abs(d0), min(1.7 * omega * abs(d0), v0)) }
                    return to + CGFloat(spring.state(displacement: d0, velocity: v0, at: t).displacement)
                }
                let next = CGPoint(x: axis(state.from.x, state.to.x, state.velocity.width), y: axis(state.from.y, state.to.y, state.velocity.height))
                let left = max(abs(next.x - state.to.x), abs(next.y - state.to.y))
                progress = t > 0.05 && left < 0.25 ? 1 : 0
                contentOffset = progress >= 1 ? state.to : next
            } else {
                let duration = environment.platformProfile.metrics.scrollTargetSettleSeconds
                progress = duration > 0 ? min(1, state.elapsed / duration) : 1
                let eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
                contentOffset = CGPoint(x: state.from.x + (state.to.x - state.from.x) * eased, y: state.from.y + (state.to.y - state.from.y) * eased)
            }
            runtime.noteScrolled(self)
            runtime.requestLayout(invalidatingSizes: false)
            updatePositionBinding()
            if progress >= 1 {
                settle = nil
                phase = .idle
            } else {
                settle = state
                animating = true
            }
            indicatorHold = PlatformMetrics.scrollerHoldSeconds
        }
        if wheelIdle > 0 {
            wheelIdle = max(0, wheelIdle - elapsed)
            if wheelIdle > 0 {
                animating = true
            } else if environment._scrollTargetBehavior != nil {
                settleWithBehavior(velocity: .zero)
                if settle != nil { animating = true }
            } else {
                phase = .idle
            }
        }
        if velocity != .zero {
            // Exact friction over the real frame time (`DecayModel`): the same coast at any
            // frame rate.
            let decay = DecayModel(rate: PlatformMetrics.scrollDecelerationRate)
            let x = decay.state(velocity: Double(velocity.width), at: elapsed), y = decay.state(velocity: Double(velocity.height), at: elapsed)
            let remaining = scroll(by: CGSize(width: x.offset, height: y.offset))
            // Momentum stops at an edge (no rubber band, see the element doc) and below a floor.
            velocity = CGSize(width: remaining.width == 0 ? x.velocity : 0,
                              height: remaining.height == 0 ? y.velocity : 0)
            if abs(velocity.width) < PlatformMetrics.scrollVelocityFloor { velocity.width = 0 }
            if abs(velocity.height) < PlatformMetrics.scrollVelocityFloor { velocity.height = 0 }
            if velocity != .zero { animating = true } else if phase == .decelerating { phase = .idle }
            indicatorHold = PlatformMetrics.scrollerHoldSeconds
        }
        if indicatorOpacity > 0 {
            if indicatorHold > 0 {
                indicatorHold = max(0, indicatorHold - elapsed)
            } else {
                indicatorOpacity = max(0, indicatorOpacity - elapsed / PlatformMetrics.scrollerFadeSeconds)
                runtime.requestLayout(invalidatingSizes: false)
            }
            if indicatorOpacity > 0 { animating = true }
        }
        return animating
    }

    // MARK: Painting and hit testing

    override package var paintedChildren: [ViewNode] { [child] }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let clips = !environment.isScrollClipDisabled
        var context = context
        if clips {
            var bounds = absoluteBounds(context)
            // Under an iOS navigation bar the content shows through the bar's glass: the clip
            // reaches up to the window's top (ios/nav/scroll `row1`).
            let overhang = environment._navigationBarOverhang
            if overhang > 0 { bounds = CGRect(x: bounds.minX, y: bounds.minY - overhang, width: bounds.width, height: bounds.height + overhang) }
            // An edge on the safe area's boundary shows the content scrolling on under the
            // status bar and the home indicator, as UIKit's scroll view reaches the screen's edges
            // with its content inset by the safe area; at rest nothing moves.
            let reach = safeAreaExtension
            if reach != EdgeInsets() {
                let top = max(0, reach.top - max(0, overhang))
                bounds = CGRect(x: bounds.minX - reach.leading, y: bounds.minY - top,
                                width: bounds.width + reach.leading + reach.trailing, height: bounds.height + top + reach.bottom)
            }
            list.append(.save)
            list.append(.clipRect(bounds))
            // Subtrees entirely outside the viewport (by more than the margin) are not painted.
            context.visibleRect = bounds.insetBy(dx: -PlatformMetrics.scrollCullMargin, dy: -PlatformMetrics.scrollCullMargin)
            context.clipRect = context.clipRect.map { $0.intersection(bounds) } ?? bounds
        }
        paintChildren(into: &list, context: context)
        if clips { list.append(.restore) }
        paintIndicators(into: &list, context: context)
        if let indicator = refreshIndicator?.layoutChildren.first, refreshOffset > 0 {
            indicator.paint(into: &list, context: context.child(at: indicator.presentedFrame))
        }
    }

    /// Overlay scrollers: a knob on the trailing edge of each scrollable axis, shown only while
    /// scrolling: a 7 pt black core at half opacity in a 1 pt white halo, 2 pt from the trailing
    /// edge and 4 pt from the ends of the track (measured from `NSScroller.drawKnob`; the hold
    /// and fade times and the minimum length are approximate). The indicator content margins
    /// shorten the track.
    private func paintIndicators(into list: inout DisplayList, context: PaintContext) {
        guard indicatorOpacity > 0 else { return }
        let shows = showsIndicators
        let thickness = PlatformMetrics.scrollerThickness, inset = PlatformMetrics.scrollerInset, endInset = PlatformMetrics.scrollerEndInset
        let halo = PlatformMetrics.scrollerHaloWidth
        let margins = environment._contentMargins.indicators
        // The track stops at the safe area (a bar or `safeAreaInset` the content runs under).
        let safe = safeAreaOverlap
        for axis in Axis.allCases where axis == .horizontal ? shows.horizontal : shows.vertical {
            let viewport = frame.size[axis], content = contentSize[axis] + insetsAlong(axis)
            let leadingMargin = (axis == .horizontal ? margins.leading : margins.top) + (axis == .horizontal ? safe.leading : safe.top)
            let trailingMargin = (axis == .horizontal ? margins.trailing : margins.bottom) + (axis == .horizontal ? safe.trailing : safe.bottom)
            let track = viewport - 2 * endInset - leadingMargin - trailingMargin
            guard content > viewport, track > 0 else { continue }
            let knob = min(track, max(PlatformMetrics.scrollerMinimumKnobLength, track * viewport / content))
            let position = endInset + leadingMargin + (track - knob) * (contentOffset[axis] / (content - viewport))
            let across = axis == .vertical ? margins.trailing : margins.bottom
            let rect = axis == .vertical
                ? CGRect(x: frame.width - inset - thickness - across, y: position, width: thickness, height: knob)
                : CGRect(x: position, y: frame.height - inset - thickness - across, width: knob, height: thickness)
            list.append(.fillRRect(context.absoluteRect(rect.insetBy(dx: -halo, dy: -halo)), cornerRadius: thickness / 2 + halo,
                                   PlatformMetrics.scrollerHalo.multiplyingAlpha(by: indicatorOpacity)))
            list.append(.fillRRect(context.absoluteRect(rect), cornerRadius: thickness / 2,
                                   PlatformMetrics.scrollerKnob.multiplyingAlpha(by: indicatorOpacity)))
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "ScrollView" }
}

/// Node for `ScrollViewReader`: evaluates the content closure with a proxy to itself, tracking
/// the observable state the closure reads, and is transparent to layout.
@MainActor
package final class ScrollViewReaderNode<Content: View>: TypedNode<ScrollViewReader<Content>> {
    package private(set) var child: TypedNode<Content>!

    package init(_ context: _NodeContext<ScrollViewReader<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        evaluate()
    }

    override package func update(view: ScrollViewReader<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        evaluate()
    }

    private func evaluate() {
        let content = _trackingObservation(for: self) { view.content(ScrollViewProxy(reader: self)) }
        if let child {
            child.update(view: content, environment: environment)
        } else {
            child = Content._makeNode(_NodeContext(view: content, parent: self, environment: environment))
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ScrollViewReader" }
}

extension IDNode: _IdentifiedNode {
    package var identifier: AnyHashable { AnyHashable(view.id) }
}

// MARK: - Runtime: user scrolling

/// A touch pan in progress: the scroll views under the finger, innermost first.
package struct PanState {
    package let nodes: [ViewNode & _Scrollable]
    package let start: CGPoint
    package let startTime: Double
    package var last: CGPoint
    package var lastTime: Double
    package var velocity: CGSize = .zero
    package var active = false
    /// An iOS sheet under the finger: it takes what a downward drag leaves over (all of it
    /// without a scroll view, what is past the top with one) and follows the finger down.
    package var sheet: PresentationNode?
    package var sheetDragged = false
    /// The scroll view that owns the pan: the innermost one under the finger that scrolls along
    /// the way the finger set off (iOS: a sideways pager's pan fails for a vertical finger, so
    /// the page around it takes the touch, its pull and its momentum). Set on the first move.
    package var owner: (ViewNode & _Scrollable)?
    /// The finger's recent path, for its speed at the lift.
    package var tracker = VelocityTracker()

    /// The finger's speed over the last 50 ms of its path (points per second, content
    /// direction: against the finger), as UIKit measures it (`VelocityTracker`).
    package var recentVelocity: CGSize? {
        tracker.recentVelocity.map { CGSize(width: -$0.width, height: -$0.height) }
    }
}

extension Runtime {
    /// Scroll views on the hit path under `point` (window coordinates), innermost first.
    package func scrollableNodes(at point: CGPoint) -> [ViewNode & _Scrollable] {
        var result: [ViewNode & _Scrollable] = []
        func visit(_ node: ViewNode, _ local: CGPoint) {
            if let scrollable = node as? (ViewNode & _Scrollable) { result.append(scrollable) }
            for child in node.paintedChildren.reversed() {
                let childPoint = CGPoint(x: local.x - child.frame.minX, y: local.y - child.frame.minY)
                guard child.contains(childPoint) else { continue }
                visit(child, childPoint)
                return
            }
        }
        // The topmost presentation's scroll views under its panel (where it is drawn); nothing
        // under a modal one.
        if let top = presentations.last {
            var inPanel = point
            if top.slides { inPanel.y -= CGFloat(top.slide.position) }
            if top.panel.contains(inPanel) {
                for node in top.semanticsRoots.reversed() {
                    let local = CGPoint(x: inPanel.x - node.frame.minX, y: inPanel.y - node.frame.minY)
                    guard node.contains(local) else { continue }
                    visit(node, local)
                    break
                }
                return result.reversed()
            }
            if top.isModal { return [] }
        }
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            guard node.contains(local) else { continue }
            visit(node, local)
            break
        }
        return result.reversed()
    }

    /// The iOS sheet a touch at `point` can drag down: the topmost presentation, when it is one
    /// and the touch is on it.
    package func draggableSheet(at point: CGPoint) -> PresentationNode? {
        guard let top = presentations.last, top.dragsToDismiss else { return nil }
        let inPanel = CGPoint(x: point.x, y: point.y - CGFloat(top.slide.position))
        return top.panel.contains(inPanel) ? top : nil
    }

    /// Applies a scroll delta (points; positive moves the content up and left) to the scroll
    /// views under `point`, innermost first, each taking what it can (scroll chaining).
    @discardableResult
    package func scroll(by delta: CGSize, at point: CGPoint) -> CGSize {
        scroll(by: delta, through: scrollableNodes(at: point))
    }

    private func scroll(by delta: CGSize, through nodes: [ViewNode & _Scrollable]) -> CGSize {
        var remaining = delta
        for node in nodes {
            let before = node.contentOffset
            remaining = node.scroll(by: remaining)
            if node.contentOffset != before { node.showIndicators() }
            if remaining == .zero { break }
        }
        return remaining
    }

    /// A wheel event at `point`; deltas are in points (the host has already normalised line and
    /// page modes). Desktop wheel deltas carry the OS's own momentum, so none is added.
    public func scrollWheel(by delta: CGSize, at point: CGPoint) {
        // A sideways scroll over a list row with swipe actions swipes the row (macOS trackpads).
        if abs(delta.width) > abs(delta.height), let list = swipeWheelReceiver(at: point) {
            let origin = list.frameInRoot.origin
            if list.swipeWheel(by: delta.width, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y)) { return }
        }
        // A scroll view inside a hosted tree under the pointer takes the wheel first; what it
        // leaves (at its end) chains to the scroll views around it (ios/representable/wheel).
        var delta = delta
        if let host = interactiveNode(at: point) as? any _PlatformViewHosting, let node = host as? ViewNode {
            let origin = node.frameInRoot.origin
            delta = host.tree.scrollWheel(by: delta, at: CGPoint(x: point.x - origin.x, y: point.y - origin.y))
            if delta == .zero { return }
        }
        wheelGestureEvent(delta, at: point)
    }

    /// A trackpad gesture as wheel events, the way a finger drives an iPhone's scroll views
    /// (new-website#216). A browser's wheel events carry no phase: where the finger lifts and
    /// the OS's momentum tail begins is read from the events themselves.
    ///
    /// - A gesture keeps to the axis it started along and to the scroll views under it then: a
    ///   vertical swipe never turns a sideways pager, a sideways one never scrolls the page.
    /// - The tail is recognised as AppKit synthesises it: the speed falling by a steady ratio.
    ///   When the last five ratios of successive speeds all lie in 0.6…0.96 (the rule of the
    ///   wheel-gestures library behind Embla's carousels), the finger has lifted.
    /// - A paging view then settles on one page, in the direction the gesture moved, and the
    ///   rest of the gesture is its momentum, swallowed: one swipe turns one page, as AppKit's
    ///   fluid swiping commits ±1 at the gesture's end.
    /// - In the tail, only a clear new push starts the next gesture (a delta over twice the last
    ///   and over 2 pt), or a pause; before it, a pause of a tenth of a second or an event wholly
    ///   along the other axis. A tail's own noise (a delta a little larger than the last) no
    ///   longer starts a gesture that pages again and then settles back.
    private func wheelGestureEvent(_ delta: CGSize, at point: CGPoint) {
        let now = wheelEventTime ?? wheelClock()
        let magnitude = max(abs(delta.width), abs(delta.height))
        var gesture: WheelGesture
        if var current = wheelGesture, current.nodes.allSatisfy(\.isMounted), current.continues(with: delta, magnitude: magnitude, at: now) {
            current.record(delta, magnitude: magnitude, at: now)
            gesture = current
        } else {
            // Along the larger delta; an event as far one way as the other keeps the last
            // gesture's axis.
            let axis: Axis = abs(delta.width) == abs(delta.height) ? (wheelGesture?.axis ?? .vertical)
                : abs(delta.width) > abs(delta.height) ? .horizontal : .vertical
            let nodes = scrollableNodes(at: point).filter { $0.scrollAxes.contains(Axis.Set(axis)) }
            // A view still settling from the last swipe counts this one from where it settles.
            for node in nodes { node.beginWheelGesture() }
            gesture = WheelGesture(axis: axis, nodes: nodes, lastTime: now, lastMagnitude: magnitude)
            gesture.displacement = axis == .horizontal ? delta.width : delta.height
        }
        defer { wheelGesture = gesture }
        // The momentum of a settled gesture belongs to the view that settled.
        if gesture.settled { return }
        let locked = gesture.axis == .horizontal ? CGSize(width: delta.width, height: 0) : CGSize(width: 0, height: delta.height)
        var remaining = locked
        for node in gesture.nodes {
            let before = node.contentOffset
            remaining = node.scroll(by: remaining)
            if node.contentOffset != before {
                node.showIndicators()
                if gesture.mover == nil { gesture.mover = node }
            }
            if remaining == .zero { break }
        }
        if gesture.inMomentum, let mover = gesture.mover, mover.settlesOnRelease {
            gesture.settled = true
            // The direction the gesture moved, at the speed the finger left with.
            let speed = gesture.displacement.sign == .minus ? -abs(gesture.liftSpeed) : abs(gesture.liftSpeed)
            mover.endTracking(velocity: gesture.axis == .horizontal ? CGSize(width: speed, height: 0) : CGSize(width: 0, height: speed))
            requestLayout(invalidatingSizes: false)
        }
    }

    /// A wheel event with its time (seconds, the host's clock): gesture gaps are measured
    /// between the events themselves, not between the moments a busy page got to them.
    public func scrollWheel(by delta: CGSize, at point: CGPoint, time: Double) {
        wheelEventTime = time
        defer { wheelEventTime = nil }
        scrollWheel(by: delta, at: point)
    }

    /// The deepest list under `point` that takes sideways scrolls as swipes.
    private func swipeWheelReceiver(at point: CGPoint) -> (ViewNode & _SwipeWheelReceiving)? {
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            if let hit = node.hitTest(local, where: { $0 is _SwipeWheelReceiving }) { return hit as? (ViewNode & _SwipeWheelReceiving) }
        }
        return nil
    }

    /// Registers a scroll view whose momentum or indicators need frames.
    package func animate(_ node: ViewNode & _Scrollable) {
        if !animatingScrollNodes.contains(where: { $0 === node }) { animatingScrollNodes.append(node) }
        requestLayout(invalidatingSizes: false)
    }

    /// Advances scroll momentum and indicator fades by `elapsed` seconds. Hosts call this once
    /// per frame; true means another frame is needed.
    public func advanceScrollAnimations(elapsed: Double) -> Bool {
        animatingScrollNodes.removeAll { !$0.isMounted }
        animatingScrollNodes = animatingScrollNodes.filter { $0.advance(elapsed: elapsed) }
        return !animatingScrollNodes.isEmpty
    }

    // MARK: Touch panning

    /// Starts tracking a touch that may become a pan of the scroll views under `point`.
    package func beginPan(at point: CGPoint, time: Double) {
        let nodes = scrollableNodes(at: point)
        let sheet = draggableSheet(at: point)
        guard !nodes.isEmpty || sheet != nil else { return }
        var state = PanState(nodes: nodes, start: point, startTime: time, last: point, lastTime: time)
        state.sheet = sheet
        // A finger landing on decelerating content stops it where it is and owns the touch:
        // the content follows it at once and lifting delivers no press (iOS behaviour).
        let decelerating = nodes.filter(\.isDecelerating)
        if !decelerating.isEmpty {
            for node in decelerating { node.stopMomentum() }
            state.active = true
            requestLayout(invalidatingSizes: false)
        }
        nodes.first?.beginTracking()
        pan = state
    }

    /// Feeds a touch move to the pan; once the finger has travelled `PlatformMetrics.panSlop`
    /// the pan is active, the pending press is cancelled and the content follows the finger.
    /// A control that tracks drags (`dragAxes`) keeps the touch instead when the finger set off
    /// along one of its axes, or rested on it first (UIScrollView's delayed content touches):
    /// a slider in a vertical scroll view follows a sideways finger, and a finger that then
    /// wanders up or down still drives the slider rather than the scroll.
    package func continuePan(to point: CGPoint, time: Double) {
        guard var state = pan else { return }
        // Every move of the finger, from the touch on, for its speed at the lift.
        if state.tracker.samples.isEmpty { state.tracker.add(state.start, at: state.startTime) }
        state.tracker.add(point, at: time)
        if !state.active {
            let dx = point.x - state.start.x, dy = point.y - state.start.y
            guard dx * dx + dy * dy >= PlatformMetrics.panSlop * PlatformMetrics.panSlop else { pan = state; return }
            if let pressed = pressedNode, !pressed.dragAxes.isEmpty {
                let dominant: Axis.Set = abs(dx) >= abs(dy) ? .horizontal : .vertical
                if pressed.dragAxes.contains(dominant) || time - state.startTime >= PlatformMetrics.touchHoldInterval {
                    pan = nil
                    state.nodes.first?.endTracking(velocity: .zero)
                    return
                }
            }
            state.active = true
            // The content follows from here: the slop the finger travelled first is not made
            // up at once (iOS: a 100 pt drag moves the content 90 pt, no jump at the start).
            let travelled = (dx * dx + dy * dy).squareRoot()
            let crossing = CGPoint(x: state.start.x + dx * PlatformMetrics.panSlop / travelled, y: state.start.y + dy * PlatformMetrics.panSlop / travelled)
            state.last = crossing
            pressedNode?.pressEnded(inside: false)
            pressedNode = nil
            for node in simultaneousPressNodes { node.pressEnded(inside: false) }
            simultaneousPressNodes = []
            // iOS: scrolling dismisses the keyboard (`scrollDismissesKeyboard`).
            if let first = state.nodes.first, first.dismissesKeyboardOnScroll { focusTextField(nil) }
        }
        // The way the finger set off picks the scroll view that owns the pan (`PanState.owner`).
        if state.owner == nil, point != state.start {
            let dx = point.x - state.start.x, dy = point.y - state.start.y
            let axis: Axis.Set = abs(dx) >= abs(dy) ? .horizontal : .vertical
            let owner = state.nodes.first(where: { $0.scrollAxes.contains(axis) }) ?? state.nodes.first
            if let owner, let first = state.nodes.first, owner !== first { owner.beginTracking() }
            state.owner = owner
        }
        // The pan is active before it moves anything: the scroll views tell a finger's move from
        // a wheel's by it, and a first move read as a wheel's started the wheel's quiet period,
        // whose settle then pulled a paged view back to its page while the finger still dragged
        // it (new-website#216: the card followed for a sixth of a second, then slid back).
        pan = state
        var delta = CGSize(width: state.last.x - point.x, height: state.last.y - point.y)
        // A finger going back up over a sheet it pulled down raises the sheet first.
        if let sheet = state.sheet, sheet.dragsToDismiss, delta.height > 0, sheet.slide.position > 0 {
            let take = min(Double(delta.height), sheet.slide.position)
            sheet.dragSlide(to: sheet.slide.position - take, velocity: 0)
            delta.height -= CGFloat(take)
        }
        let remaining = scroll(by: delta, through: state.nodes)
        if remaining.height < 0, let sheet = state.sheet, sheet.dragsToDismiss {
            // What the scroll views leave of a downward drag (all of it on a sheet's plain
            // content, what is past the top of a scroll view) pulls the sheet down.
            sheet.dragSlide(to: sheet.slide.position - Double(remaining.height), velocity: 0)
            state.sheetDragged = true
        } else if remaining.height < 0, let owner = state.owner ?? state.nodes.first, owner.pull(by: -remaining.height) {
            // A finger past the top of a refreshable scroll view pulls it (iOS).
        }
        let dt = time - state.lastTime
        if dt > 0 {
            let sample = CGSize(width: delta.width / dt, height: delta.height / dt)
            state.velocity = CGSize(width: 0.6 * sample.width + 0.4 * state.velocity.width,
                                    height: 0.6 * sample.height + 0.4 * state.velocity.height)
        }
        state.last = point
        state.lastTime = time
        pan = state
    }

    /// Ends the pan; an active one hands its velocity to the scroll view that owns it (the
    /// innermost one along the finger's way, `PanState.owner`); the innermost one, which began
    /// tracking at the touch, ends without. Returns whether a pan consumed the touch (so no
    /// press should be delivered).
    @discardableResult
    package func endPan(time: Double) -> Bool {
        guard let state = pan else { return false }
        pan = nil
        guard state.active else {
            state.nodes.first?.endTracking(velocity: .zero)
            return false
        }
        let owner = state.owner ?? state.nodes.first
        owner?.endPull()
        // A finger that stopped before lifting leaves no momentum.
        let velocity = time - state.lastTime < PlatformMetrics.panRestInterval ? (state.recentVelocity ?? state.velocity) : .zero
        if state.sheetDragged, let sheet = state.sheet, sheet.dragsToDismiss {
            // The sheet takes the finger's speed down (content velocity runs against the finger).
            owner?.endTracking(velocity: .zero)
            if let first = state.nodes.first, let owner, first !== owner { first.endTracking(velocity: .zero) }
            sheet.endDragSlide(velocity: -Double(velocity.height))
            return true
        }
        owner?.endTracking(velocity: velocity)
        if let first = state.nodes.first, let owner, first !== owner { first.endTracking(velocity: .zero) }
        return true
    }
}

extension Runtime {
    /// Every scroll view's frame in the window and its content offset (`HostedScene`), the
    /// presentations' last.
    public var debugScrollViews: [[Double]] {
        // The window's, then those in its presentations (a sheet's, drawn where it slides).
        let nodes = root.descendants(where: { $0 is any _Scrollable }) + presentations.flatMap { $0.descendants(where: { $0 is any _Scrollable }) }
        return nodes.compactMap { node in
            guard let scroll = node as? (ViewNode & _Scrollable), node.isMounted else { return nil }
            let f = node.frameInRoot
            return [f.minX, f.minY, f.width, f.height, scroll.contentOffset.x, scroll.contentOffset.y].map { Double($0) }
        }
    }
}
