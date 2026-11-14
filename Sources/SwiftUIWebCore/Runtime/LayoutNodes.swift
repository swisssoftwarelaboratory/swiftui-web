// Layout-participating nodes. `LayoutNode` is the base; `LayoutContainerNode` drives a
// `Layout`; `UnaryLayoutModifierNode` wraps one child (and distributes over lists);
// leaves size themselves.

/// A node that occupies one slot in its container's layout.
@MainActor
open class LayoutNode<V: View>: TypedNode<V> {
    override package var isLayoutNode: Bool { true }
    override package var layoutChildren: [ViewNode] { [self] }
}

/// Node for a primitive view without children. Default sizing: the proposal, with unspecified
/// dimensions replaced by 10 (the behaviour of `Color` and shapes).
@MainActor
open class LeafNode<V: View>: LayoutNode<V> {
    public init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .unspecifiedIdeal)
    }
}

// MARK: - Layout containers

/// Node for a view whose geometry is defined by a `Layout` (stacks, custom layouts).
@MainActor
package final class LayoutContainerNode<V: View, L: Layout, Content: View>: LayoutNode<V> {
    private let layoutPath: KeyPath<V, L>
    private let contentPath: KeyPath<V, Content>
    package private(set) var child: TypedNode<Content>!
    private var cache: L.Cache?

    package init(_ context: _NodeContext<V>, layout: KeyPath<V, L>, content: KeyPath<V, Content>) {
        layoutPath = layout
        contentPath = content
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view[keyPath: content], parent: self,
                                               environment: context.environment))
    }

    /// The layout's own parameters (spacing, alignment); the subviews' changes reach the sizes
    /// through `child`.
    override package func newValueChangesSizes(from old: V, to new: V) -> Bool {
        _valuesDiffer(old[keyPath: layoutPath], new[keyPath: layoutPath])
    }

    /// The layout to size and place with: the view's, its animatable data interpolated while a
    /// tween of the layout's parameters runs (`Layout: Animatable`, sw-custom-layout).
    package var layout: L {
        var layout = view[keyPath: layoutPath]
        if let tweenFrom, let tweenTo, let progress = presentation?.effect?.value(at: runtime.animationClock).first {
            layout.animatableData = tweenFrom.interpolated(towards: tweenTo, amount: progress)
        }
        return layout
    }
    /// The animatable data a running tween goes from and to; the `effect` presentation slot
    /// carries the tween's progress (0 to 1), and the frame loop lays out again while it runs.
    private var tweenFrom: L.AnimatableData?
    private var tweenTo: L.AnimatableData?
    /// Whether the subviews changed since the cache was made (the cache is then updated, not remade).
    private var cachedSubviewCount: Int?

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let old = layout.animatableData
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        let new = view[keyPath: layoutPath].animatableData
        if (old - new).magnitudeSquared > 0 {
            tweenFrom = old
            tweenTo = new
            tweenEffect(from: [0], to: [1])
            if presentation?.effect == nil { tweenFrom = nil; tweenTo = nil }
        }
        // The cache lives on: `updateCache` runs on the next pass (SwiftUI remakes it only for a
        // new layout value type).
        cacheNeedsUpdate = true
        child.update(view: view[keyPath: contentPath], environment: environment, force: force)
    }
    private var cacheNeedsUpdate = false

    package var subviews: LayoutSubviews {
        let orientation = L.layoutProperties.stackOrientation
        let nodes = child.layoutChildren
        for node in nodes { node.stackOrientation = orientation }
        return LayoutSubviews(nodes.enumerated().map { LayoutSubview(node: $1, container: self, index: $0) })
    }

    private func withCache<R>(_ subviews: LayoutSubviews, _ body: (inout L.Cache) -> R) -> R {
        var current: L.Cache
        if var existing = cache {
            if cacheNeedsUpdate || cachedSubviewCount != subviews.count {
                layout.updateCache(&existing, subviews: subviews)
                cacheNeedsUpdate = false
            }
            current = existing
        } else {
            current = layout.makeCache(subviews: subviews)
            cacheNeedsUpdate = false
        }
        cachedSubviewCount = subviews.count
        let result = body(&current)
        cache = current
        return result
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let subviews = subviews
        return withCache(subviews) { layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &$0) }
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let bounds = CGRect(origin: .zero, size: size)
        return ViewDimensions(size: size) { [weak self] key in
            guard let self else { return nil }
            let subviews = self.subviews
            return self.withCache(subviews) { cache in
                switch key.axis {
                case .horizontal:
                    return self.layout.explicitAlignment(of: HorizontalAlignment(key.type), in: bounds, proposal: proposal,
                                                    subviews: subviews, cache: &cache)
                case .vertical:
                    return self.layout.explicitAlignment(of: VerticalAlignment(key.type), in: bounds, proposal: proposal,
                                                    subviews: subviews, cache: &cache)
                }
            }
        }
    }

    override package var layoutSpacing: ViewSpacing {
        let subviews = subviews
        return withCache(subviews) { layout.spacing(subviews: subviews, cache: &$0) }
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let subviews = subviews
        let bounds = CGRect(origin: .zero, size: frame.size)
        withCache(subviews) { layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &$0) }
    }

    override package var paintedChildren: [ViewNode] { child.layoutChildren }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Layout<\(_shortTypeName(L.self))>" }
}

