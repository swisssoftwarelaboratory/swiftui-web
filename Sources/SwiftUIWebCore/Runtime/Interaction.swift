// Hit testing and pointer handling live entirely in Swift (decision 0002): hosts forward raw
// pointer events in points; the runtime finds the deepest interactive node under the point.

/// A layout node that reacts to pointer input.
@MainActor
package protocol _Interactive: AnyObject {
    /// Whether the node takes presses at all (a text takes them only where it has links).
    var isInteractive: Bool { get }
    /// Called when a press starts inside the node.
    func pressBegan()
    /// Like `pressBegan()`, with the press point in the node's coordinate space (sliders jump to
    /// it). The default forwards to `pressBegan()`.
    func pressBegan(at point: CGPoint)
    /// The pointer moved while pressed, in the node's coordinate space. The default ignores it.
    func pressMoved(to point: CGPoint)
    /// Called when the press ends; `inside` tells whether the pointer is still over the node.
    func pressEnded(inside: Bool)
    /// Like `pressEnded(inside:)`, with the release point in the node's coordinate space (lists
    /// pick the row from it). The default forwards to `pressEnded(inside:)`.
    func pressEnded(inside: Bool, at point: CGPoint)
    /// A pan of the scroll views around the node took the press. The default ends the press
    /// outside.
    func pressCancelled(at point: CGPoint)
    /// Accessibility role and label for the semantics overlay.
    var semantics: SemanticsNode { get }
    /// Whether the element's descendants are exposed as their own elements (containers).
    var exposesChildren: Bool { get }
    /// The axes along which a press that starts moving stays with this node instead of becoming
    /// a pan of the scroll views around it (a slider keeps a sideways finger). Empty for most.
    var dragAxes: Axis.Set { get }
}

extension ViewNode {
    /// Whether this node takes presses (`_Interactive` and enabled for them).
    package var isInteractiveNode: Bool { (self as? any _Interactive)?.isInteractive ?? false }
}

extension _Interactive {
    package var isInteractive: Bool { true }
    package func pressBegan(at point: CGPoint) { pressBegan() }
    package func pressMoved(to point: CGPoint) {}
    package func pressEnded(inside: Bool, at point: CGPoint) { pressEnded(inside: inside) }
    package func pressCancelled(at point: CGPoint) { pressEnded(inside: false, at: point) }
    package var exposesChildren: Bool { false }
    package var dragAxes: Axis.Set { [] }
}

/// A node that is an accessibility element without being interactive (text, images).
@MainActor
package protocol _SemanticsProviding: AnyObject {
    var staticSemantics: SemanticsNode? { get }
}

/// A node whose value assistive technology can adjust or set (sliders, steppers).
@MainActor
package protocol _Adjustable: AnyObject {
    func adjust(increment: Bool)
    func setValue(_ value: Double)
}

extension ViewNode {
    /// The deepest node containing `point` (in this node's space) that satisfies `predicate`,
    /// searching later-painted children first.
    package func hitTest(_ point: CGPoint, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if capturesHit(at: point), predicate(self), contains(point) { return self }
        for child in paintOrderedChildren.reversed() {
            let shift = child.hitTestOffset
            var local = CGPoint(x: point.x - child.frame.minX - shift.x, y: point.y - child.frame.minY - shift.y)
            // A transformed child is hit where it paints: the point goes back through its transform.
            let transform = child.hitTestTransform
            if transform != .identity, transform.a * transform.d - transform.b * transform.c != 0 { local = local.applying(transform.inverted()) }
            if child.clipsHitTesting, !child.contains(local) { continue }
            if let hit = child.hitTest(local, where: predicate) { return hit }
        }
        return predicate(self) && contains(point) ? self : nil
    }

    /// All nodes in paint order that satisfy `predicate` (an accessibility representation's
    /// nodes count, though never painted: assistive technology reaches them).
    package func collectNodes(where predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var result: [ViewNode] = []
        if predicate(self) { result.append(self) }
        for child in paintedChildren { result += child.collectNodes(where: predicate) }
        if let replacing = self as? any _AccessibilityReplacing {
            for child in replacing.replacementRoots { result += child.collectNodes(where: predicate) }
        }
        return result
    }

    /// All nodes in structural order that satisfy `predicate`.
    package func descendants(where predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var result: [ViewNode] = []
        if predicate(self) { result.append(self) }
        for child in structuralChildren { result += child.descendants(where: predicate) }
        return result
    }
}

