import Observation

// The runtime's node tree mirrors the view *type* tree (Docs/ARCHITECTURE.md, invariant 1):
// every view value in a body is represented by one node whose class is chosen statically
// through `View._makeNode`. There is no AttributeGraph and no general diffing; identity is
// structural, and only `ForEach` reconciles by key.

/// A node in the runtime tree. Members are `package`; the class is public only because the
/// hidden `View._makeNode` hook must name it.
@MainActor
open class ViewNode {
    /// The runtime this node belongs to.
    package unowned let runtime: Runtime
    /// Animation state while a tween or transition runs (Runtime/AnimationNodes.swift).
    package var presentation: NodePresentation?
    /// Structural children removed under an animation that still paint their removal transition.
    package var exitingChildren: [ViewNode] = []
    package var hasBeenPlaced = false
    /// Set while the node lingers as a ghost through its removal transition.
    package var isExiting = false

    /// The structural parent, `nil` for the root.
    package private(set) weak var parent: ViewNode?

    /// Distance from the root. The scheduler updates dirty nodes top-down by depth.
    package let depth: Int

    /// The environment in which this node's view lives.
    package var environment: EnvironmentValues {
        didSet { if oldValue.generation != environment.generation { invalidateSizeMemosUpward() } }   // see `clearNeedsUpdate`
    }

    /// Set by `invalidate()`; cleared once the node has been updated.
    package private(set) var needsUpdate = false

    /// False once `unmount()` has run.
    package private(set) var isMounted = true

    /// Identifies the most recent body evaluation, so an `onChange` from a stale observation
    /// session (one armed by an earlier evaluation) does not invalidate the node again.
    package private(set) var observationToken = ObservationToken()

    // MARK: Layout state (meaningful for layout nodes only)

    /// The node's frame in the coordinate space of `layoutParent`'s bounds.
    package var frame: CGRect = .zero

    /// The layout node that placed this node (a container, a modifier, or the root).
    package private(set) weak var layoutParent: ViewNode?

    /// Orientation of the stack that contains this node directly, set by the container before
    /// measuring; `Spacer` and `Divider` read it. Modifier nodes forward it to their content.
    package var stackOrientation: Axis? {
        didSet { if stackOrientation != oldValue { stackOrientationDidChange() } }
    }

    /// Hook for nodes that wrap other layout nodes.
    package func stackOrientationDidChange() {}

    private var sizeCache: [ProposedViewSize: CGSize] = [:]
    private var sizeCacheGeneration: UInt64 = 0
    /// A layout's intermediate result for a proposal (a stack's plan), memoised with the sizes:
    /// a stack plans for its size, again to place, and once more for each alignment guide its
    /// container asks for, and every plan asks the children for theirs.
    private var planCache: [AnyHashable: Any] = [:]

    package init(parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.runtime = runtime
        self.parent = parent
        self.depth = (parent?.depth ?? -1) + 1
        self.environment = environment
    }

    // MARK: Invalidation

    /// Marks the node dirty and asks the scheduler for a flush; the transaction's animation, if
    /// any, is kept for the flush and layout that apply the change.
    package func invalidate() {
        guard isMounted else { return }
        if let transaction = Transaction._current {
            if !transaction.disablesAnimations, let animation = transaction.animation {
                runtime.pendingAnimation = animation
                if animation.repeatCount == 0 { runtime.pendingRepeatingScopes.append(WeakNode(node: self)) }
            }
            for entry in transaction._completions where !entry.claimed {
                entry.claimed = true
                runtime.pendingAnimationCompletions.append(entry)
            }
        }
        guard !needsUpdate else { return }
        needsUpdate = true
        runtime.scheduler.schedule(self)
    }

    /// Re-runs this node's update from its stored view. Called by the scheduler.
    package func updateIfNeeded() {
        guard needsUpdate, isMounted else { return }
        performUpdate()
    }

    /// Subclasses re-evaluate from their stored state. Must call `clearNeedsUpdate()`.
    package func performUpdate() {
        needsForcedInvalidation = true
        clearNeedsUpdate()
    }

