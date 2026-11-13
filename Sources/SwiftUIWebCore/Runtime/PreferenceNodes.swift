// Preferences flow bottom-up: a node's value for a key is what it writes, else the reduction
// of its structural children's values. Observers are evaluated after every layout pass.

extension ViewNode {
    /// The nearest ancestor (including self) that names `space`, if any.
    package func ancestorCoordinateSpace(_ space: CoordinateSpace) -> ViewNode? {
        var node: ViewNode? = self
        while let current = node {
            if let named = current as? _NamedCoordinateSpace, named.coordinateSpace == space { return current }
            node = current.parent
        }
        return nil
    }

    /// This node's frame expressed in `space`.
    package func frame(in space: CoordinateSpace) -> CGRect {
        switch space {
        case .local:
            return CGRect(origin: .zero, size: frame.size)
        case .global:
            return frameInRoot
        case .named:
            guard let ancestor = ancestorCoordinateSpace(space) else { return frameInRoot }
            let mine = frameInRoot, origin = ancestor.frameInRoot.origin
            return CGRect(x: mine.minX - origin.x, y: mine.minY - origin.y, width: mine.width, height: mine.height)
        }
    }
}

@MainActor
package protocol _NamedCoordinateSpace: AnyObject {
    var coordinateSpace: CoordinateSpace { get }
}

@MainActor
package final class PreferenceWritingNode<Content: View, K: PreferenceKey>: UnaryLayoutModifierNode<Content, _PreferenceWritingModifier<K>> {
    override package func transformPreference<Key: PreferenceKey>(_ key: Key.Type, _ value: Key.Value?) -> Key.Value? {
        if Key.self == K.self { return modifier.value as? Key.Value }
        return value
    }
}

@MainActor
package final class PreferenceTransformNode<Content: View, K: PreferenceKey>: UnaryLayoutModifierNode<Content, _PreferenceTransformModifier<K>> {
    override package func transformPreference<Key: PreferenceKey>(_ key: Key.Type, _ value: Key.Value?) -> Key.Value? {
        guard Key.self == K.self else { return value }
        var current = (value as? K.Value) ?? K.defaultValue
        modifier.transform(&current)
        return current as? Key.Value
    }
}

/// Observes a subtree's preference value after each layout pass.
@MainActor
package protocol _PreferenceObserver: AnyObject {
    var isMounted: Bool { get }
    /// Whether the value comes from the node's geometry alone (`onGeometryChange`), so it is
    /// re-read when scrolled content moves without a layout pass.
    var observesGeometry: Bool { get }
    func evaluatePreference()
}

extension _PreferenceObserver {
    package var observesGeometry: Bool { false }
}

@MainActor
package final class PreferenceActionNode<Content: View, K: PreferenceKey>:
    UnaryLayoutModifierNode<Content, _PreferenceActionModifier<K>>, _PreferenceObserver where K.Value: Equatable
{
    private var lastValue: K.Value?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _PreferenceActionModifier<K>>>) {
        super.init(context)
        runtime.preferenceObservers.append(WeakObserver(self))
    }

    package func evaluatePreference() {
        let value = child.preferenceValue(for: K.self) ?? K.defaultValue
        guard value != lastValue else { return }
        lastValue = value
        modifier.action(value)
    }
}

package struct WeakObserver {
    package weak var node: (any _PreferenceObserver)?
    package init(_ node: any _PreferenceObserver) { self.node = node }
}

/// Transparent modifier node that names a coordinate space.
@MainActor
package final class CoordinateSpaceNode<Content: View, Name: Hashable>:
    UnaryLayoutModifierNode<Content, _CoordinateSpaceModifier<Name>>, _NamedCoordinateSpace
{
    package var coordinateSpace: CoordinateSpace {
        if let space = modifier.name as? CoordinateSpace { return space }
        return .named(AnyHashable(modifier.name))
    }
}