extension LayoutContainerNode: _RelayoutWhileAnimating {}

/// Nodes whose geometry follows an `effect` tween: the frame loop lays the tree out again every
/// frame the tween runs (a `Layout`'s animatable parameters).
@MainActor package protocol _RelayoutWhileAnimating: AnyObject {}

// MARK: - Unary layout modifiers

/// Type-erased operations of a unary modifier on one target node, used by proxies.
@MainActor
package protocol _UnaryLayoutModifier: AnyObject {
    /// The node of the modified content (not the modifier's own layers, e.g. a background).
    var modifiedContent: ViewNode { get }
    /// The layout children of the modified content, one per proxy in `layoutChildren`.
    var targets: [ViewNode] { get }
    func measure(_ target: ViewNode, proposal: ProposedViewSize) -> CGSize
    func dimensions(of target: ViewNode, in proposal: ProposedViewSize) -> ViewDimensions
    func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode)
    func priority(of target: ViewNode) -> Double
    func spacing(of target: ViewNode) -> ViewSpacing
    func zIndex(of target: ViewNode) -> Double
    /// Whether the targets are hidden (`hidden`): not painted, hit tested or exposed.
    var hidesTargets: Bool { get }
    /// Whether the modifier changes its child's size (frames, padding).
    var changesChildSize: Bool { get }
    func layoutValue<K: LayoutValueKey>(of target: ViewNode, for key: K.Type) -> K.Value
    /// The nodes painted (and hit tested) for one target: the target itself unless hidden, plus
    /// any per-target views of the modifier (`safeAreaInset` on a list).
    func paintedChildren(of target: ViewNode) -> [ViewNode]
    func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext)
}