    package func clearNeedsUpdate() {
        needsUpdate = false
        // Every update is applied through here; a node whose view or environment changed has
        // forgotten its memoised sizes and its ancestors' as they were assigned (theirs are
        // computed from it), and the rest of the page keeps its memos across the update, where
        // a generation bump would measure everything again (a row appearing in Ember's thread
        // laid the whole thread out again, 100 ms a time). A node re-evaluated by force keeps
        // nothing: its subtree may have been rebuilt from state its value does not show.
        if needsForcedInvalidation { needsForcedInvalidation = false; invalidateSizeMemosUpward() }
    }

    /// Set by `performUpdate` (a node invalidated by observation or `invalidate()`): the next
    /// `clearNeedsUpdate` forgets the memos whatever the value comparison says.
    package var needsForcedInvalidation = false

    /// Starts a new observation session for this node; earlier sessions become stale.
    package func beginObservationSession() {
        observationToken = ObservationToken()
    }

    // MARK: Tree

    /// Children in structural order (for debugging and tree-shape tests).
    package var structuralChildren: [ViewNode] { [] }

    /// The nodes this subtree contributes to the enclosing layout container (invariant 2).
    /// Lists (`TupleView`, `Group`, `Optional`, `_ConditionalContent`, environment modifiers)
    /// contribute their children; layout-participating nodes contribute themselves.
    package var layoutChildren: [ViewNode] { [self] }

    /// Where this node's painted content sits relative to its frame (an `offset` effect moves
    /// hit testing with it).
    package var hitTestOffset: CGPoint { .zero }

    /// The transform this node paints its content through, in its own coordinates (rotation,
    /// scale, affine and 3D effects); hit testing maps points through its inverse.
    package var hitTestTransform: CGAffineTransform { .identity }

    /// Whether points outside this node's bounds cannot hit its descendants (scroll views clip;
    /// other containers let offset or transformed children be hit where they paint).
    package var clipsHitTesting: Bool { false }

    /// Short description of the node for tree dumps.
    package var nodeDescription: String {
        String(describing: type(of: self))
    }

    /// Tears the subtree down. Subclasses unmount children first, then call super.
    package func unmount() {
        for child in structuralChildren { child.unmount() }
        isMounted = false
        needsUpdate = false
    }

    // MARK: Layout

    /// Whether this node occupies a slot in its container's layout (as opposed to contributing
    /// its children).
    package var isLayoutNode: Bool { false }

    /// The layout priority a containing stack uses to apportion space.
    package var layoutPriority: Double { 0 }

    /// The `zIndex` trait: a containing node paints its children in ascending order of this
    /// value (declaration order among equals) and hit tests them in the reverse.
    package var zIndex: Double { 0 }

    /// The preferred spacing to neighbours.
    package var layoutSpacing: ViewSpacing { ViewSpacing() }

    /// The value stored for a `LayoutValueKey`, or its default.
    package func layoutValue<K: LayoutValueKey>(for key: K.Type) -> K.Value { K.defaultValue }

    /// The size this node wants for `proposal`, memoised for the duration of one layout pass.
    package final func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        refreshSizeMemo()
        runtime.measureCount += 1
        if let cached = sizeCache[proposal] { return cached }
        runtime.computeCount += 1
        if runtime.profileLayout {
            let name = nodeDescription
            runtime.computeHistogram[name, default: 0] += 1
            runtime.proposalCounts[ObjectIdentifier(self), default: (name, 0)].1 += 1
            runtime.profiledNodes[ObjectIdentifier(self)] = self
            runtime.proposalLog[ObjectIdentifier(self), default: []].append("\(proposal.width.map { "\($0)" } ?? "nil")x\(proposal.height.map { "\($0)" } ?? "nil")")
        }
        // The platform metrics of this node's profile, for it and its subtree (restored for the
        // caller: a macOS stack may hold an iOS subtree).
        let previousMetrics = PlatformMetrics.select(environment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        let size = computeSizeThatFits(proposal)
        sizeCache[proposal] = size
        return size
    }