/// Fills its proposal and builds its content from the resulting size during layout.
///
/// As in SwiftUI, the content is built again only when something it can depend on changed:
/// the reader's size or safe area, its own value or environment (the parent's body ran again),
/// or state the content closure read. A pass that changes none of them places the content as
/// it is, with its memoised sizes: a reader around a whole screen (an app's tab) no longer makes
/// every keystroke or scroll step measure that screen again (new-website#216: 10,000 views a
/// frame in a real app). A reader whose content asked where it is (`frame(in: .global)`, an
/// anchor) can change with any pass, so it builds its content on every one, as before.
@MainActor
package final class GeometryReaderNode<Content: View>: LayoutNode<GeometryReader<Content>> {
    /// Only a reader whose content reads its position follows a scroll: one that reads its size
    /// alone lets the scroll view move its content without laying it out.
    override package var readsGeometry: Bool { readsPosition }
    /// A reader is laid out in the safe area like any view (its size is the safe part, as on
    /// iOS) and reports the unsafe depth beyond its edges as `proxy.safeAreaInsets`
    /// (`position/safe-area-geometry`); its content is placed past any overlap it has.
    package private(set) var child: TypedNode<Content>?

    /// Set for good once the content (or a view holding the proxy) asked where the reader is.
    package private(set) var readsPosition = false
    /// The size and safe area the content was last built for; nil until it is built, and again
    /// after an update (a new value, a new environment, an observed change in the closure).
    private var builtFor: (size: CGSize, safeArea: EdgeInsets)?
    /// Number of times the content closure ran, for tests.
    package private(set) var contentBuilds = 0

    package init(_ context: _NodeContext<GeometryReader<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
    }

    override package func proxyReadPosition() {
        guard !readsPosition else { return }
        readsPosition = true
        markPlacementStale()
    }

    override package func update(view: GeometryReader<Content>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        builtFor = nil
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .unspecifiedIdeal)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let safe = safeAreaOverlap
        if child == nil || readsPosition || builtFor?.size != frame.size || builtFor?.safeArea != safe {
            noteMemoReset(child == nil ? "reader built" : readsPosition ? "reader read its position" : builtFor == nil ? "reader updated"
                          : builtFor?.size != frame.size ? "reader resized \(builtFor!.size) to \(frame.size)" : "reader safe area \(builtFor!.safeArea) to \(safe)")
            builtFor = (frame.size, safe)
            contentBuilds += 1
            let proxy = GeometryProxy(node: self, size: frame.size)
            // The closure's own reads of observable state rebuild it (the views it makes track
            // their bodies themselves).
            let content = _trackingObservation(for: self) { view.content(proxy) }
            if let child {
                child.update(view: content, environment: environment, force: true)
            } else {
                child = Content._makeNode(_NodeContext(view: content, parent: self, environment: environment))
            }
        }
        let childProposal = ProposedViewSize(width: max(0, frame.width - safe.leading - safe.trailing), height: max(0, frame.height - safe.top - safe.bottom))
        for node in child!.layoutChildren {
            node.place(at: CGPoint(x: safe.leading, y: safe.top), anchor: .topLeading, proposal: childProposal, by: self)
        }
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var paintedChildren: [ViewNode] { child?.layoutChildren ?? [] }
    override package var nodeDescription: String { "GeometryReader" }
}

/// Node for `anchorPreference` and `transformAnchorPreference`: the anchor is taken from this
/// node's frame in the root's coordinates when the preference is read (after the content is
/// placed), so a reader converting it with `GeometryProxy` gets the view's current geometry.
@MainActor
package final class AnchorPreferenceNode<Content: View, A, K: PreferenceKey>: UnaryLayoutModifierNode<Content, _AnchorPreferenceModifier<A, K>> {
    override package func transformPreference<Key: PreferenceKey>(_ key: Key.Type, _ value: Key.Value?) -> Key.Value? {
        guard Key.self == K.self else { return value }
        let anchor = modifier.source.make(frameInRoot)
        switch modifier.write {
        case .set(let transform):
            return transform(anchor) as? Key.Value
        case .transform(let transform):
            var current = (value as? K.Value) ?? K.defaultValue
            transform(&current, anchor)
            return current as? Key.Value
        }
    }

    override package var nodeDescription: String { "AnchorPreference" }
}

/// Node for `overlayPreferenceValue` and `backgroundPreferenceValue`: once the content is
/// placed, the layer is rebuilt from the content's value of the key (anchors in it resolve
/// against the frames just laid out), proposed the content's size and aligned within it.
@MainActor
package final class PreferenceValueLayerNode<Content: View, K: PreferenceKey, Layer: View>:
    UnaryLayoutModifierNode<Content, _PreferenceValueLayerModifier<K, Layer>>
{
    package private(set) var layer: TypedNode<Layer>!

    override package init(_ context: _NodeContext<ModifiedContent<Content, _PreferenceValueLayerModifier<K, Layer>>>) {
        super.init(context)
        layer = Layer._makeNode(_NodeContext(view: modifier.transform(currentValue), parent: self, environment: context.environment))
    }

    /// The content's value of the key.
    private var currentValue: K.Value { child.preferenceValue(for: K.self) ?? K.defaultValue }

    override package func update(view: ModifiedContent<Content, _PreferenceValueLayerModifier<K, Layer>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        layer.update(view: modifier.transform(currentValue), environment: environment, force: force)
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        guard target === targets.first else { return }
        layer.update(view: modifier.transform(currentValue), environment: environment, force: false)
        let alignment = modifier.alignment
        let container = ViewDimensions(size: bounds.size)
        let layerProposal = ProposedViewSize(bounds.size)
        for node in layer.layoutChildren {
            let dims = node.dimensions(in: layerProposal)
            let origin = CGPoint(x: bounds.minX + container[alignment.horizontal] - dims[alignment.horizontal],
                                 y: bounds.minY + container[alignment.vertical] - dims[alignment.vertical])
            node.place(at: origin, anchor: .topLeading, proposal: layerProposal, by: placer)
        }
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let layerNodes = target === targets.first ? layer.layoutChildren : []
        if !modifier.isOverlay {
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
        }
        super.paintTarget(target, in: node, into: &list, context: context)
        if modifier.isOverlay {
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
        }
    }

    override package var structuralChildren: [ViewNode] {
        guard let layer else { return [child] }
        return [child, layer]
    }
    override package var nodeDescription: String { modifier.isOverlay ? "PreferenceOverlay" : "PreferenceBackground" }
}