/// Base class for modifiers that wrap exactly one layout child (frame, padding, background…).
/// When the modified content is a list, SwiftUI applies the modifier to every element; this
/// node then contributes one proxy per element instead of itself.
@MainActor
open class UnaryLayoutModifierNode<Content: View, Modifier: ViewModifier>:
    LayoutNode<ModifiedContent<Content, Modifier>>, _UnaryLayoutModifier
{
    package private(set) var child: TypedNode<Content>!
    private var proxies: [ObjectIdentifier: LayoutModifierProxy] = [:]

    package init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self,
                                               environment: context.environment))
    }

    package var modifier: Modifier { view.modifier }

    /// The modifier's own parameters; the content's changes reach the sizes through `child`.
    override package func newValueChangesSizes(from old: ModifiedContent<Content, Modifier>, to new: ModifiedContent<Content, Modifier>) -> Bool {
        _valuesDiffer(old.modifier, new.modifier)
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
    }

    package var modifiedContent: ViewNode { child }
    package var targets: [ViewNode] { child.layoutChildren }

    override package func stackOrientationDidChange() {
        for target in targets { target.stackOrientation = stackOrientation }
    }

    override package func layoutValue<K: LayoutValueKey>(for key: K.Type) -> K.Value {
        targets.first?.layoutValue(for: key) ?? K.defaultValue
    }

    override package var layoutChildren: [ViewNode] {
        let targets = targets
        if targets.count == 1 { return [self] }
        return targets.map { target in
            let key = ObjectIdentifier(target)
            if let proxy = proxies[key] { return proxy }
            let proxy = LayoutModifierProxy(owner: self, target: target)
            proxies[key] = proxy
            return proxy
        }
    }

    // MARK: Hooks

    /// The proposal forwarded to the child.
    package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize { proposal }

    /// This node's size given the child's size.
    package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize { childSize }

    /// Where the child sits within this node's bounds.
    package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint { .zero }

    /// Additional explicit guides this modifier contributes (`alignmentGuide`).
    package func explicitGuides(_ child: ViewDimensions) -> [AlignmentKey: CGFloat] { [:] }

    package func priority(of target: ViewNode) -> Double { target.layoutPriority }
    package func spacing(of target: ViewNode) -> ViewSpacing { target.layoutSpacing }
    package func zIndex(of target: ViewNode) -> Double { target.zIndex }
    package var hidesTargets: Bool { false }
    package func layoutValue<K: LayoutValueKey>(of target: ViewNode, for key: K.Type) -> K.Value {
        target.layoutValue(for: key)
    }

    // MARK: Target-based implementation shared by the node and its proxies

    package func measure(_ target: ViewNode, proposal: ProposedViewSize) -> CGSize {
        size(forChild: target.sizeThatFits(childProposal(proposal)), proposal: proposal)
    }

    package func dimensions(of target: ViewNode, in proposal: ProposedViewSize) -> ViewDimensions {
        let childDims = target.dimensions(in: childProposal(proposal))
        let size = size(forChild: childDims.size, proposal: proposal)
        let origin = childOrigin(childDims, in: size)
        var dims = childDims.offset(by: origin, size: size)
        for (key, value) in explicitGuides(childDims) { dims.explicit[key] = value + origin[key.axis] }
        return dims
    }

    package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        let cp = childProposal(proposal)
        let childDims = target.dimensions(in: cp)
        let origin = childOrigin(childDims, in: bounds.size)
        target.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                     anchor: .topLeading, proposal: cp, by: placer)
    }

    // MARK: Single-target node behaviour

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        guard let target = targets.first else { return .zero }
        return measure(target, proposal: proposal)
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        guard let target = targets.first else { return ViewDimensions(size: .zero) }
        return dimensions(of: target, in: proposal)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        guard let target = targets.first else { return }
        placeTarget(target, in: CGRect(origin: .zero, size: frame.size), proposal: proposal, by: self)
    }

    override package var layoutPriority: Double { targets.first.map(priority(of:)) ?? 0 }
    override package var layoutSpacing: ViewSpacing { targets.first.map(spacing(of:)) ?? ViewSpacing() }
    override package var zIndex: Double { targets.first.map(zIndex(of:)) ?? 0 }

    /// Whether this modifier changes its child's size (frames, padding): such a modifier does
    /// not extend into the safe area with its child.
    package var changesChildSize: Bool { false }
    /// A probed or painted Spacer is still a Spacer to its stack.
    override package var isSpacer: Bool {
        let targets = targets
        return !changesChildSize && targets.count == 1 && targets[0].isSpacer
    }
    override package var extendsIntoSafeArea: Bool {
        let targets = targets
        return !changesChildSize && targets.count == 1 && targets[0].extendsIntoSafeArea
    }

    override package var paintedChildren: [ViewNode] {
        let targets = targets
        return targets.count == 1 ? paintedChildren(of: targets[0]) : []
    }

    package func paintedChildren(of target: ViewNode) -> [ViewNode] { hidesTargets ? [] : [target] }

    override package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        for target in paintedChildren { paintTarget(target, in: self, into: &list, context: context) }
    }

    /// Paints one target inside `node` (this node, or the proxy standing in for the target when
    /// the content is a list). Painting modifiers override this so they apply per element.
    package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        target.paint(into: &list, context: context.child(at: target.presentedFrame))
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "\(_shortTypeName(Modifier.self))" }
}

/// One element of a list modified by a unary modifier.
@MainActor
package final class LayoutModifierProxy: ViewNode {
    package unowned let owner: any _UnaryLayoutModifier
    package let target: ViewNode

    init(owner: ViewNode & _UnaryLayoutModifier, target: ViewNode) {
        self.owner = owner
        self.target = target
        super.init(parent: owner, runtime: owner.runtime, environment: owner.environment)
    }

    override package var isLayoutNode: Bool { true }
    override package func stackOrientationDidChange() { target.stackOrientation = stackOrientation }
    override package func layoutValue<K: LayoutValueKey>(for key: K.Type) -> K.Value {
        owner.layoutValue(of: target, for: key)
    }
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        owner.measure(target, proposal: proposal)
    }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        owner.dimensions(of: target, in: proposal)
    }
    override package func layoutContents(proposal: ProposedViewSize) {
        owner.placeTarget(target, in: CGRect(origin: .zero, size: frame.size), proposal: proposal, by: self)
    }
    override package var layoutPriority: Double { owner.priority(of: target) }
    override package var layoutSpacing: ViewSpacing { owner.spacing(of: target) }
    override package var zIndex: Double { owner.zIndex(of: target) }
    override package var extendsIntoSafeArea: Bool { !owner.changesChildSize && target.extendsIntoSafeArea }
    override package var paintedChildren: [ViewNode] { owner.paintedChildren(of: target) }
    override package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        for node in paintedChildren { owner.paintTarget(node, in: self, into: &list, context: context) }
    }
    override package var nodeDescription: String { "Proxy" }
}