extension Runtime {
    /// The interactive node under `point` (window coordinates), if any.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        let presented = presentationHit(at: point)
        if presented.handled { return presented.node }
        if let toolbar, toolbar.frame.contains(point) { return toolbar.interactiveNode(at: point) }
        for node in root.layoutChildren.reversed() {
            let shift = node.hitTestOffset
            let local = CGPoint(x: point.x - node.frame.minX - shift.x, y: point.y - node.frame.minY - shift.y)
            if node.clipsHitTesting, !node.contains(local) { continue }
            if let hit = node.hitTest(local, where: { $0.isInteractiveNode }) { return hit as? (ViewNode & _Interactive) }
        }
        return nil
    }

    /// The modifier keys held as a pointer event arrives (`HostedScene`).
    public func pointerModifiersChanged(_ modifiers: EventModifiers) { pointerModifiers = modifiers }

    /// Pointer went down at `point` (points, window coordinates). A touch also starts tracking a
    /// pan of the scroll views under it; `time` is in seconds (any monotonic clock).
    public func pointerDown(at point: CGPoint, type: PointerType = .mouse, time: Double = 0) {
        lastPointerTime = time
        lastPointerType = type
        if type == .touch { beginPan(at: point, time: time) }
        // A touch that stopped a decelerating scroll view belongs to it, not to a control.
        if pan?.active == true { return }
        pendingDrag = dragSource(at: point).map { ($0, point) }
        // The secondary window a press lands in takes the keyboard (Tab cycles its controls);
        // a press beside every window gives it back to the main one (sw-windows).
        if hasPresentations { keyWindow = presentations.last { $0.kind.isWindow && $0.panel.contains(point) } }
        var node = interactiveNode(at: point)
        // A `focusable` view takes focus from the press at its end and nothing else; the press
        // goes to the interactive view around it (a gesture, a button) when there is one.
        focusPressNode = nil
        if let hit = node, hit is _FocusOnly {
            focusPressNode = hit
            if let around = interactiveAncestor(of: hit) { node = around }
        } else if let hit = node, hit is _PinchTarget {
            // A gesture inside a focusable view: the press is the view's as much as the
            // gesture's (a control inside it keeps the press to itself).
            focusPressNode = focusOnlyAncestor(of: hit)
        }
        // A press anywhere but on the selected text clears its selection.
        if let owner = textSelectionOwner, owner !== node { textSelectionOwner = nil }
        guard let node else { return }
        pressedNode = node
        node.pressBegan(at: local(point, in: node))
        // `simultaneousGesture` ancestors see the press the subview took.
        simultaneousPressNodes = simultaneousGestureNodes(above: node)
        for ancestor in simultaneousPressNodes { ancestor.pressBegan(at: local(point, in: ancestor)) }
    }

    /// The nearest interactive node above `node` that takes presses.
    private func interactiveAncestor(of node: ViewNode) -> (ViewNode & _Interactive)? {
        var current = node.parent
        while let candidate = current {
            if let interactive = candidate as? (ViewNode & _Interactive), interactive.isInteractive, !(candidate is _FocusOnly) { return interactive }
            current = candidate.parent
        }
        return nil
    }

    /// The `focusable` view above `node`, reached through gesture nodes only.
    private func focusOnlyAncestor(of node: ViewNode) -> (ViewNode & _Interactive)? {
        var current = node.parent
        while let candidate = current {
            if candidate is _FocusOnly { return candidate as? (ViewNode & _Interactive) }
            if candidate.isInteractiveNode, !(candidate is _PinchTarget) { return nil }
            current = candidate.parent
        }
        return nil
    }

    /// The `simultaneousGesture` nodes above `node` (outermost last) that take presses.
    private func simultaneousGestureNodes(above node: ViewNode) -> [ViewNode & _Interactive] {
        var result: [ViewNode & _Interactive] = []
        var current = node.parent
        while let candidate = current {
            if let target = candidate as? _PinchTarget, target.isSimultaneousGesture, let interactive = candidate as? (ViewNode & _Interactive), interactive.isInteractive {
                result.append(interactive)
            }
            current = candidate.parent
        }
        return result
    }

    /// Pointer moved (pressed or not): drives presses, pans and hovering.
    public func pointerMoved(to point: CGPoint, time: Double = 0) {
        lastPointerTime = time
        pointerPosition = point
        continuePan(to: point, time: time)
        if dragSession != nil {
            updateDrag(to: point)
            return
        }
        // A press on a drag source that travels 4 pt lifts the payload.
        if let pending = pendingDrag, abs(point.x - pending.start.x) + abs(point.y - pending.start.y) >= 4 {
            pendingDrag = nil
            beginDrag(from: pending.source, pressedAt: pending.start, at: point)
            return
        }
        if let node = pressedNode { node.pressMoved(to: local(point, in: node)) }
        for node in simultaneousPressNodes { node.pressMoved(to: local(point, in: node)) }
        updateHover(at: point)
    }

    /// The pointer left the window: every hover ends.
    public func pointerLeft() {
        pointerPosition = CGPoint(x: -1, y: -1)
        updateHover(at: nil)
    }

    private func local(_ point: CGPoint, in node: ViewNode) -> CGPoint {
        let origin = node.frameInRoot.origin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// Pointer released at `point`. Activates the pressed node if the pointer is still over it
    /// and no pan took the touch.
    public func pointerUp(at point: CGPoint, time: Double = 0) {
        lastPointerTime = time
        pendingDrag = nil
        if dragSession != nil {
            endDrag(at: point)
            return
        }
        let panned = endPan(time: time)
        let simultaneous = simultaneousPressNodes
        simultaneousPressNodes = []
        let focusing = focusPressNode
        focusPressNode = nil
        guard let node = pressedNode else { return }
        pressedNode = nil
        if panned {
            node.pressCancelled(at: local(point, in: node))
            for ancestor in simultaneous { ancestor.pressCancelled(at: local(point, in: ancestor)) }
            return
        }
        let released = interactiveNode(at: point)
        // The focusable view the press began on takes focus when it ends on it.
        if let focusing, focusing !== node {
            let localPoint = local(point, in: focusing)
            focusing.pressEnded(inside: focusing.contains(localPoint), at: localPoint)
        }
        node.pressEnded(inside: released === node || (focusing != nil && released === focusing), at: local(point, in: node))
        for ancestor in simultaneous {
            let localPoint = local(point, in: ancestor)
            ancestor.pressEnded(inside: ancestor.contains(localPoint), at: localPoint)
        }
    }

    /// The pinch targets under a point: the deepest gesture node taking pinches and the
    /// `simultaneousGesture` nodes above it.
    private func pinchTargets(at point: CGPoint) -> [ViewNode & _PinchTarget] {
        let accepts: (ViewNode) -> Bool = { ($0 as? _PinchTarget)?.acceptsPinch == true }
        var roots: [ViewNode] = root.layoutChildren
        for presentation in presentations { roots += presentation.semanticsRoots }
        var deepest: ViewNode?
        for node in roots.reversed() {
            let shift = node.hitTestOffset
            let local = CGPoint(x: point.x - node.frame.minX - shift.x, y: point.y - node.frame.minY - shift.y)
            if node.clipsHitTesting, !node.contains(local) { continue }
            if let hit = node.hitTest(local, where: accepts) { deepest = hit; break }
        }
        guard let deepest, let target = deepest as? (ViewNode & _PinchTarget) else { return [] }
        var result: [ViewNode & _PinchTarget] = [target]
        var current = deepest.parent
        while let candidate = current {
            if let ancestor = candidate as? (ViewNode & _PinchTarget), ancestor.acceptsPinch, ancestor.isSimultaneousGesture { result.append(ancestor) }
            current = candidate.parent
        }
        return result
    }

    /// A pinch from the host (`HostedScene.pinch`): `scale` and `rotation` (radians) are
    /// cumulative since `began`; `point` is the pinch's centre in window coordinates. The
    /// targets are fixed when the pinch begins.
    public func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: Double, at point: CGPoint, time: Double) {
        lastPointerTime = time
        if phase == .began {
            pinchNodes = pinchTargets(at: point)
        }
        for node in pinchNodes {
            let event = PinchEvent(location: local(point, in: node), scale: scale, rotation: rotation, time: time, bounds: node.frame.size)
            switch phase {
            case .began: node.pinchBegan(event)
            case .changed: node.pinchChanged(event)
            case .ended: node.pinchEnded(event, cancelled: false)
            case .cancelled: node.pinchEnded(event, cancelled: true)
            }
        }
        if phase == .ended || phase == .cancelled { pinchNodes = [] }
    }

    /// A click delivered by the accessibility overlay, by semantics identifier.
    public func activate(semanticsIdentifier: Int) {
        // An element's default accessibility action comes before the control's own activation.
        if performAccessibilityAction(semanticsIdentifier: semanticsIdentifier, kind: .default) { return }
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) else {
            platformTree(handling: semanticsIdentifier)?.activate(semanticsIdentifier: semanticsIdentifier)
            return
        }
        node.pressBegan()
        node.pressEnded(inside: true)
    }

    package var interactiveNodes: [ViewNode & _Interactive] {
        (toolbar?.interactiveNodes ?? [])
            + root.layoutChildren.flatMap { $0.collectNodes(where: { $0.isInteractiveNode }) }.compactMap { $0 as? (ViewNode & _Interactive) }
            + presentations.flatMap(\.interactiveNodes)
    }

    /// The accessibility tree after the last layout, in window coordinates: interactive nodes,
    /// static text and images, in paint order, with accessibility modifiers applied
    /// (Runtime/AccessibilityNodes.swift). After a frame that only moved scrolled content the
    /// tree is the last full walk with its frames refreshed: nothing else can have changed
    /// without a state update, which forces a full layout (`semanticsCacheIsValid`).
    public func semanticsTree() -> [SemanticsNode] {
        if semanticsCacheIsValid {
            return semanticsCache.map { entry in
                var element = entry.element
                var frame = entry.node.frameInRoot
                if let relative = entry.relativeFrame { frame = relative.offsetBy(dx: frame.minX, dy: frame.minY) }
                if var input = element.textInput {
                    input.textRect = input.textRect.offsetBy(dx: frame.minX - element.frame.minX, dy: frame.minY - element.frame.minY)
                    element.textInput = input
                }
                element.frame = frame
                return element
            }
        }
        var entries: [SemanticsEntry] = []
        for node in toolbar?.layoutChildren ?? [] { collectSemantics(node, attributes: nil, into: &entries) }
        for node in root.layoutChildren { collectSemantics(node, attributes: nil, into: &entries) }
        for presentation in presentations {
            for node in presentation.semanticsRoots { collectSemantics(node, attributes: nil, into: &entries) }
        }
        resolveRotors(in: &entries)
        semanticsCache = entries
        semanticsCacheLayout = fullLayoutCount
        return entries.map(\.element)
    }

    /// Increments or decrements an adjustable element (arrow keys on a stepper or slider).
    public func adjust(semanticsIdentifier: Int, increment: Bool) {
        if performAdjustableAction(semanticsIdentifier: semanticsIdentifier, increment: increment) { return }
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _Adjustable else {
            platformTree(handling: semanticsIdentifier)?.adjust(semanticsIdentifier: semanticsIdentifier, increment: increment)
            return
        }
        node.adjust(increment: increment)
    }

    /// Sets a slider's value from its range input.
    public func setValue(semanticsIdentifier: Int, value: Double) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _Adjustable else {
            platformTree(handling: semanticsIdentifier)?.setValue(semanticsIdentifier: semanticsIdentifier, value: value)
            return
        }
        node.setValue(value)
    }
}

