/// Keyboard focus as view state (`Docs/elements/Focus.md`): `@FocusState` holds which view is
/// focused, `focused(_:)`/`focused(_:equals:)` tie a view to it in both directions;
/// `defaultFocus` picks the initial focus, `focusSection` keeps a group together in the Tab
/// order, `focusScope` and `prefersDefaultFocus` choose where focus lands entering a scope and
/// `resetFocus` sends it there.
@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
    package var box: _FocusStateBox<Value>?
    package let initial: Value

    /// Creates a focus state that binds to a Boolean.
    public init() where Value == Bool {
        initial = false
    }

    /// Creates a focus state that binds to an optional value.
    public init<T: Hashable>() where Value == T? {
        initial = nil
    }

    /// The current state value, taking into account whatever bindings might be associated
    /// with the property. Setting it moves focus.
    public var wrappedValue: Value {
        get { box?.value ?? initial }
        nonmutating set { box?.set(newValue) }
    }

    /// A projection of the focus state value that returns a binding.
    public var projectedValue: Binding { Binding(box: box, initial: initial) }

    /// A property wrapper type that can read and write a value that indicates the current focus.
    @propertyWrapper
    public struct Binding {
        package let box: _FocusStateBox<Value>?
        package let initial: Value

        public var wrappedValue: Value {
            get { box?.value ?? initial }
            nonmutating set { box?.set(newValue) }
        }

        public var projectedValue: Binding { self }
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        if let existing = slot as? _FocusStateBox<Value> {
            box = existing
        } else {
            let created = _FocusStateBox(value: initial, node: node)
            slot = created
            box = created
        }
    }
}

/// Storage for one `@FocusState`: the value, the owning node (invalidated when the value
/// changes) and the focus targets that follow it.
@MainActor
package final class _FocusStateBox<Value: Hashable> {
    package nonisolated(unsafe) private(set) var value: Value
    private weak var node: ViewNode?
    /// The nodes with `focused` modifiers bound to this state, by their focus value.
    package var targets: [(value: Value, node: WeakNode)] = []

    package init(value: Value, node: ViewNode) {
        self.value = value
        self.node = node
    }

    /// A programmatic focus change: records the value, re-renders, and moves the runtime's focus.
    package nonisolated func set(_ newValue: Value) {
        nonisolated(unsafe) let value = newValue
        MainActor.assumeIsolated { applyProgrammatic(value) }
    }

    private func applyProgrammatic(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        node?.invalidate()
        guard let runtime = node?.runtime else { return }
        if let target = targets.first(where: { $0.value == newValue })?.node.node as? any _FocusTargetProviding {
            // A text field takes the text-field path straight away: `focus(semanticsIdentifier:)`
            // knows it only once it is interactive, and a screen that focuses its field as it
            // appears (still sliding in) would focus it as a plain control, with a ring and no
            // keyboard input.
            if let field = target.focusTargetTextField { runtime.focusTextField(field) } else {
                runtime.focus(semanticsIdentifier: target.focusTargetIdentifier)
            }
        } else if isUnfocusedValue(newValue) {
            runtime.focus(semanticsIdentifier: nil)
        }
    }

    /// The runtime's focus changed: mirror it into the value without moving focus again.
    package func focusDidChange(to identifier: Int?) {
        let newValue: Value
        if let identifier, let target = targets.first(where: { ($0.node.node as? any _FocusTargetProviding)?.focusTargetIdentifier == identifier }) {
            newValue = target.value
        } else if let identifier, targets.contains(where: { _ in true }), Value.self == Bool.self {
            _ = identifier
            newValue = false as! Value
        } else if let identifier {
            _ = identifier
            newValue = unfocusedValue()
        } else {
            newValue = unfocusedValue()
        }
        guard newValue != value else { return }
        value = newValue
        node?.invalidate()
    }

    private func unfocusedValue() -> Value {
        if Value.self == Bool.self { return false as! Value }
        return (Optional<Any>.none as Any) as? Value ?? value
    }

    private func isUnfocusedValue(_ value: Value) -> Bool {
        if let bool = value as? Bool { return !bool }
        if case Optional<Any>.none = (value as Any) { return true }
        return false
    }
}