// MARK: Concrete modifier nodes

@MainActor
package final class FrameNode<Content: View>: UnaryLayoutModifierNode<Content, _FrameLayout> {
    override package var changesChildSize: Bool { true }
    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: modifier.width ?? proposal.width, height: modifier.height ?? proposal.height)
    }
    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        CGSize(width: modifier.width ?? childSize.width, height: modifier.height ?? childSize.height)
    }
    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        _alignedOrigin(child, in: size, alignment: modifier.alignment)
    }
}

@MainActor
package final class FlexFrameNode<Content: View>: UnaryLayoutModifierNode<Content, _FlexFrameLayout> {
    override package var changesChildSize: Bool { true }
    private func clampedProposal(_ length: CGFloat?, min: CGFloat?, ideal: CGFloat?, max: CGFloat?) -> CGFloat? {
        (length ?? ideal)?.clamped(min, max)
    }

    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(
            width: clampedProposal(proposal.width, min: modifier.minWidth, ideal: modifier.idealWidth, max: modifier.maxWidth),
            height: clampedProposal(proposal.height, min: modifier.minHeight, ideal: modifier.idealHeight, max: modifier.maxHeight))
    }

    /// SwiftUI's rule, measured with `NSHostingController.sizeThatFits` on macOS 26: the child's
    /// length, at least the proposal where a maximum is given (up to it), at most the proposal
    /// where a minimum is given (down to it). A frame is never shorter than a child that can't
    /// shrink unless its maximum says so: `.frame(maxHeight: .infinity)` round a 212 pt chart
    /// offered 50 is 212 tall, not 50. (Taking the proposal outright made such a card answer 0
    /// to a stack's zero probe, so a stack placed at its ideal length shared that length out and
    /// squeezed the card under its sibling: Paulo's day-one Weight history.)
    private func resolve(proposal: CGFloat?, child: CGFloat, min: CGFloat?, ideal: CGFloat?, max: CGFloat?) -> CGFloat {
        guard let proposal else {
            return (ideal ?? child).clamped(min, max)
        }
        var length = child
        if let min { length = Swift.max(min, Swift.min(length, proposal)) }
        if let max { length = Swift.min(max, Swift.max(length, proposal)) }
        return length
    }

    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        CGSize(
            width: resolve(proposal: proposal.width, child: childSize.width, min: modifier.minWidth,
                           ideal: modifier.idealWidth, max: modifier.maxWidth),
            height: resolve(proposal: proposal.height, child: childSize.height, min: modifier.minHeight,
                            ideal: modifier.idealHeight, max: modifier.maxHeight))
    }

    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        _alignedOrigin(child, in: size, alignment: modifier.alignment)
    }
}

/// Origin of a child within `size` so that the child's guide meets the container's guide.
@MainActor
package func _alignedOrigin(_ child: ViewDimensions, in size: CGSize, alignment: Alignment) -> CGPoint {
    let container = ViewDimensions(size: size)
    return CGPoint(x: container[alignment.horizontal] - child[alignment.horizontal],
                   y: container[alignment.vertical] - child[alignment.vertical])
}

@MainActor
package final class PaddingNode<Content: View>: UnaryLayoutModifierNode<Content, _PaddingLayout> {
    override package var changesChildSize: Bool { true }
    package var insets: EdgeInsets {
        modifier.insets ?? EdgeInsets(modifier.edges, PlatformMetrics.defaultPadding)
    }
    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let insets = insets
        return ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.horizontal) },
                                height: proposal.height.map { max(0, $0 - insets.vertical) })
    }
    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        let insets = insets
        return CGSize(width: childSize.width + insets.horizontal, height: childSize.height + insets.vertical)
    }
    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        CGPoint(x: insets.leading, y: insets.top)
    }
}

@MainActor
package final class FixedSizeNode<Content: View>: UnaryLayoutModifierNode<Content, _FixedSizeLayout> {
    override package var changesChildSize: Bool { true }
    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: modifier.horizontal ? nil : proposal.width,
                         height: modifier.vertical ? nil : proposal.height)
    }
}

