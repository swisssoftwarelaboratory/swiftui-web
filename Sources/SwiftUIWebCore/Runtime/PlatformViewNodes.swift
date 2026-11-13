// Hosting another framework's view tree as one leaf of the SwiftUI tree (decision 0014,
// Phase 2): `UIViewRepresentable` and `UIViewControllerRepresentable` in SwiftUIWebUIKit build a
// `_PlatformViewHostNode` over a `_PlatformViewTree`. The node owns the SwiftUI side (its slot
// in the layout, its frame, the memoised size, painting position, the press routed to it, its
// place in the semantics walk); the tree owns what is inside. Points cross the seam in the
// tree's own space, with the origin at the node's top left.

/// What a hosted tree provides to its node.
@MainActor
package protocol _PlatformViewTree: AnyObject {
    /// A view inside changed something the host must lay out again for (an intrinsic size, a
    /// frame, a colour). Set by the node.
    var onNeedsFrame: (@MainActor @Sendable () -> Void)? { get set }
    /// The text field inside with keyboard focus changed (nil: none). Set by the node.
    var onFocusedTextFieldChange: (@MainActor (Int?) -> Void)? { get set }

    /// Gives the tree the runtime's services before it measures or paints (the text engine that
    /// answers the host's strings, the app's asset catalog).
    func prepare(textEngine: any TextEngine, assetCatalog: AssetCatalog)
    /// The runtime's pasteboard, for the tree's own (`UIPasteboard.general` follows it).
    func connectPasteboard(_ bridge: _PasteboardBridge)
    /// The host's share sheet and file panels, for the tree's own system sheets
    /// (`UIActivityViewController`, `UIDocumentPickerViewController`, uk-system-sheets).
    func connectHostServices(_ services: _HostServices)
    /// The host's rasteriser for recorded drawings, if any. Set by the node.
    var imageRasterizer: ImageRasterizer? { get set }
    /// Lays the tree out in `size`, with `safeAreaInsets` as the part of it under the host's
    /// bars and insets, in the host's `environment` (the traits the tree resolves against).
    func layout(size: CGSize, safeAreaInsets: EdgeInsets, environment: EnvironmentValues)
    /// The first and last text baselines of the content laid out in `size`, from its top.
    func baselines(in size: CGSize) -> (first: CGFloat, last: CGFloat)
    /// Paints the tree; `context.origin` is the tree's origin in absolute coordinates.
    func paint(into list: inout DisplayList, context: PaintContext)
    /// The elements the host shows as its own (a web view's frame) among the views painted,
    /// with their frames in window space; `identify` gives a view its lasting identifier.
    func hostElements(in context: PaintContext, identify: (AnyObject) -> Int) -> [HostElement]
    /// Advances the tree's clocks by `elapsed` seconds; true means it needs another frame.
    /// `frame` identifies the host's frame: trees sharing one clock advance it once per frame.
    func advanceFrame(elapsed: Double, frame: _HostFrame) -> Bool

    func pointerDown(at point: CGPoint, type: PointerType, time: Double)
    func pointerMoved(to point: CGPoint, time: Double)
    func pointerUp(at point: CGPoint, time: Double)
    /// The host's own scrolling took the press.
    func pointerCancelled(at point: CGPoint, time: Double)
    /// The axes a press at `point` may drag along without becoming a pan of the host's scroll
    /// views (a scroll view inside the tree).
    func dragAxes(at point: CGPoint) -> Axis.Set
    /// A wheel scroll at `point`; returns what the tree's scroll views left of the delta (the
    /// whole delta when nothing inside scrolls), for the host's scroll views to take.
    func scrollWheel(by delta: CGSize, at point: CGPoint) -> CGSize
    /// The pointer hovers at `point` in the tree's space (no press), or left it (`nil`).
    func hover(at point: CGPoint?)
    /// The pointer style the hovered view inside asks for, if any.
    var pointerStyle: PointerStyle? { get }

    /// The tree's accessibility elements, frames in the tree's coordinates.
    func semantics() -> [SemanticsNode]
    func contains(semanticsIdentifier: Int) -> Bool
    func activate(semanticsIdentifier: Int)
    func adjust(semanticsIdentifier: Int, increment: Bool)
    func setValue(semanticsIdentifier: Int, value: Double)
    /// A custom action of an element inside, by name.
    func performAccessibilityAction(semanticsIdentifier: Int, name: String)
    /// The events the tree's scene posted for the assistive layer since the last frame.
    func takeAccessibilityEvents() -> [AccessibilityEvent]
    func focus(semanticsIdentifier: Int)
    func blur(semanticsIdentifier: Int)
    /// The text field inside with keyboard focus.
    var focusedTextFieldIdentifier: Int? { get }
    /// Keyboard focus moved out of the tree.
    func resignFocus()
    func textField(_ semanticsIdentifier: Int, didChange text: String)
    func textFieldDidSubmit(_ semanticsIdentifier: Int)
    func textField(_ semanticsIdentifier: Int, focused: Bool)

    /// The node was unmounted: the tree comes down.
    func dismantle()

    // MARK: Drags (uk-dragdrop): a tree with drag sessions of its own, in its coordinates

    /// Whether a press at `point` can start a drag inside the tree.
    func hasDragSource(at point: CGPoint) -> Bool
    /// Whether the tree has a drag in flight (its own pointer, or the host's system drag).
    var isDragging: Bool { get }
    func externalDragItems() -> [ExternalDragItem]
    func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem]
    func externalDragUpdated(types: [String], at point: CGPoint) -> Bool
    func externalDragExited()
    func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool
    func externalDragEnded(dropped: Bool)
    func externalDragPreview() -> ExternalDragPreview?
    /// Paints the tree's lifted preview (a drag by the pointer) over the host's content.
    func paintDragPreview(into list: inout DisplayList, context: PaintContext)
}

