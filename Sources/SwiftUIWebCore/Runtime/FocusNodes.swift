// Focus runtime: `focused` modifier nodes register with their focus state box and report the
// text field they cover; the runtime tells every box when its focused field changes.
// `defaultFocus` sets the initial focus after mounting, `focusSection` groups the Tab order,
// `focusScope` with `prefersDefaultFocus` chooses where focus lands entering a scope.

@MainActor
package final class FocusedNode<Content: View, Value: Hashable>: UnaryLayoutModifierNode<Content, _FocusedModifier<Value>>, _FocusTargetProviding {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _FocusedModifier<Value>>>) {
        super.init(context)
        register()
        runtime.registerFocusBox(modifier.box)
        // Focus already on this value (set before the view existed) takes effect now.
        if let box = modifier.box, box.value == modifier.value {
            // A text field mounts before it is interactive, which `focus(semanticsIdentifier:)`
            // needs to know it as one: it takes the text-field path directly (else a state set
            // before the field appeared focused it as a plain control, a ring and no typing).
            if let field = focusTargetTextField { runtime.focusTextField(field) }
            else if let id = focusTargetIdentifier { runtime.focus(semanticsIdentifier: id) }
        }
    }

    override package func update(view: ModifiedContent<Content, _FocusedModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        register()
    }

    private func register() {
        guard let box = modifier.box else { return }
        if !box.targets.contains(where: { $0.node.node === self }) {
            box.targets.append((modifier.value, WeakNode(node: self)))
        }
        box.targets.removeAll { $0.node.node == nil }
    }

    /// The first text field in the subtree, else its first interactive or focusable view, else
    /// its first static element (`accessibilityFocused` on text or an image).
    /// The subtree's first text field, if it has one.
    package var focusTargetTextField: Int? { (descendants(where: { $0 is TextFieldNode }).first as? TextFieldNode)?.identifier }

    package var focusTargetIdentifier: Int? {
        if let field = focusTargetTextField { return field }
        if let interactive = descendants(where: { $0.isInteractiveNode }).first as? any _Interactive { return interactive.semantics.identifier }
        return descendants(where: { ($0 as? any _SemanticsProviding)?.staticSemantics != nil }).first?.semanticsIdentifier
    }
}

/// Type-erased access to a focus state box for the runtime's notifications.
@MainActor
package protocol _FocusBoxObserving: AnyObject {
    func focusDidChange(to identifier: Int?)
}

extension _FocusStateBox: _FocusBoxObserving {}

extension Runtime {
    package func registerFocusBox(_ box: (any _FocusBoxObserving)?) {
        guard let box, !focusBoxes.contains(where: { $0.box === box }) else { return }
        focusBoxes.append(WeakFocusBox(box: box))
    }

    /// Moves keyboard focus to a text field (or nowhere) and tells the host and the focus states.
    package func focusTextField(_ identifier: Int?) {
        guard focusedTextFieldIdentifier != identifier || focusedIdentifier != identifier else { return }
        let previous = focusedTextFieldIdentifier
        focusedTextFieldIdentifier = identifier
        focusedIdentifier = identifier
        focusVisible = true
        if let previous, previous != identifier { textInputNode(previous)?.focusChanged(false) }
        if let identifier, identifier != previous { textInputNode(identifier)?.focusChanged(true) }
        notifyFocusChanged()
        setNeedsDisplay()
    }

    package func notifyFocusChanged() {
        focusBoxes.removeAll { $0.box == nil }
        for entry in focusBoxes { entry.box?.focusDidChange(to: focusedIdentifier) }
        focusedValuesDidChange()
    }
}

package struct WeakFocusBox {
    package weak var box: (any _FocusBoxObserving)?
}

// MARK: - Default focus, sections and scopes

/// `defaultFocus`: once mounted, sets the state (moving focus) when nothing is focused in the
/// node's window or presentation.
@MainActor
package final class DefaultFocusNode<Content: View, Value: Hashable>: UnaryLayoutModifierNode<Content, _DefaultFocusModifier<Value>> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _DefaultFocusModifier<Value>>>) {
        super.init(context)
        runtime.scheduler.enqueue { [weak self] in self?.applyIfNothingFocused() }
    }

    private func applyIfNothingFocused() {
        guard isMounted, let box = modifier.box else { return }
        if let focusedIdentifier = runtime.focusedIdentifier, let focused = runtime.interactiveNode(semanticsIdentifier: focusedIdentifier),
           focused.topAncestor === topAncestor {
            return
        }
        box.set(modifier.value)
    }

    override package var nodeDescription: String { "DefaultFocus" }
}