@MainActor
package final class LayoutPriorityNode<Content: View>: UnaryLayoutModifierNode<Content, _LayoutPriorityModifier> {
    override package func priority(of target: ViewNode) -> Double { modifier.priority }
}

@MainActor
package final class AlignmentGuideNode<Content: View>: UnaryLayoutModifierNode<Content, _AlignmentGuideModifier> {
    override package func explicitGuides(_ child: ViewDimensions) -> [AlignmentKey: CGFloat] {
        [modifier.key: modifier.computeValue(child)]
    }
}

@MainActor
package final class LayoutValueNode<Content: View, K: LayoutValueKey>: UnaryLayoutModifierNode<Content, _LayoutValueModifier<K>> {
    override package func layoutValue<Key: LayoutValueKey>(of target: ViewNode, for key: Key.Type) -> Key.Value {
        if Key.self == K.self, let value = modifier.value as? Key.Value { return value }
        return target.layoutValue(for: key)
    }
    override package func layoutValue<Key: LayoutValueKey>(for key: Key.Type) -> Key.Value {
        // The value is the modifier's whatever it wraps: a `NavigationLink` whose label is an
        // `EmptyView` (the hidden link under a custom list row) has no target and still activates.
        if Key.self == K.self, let value = modifier.value as? Key.Value { return value }
        guard let target = targets.first else { return Key.defaultValue }
        return layoutValue(of: target, for: key)
    }
}

// MARK: - Leaves

@MainActor
package final class ColorNode: LeafNode<Color> {
    override package func update(view: Color, environment: EnvironmentValues, force: Bool) {
        let old = presentedColor
        super.update(view: view, environment: environment, force: force)
        let new = view.resolve(in: environment)
        guard new != old else { return }
        if let animation = runtime.effectiveUpdateAnimation(for: self) {
            let presentation = self.presentation ?? NodePresentation()
            presentation.color = Tween(from: [old.red, old.green, old.blue, old.alpha], to: [new.red, new.green, new.blue, new.alpha],
                                       animation: animation, start: runtime.animationClock)
            self.presentation = presentation
            runtime.register(animating: self)
        } else {
            presentation?.color = nil
        }
    }

    /// The colour to paint: the tween's value while animating.
    package var presentedColor: RGBA {
        if let v = presentation?.color?.value(at: runtime.animationClock) { return RGBA(red: v[0], green: v[1], blue: v[2], alpha: v[3]) }
        return view.resolve(in: environment)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let color = presentedColor
        guard color.alpha > 0 else { return }
        list.append(.fillRect(absoluteBounds(context), color))
    }
}

@MainActor
package final class SpacerNode: LeafNode<Spacer> {
    package var minLength: CGFloat { view.minLength ?? PlatformMetrics.defaultSpacing }
    override package var isSpacer: Bool { true }

    /// A spacer declares no spacing categories, so its distance to any neighbour is 0
    /// (fixture layout/spacer).
    override package var layoutSpacing: ViewSpacing { ViewSpacing(minima: [:]) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let minLength = minLength
        func length(_ proposed: CGFloat?) -> CGFloat { proposed.map { max($0, minLength) } ?? minLength }
        switch stackOrientation {
        case .horizontal: return CGSize(width: length(proposal.width), height: 0)
        case .vertical: return CGSize(width: 0, height: length(proposal.height))
        case nil: return CGSize(width: length(proposal.width), height: length(proposal.height))
        }
    }
}

@MainActor
package final class DividerNode: LeafNode<Divider> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if environment._inMenu {
            // A menu separator: a full-width line with the menu's spacing above and below.
            return CGSize(width: proposal.width ?? 0, height: PlatformMetrics.menuSeparatorHeight)
        }
        let thickness = PlatformMetrics.dividerThickness
        switch stackOrientation {
        case .horizontal:
            return CGSize(width: thickness, height: proposal.height ?? CGSize.unspecifiedIdeal.height)
        default:
            return CGSize(width: proposal.width ?? CGSize.unspecifiedIdeal.width, height: thickness)
        }
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        guard environment._inMenu else { return }
        let bounds = absoluteBounds(context)
        let line = CGRect(x: bounds.minX + PlatformMetrics.menuSeparatorInset, y: context.round(bounds.midY - PlatformMetrics.dividerThickness / 2),
                          width: max(0, bounds.width - 2 * PlatformMetrics.menuSeparatorInset), height: PlatformMetrics.dividerThickness)
        list.append(.fillRect(line, environment._ink(PlatformMetrics.menuSeparatorAlpha)))
    }
}