    /// Forgets this node's memoised sizes and its ancestors' (theirs are computed from it):
    /// a subtree that changed inside one layout pass, such as a lazy element created where a
    /// placeholder stood. Every other node keeps its memo, where a generation bump
    /// (`Runtime.invalidateSizeMemos`) would re-measure the whole tree.
    package final func invalidateSizeMemosUpward() {
        var node: ViewNode? = self
        while let current = node {
            current.invalidateSizeMemo()
            node = current.parent
        }
    }

    /// Forgets this node's memoised sizes alone.
    package final func invalidateSizeMemo() {
        sizeCache.removeAll(keepingCapacity: true)
        planCache.removeAll(keepingCapacity: true)
    }

    /// The memos go when the runtime's layout generation moved on.
    private func refreshSizeMemo() {
        let generation = runtime.layoutGeneration
        if sizeCacheGeneration != generation {
            invalidateSizeMemo()
            sizeCacheGeneration = generation
        }
    }

    /// `make()`'s result for `key`, memoised like the sizes (see `planCache`).
    package final func memoisedPlan<Key: Hashable, Plan>(for key: Key, _ make: () -> Plan) -> Plan {
        refreshSizeMemo()
        if let cached = planCache[key] as? Plan { return cached }
        let plan = make()
        planCache[key] = plan
        return plan
    }