/// Transparent modifier node: the button's press state and activation.
@MainActor
package final class ButtonHostNode: LayoutNode<_ButtonHost>, _Interactive {
    package private(set) var child: TypedNode<AnyView>!
    private static var nextIdentifier = 0
    private let identifier: Int

    package init(_ context: _NodeContext<_ButtonHost>) {
        Self.nextIdentifier += 1
        identifier = Self.nextIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = AnyView._makeNode(_NodeContext(view: context.view.label, parent: self, environment: context.environment))
    }

    override package func update(view: _ButtonHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.label, environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        target?.sizeThatFits(proposal) ?? .zero
    }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero)
    }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }
    /// A button spaces like a plain view (8 to controls, the text's distance next to text:
    /// form/basic `button` sits 8.15 under a stepper and 4.74 over a text).
    /// macOS: a control's plain spacing. iOS: the label's above (a borderless button sits 8.43
    /// under a toggle, its text's distance from a control) and the plain 8 below (8 to the
    /// bordered button under it; ios/layout/controls); a bordered one declares plain spacing
    /// itself (`_PlainSpacingModifier`).
    override package var layoutSpacing: ViewSpacing {
        guard PlatformMetrics.controlsUsePlainSpacing, var spacing = target?.layoutSpacing else { return ViewSpacing() }
        for category in [ViewSpacing.Category.textToText, .textBaseline, .edgeBelowText, .edgeAboveText] { spacing[category, .bottom] = nil }
        spacing[nil, .bottom] = ViewSpacing.defaultDistance
        spacing[.edgeAboveText, .bottom] = 0
        return spacing
    }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Button" }

    /// Its sizes are its label's (the action and press binding change none).
    override package func newValueChangesSizes(from old: _ButtonHost, to new: _ButtonHost) -> Bool { false }

    package func pressBegan() { if environment.isEnabled { view.isPressed.wrappedValue = true } }
    package func pressEnded(inside: Bool) {
        view.isPressed.wrappedValue = false
        if inside, environment.isEnabled {
            view.action.run()
            if environment._dismissesOnActivation {
                if environment._inMenu {
                    if environment._menuActionDismissBehavior.dismisses { runtime.dismissMenus() }
                } else {
                    environment.dismiss()
                }
            }
        }
    }

    package var semantics: SemanticsNode {
        // The texts inside, else the images' labels: a system symbol reads as its description
        // ("plus" → "Add", as SwiftUI labels an image-only button); an `accessibilityLabel`
        // inside stands for what it wraps.
        func labels(under node: ViewNode) -> [String] {
            if let attributed = node as? any _AccessibilityAttributing {
                // Hidden says nothing (a label's icon beside its title); an outer modifier's
                // answer wins, as in the elements, so an icon-only style's un-hiding counts.
                if attributed.attributes.hidden == true { return [] }
                if let label = attributed.attributes.label { return [label] }
                if attributed.attributes.hidden == false { return labelsIgnoringHidden(under: node) }
            }
            if let text = node as? TextNode { return [text.view.resolvedString] }
            if let image = node as? ImageNode {
                guard !image.view.isDecorative, let label = image.view.label else { return [] }
                if case .system(let name) = image.view.source, label == name { return [_SymbolDescriptions.description(of: name)] }
                return [label]
            }
            return node.structuralChildren.flatMap { labels(under: $0) }
        }
        func labelsIgnoringHidden(under node: ViewNode) -> [String] {
            if let attributed = node as? any _AccessibilityAttributing, let label = attributed.attributes.label { return [label] }
            if let text = node as? TextNode { return [text.view.resolvedString] }
            if let image = node as? ImageNode {
                guard !image.view.isDecorative, let label = image.view.label else { return [] }
                if case .system(let name) = image.view.source, label == name { return [_SymbolDescriptions.description(of: name)] }
                return [label]
            }
            return node.structuralChildren.flatMap { labelsIgnoringHidden(under: $0) }
        }
        let label = labels(under: child).joined(separator: " ")
        return SemanticsNode(role: .button, label: label, frame: frameInRoot, identifier: identifier)
    }
}

