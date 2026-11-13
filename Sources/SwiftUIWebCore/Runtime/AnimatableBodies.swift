// Animatable views and modifiers with a body (a `View` that conforms to `Animatable`, an
// `AnimatableModifier`): when one's animatable data changes under an animation, its body is
// evaluated once per frame with the data interpolated from the value shown to the new one, as
// SwiftUI does (Docs/elements/Animation.md). Such a type gets a node of its own, chosen by the
// constrained `_makeNode` defaults below, so `CompositeNode` and `ModifierBodyNode` (one
// specialisation per view and modifier type in an app) carry nothing for it and nothing is
// cast at run time. A custom `Shape` is an animatable view and interpolates the same way;
// geometry effects have nodes of their own.

extension View where Self: Animatable {
    /// Hidden hook: an animatable view's body is evaluated with its data interpolated.
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        AnimatableBodyNode(context)
    }
}

extension ViewModifier where Self: Animatable {
    /// Hidden hook: an animatable modifier's body is evaluated with its data interpolated.
    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        precondition(Body.self != Never.self,
                     "\(Self.self) is a primitive modifier and must implement _makeNode")
        return AnimatableModifierBodyNode(context)
    }
}

extension Shape where AnimatableData == EmptyAnimatableData {
    /// Hidden hook: a shape with nothing to interpolate (a rectangle, a circle, a capsule) is a
    /// plain composite, as the library's controls draw many of them.
    @MainActor
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        CompositeNode(context)
    }
}

// Protocols with node hooks of their own keep them when a conformer is also `Animatable`
// (the representables do the same in their own files).

extension EnvironmentalModifier where Self: Animatable {
    @MainActor public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentalModifierNode(context)
    }
}

/// A running interpolation of a value's animatable data, from the data shown when it started.
@MainActor
package final class _AnimatableBodyDriver<Value: Animatable>: _FrameSubscriber {
    private unowned let node: ViewNode
    private var tween: (progress: Tween, from: Value.AnimatableData, to: Value.AnimatableData)?

    init(node: ViewNode) { self.node = node }

    /// `value` (the newest, with its dynamic properties installed) with the data shown now.
    func presented(_ value: Value) -> Value {
        guard let tween else { return value }
        var shown = value
        let progress = tween.progress.value(at: node.runtime.animationClock)[0]
        shown.animatableData = tween.from.interpolated(towards: tween.to, amount: progress)
        return shown
    }

    /// Records a change of the value from `old` to `new`: a change of its animatable data under
    /// an animation tweens from what is on screen, one without jumps. An update that leaves the
    /// data as it was (a frame's re-evaluation, a parent's change) keeps a running tween.
    func change(from old: Value, to new: Value) {
        let target = new.animatableData
        guard (old.animatableData - target).magnitudeSquared > 0 else { return }
        let shown = presented(old).animatableData
        if let animation = node.runtime.effectiveUpdateAnimation(for: node),
           (shown - target).magnitudeSquared > 0 {
            tween = (Tween(from: [0], to: [1], animation: animation, start: node.runtime.animationClock), shown, target)
            node.runtime.subscribeFrames(self)
        } else {
            stop()
        }
    }

    func stop() {
        tween = nil
        node.runtime.unsubscribeFrames(self)
    }

    package func frameDidAdvance() {
        guard let tween else { return }
        if tween.progress.isFinished(at: node.runtime.animationClock) { stop() }
        node.invalidate()
    }
}

/// `CompositeNode` for an animatable view: the body is evaluated with the presented data.
@MainActor
package final class AnimatableBodyNode<V: View & Animatable>: TypedNode<V> {
    package private(set) var child: TypedNode<V.Body>?
    package private(set) var bodyEvaluations = 0
    package private(set) var propertyStorage: AnyObject?
    private var driver: _AnimatableBodyDriver<V>!

    package init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        driver = _AnimatableBodyDriver(node: self)
        evaluateBody()
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view, view)
            || self.environment.generation != environment.generation
        driver.change(from: self.view, to: view)
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<V>.installAll(into: &view, node: self, slot: &propertyStorage)
        let shown = driver.presented(view)
        let body = _trackingObservation(for: self) { shown.body }
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = V.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    override package func unmount() {
        driver.stop()
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
}

/// `ModifierBodyNode` for an animatable modifier: the body is evaluated with the presented data.
@MainActor
package final class AnimatableModifierBodyNode<Content: View, Modifier: ViewModifier & Animatable>:
    TypedNode<ModifiedContent<Content, Modifier>>, _ModifierContentProvider
{
    package private(set) var child: TypedNode<Modifier.Body>!
    package private(set) var bodyEvaluations = 0
    package private(set) var propertyStorage: AnyObject?
    private var driver: _AnimatableBodyDriver<Modifier>!

    init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        driver = _AnimatableBodyDriver(node: self)
        evaluateBody()
    }

    override package func update(view: ModifiedContent<Content, Modifier>,
                                 environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view.modifier, view.modifier)
            || _valuesDiffer(self.view.content, view.content)
            || self.environment.generation != environment.generation
        driver.change(from: self.view.modifier, to: view.modifier)
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<Modifier>.installAll(into: &view.modifier, node: self, slot: &propertyStorage)
        let shown = driver.presented(view.modifier)
        let body = _trackingObservation(for: self) { shown.body(content: _ViewModifier_Content<Modifier>()) }
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = Modifier.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    package var modifierType: Any.Type { Modifier.self }

    package func makeContentNode(parent: ViewNode, environment: EnvironmentValues) -> ViewNode {
        Content._makeNode(_NodeContext(view: view.content, parent: parent, environment: environment))
    }

    package func updateContentNode(_ node: ViewNode, environment: EnvironmentValues) {
        (node as! TypedNode<Content>).update(view: view.content, environment: environment)
    }

    override package func unmount() {
        driver.stop()
        super.unmount()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Modifier<\(_shortTypeName(Modifier.self))>" }
}