    /// Layout nodes override this.
    package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        fatalError("\(nodeDescription) is not a layout node")
    }

    /// Size plus alignment guides for `proposal`. Default: no explicit guides.
    package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        ViewDimensions(size: sizeThatFits(proposal))
    }

    /// Positions this node: computes its size for `proposal`, records the frame relative to
    /// `placer`, then lays out its own contents.
    package final func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize, by placer: ViewNode) {
        let previousMetrics = PlatformMetrics.select(environment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        let size = sizeThatFits(proposal)
        let previous = hasBeenPlaced ? presentedFrame : nil
        let oldTarget = frame
        layoutParent = placer
        var origin = CGPoint(x: position.x - size.width * anchor.x, y: position.y - size.height * anchor.y)
        // A right-to-left container mirrors every placement inside its bounds (sw-rtl): the
        // layout math stays left-to-right and the flip happens here, once per level, so leading
        // alignment, leading padding, stacks, grids, custom layouts, offsets and positions all
        // come out mirrored, and a left-to-right island inside stays as written.
        if placer.mirrorsPlacements { origin.x = placer.frame.width - origin.x - size.width }
        frame = CGRect(origin: origin, size: size)
        if let previous, frame != oldTarget {
            if let animation = runtime.effectiveLayoutAnimation(for: self) {
                beginFrameTween(from: previous, animation: animation)
            } else {
                presentation?.frame = nil
            }
        }
        hasBeenPlaced = true
        placer.assignSafeArea(to: self)
        layoutContents(proposal: proposal)
    }

    /// Lays out children inside `CGRect(origin: .zero, size: frame.size)`. Layout nodes with
    /// children override this.
    package func layoutContents(proposal: ProposedViewSize) {}

    /// Whether this node's placements are mirrored (`layoutDirection == .rightToLeft`). Nodes
    /// that place in window coordinates computed from measured frames (the root, presenters)
    /// say no.
    package var mirrorsPlacements: Bool { environment.layoutDirection == .rightToLeft }


    /// This node's frame in the root's coordinate space, following the chain of placers.
    package var frameInRoot: CGRect {
        var origin = frame.origin
        var ancestor = layoutParent
        while let node = ancestor, node.parent != nil || node.layoutParent != nil {
            origin.x += node.frame.origin.x
            origin.y += node.frame.origin.y
            ancestor = node.layoutParent
        }
        return CGRect(origin: origin, size: frame.size)
    }

    // MARK: Preferences

    /// The subtree's value for `key`, or `nil` if nothing in it writes the key.
    package func preferenceValue<K: PreferenceKey>(for key: K.Type) -> K.Value? {
        var result: K.Value?
        for child in structuralChildren {
            guard let value = child.preferenceValue(for: key) else { continue }
            if result == nil {
                result = value
            } else {
                K.reduce(value: &result!, nextValue: { value })
            }
        }
        return transformPreference(key, result)
    }

    /// Hook for nodes that write or transform a preference. Default: pass through.
    package func transformPreference<K: PreferenceKey>(_ key: K.Type, _ value: K.Value?) -> K.Value? {
        value
    }

    // MARK: Painting

    /// Emits this node's drawing (self first, then children). Only layout nodes are painted; a
    /// placer paints the nodes it placed at their frames.
    package func paint(into list: inout DisplayList, context: PaintContext) {
        let previousMetrics = PlatformMetrics.select(environment.platformProfile)
        defer { PlatformMetrics.current = previousMetrics }
        let opacity = presentedTransitionOpacity
        guard opacity > 0 else { return }
        if opacity < 1 { list.append(.beginGroup(opacity: opacity)) }
        let scale = presentedTransitionScale
        if scale != 1 {
            let size = presentedFrame.size
            let anchor = presentation?.transition?.effects.scaleAnchor ?? .center
            let centre = CGPoint(x: context.origin.x + size.width * anchor.x, y: context.origin.y + size.height * anchor.y)
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: -centre.x, y: -centre.y).concatenating(CGAffineTransform(scaleX: scale, y: scale))
                                    .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))))
        }
        if context.effects.isEmpty {
            paintSelf(into: &list, context: context)
        } else {
            context.withEffects(absoluteBounds(context), into: &list) { paintSelf(into: &$0, context: context) }
        }
        paintChildren(into: &list, context: context)
        paintExiting(into: &list, context: context)
        if scale != 1 { list.append(.restore) }
        if opacity < 1 { list.append(.endGroup) }
    }

    /// Ghosts of removed subtrees still animating out, at the frames they last had.
    package func paintExiting(into list: inout DisplayList, context: PaintContext) {
        for ghost in collectExiting() {
            ghost.paint(into: &list, context: context.child(at: ghost.presentedFrame))
        }
    }

    /// This node's own drawing, before its children.
    package func paintSelf(into list: inout DisplayList, context: PaintContext) {}

    /// The layout nodes this node placed, painted at their frames. Default: none.
    package var paintedChildren: [ViewNode] { [] }

    /// `paintedChildren` in painting order: stable-sorted by `zIndex`.
    package var paintOrderedChildren: [ViewNode] {
        let children = paintedChildren
        guard children.contains(where: { $0.zIndex != 0 }) else { return children }
        return children.enumerated().sorted { a, b in
            a.element.zIndex != b.element.zIndex ? a.element.zIndex < b.element.zIndex : a.offset < b.offset
        }.map(\.element)
    }

    /// A pinned header or footer: its placer skips it and the lazy container paints it last.
    package var paintsDeferred = false

    package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        for child in paintOrderedChildren where !child.paintsDeferred {
            let frame = child.presentedFrame
            if let visible = context.visibleRect, !child.paintsOutsideFrame, frame.width > 0, frame.height > 0,
               !frame.offsetBy(dx: context.origin.x, dy: context.origin.y).intersects(visible) {
                continue
            }
            child.paint(into: &list, context: context.child(at: frame))
        }
    }

    /// Whether this node's painting can reach beyond its frame (offsets, transforms): such
    /// nodes are never culled by a scroll view's viewport.
    package var paintsOutsideFrame: Bool { false }

    /// Whether this node takes hits before its children (`highPriorityGesture`).
    package var capturesHitTesting: Bool { false }

    /// Whether this node takes the hit at `point` (in its space) before its children: a split
    /// view's divider zones. The default is `capturesHitTesting` everywhere.
    package func capturesHit(at point: CGPoint) -> Bool { capturesHitTesting }

    /// Whether `point` (in this node's coordinate space) is inside the node: its bounds, or
    /// its content shape (`contentShape`).
    package func contains(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: frame.size).contains(point)
    }

    /// Whether this node is a `Spacer`: stacks size it after every other child, from the leftover
    /// (Layout/StackLayout.swift).
    package var isSpacer: Bool { false }

    // MARK: Safe area

    /// Whether this node keeps the full bounds under a safe-area modifier and insets its own
    /// content instead (scroll views). Wrapper nodes forward their child's.
    package var extendsIntoSafeArea: Bool { false }

    /// The safe area as placed, set by the placer in `place(at:...)` (Docs/elements/Position.md):
    /// `safeAreaOverlap` is how much of this node's frame lies in the unsafe region on each edge
    /// (a scroll view insets its content by it); `safeAreaExtension` is how far beyond an edge
    /// that touches the safe boundary the unsafe region reaches (`ignoresSafeArea` extends into
    /// it). `platformSafeAreaOverlap` is the overlap by geometry alone, which `ignoresSafeArea`
    /// does not clear: a hosted UIKit view takes it as its insets.
    package var safeAreaOverlap = EdgeInsets()
    package var safeAreaExtension = EdgeInsets()
    package var platformSafeAreaOverlap = EdgeInsets()

    /// The insets this node adds to the safe area of its children (`safeAreaInset`, a navigation
    /// bar, the host's own safe area); zero for other nodes.
    package func providedSafeAreaInsets(for child: ViewNode) -> EdgeInsets { EdgeInsets() }

    /// Sets `child`'s safe area from its frame in this node: per edge, a child edge inside the
    /// safe boundary gets nothing; one on the boundary may extend through the whole unsafe
    /// depth; one past it overlaps the unsafe region by the distance and may extend through the
    /// rest (ios/representable/safearea-rule: a colour padded 10 pt from the bar's edge stays
    /// put, one whose frame touches it extends under the bar, through a frame or padding on the
    /// other edges).
    package func assignSafeArea(to child: ViewNode) {
        assignSafeArea(to: child, in: CGRect(origin: .zero, size: frame.size), own: providedSafeAreaInsets(for: child))
    }

    /// The rule above against `bounds` (in this node's space) with `own` unsafe depths at its
    /// edges: the root places a presentation's content in the presentation's own area.
    package final func assignSafeArea(to child: ViewNode, in bounds: CGRect, own: EdgeInsets) {
        let frame = child.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        let size = bounds.size
        func edge(_ distance: CGFloat, boundary: CGFloat, depth: CGFloat) -> (overlap: CGFloat, reach: CGFloat) {
            if distance > boundary + 0.01 { return (0, 0) }
            if distance > boundary - 0.01 { return (0, depth) }
            let inside = boundary - distance
            return (min(depth, inside), max(0, depth - inside))
        }
        func assign(_ overlap: EdgeInsets, _ reach: EdgeInsets) -> (EdgeInsets, EdgeInsets) {
            let top = edge(frame.minY, boundary: overlap.top + own.top, depth: overlap.top + own.top + reach.top)
            let leading = edge(frame.minX, boundary: overlap.leading + own.leading, depth: overlap.leading + own.leading + reach.leading)
            let bottom = edge(size.height - frame.maxY, boundary: overlap.bottom + own.bottom, depth: overlap.bottom + own.bottom + reach.bottom)
            let trailing = edge(size.width - frame.maxX, boundary: overlap.trailing + own.trailing, depth: overlap.trailing + own.trailing + reach.trailing)
            return (EdgeInsets(top: top.overlap, leading: leading.overlap, bottom: bottom.overlap, trailing: trailing.overlap),
                    EdgeInsets(top: top.reach, leading: leading.reach, bottom: bottom.reach, trailing: trailing.reach))
        }
        (child.safeAreaOverlap, child.safeAreaExtension) = assign(safeAreaOverlap, safeAreaExtension)
        child.platformSafeAreaOverlap = assign(platformSafeAreaOverlap, safeAreaExtension).0
    }

    /// Whether this node reads its own geometry during layout (GeometryReader, probes): a scroll
    /// view holding one lays its content out on every scroll frame instead of moving it.
    package var readsGeometry: Bool { false }

    /// Moves a placed node without laying it out again (a scroll frame whose content is unchanged).
    package final func moveFrame(toOrigin origin: CGPoint) {
        frame.origin = origin
    }

    /// This node's own bounds (the presented size while animating), pixel aligned, in absolute
    /// coordinates.
    package func absoluteBounds(_ context: PaintContext) -> CGRect {
        context.absoluteRect(CGRect(origin: .zero, size: presentedFrame.size))
    }

    /// Indented dump of the subtree, one node per line, for tests and debugging.
    package func dump(indent: Int = 0) -> String {
        var lines = [String(repeating: "  ", count: indent) + nodeDescription]
        for child in structuralChildren {
            lines.append(child.dump(indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}

/// A node whose view type is known statically. `View._makeNode` returns one of these so parents
/// can push new view values to their children without casts.
@MainActor
open class TypedNode<V: View>: ViewNode {
    /// The most recent view value. A value that differs forgets the memoised sizes computed
    /// from the old one (this node's and its ancestors'; see `clearNeedsUpdate`); an equal one
    /// — a body re-evaluated for a change elsewhere hands every node its value again — keeps
    /// them, which is what makes an update cost its own subtree rather than the page. The
    /// comparison is `_valuesDiffer`'s cheap one: a value that is neither `Equatable` nor
    /// plain data (most hold a closure) counts as changed; the member-by-member one, tried,
    /// reflected over every node of a re-evaluated screen for longer than measuring it took.
    package var view: V {
        didSet { if _valuesDiffer(oldValue, view) { invalidateSizeMemosUpward() } }
    }

    package init(view: V, parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.view = view
        super.init(parent: parent, runtime: runtime, environment: environment)
    }

    /// Receives a new view value from the parent. `force` is set when the parent knows the
    /// subtree must be re-evaluated regardless of equality (for example after `invalidate()`).
    package func update(view: V, environment: EnvironmentValues, force: Bool = false) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
    }

    override package func performUpdate() {
        needsForcedInvalidation = true
        update(view: view, environment: environment, force: true)
    }

    override package var nodeDescription: String {
        _shortTypeName(type(of: self))
    }
}

/// The information `View._makeNode` receives to build a node.
public struct _NodeContext<V: View> {
    package let view: V
    package let parent: ViewNode
    package let environment: EnvironmentValues

    package init(view: V, parent: ViewNode, environment: EnvironmentValues) {
        self.view = view
        self.parent = parent
        self.environment = environment
    }

    package var runtime: Runtime { parent.runtime }
}

extension View {
    /// Hidden hook: builds the runtime node for a view value and performs its first update.
    /// Composite views get a `CompositeNode`; primitive views override this.
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        CompositeNode(context)
    }
}

extension Never {
    public static func _makeNode(_ context: _NodeContext<Never>) -> TypedNode<Never> {
        switch context.view {}
    }
}

/// Node for a view with a `body`: evaluates it and keeps one child for `V.Body`.
@MainActor
package final class CompositeNode<V: View>: TypedNode<V> {
    package private(set) var child: TypedNode<V.Body>?

    /// Number of body evaluations, for tests.
    package private(set) var bodyEvaluations = 0

    /// Storage for the view's dynamic properties (`@State` boxes and the like).
    package private(set) var propertyStorage: AnyObject?

    package init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        evaluateBody()
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view, view)
            || self.environment.generation != environment.generation
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<V>.installAll(into: &view, node: self, slot: &propertyStorage)
        let body = _trackingObservation(for: self) { view.body }
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = V.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
}