extension _PlatformViewTree {
    package func connectHostServices(_ services: _HostServices) {}
    package func hostElements(in context: PaintContext, identify: (AnyObject) -> Int) -> [HostElement] { [] }
    package func hasDragSource(at point: CGPoint) -> Bool { false }
    package var isDragging: Bool { false }
    package func externalDragItems() -> [ExternalDragItem] { [] }
    package func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem] { [] }
    package func externalDragUpdated(types: [String], at point: CGPoint) -> Bool { false }
    package func externalDragExited() {}
    package func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool { false }
    package func externalDragEnded(dropped: Bool) {}
    package func externalDragPreview() -> ExternalDragPreview? { nil }
    package func paintDragPreview(into list: inout DisplayList, context: PaintContext) {}
}

/// One frame of a host runtime, for clocks shared between its hosted trees.
public struct _HostFrame: Hashable, Sendable {
    public let host: ObjectIdentifier
    public let number: UInt64
    public init(host: ObjectIdentifier, number: UInt64) {
        self.host = host
        self.number = number
    }
}

/// Type-erased access to a host node for the runtime's routing.
@MainActor
package protocol _PlatformViewHosting: AnyObject {
    var tree: any _PlatformViewTree { get }
    /// The tree's frame in the window (the drag hooks convert points into the tree's space).
    var hostFrameInRoot: CGRect { get }
}

