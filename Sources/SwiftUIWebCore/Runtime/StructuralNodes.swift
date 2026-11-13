// Nodes for the library's structural (list-like) views. None of these participate in layout
// themselves: their `layoutChildren` are the flattened children (invariant 2).

extension EmptyView {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<EmptyView>) -> TypedNode<EmptyView> {
        EmptyNode(context)
    }
}

@MainActor
package final class EmptyNode: TypedNode<EmptyView> {
    init(_ context: _NodeContext<EmptyView>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
    }
    override package var layoutChildren: [ViewNode] { [] }
    override package var nodeDescription: String { "Empty" }
}

// MARK: TupleView

extension TupleView {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<TupleView<T>>) -> TypedNode<TupleView<T>> {
        TupleNode(context)
    }
}

@MainActor
package final class TupleNode<T>: TypedNode<TupleView<T>> {
    package private(set) var children: [ViewNode] = []
    private let elements = TupleElement<T>.all

    init(_ context: _NodeContext<TupleView<T>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        children = elements.map { $0.make(context.view.value, self, context.environment) }
    }

    override package func update(view: TupleView<T>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        for (element, child) in zip(elements, children) {
            element.update(child, view.value, environment)
        }
    }

    override package var structuralChildren: [ViewNode] { children }
    override package var layoutChildren: [ViewNode] { children.flatMap(\.layoutChildren) }
    override package var nodeDescription: String { "Tuple(\(children.count))" }

    /// Its elements are fixed by its type; each compares its own new value.
    override package func newValueChangesSizes(from old: TupleView<T>, to new: TupleView<T>) -> Bool { false }
}

// MARK: _ConditionalContent

extension _ConditionalContent where TrueContent: View, FalseContent: View {
    @MainActor
    public static func _makeNode(
        _ context: _NodeContext<_ConditionalContent<TrueContent, FalseContent>>
    ) -> TypedNode<_ConditionalContent<TrueContent, FalseContent>> {
        ConditionalNode(context)
    }
}

/// The active branch is the node's identity: switching branches unmounts the old subtree.
@MainActor
package final class ConditionalNode<TrueContent: View, FalseContent: View>:
    TypedNode<_ConditionalContent<TrueContent, FalseContent>>
{
    package enum Branch {
        case first(TypedNode<TrueContent>)
        case second(TypedNode<FalseContent>)
    }

    package private(set) var branch: Branch!

    init(_ context: _NodeContext<_ConditionalContent<TrueContent, FalseContent>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        branch = makeBranch(for: context.view, environment: context.environment)
    }

    private func makeBranch(for view: _ConditionalContent<TrueContent, FalseContent>,
                            environment: EnvironmentValues) -> Branch {
        switch view.storage {
        case .trueContent(let content):
            return .first(TrueContent._makeNode(_NodeContext(view: content, parent: self, environment: environment)))
        case .falseContent(let content):
            return .second(FalseContent._makeNode(_NodeContext(view: content, parent: self, environment: environment)))
        }
    }

    override package func update(view: _ConditionalContent<TrueContent, FalseContent>,
                                 environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        switch (view.storage, branch!) {
        case (.trueContent(let content), .first(let node)):
            node.update(view: content, environment: environment)
        case (.falseContent(let content), .second(let node)):
            node.update(view: content, environment: environment)
        default:
            retire(activeNode)
            branch = makeBranch(for: view, environment: environment)
            noteInserted(activeNode)
        }
    }

    /// Only a switch of branch (a new subtree); within a branch, the branch compares itself.
    override package func newValueChangesSizes(from old: _ConditionalContent<TrueContent, FalseContent>,
                                               to new: _ConditionalContent<TrueContent, FalseContent>) -> Bool {
        switch (old.storage, new.storage) {
        case (.trueContent, .trueContent), (.falseContent, .falseContent): return false
        default: return true
        }
    }

    package var activeNode: ViewNode {
        switch branch! {
        case .first(let node): return node
        case .second(let node): return node
        }
    }

    override package var structuralChildren: [ViewNode] { [activeNode] }
    override package var layoutChildren: [ViewNode] { activeNode.layoutChildren }
    override package var nodeDescription: String {
        switch branch! {
        case .first: return "Conditional(first)"
        case .second: return "Conditional(second)"
        }
    }
}

// MARK: Optional

extension Optional where Wrapped: View {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<Wrapped?>) -> TypedNode<Wrapped?> {
        OptionalNode(context)
    }
}

/// `nil` contributes nothing; a value that appears is a fresh subtree, and one that disappears
/// is unmounted (its state is lost, as in SwiftUI).
@MainActor
package final class OptionalNode<Wrapped: View>: TypedNode<Wrapped?> {
    package private(set) var child: TypedNode<Wrapped>?

    init(_ context: _NodeContext<Wrapped?>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        if let wrapped = context.view {
            child = Wrapped._makeNode(_NodeContext(view: wrapped, parent: self, environment: context.environment))
        }
    }

    override package func update(view: Wrapped?, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        switch (view, child) {
        case (.some(let wrapped), .some(let node)):
            node.update(view: wrapped, environment: environment)
        case (.some(let wrapped), .none):
            let node = Wrapped._makeNode(_NodeContext(view: wrapped, parent: self, environment: environment))
            child = node
            noteInserted(node)
        case (.none, .some(let node)):
            retire(node)
            child = nil
        case (.none, .none):
            break
        }
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
    override package var nodeDescription: String { child == nil ? "Optional(none)" : "Optional(some)" }
}

// MARK: Group

extension Group where Content: View {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<Group<Content>>) -> TypedNode<Group<Content>> {
        GroupNode(context)
    }
}

@MainActor
package final class GroupNode<Content: View>: TypedNode<Group<Content>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<Group<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: Group<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "Group" }
}

// MARK: AnyView

extension AnyView {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<AnyView>) -> TypedNode<AnyView> {
        AnyViewNode(context)
    }
}

/// Rebuilds its subtree whenever the wrapped view's dynamic type changes.
@MainActor
package final class AnyViewNode: TypedNode<AnyView> {
    package private(set) var child: ViewNode!
    package private(set) var childType: Any.Type

    init(_ context: _NodeContext<AnyView>) {
        childType = context.view.viewType
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = makeChild(for: context.view, environment: context.environment)
    }

    private func makeChild(for view: AnyView, environment: EnvironmentValues) -> ViewNode {
        var visitor = Maker(parent: self, environment: environment)
        return view.visit(&visitor)
    }

    override package func update(view: AnyView, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if view.viewType == childType {
            var visitor = Updater(node: child, environment: environment)
            view.visit(&visitor)
        } else {
            child.unmount()
            childType = view.viewType
            child = makeChild(for: view, environment: environment)
        }
    }

    private struct Maker: _AnyViewVisitor {
        let parent: ViewNode
        let environment: EnvironmentValues
        func visit<V: View>(_ view: V) -> ViewNode {
            V._makeNode(_NodeContext(view: view, parent: parent, environment: environment))
        }
    }

    private struct Updater: _AnyViewVisitor {
        let node: ViewNode
        let environment: EnvironmentValues
        func visit<V: View>(_ view: V) {
            (node as! TypedNode<V>).update(view: view, environment: environment)
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "AnyView(\(_shortTypeName(childType)))" }

    /// Only a view of another type (a new subtree); a view of the same type compares itself.
    override package func newValueChangesSizes(from old: AnyView, to new: AnyView) -> Bool { old.viewType != new.viewType }
}