// MARK: - Observation

/// Evaluates `body` while recording every `@Observable` property it reads; the first later
/// mutation of any of them invalidates `node`. Tracking is re-armed by the next evaluation, so
/// a node only ever depends on what its most recent body actually read.
@MainActor
package func _trackingObservation<Result>(for node: ViewNode, _ body: () -> Result) -> Result {
    node.beginObservationSession()
    let token = node.observationToken
    // A body reads the platform metrics of its own profile (a page can hold an iOS subtree).
    let previousMetrics = PlatformMetrics.select(node.environment.platformProfile)
    defer { PlatformMetrics.current = previousMetrics }
    return withObservationTracking(body) { [weak node] in
        // Observation calls this from the property's `willSet`, on the mutating thread. State
        // mutation is main-actor only in SwiftUI and here, so hop synchronously. The node is held
        // weakly: a task finishing after its tree was torn down must not revive a dead node (whose
        // runtime is unowned).
        MainActor.assumeIsolated {
            guard let node, token.isCurrent(for: node) else { return }
            node.invalidate()
        }
    }
}

/// A fresh identity per observation session.
package final class ObservationToken: Sendable {
    package init() {}

    @MainActor
    package func isCurrent(for node: ViewNode) -> Bool {
        node.observationToken === self && node.isMounted
    }
}