/// The leaf that stands for a hosted tree in the SwiftUI layout.
@MainActor
package final class _PlatformViewHostNode<V: View>: LeafNode<V>, _Interactive, _PlatformViewHosting, _FocusBoxObserving, _HoverTracking, _PointerStyled {
    package let tree: any _PlatformViewTree
    package var hostFrameInRoot: CGRect { frameInRoot }
    /// The size the tree wants for a proposal (the representable's own `sizeThatFits`, else the
    /// framework's rule for the hosted view).
    private let sizing: @MainActor (ProposedViewSize, V, EnvironmentValues) -> CGSize
    /// Pushes the view value into the hosted content (`updateUIView`) under a transaction.
    private let updateContent: @MainActor (V, EnvironmentValues, Transaction) -> Void
    /// The size the tree was last laid out in (the presented size while a frame tween runs).
    private var laidOutSize: CGSize?
    /// Whether the tree takes the safe area the node lies under as its own insets
    /// (`_PlatformViewRepresentableLayoutOptions.propagatesSafeArea`).
    private let propagatesSafeArea: Bool
    private let identifier: Int
    private var lastPressPoint = CGPoint.zero
    /// The environment generation the content was last updated for.
    private var updatedGeneration: UInt64?
    /// Sizes measured per proposal: SwiftUI measures a representable again only when its value,
    /// its environment or the proposal changes, not when the platform view's own content does
    /// (ios/representable/hostingsizing: a hosted view that grows keeps its representable's
    /// frame; ios/representable/update: a new text re-measures).
    private var measured: [ProposedViewSize: CGSize] = [:]

    package init(_ context: _NodeContext<V>, tree: any _PlatformViewTree, propagatesSafeArea: Bool = true,
                 sizing: @escaping @MainActor (ProposedViewSize, V, EnvironmentValues) -> CGSize,
                 update: @escaping @MainActor (V, EnvironmentValues, Transaction) -> Void) {
        self.tree = tree
        self.propagatesSafeArea = propagatesSafeArea
        self.sizing = sizing
        self.updateContent = update
        identifier = _nextGestureIdentifier()
        super.init(context)
        runtime.registerPlatformHost(self)
        runtime.registerFocusBox(self)
        tree.onNeedsFrame = { [weak self] in self?.treeNeedsFrame() }
        tree.onFocusedTextFieldChange = { [weak self] identifier in self?.treeFocusedTextFieldDidChange(to: identifier) }
        prepareTree()
        pushContent()
    }

    private func prepareTree() {
        tree.prepare(textEngine: runtime.textEngine, assetCatalog: runtime.assetCatalog)
        tree.imageRasterizer = runtime.imageRasterizer
        tree.connectPasteboard(runtime.pasteboardBridge)
        tree.connectHostServices(_HostServices(share: runtime.shareHandler, open: runtime.fileOpenHandler, save: runtime.fileSaveHandler))
    }

    /// Runs the representable's update with observation tracking, as a body evaluation: the
    /// `@Observable` properties it reads invalidate the node when they change. The context's
    /// transaction carries the animation of the state change being flushed (`withAnimation`,
    /// an `animation(_:value:)` scope).
    private func pushContent() {
        var transaction = Transaction()
        transaction.animation = runtime.effectiveUpdateAnimation(for: self)
        _trackingObservation(for: self) { updateContent(view, environment, transaction) }
        updatedGeneration = environment.generation
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate || _valuesDiffer(self.view, view) || updatedGeneration != environment.generation
        if force || _valuesDifferMemberwise(self.view, view) || updatedGeneration != environment.generation { measured.removeAll() }
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { pushContent() }
    }

    /// An observed property the update read changed: the content is pushed again from the
    /// stored value, which keeps the memoised sizes (the value did not change).
    override package func performUpdate() {
        update(view: view, environment: environment, force: false)
    }

    override package func unmount() {
        runtime.forgetHover(self)
        tree.dismantle()
        runtime.forgetPlatformHost(self)
        super.unmount()
    }

    override package var nodeDescription: String { "PlatformView(\(_shortTypeName(V.self)))" }

    // MARK: Layout and painting

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let size = measured[proposal] { return size }
        prepareTree()
        let size = sizing(proposal, view, environment)
        measured[proposal] = size
        return size
    }

    /// The tree's safe area is the part of the node under a bar or inset, by geometry: zero for
    /// a representable laid out inside the safe area, the bar's height for one that ignores it
    /// (ios/representable/safearea, safearea-ignored; Docs/elements/Representable.md).
    override package func layoutContents(proposal: ProposedViewSize) {
        layoutTree(size: frame.size)
    }

    private func layoutTree(size: CGSize) {
        tree.layout(size: size, safeAreaInsets: propagatesSafeArea ? platformSafeAreaOverlap : EdgeInsets(), environment: environment)
        laidOutSize = size
    }

    /// The hosted content's baselines are the representable's alignment guides.
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let baselines = tree.baselines(in: size)
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: baselines.first,
            VerticalAlignment.lastTextBaseline.key: baselines.last,
        ])
    }

    /// While the node's frame tweens (`withAnimation` resizing the representable) the tree is
    /// laid out at each interpolated size, as SwiftUI animates a platform view's frame.
    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let size = presentedFrame.size
        if size != laidOutSize { layoutTree(size: size) }
        tree.paint(into: &list, context: context)
        // A web view inside is the host's frame at the view's place (Ember's reader and
        // sign-in sheets, decision 0021), registered like a SwiftUI host element.
        runtime.hostElementsThisFrame += tree.hostElements(in: context) { [unowned runtime] view in
            let key = ObjectIdentifier(view)
            if let identifier = runtime.platformHostElementIdentifiers[key] { return identifier }
            let identifier = runtime.nextHostElementIdentifier()
            runtime.platformHostElementIdentifiers[key] = identifier
            return identifier
        }
    }

    /// A change inside the tree: the sizes may differ, so the next frame lays out again.
    private func treeNeedsFrame() {
        guard isMounted, !runtime.isLayingOut else { return }
        runtime.requestLayout()
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        lastPressPoint = point
        tree.pointerDown(at: point, type: runtime.lastPointerType, time: runtime.lastPointerTime)
    }
    package func pressMoved(to point: CGPoint) { tree.pointerMoved(to: point, time: runtime.lastPointerTime) }
    package func pressEnded(inside: Bool) {}
    package func pressEnded(inside: Bool, at point: CGPoint) { tree.pointerUp(at: point, time: runtime.lastPointerTime) }
    package func pressCancelled(at point: CGPoint) { tree.pointerCancelled(at: point, time: runtime.lastPointerTime) }
    package var dragAxes: Axis.Set { tree.dragAxes(at: lastPressPoint) }

    /// SwiftUI's hover reaches the tree as the pointer's position inside it, and the tree's
    /// hovered view sets the host's cursor (Docs/elements/Representable.md, hover).
    package func hoverChanged(inside: Bool, at point: CGPoint) {
        tree.hover(at: inside ? point : nil)
    }

    package var pointerStyle: PointerStyle? { tree.pointerStyle }

    /// The whole tree as one element (the semantics walk lists the tree's own elements instead).
    package var semantics: SemanticsNode {
        SemanticsNode(role: .group, label: "", frame: frameInRoot, identifier: identifier)
    }

    /// The tree's elements in window coordinates, with the frames they have inside the tree.
    package var semanticsEntries: [SemanticsEntry] {
        let origin = frameInRoot.origin
        return tree.semantics().map { element in
            var moved = element
            moved.frame = element.frame.offsetBy(dx: origin.x, dy: origin.y)
            if var input = moved.textInput {
                input.textRect = input.textRect.offsetBy(dx: origin.x, dy: origin.y)
                moved.textInput = input
            }
            return SemanticsEntry(node: self, element: moved, relativeFrame: element.frame)
        }
    }

    // MARK: Focus

    private func treeFocusedTextFieldDidChange(to identifier: Int?) {
        guard isMounted else { return }
        if let identifier {
            runtime.focusTextField(identifier)
        } else if let focused = runtime.focusedTextFieldIdentifier, tree.contains(semanticsIdentifier: focused) {
            runtime.focusTextField(nil)
        }
    }

    package func focusDidChange(to identifier: Int?) {
        if let identifier, tree.contains(semanticsIdentifier: identifier) { return }
        tree.resignFocus()
    }
}