/// `focusSection`: a marker the Tab order groups by.
@MainActor
package final class FocusSectionNode<Content: View>: UnaryLayoutModifierNode<Content, _FocusSectionModifier>, _FocusSectionMarking {
    override package var nodeDescription: String { "FocusSection" }
}

@MainActor package protocol _FocusSectionMarking: AnyObject {}

/// `focusScope`: a marker with a namespace.
@MainActor
package final class FocusScopeNode<Content: View>: UnaryLayoutModifierNode<Content, _FocusScopeModifier>, _FocusScoping {
    package var namespace: Namespace.ID { modifier.namespace }
    override package var nodeDescription: String { "FocusScope" }
}

@MainActor package protocol _FocusScoping: AnyObject {
    var namespace: Namespace.ID { get }
}

/// `prefersDefaultFocus`: the view focus lands on entering its scope.
@MainActor
package final class PrefersDefaultFocusNode<Content: View>: UnaryLayoutModifierNode<Content, _PrefersDefaultFocusModifier>, _DefaultFocusPreferring {
    package var prefersDefaultFocus: Bool { modifier.prefers }
    package var namespace: Namespace.ID { modifier.namespace }
    override package var nodeDescription: String { "PrefersDefaultFocus" }
}

@MainActor package protocol _DefaultFocusPreferring: AnyObject {
    var prefersDefaultFocus: Bool { get }
    var namespace: Namespace.ID { get }
}

extension ViewNode {
    /// The root of this node's tree (the window's root or a presentation's content).
    package var topAncestor: ViewNode {
        var node: ViewNode = self
        while let parent = node.parent { node = parent }
        return node
    }

    /// The nearest ancestor (or self) satisfying `predicate`.
    package func nearestAncestor(where predicate: (ViewNode) -> Bool) -> ViewNode? {
        var node: ViewNode? = self
        while let current = node {
            if predicate(current) { return current }
            node = current.parent
        }
        return nil
    }
}

extension Runtime {
    /// The focusable element inside `scope` that prefers default focus, if any.
    private func preferredDefaultFocus(in scope: ViewNode & _FocusScoping) -> Int? {
        let order = focusOrder
        for node in scope.descendants(where: { $0 is any _DefaultFocusPreferring }) {
            guard let preferring = node as? any _DefaultFocusPreferring, preferring.prefersDefaultFocus, preferring.namespace == scope.namespace else { continue }
            if let identifier = node.descendants(where: { $0.isInteractiveNode }).compactMap({ ($0 as? any _Interactive)?.semantics.identifier }).first(where: order.contains) {
                return identifier
            }
        }
        return nil
    }

    /// Where focus lands moving to `identifier` from `current`: the preferred default of the
    /// scope being entered, else `identifier` itself.
    package func focusTarget(entering identifier: Int, from current: Int?) -> Int {
        guard let node = interactiveNode(semanticsIdentifier: identifier),
              let scope = node.nearestAncestor(where: { $0 is any _FocusScoping }) as? (ViewNode & _FocusScoping) else { return identifier }
        if let current, let currentNode = interactiveNode(semanticsIdentifier: current),
           currentNode.nearestAncestor(where: { $0 is any _FocusScoping }) === scope {
            return identifier
        }
        return preferredDefaultFocus(in: scope) ?? identifier
    }

    /// `resetFocus(in:)`: focus moves to the preferred default of the scope with `namespace`.
    package func resetFocus(in namespace: Namespace.ID) {
        let scopes = root.descendants(where: { ($0 as? any _FocusScoping)?.namespace == namespace })
            + presentations.flatMap { $0.semanticsRoots.flatMap { $0.descendants(where: { ($0 as? any _FocusScoping)?.namespace == namespace }) } }
        for scope in scopes.compactMap({ $0 as? (ViewNode & _FocusScoping) }) {
            if let identifier = preferredDefaultFocus(in: scope) {
                focus(semanticsIdentifier: identifier, keyboard: true)
                return
            }
        }
    }
}