// MARK: - Change detection

/// Whether two view values differ. Equatable types compare with `==`; plain-old-data types
/// compare bitwise; anything else (closures, existentials) is assumed to have changed.
/// Never specialized: in release builds on CI's macOS 15 runners, Swift 6.4.2 crashed folding
/// `T.self as? any Equatable.Type` in a specialization, in SILCombine for `Text` and in IRGen for
/// `Path` (decision 0026). The cast stays a runtime lookup, which the runtime caches per type.
@inline(never) @_semantics("optimize.sil.specialize.generic.never")
package func _valuesDiffer<T>(_ old: T, _ new: T) -> Bool {
    if let equatable = T.self as? any Equatable.Type {
        return !_openEquatable(equatable, old, new)
    }
    if _isPOD(T.self) {
        return withUnsafeBytes(of: old) { a in
            withUnsafeBytes(of: new) { b in
                !a.elementsEqual(b)
            }
        }
    }
    return true
}

private func _openEquatable<E: Equatable>(_: E.Type, _ a: Any, _ b: Any) -> Bool {
    (a as! E) == (b as! E)
}

/// Whether two values differ member by member, as SwiftUI compares a representable's value:
/// `Equatable` members by `==`, class references by identity, plain-data members by their
/// bytes, nested structs recursively; a member that is none of those (a closure) differs.
package func _valuesDifferMemberwise<T>(_ old: T, _ new: T) -> Bool {
    func differ(_ a: Any, _ b: Any) -> Bool {
        let type = Swift.type(of: a)
        guard type == Swift.type(of: b) else { return true }
        if let equatable = type as? any Equatable.Type { return !_openEquatable(equatable, a, b) }
        if type is AnyObject.Type { return (a as AnyObject) !== (b as AnyObject) }
        let mirrorA = Mirror(reflecting: a), mirrorB = Mirror(reflecting: b)
        guard mirrorA.displayStyle == .struct || mirrorA.displayStyle == .tuple || mirrorA.displayStyle == .optional || mirrorA.displayStyle == .enum else { return true }
        guard mirrorA.children.count == mirrorB.children.count else { return true }
        if mirrorA.children.isEmpty { return mirrorA.displayStyle == .enum ? String(describing: a) != String(describing: b) : false }
        for (childA, childB) in zip(mirrorA.children, mirrorB.children) where differ(childA.value, childB.value) { return true }
        return false
    }
    return differ(old, new)
}

/// Strips module and private-context qualifiers from a type description, inside generic
/// arguments too: `Module.(unknown context at $1).Outer.Inner<Module.Arg>` → `Inner<Arg>`.
package func _shortTypeName(_ type: Any.Type) -> String {
    let full = Array(String(describing: type))
    var out = ""
    var token = ""
    var index = 0
    func flushToken() {
        if let dot = token.lastIndex(of: ".") {
            out += token[token.index(after: dot)...]
        } else {
            out += token
        }
        token = ""
    }
    while index < full.count {
        let character = full[index]
        if character == "(" {
            // Drop `(unknown context at $…)` and `(extension in Module)` qualifiers entirely.
            if let close = full[index...].firstIndex(of: ")"),
               String(full[index...close]).hasPrefix("(unknown context") ||
               String(full[index...close]).hasPrefix("(extension in")
            {
                index = close + 1
                continue
            }
        }
        if character.isLetter || character.isNumber || character == "_" || character == "." || character == "$" {
            token.append(character)
        } else {
            flushToken()
            out.append(character)
        }
        index += 1
    }
    flushToken()
    return out
}