/// A node whose subtree's text field can take focus for a `focused` modifier.
@MainActor
package protocol _FocusTargetProviding: AnyObject {
    var focusTargetIdentifier: Int? { get }
    /// The subtree's text field, if the target is one.
    var focusTargetTextField: Int? { get }
}

/// `focused(_:)`/`focused(_:equals:)`: registers the modified view with the focus state.
public struct _FocusedModifier<Value: Hashable> {
    package let box: _FocusStateBox<Value>?
    package let value: Value

    package init(box: _FocusStateBox<Value>?, value: Value) {
        self.box = box
        self.value = value
    }
}

extension _FocusedModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusedNode(context)
    }
}

extension View {
    /// Modifies this view by binding its focus state to the given Boolean state value.
    nonisolated public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        modifier(_FocusedModifier(box: condition.box, value: true))
    }

    /// Modifies this view by binding its focus state to the given state value.
    nonisolated public func focused<Value: Hashable>(_ binding: FocusState<Value?>.Binding, equals value: Value) -> some View {
        modifier(_FocusedModifier(box: binding.box, value: value))
    }
}

// MARK: - Default focus, sections and scopes

/// How strongly a `defaultFocus` applies (accepted: both set the initial focus).
public struct DefaultFocusEvaluationPriority: Hashable, Sendable {
    package let rank: Int
    public static let automatic = DefaultFocusEvaluationPriority(rank: 0)
    public static let userInitiated = DefaultFocusEvaluationPriority(rank: 1)
}

/// `defaultFocus`: sets the focus state to `value` when the view appears with nothing focused
/// in its window or presentation.
public struct _DefaultFocusModifier<Value: Hashable> {
    package let box: _FocusStateBox<Value>?
    package let value: Value
    package let priority: DefaultFocusEvaluationPriority
}

extension _DefaultFocusModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        DefaultFocusNode(context)
    }
}

/// `focusSection`: the focusable views inside stay together in the Tab order.
public struct _FocusSectionModifier {}

extension _FocusSectionModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusSectionNode(context)
    }
}

/// `focusScope`: focus entering the scope lands on the view that prefers default focus in it.
public struct _FocusScopeModifier {
    package let namespace: Namespace.ID
}

extension _FocusScopeModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusScopeNode(context)
    }
}

/// `prefersDefaultFocus`: the view focus lands on when its scope is entered or reset.
public struct _PrefersDefaultFocusModifier {
    package let prefers: Bool
    package let namespace: Namespace.ID
}

extension _PrefersDefaultFocusModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PrefersDefaultFocusNode(context)
    }
}

/// `resetFocus`: moves focus to the preferred default of a scope.
public struct ResetFocusAction {
    package weak var runtime: Runtime?
    package init(runtime: Runtime? = nil) { self.runtime = runtime }
    @MainActor public func callAsFunction(in namespace: Namespace.ID) { runtime?.resetFocus(in: namespace) }
}

package struct ResetFocusKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue = ResetFocusAction()
}

extension EnvironmentValues {
    /// An action that requests the focus system to reevaluate default focus in a scope.
    public var resetFocus: ResetFocusAction {
        get { self[ResetFocusKey.self] }
        set { self[ResetFocusKey.self] = newValue }
    }
}

extension View {
    /// Defines the view the focus state takes when its window or presentation appears with
    /// nothing focused.
    nonisolated public func defaultFocus<V: Hashable>(_ binding: FocusState<V>.Binding, _ value: V, priority: DefaultFocusEvaluationPriority = .automatic) -> some View {
        modifier(_DefaultFocusModifier(box: binding.box, value: value, priority: priority))
    }

    /// Keeps the focusable views inside together in the Tab order.
    nonisolated public func focusSection() -> some View {
        modifier(_FocusSectionModifier())
    }

    /// Creates a focus scope: focus entering it lands on the view that prefers default focus.
    nonisolated public func focusScope(_ namespace: Namespace.ID) -> some View {
        modifier(_FocusScopeModifier(namespace: namespace))
    }

    /// Marks the view as the one focus should land on when its scope is entered.
    nonisolated public func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View {
        modifier(_PrefersDefaultFocusModifier(prefers: prefersDefaultFocus, namespace: namespace))
    }
}