extension Runtime {
    package func registerPlatformHost(_ node: any _PlatformViewHosting) {
        platformHosts.removeAll { $0.node == nil }
        platformHosts.append(WeakPlatformHost(node: node))
    }

    package func forgetPlatformHost(_ node: any _PlatformViewHosting) {
        platformHosts.removeAll { $0.node == nil || $0.node === node }
    }

    /// The hosted tree under `point` (window coordinates) and the point in its space.
    package func platformTree(at point: CGPoint) -> (tree: any _PlatformViewTree, local: CGPoint)? {
        for entry in platformHosts.reversed() {
            guard let node = entry.node else { continue }
            let frame = node.hostFrameInRoot
            if frame.contains(point) { return (node.tree, CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)) }
        }
        return nil
    }

    /// The hosted tree with a drag in flight, if any.
    package var draggingPlatformTree: (tree: any _PlatformViewTree, frame: CGRect)? {
        for entry in platformHosts {
            if let node = entry.node, node.tree.isDragging { return (node.tree, node.hostFrameInRoot) }
        }
        return nil
    }

    /// The hosted tree whose elements include `identifier`, if any.
    package func platformTree(handling identifier: Int) -> (any _PlatformViewTree)? {
        for entry in platformHosts {
            if let node = entry.node, node.tree.contains(semanticsIdentifier: identifier) { return node.tree }
        }
        return nil
    }

    /// Advances every hosted tree's clocks; true means one needs another frame. Trees sharing
    /// a clock (UIKit's scene) see the same frame and advance it once.
    package func advancePlatformHosts(elapsed: Double) -> Bool {
        hostFrameNumber += 1
        let frame = _HostFrame(host: ObjectIdentifier(self), number: hostFrameNumber)
        var animating = false
        for entry in platformHosts {
            if entry.node?.tree.advanceFrame(elapsed: elapsed, frame: frame) == true { animating = true }
        }
        return animating
    }
}

