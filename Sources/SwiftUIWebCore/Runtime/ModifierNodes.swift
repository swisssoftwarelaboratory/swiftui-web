// `ModifiedContent<Content, Modifier>` dispatches node creation to the modifier, so that
// primitive modifiers (environment, padding, frame, background…) can provide their own node
// while user modifiers with a `body(content:)` get `ModifierBodyNode`.

extension ModifiedContent where Content: View, Modifier: ViewModifier {
    @MainActor
    public static func _makeNode(
        _ context: _NodeContext<ModifiedContent<Content, Modifier>>
    ) -> TypedNode<ModifiedContent<Content, Modifier>> {
        Modifier._makeNode(context)
    }
}

extension ViewModifier {
    /// Hidden hook: builds the node for `content.modifier(self)`. Primitive modifiers override.
    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        precondition(Body.self != Never.self,
                     "\(Self.self) is a primitive modifier and must implement _makeNode")
        return ModifierBodyNode(context)
    }
}

/// Type-erased access to a modifier host's content, used by `_ViewModifier_Content` nodes.
@MainActor
package protocol _ModifierContentProvider: AnyObject {
    var modifierType: Any.Type { get }
    func makeContentNode(parent: ViewNode, environment: EnvironmentValues) -> ViewNode
    func updateContentNode(_ node: ViewNode, environment: EnvironmentValues)
}

/// Node for a modifier with a `body(content:)`: evaluates the body with a placeholder content
/// view and hosts the real content for the placeholder nodes that appear inside it.
@MainActor
package final class ModifierBodyNode<Content: View, Modifier: ViewModifier>:
    TypedNode<ModifiedContent<Content, Modifier>>, _ModifierContentProvider
{
    package private(set) var child: TypedNode<Modifier.Body>!
    package private(set) var bodyEvaluations = 0
    package private(set) var propertyStorage: AnyObject?

    init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        evaluateBody()
    }

    override package func update(view: ModifiedContent<Content, Modifier>,
                                 environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view.modifier, view.modifier)
            || _valuesDiffer(self.view.content, view.content)
            || self.environment.generation != environment.generation
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<Modifier>.installAll(into: &view.modifier, node: self, slot: &propertyStorage)
        let body = _trackingObservation(for: self) { view.modifier.body(content: _ViewModifier_Content<Modifier>()) }
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = Modifier.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    package var modifierType: Any.Type { Modifier.self }

    /// Its sizes are its body's (see `CompositeNode`).
    override package func newValueChangesSizes(from old: ModifiedContent<Content, Modifier>, to new: ModifiedContent<Content, Modifier>) -> Bool { false }

    package func makeContentNode(parent: ViewNode, environment: EnvironmentValues) -> ViewNode {
        Content._makeNode(_NodeContext(view: view.content, parent: parent, environment: environment))
    }

    package func updateContentNode(_ node: ViewNode, environment: EnvironmentValues) {
        (node as! TypedNode<Content>).update(view: view.content, environment: environment)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Modifier<\(_shortTypeName(Modifier.self))>" }
}

extension _ViewModifier_Content {
    @MainActor
    public static func _makeNode(
        _ context: _NodeContext<_ViewModifier_Content<Modifier>>
    ) -> TypedNode<_ViewModifier_Content<Modifier>> {
        ModifierContentNode(context)
    }
}

/// Node for the `content` placeholder inside a modifier body. Finds the nearest enclosing host
/// for the same modifier type and mounts that host's content here.
@MainActor
package final class ModifierContentNode<Modifier: ViewModifier>: TypedNode<_ViewModifier_Content<Modifier>> {
    package private(set) var child: ViewNode!
    private unowned let provider: any _ModifierContentProvider

    init(_ context: _NodeContext<_ViewModifier_Content<Modifier>>) {
        var ancestor: ViewNode? = context.parent
        var found: (any _ModifierContentProvider)?
        while let node = ancestor {
            if let host = node as? any _ModifierContentProvider, host.modifierType == Modifier.self {
                found = host
                break
            }
            ancestor = node.parent
        }
        guard let found else {
            fatalError("_ViewModifier_Content<\(Modifier.self)> used outside of that modifier's body")
        }
        provider = found
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = provider.makeContentNode(parent: self, environment: context.environment)
    }

    override package func update(view: _ViewModifier_Content<Modifier>,
                                 environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        provider.updateContentNode(child, environment: environment)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ModifierContent" }
}

// MARK: Environment modifiers

extension _EnvironmentKeyWritingModifier {
    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

extension _EnvironmentKeyTransformModifier {
    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

/// Applies an environment-changing modifier and passes the result to its content. Transparent
/// to layout. When neither the modifier nor the incoming environment changed, the child sees the
/// same environment generation and can skip work.
@MainActor
package final class EnvironmentModifierNode<Content: View, Modifier: ViewModifier & _EnvironmentModifier>:
    TypedNode<ModifiedContent<Content, Modifier>>
{
    package private(set) var child: TypedNode<Content>!
    package private(set) var childEnvironment: EnvironmentValues

    init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        childEnvironment = Self.apply(context.view.modifier, to: context.environment)
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: childEnvironment))
    }

    private static func apply(_ modifier: Modifier, to environment: EnvironmentValues) -> EnvironmentValues {
        var result = environment
        modifier.modifyEnvironment(&result)
        return result
    }

    override package func update(view: ModifiedContent<Content, Modifier>,
                                 environment: EnvironmentValues, force: Bool) {
        // Not `force`: an equal modifier applied to the same environment gives the same values,
        // so the content keeps its generation and its memoised sizes. A forced update came from
        // above (a geometry reader building its content again) and reaches the content anyway;
        // making a new generation for it made a whole screen forget its sizes on every keystroke
        // (new-website#216). A modifier that cannot be compared still counts as changed.
        if needsUpdate
            || self.environment.generation != environment.generation
            || _valuesDiffer(self.view.modifier, view.modifier)
        {
            childEnvironment = Self.apply(view.modifier, to: environment)
        }
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: childEnvironment, force: force)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Environment<\(_shortTypeName(Modifier.self))>" }

    /// Transparent to layout: a new environment reaches the content's sizes through it.
    override package func newValueChangesSizes(from old: ModifiedContent<Content, Modifier>, to new: ModifiedContent<Content, Modifier>) -> Bool { false }
}
