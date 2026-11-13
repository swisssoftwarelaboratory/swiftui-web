// The nodes of `onGeometryChange` and `containerRelativeFrame` (API/GeometryChange.swift).

/// Node for `onGeometryChange`: after each layout pass it derives the value from its own frame
/// and queues the action when the value changed (the first pass runs it with the value as both
/// the old and the new one).
@MainActor
package final class GeometryChangeNode<Content: View, Value: Equatable>:
    UnaryLayoutModifierNode<Content, _GeometryChangeModifier<Value>>, _PreferenceObserver
{
    private var last: Value?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _GeometryChangeModifier<Value>>>) {
        super.init(context)
        runtime.preferenceObservers.append(WeakObserver(self))
    }

    package var observesGeometry: Bool { true }

    package func evaluatePreference() {
        guard hasBeenPlaced else { return }
        let modifier = self.modifier
        let value = modifier.transform(GeometryProxy(node: self, size: frame.size))
        guard let previous = last else {
            last = value
            runtime.scheduler.enqueue { modifier.action(value, value) }
            return
        }
        guard previous != value else { return }
        last = value
        runtime.scheduler.enqueue { modifier.action(previous, value) }
    }

    override package var nodeDescription: String { "OnGeometryChange" }
}

/// A view whose size `containerRelativeFrame` inside it is relative to (a scroll view).
@MainActor
package protocol _RelativeFrameContainer: AnyObject {
    /// The size the container's content is laid out against.
    var relativeFrameContainerSize: CGSize { get }
    /// Has `node` forget its sizes when the container's size changes.
    func addRelativeFrameDependent(_ node: ViewNode)
}

/// A view whose size follows lengths of its `_RelativeFrameContainer` along these axes only.
@MainActor
package protocol _RelativeFrameDependent: AnyObject {
    var relativeFrameAxes: Axis.Set { get }
}

/// Node for `containerRelativeFrame`: proposes the child, and takes along the modifier's axes,
/// the length computed from the nearest container's (a scroll view's visible size, else the
/// window's safe area), aligning the child within it.
@MainActor
package final class ContainerRelativeFrameNode<Content: View>: UnaryLayoutModifierNode<Content, _ContainerRelativeFrameModifier>, _RelativeFrameDependent {
    private weak var registeredContainer: AnyObject?
    package var relativeFrameAxes: Axis.Set { modifier.axes }
    override package var changesChildSize: Bool { true }

    /// The nearest container's size; the window's safe area below the toolbar when there is none.
    private var containerSize: CGSize {
        var node = parent
        while let current = node {
            if let container = current as? any _RelativeFrameContainer {
                if registeredContainer !== container {
                    container.addRelativeFrameDependent(self)
                    registeredContainer = container
                }
                return container.relativeFrameContainerSize
            }
            node = current.parent
        }
        let window = runtime.layoutSize, insets = runtime.safeAreaInsets
        let top = runtime.toolbar?.frame.height ?? 0
        return CGSize(width: max(0, window.width - insets.leading - insets.trailing),
                      height: max(0, window.height - top - insets.top - insets.bottom))
    }

    /// The proposal with the modifier's axes fixed at their container-relative lengths.
    private func relativeProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let container = containerSize
        var result = proposal
        if modifier.axes.contains(.horizontal) { result.width = max(0, modifier.length(container.width, .horizontal)) }
        if modifier.axes.contains(.vertical) { result.height = max(0, modifier.length(container.height, .vertical)) }
        return result
    }

    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        relativeProposal(proposal)
    }

    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        let fixed = relativeProposal(proposal)
        return CGSize(width: modifier.axes.contains(.horizontal) ? (fixed.width ?? childSize.width) : childSize.width,
                      height: modifier.axes.contains(.vertical) ? (fixed.height ?? childSize.height) : childSize.height)
    }

    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        _alignedOrigin(child, in: size, alignment: modifier.alignment)
    }

    override package var nodeDescription: String { "ContainerRelativeFrame" }
}