package struct WeakPlatformHost {
    package weak var node: (any _PlatformViewHosting)?
}

/// The host's sheets as a hosted tree sees them (nil where the host has none).
public struct _HostServices {
    public let share: ((HostShareRequest) -> Void)?
    public let open: ((HostFileOpenRequest, _ completion: @escaping @MainActor @Sendable ([HostFile]) -> Void) -> Void)?
    public let save: ((HostFile) -> Void)?
    public init(share: ((HostShareRequest) -> Void)?, open: ((HostFileOpenRequest, _ completion: @escaping @MainActor @Sendable ([HostFile]) -> Void) -> Void)?, save: ((HostFile) -> Void)?) {
        self.share = share; self.open = open; self.save = save
    }
}

/// A runtime's pasteboard as a hosted tree sees it: its text and the generation its copies
/// advance, and a way to put text on it (`UIPasteboard.general` in a hosted UIKit tree).
public struct _PasteboardBridge {
    public let generation: @MainActor () -> Int
    public let text: @MainActor () -> String?
    public let set: @MainActor (String?) -> Void
    public init(generation: @escaping @MainActor () -> Int, text: @escaping @MainActor () -> String?, set: @escaping @MainActor (String?) -> Void) {
        self.generation = generation; self.text = text; self.set = set
    }
}

extension Runtime {
    /// This runtime's pasteboard for hosted trees.
    public var pasteboardBridge: _PasteboardBridge {
        _PasteboardBridge(generation: { [weak self] in self?.rootEnvironment._pasteboardGeneration ?? 0 },
                          text: { [weak self] in self?.pasteboardText },
                          set: { [weak self] text in self?.setPasteboard(text.map { [_TransferItem($0)] } ?? []) })
    }
}