@MainActor
private var nextTapIdentifier = 1_000_000

/// A fresh semantics identifier for a gesture node (tap and other gestures share the range).
@MainActor package func _nextGestureIdentifier() -> Int {
    nextTapIdentifier += 1
    return nextTapIdentifier
}

@MainActor
package final class TapGestureNode<Content: View>: UnaryLayoutModifierNode<Content, _TapGestureModifier>, _Interactive {
    private let identifier: Int
    /// Counts taps for `count` > 1 (Runtime/GestureNodes.swift).
    private lazy var recognizer: TapRecognizer = {
        let recognizer = TapRecognizer(count: modifier.count)
        recognizer.endedHandlers.append { [weak self] in self?.modifier.action.run() }
        return recognizer
    }()

    override package init(_ context: _NodeContext<ModifiedContent<Content, _TapGestureModifier>>) {
        nextTapIdentifier += 1
        identifier = nextTapIdentifier
        super.init(context)
    }

    private func event(_ point: CGPoint) -> GestureEvent {
        GestureEvent(location: point, time: runtime.lastPointerTime, clock: runtime.animationClock, windowOrigin: frameInRoot.origin)
    }

    /// A content shape beneath the gesture decides where it is hit (sw-shape-shortcuts).
    override package func contains(_ point: CGPoint) -> Bool { _contentShapeContains(point) ?? super.contains(point) }

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) { if modifier.count > 1 { recognizer.began(event(point)) } }
    package func pressEnded(inside: Bool) {}
    package func pressEnded(inside: Bool, at point: CGPoint) {
        if modifier.count > 1 { recognizer.ended(event(point), inside: inside) } else if inside { modifier.action.run() }
    }
    package var semantics: SemanticsNode { SemanticsNode(role: .button, label: "", frame: frameInRoot, identifier: identifier) }
}

/// `_PlainSpacingModifier`: transparent for layout, plain spacing outward.
@MainActor
package final class PlainSpacingNode<Content: View>: UnaryLayoutModifierNode<Content, _PlainSpacingModifier> {
    override package func spacing(of target: ViewNode) -> ViewSpacing { ViewSpacing() }
}
