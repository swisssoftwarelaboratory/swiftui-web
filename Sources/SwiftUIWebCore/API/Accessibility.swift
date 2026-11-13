/// Accessibility modifiers (`Docs/elements/Accessibility.md`): they set attributes on the
/// semantics elements of the modified view, which hosts expose (the canvas host as a DOM
/// overlay with ARIA roles).

/// A set of accessibility traits that describe how an element behaves.
public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    public static let isLink = AccessibilityTraits(rawValue: 1 << 3)
    public static let isSearchField = AccessibilityTraits(rawValue: 1 << 4)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 5)
    public static let playsSound = AccessibilityTraits(rawValue: 1 << 6)
    public static let isKeyboardKey = AccessibilityTraits(rawValue: 1 << 7)
    public static let isStaticText = AccessibilityTraits(rawValue: 1 << 8)
    public static let isSummaryElement = AccessibilityTraits(rawValue: 1 << 9)
    public static let updatesFrequently = AccessibilityTraits(rawValue: 1 << 10)
    public static let startsMediaSession = AccessibilityTraits(rawValue: 1 << 11)
    public static let allowsDirectInteraction = AccessibilityTraits(rawValue: 1 << 12)
    public static let causesPageTurn = AccessibilityTraits(rawValue: 1 << 13)
    public static let isModal = AccessibilityTraits(rawValue: 1 << 14)
    public static let isToggle = AccessibilityTraits(rawValue: 1 << 15)
}

/// Defines the behavior for the child elements of the new accessibility element.
public struct AccessibilityChildBehavior: Hashable, Sendable {
    package enum Kind: Sendable { case contain, combine, ignore }
    package let kind: Kind
    /// Any child accessibility element's properties are ignored.
    public static let ignore = AccessibilityChildBehavior(kind: .ignore)
    /// Any child accessibility elements become children of the new accessibility element.
    public static let contain = AccessibilityChildBehavior(kind: .contain)
    /// Any child accessibility element's properties are merged into the new accessibility element.
    public static let combine = AccessibilityChildBehavior(kind: .combine)
}

/// The kind of an accessibility action.
public struct AccessibilityActionKind: Hashable, Sendable {
    package let name: String
    package init(name: String) { self.name = name }
    /// The action performed when the element is activated.
    public static let `default` = AccessibilityActionKind(name: "default")
    /// The action performed on the escape gesture or key.
    public static let escape = AccessibilityActionKind(name: "escape")
    public static let magicTap = AccessibilityActionKind(name: "magicTap")
    public static let delete = AccessibilityActionKind(name: "delete")
    public static let showMenu = AccessibilityActionKind(name: "showMenu")
}

/// The direction of an adjustable action.
public enum AccessibilityAdjustmentDirection: Hashable, Sendable {
    case increment, decrement
}

/// The level of a heading.
public struct AccessibilityHeadingLevel: Hashable, Sendable {
    package let level: Int
    public static let unspecified = AccessibilityHeadingLevel(level: 0)
    public static let h1 = AccessibilityHeadingLevel(level: 1)
    public static let h2 = AccessibilityHeadingLevel(level: 2)
    public static let h3 = AccessibilityHeadingLevel(level: 3)
    public static let h4 = AccessibilityHeadingLevel(level: 4)
    public static let h5 = AccessibilityHeadingLevel(level: 5)
    public static let h6 = AccessibilityHeadingLevel(level: 6)
}

/// The importance of custom content.
public enum AXCustomContentImportance: Hashable, Sendable {
    case `default`, high
}

/// A custom or adjustable action (a class: compared by identity, reflection ignores it).
package final class _AccessibilityAction: Equatable, @unchecked Sendable {
    package enum Kind: Equatable, Sendable {
        case kind(AccessibilityActionKind)
        case named(String)
    }
    package let kind: Kind
    package let run: @MainActor () -> Void
    package init(kind: Kind, run: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.run = run
    }
    /// The name assistive technology sees.
    package var name: String {
        switch kind {
        case .kind(let kind): return kind.name
        case .named(let name): return name
        }
    }
    package static func == (lhs: _AccessibilityAction, rhs: _AccessibilityAction) -> Bool { lhs === rhs }
}

package final class _AdjustableAction: Equatable, @unchecked Sendable {
    package let run: @MainActor (AccessibilityAdjustmentDirection) -> Void
    package init(_ run: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) { self.run = run }
    package static func == (lhs: _AdjustableAction, rhs: _AdjustableAction) -> Bool { lhs === rhs }
}

/// A rotor definition: its label and entries (resolved to elements in the semantics walk).
public final class _AccessibilityRotor: Equatable, @unchecked Sendable {
    public struct Entry: @unchecked Sendable {
        package let label: String
        package let id: AnyHashable?
        package let namespace: Namespace.ID?
        package let prepare: (@MainActor () -> Void)?
        package init(label: String, id: AnyHashable?, namespace: Namespace.ID?, prepare: (@MainActor () -> Void)?) {
            self.label = label
            self.id = id
            self.namespace = namespace
            self.prepare = prepare
        }
    }
    package let label: String
    package let entries: [Entry]
    package init(label: String, entries: [Entry]) {
        self.label = label
        self.entries = entries
    }
    public static func == (lhs: _AccessibilityRotor, rhs: _AccessibilityRotor) -> Bool { lhs === rhs }
}

/// The attributes an accessibility modifier chain sets on a view's element.
package struct AccessibilityAttributes: Equatable, Sendable {
    package var label: String?
    package var hint: String?
    package var value: String?
    package var identifier: String?
    /// Hidden from assistive technology; the outer modifier's answer wins (a label's icon is
    /// hidden beside the title and shown again, reading as the title, by an icon-only style).
    package var hidden: Bool?
    package var addedTraits: AccessibilityTraits = []
    package var removedTraits: AccessibilityTraits = []
    package var children: AccessibilityChildBehavior?
    package var actions: [_AccessibilityAction] = []
    package var adjustable: _AdjustableAction?
    package var sortPriority: Double?
    package var headingLevel: Int?
    package var help: String?
    package var focusable = false
    package var rotors: [_AccessibilityRotor] = []
    /// `accessibilityRotorEntry(id:in:)`: the key rotor entries resolve to this element by.
    package var rotorEntry: _RotorEntryKey?
    package var customContent: [String] = []

    package init() {}

    package var isEmpty: Bool { self == AccessibilityAttributes() }

    /// The outer modifier's attributes win over the inner's; actions and rotors accumulate.
    package func merged(over inner: AccessibilityAttributes) -> AccessibilityAttributes {
        var result = inner
        if let label { result.label = label }
        if let hint { result.hint = hint }
        if let value { result.value = value }
        if let identifier { result.identifier = identifier }
        if let hidden { result.hidden = hidden }
        result.addedTraits.formUnion(addedTraits)
        result.removedTraits.formUnion(removedTraits)
        if let children { result.children = children }
        // The chain is folded from the outermost modifier in, so the inner (this) one's
        // actions, rotors and content come first: declaration order.
        result.actions = actions + inner.actions
        if let adjustable { result.adjustable = adjustable }
        if let sortPriority { result.sortPriority = sortPriority }
        if let headingLevel { result.headingLevel = headingLevel }
        if let help { result.help = help }
        result.focusable = result.focusable || focusable
        result.rotors = rotors + inner.rotors
        if let rotorEntry { result.rotorEntry = rotorEntry }
        result.customContent = customContent + inner.customContent
        return result
    }
}

package struct _RotorEntryKey: Hashable, @unchecked Sendable {
    package let id: AnyHashable
    package let namespace: Namespace.ID
}

public struct _AccessibilityModifier {
    package let attributes: AccessibilityAttributes
    package init(_ attributes: AccessibilityAttributes) { self.attributes = attributes }
}

extension _AccessibilityModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AccessibilityNode(context)
    }
}

extension View {
    private nonisolated func _accessibilityChange(_ change: (inout AccessibilityAttributes) -> Void) -> some View {
        var attributes = AccessibilityAttributes()
        change(&attributes)
        return modifier(_AccessibilityModifier(attributes))
    }

    /// Adds a label to the view that describes its contents.
    nonisolated public func accessibilityLabel(_ label: Text) -> some View { _accessibilityChange { $0.label = label.resolvedString } }
    nonisolated public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> some View { _accessibilityChange { $0.label = Text(labelKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityLabel<S: StringProtocol>(_ label: S) -> some View { _accessibilityChange { $0.label = String(label) } }

    /// Communicates to the user what happens after performing the view's action.
    nonisolated public func accessibilityHint(_ hint: Text) -> some View { _accessibilityChange { $0.hint = hint.resolvedString } }
    nonisolated public func accessibilityHint(_ hintKey: LocalizedStringKey) -> some View { _accessibilityChange { $0.hint = Text(hintKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityHint<S: StringProtocol>(_ hint: S) -> some View { _accessibilityChange { $0.hint = String(hint) } }

    /// Adds a textual description of the value that the view contains.
    nonisolated public func accessibilityValue(_ value: Text) -> some View { _accessibilityChange { $0.value = value.resolvedString } }
    nonisolated public func accessibilityValue(_ valueKey: LocalizedStringKey) -> some View { _accessibilityChange { $0.value = Text(valueKey).resolvedString } }
    @_disfavoredOverload
    nonisolated public func accessibilityValue<S: StringProtocol>(_ value: S) -> some View { _accessibilityChange { $0.value = String(value) } }

    /// Uses the string you specify to identify the view (tests, automation).
    nonisolated public func accessibilityIdentifier(_ identifier: String) -> some View { _accessibilityChange { $0.identifier = identifier } }

    /// Specifies whether to hide this view from system accessibility features.
    nonisolated public func accessibilityHidden(_ hidden: Bool) -> some View { _accessibilityChange { $0.hidden = hidden } }
    /// Accepted: the browser has no Smart Invert to exempt the view from.
    nonisolated public func accessibilityIgnoresInvertColors(_ active: Bool = true) -> some View { self }

    /// Adds the given traits to the view.
    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { _accessibilityChange { $0.addedTraits = traits } }

    /// Removes the given traits from this view.
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { _accessibilityChange { $0.removedTraits = traits } }

    /// Creates a new accessibility element, or modifies the existing one, for the view.
    nonisolated public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { _accessibilityChange { $0.children = children } }

    // MARK: Actions

    /// Adds an accessibility action of a kind to the view (the default kind activates the element).
    nonisolated public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping @MainActor () -> Void) -> some View {
        _accessibilityChange { $0.actions = [_AccessibilityAction(kind: .kind(actionKind), run: handler)] }
    }

    /// Adds a named custom action.
    nonisolated public func accessibilityAction(named name: Text, _ handler: @escaping @MainActor () -> Void) -> some View {
        _accessibilityChange { $0.actions = [_AccessibilityAction(kind: .named(name.resolvedString), run: handler)] }
    }
    nonisolated public func accessibilityAction(named nameKey: LocalizedStringKey, _ handler: @escaping @MainActor () -> Void) -> some View {
        _accessibilityChange { $0.actions = [_AccessibilityAction(kind: .named(Text(nameKey).resolvedString), run: handler)] }
    }
    @_disfavoredOverload
    nonisolated public func accessibilityAction<S: StringProtocol>(named name: S, _ handler: @escaping @MainActor () -> Void) -> some View {
        _accessibilityChange { $0.actions = [_AccessibilityAction(kind: .named(String(name)), run: handler)] }
    }

    /// Adds a custom action named by its label view (the label's text; "Action" otherwise).
    nonisolated public func accessibilityAction<Label: View>(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) -> some View {
        _accessibilityChange { $0.actions = [_AccessibilityAction(kind: .named(_staticText(of: label()) ?? "Action"), run: action)] }
    }

    /// Adds custom actions from the buttons in `content` (each button's title names its action).
    nonisolated public func accessibilityActions<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        modifier(_AccessibilityActionsModifier(content: AnyView(content())))
    }

    /// Makes the element adjustable: assistive technology increments and decrements it.
    nonisolated public func accessibilityAdjustableAction(_ handler: @escaping @MainActor (AccessibilityAdjustmentDirection) -> Void) -> some View {
        _accessibilityChange { $0.adjustable = _AdjustableAction(handler) }
    }

    // MARK: Order, headings, focus and content

    /// Sets the sort priority of the element among its siblings (higher first; 0 by default).
    nonisolated public func accessibilitySortPriority(_ sortPriority: Double) -> some View { _accessibilityChange { $0.sortPriority = sortPriority } }

    /// Makes the element a heading of the given level.
    nonisolated public func accessibilityHeading(_ level: AccessibilityHeadingLevel) -> some View {
        _accessibilityChange { $0.addedTraits = .isHeader; $0.headingLevel = level.level == 0 ? nil : level.level }
    }

    /// Replaces the view's accessibility elements with those of `representation` (laid out over
    /// the view, never painted).
    nonisolated public func accessibilityRepresentation<V: View>(@ViewBuilder representation: () -> V) -> some View {
        modifier(_AccessibilityReplacementModifier(replacement: AnyView(representation()), container: false))
    }

    /// Makes the view a container whose accessibility children are those of `children`.
    nonisolated public func accessibilityChildren<V: View>(@ViewBuilder children: () -> V) -> some View {
        modifier(_AccessibilityReplacementModifier(replacement: AnyView(children()), container: true))
    }

    /// Ties assistive technology's focus on the view to a Boolean focus state.
    nonisolated public func accessibilityFocused(_ condition: AccessibilityFocusState<Bool>.Binding) -> some View {
        modifier(_FocusedModifier(box: condition.box, value: true))._accessibilityChange { $0.focusable = true }
    }

    /// Ties assistive technology's focus on the view to a focus state value.
    nonisolated public func accessibilityFocused<Value: Hashable>(_ binding: AccessibilityFocusState<Value?>.Binding, equals value: Value) -> some View {
        modifier(_FocusedModifier(box: binding.box, value: value))._accessibilityChange { $0.focusable = true }
    }

    /// Adds custom content assistive technology can read on request.
    nonisolated public func accessibilityCustomContent(_ label: Text, _ value: Text, importance: AXCustomContentImportance = .default) -> some View {
        _accessibilityChange { $0.customContent = ["\(label.resolvedString): \(value.resolvedString)"] }
    }
    nonisolated public func accessibilityCustomContent(_ labelKey: LocalizedStringKey, _ value: Text, importance: AXCustomContentImportance = .default) -> some View {
        _accessibilityChange { $0.customContent = ["\(Text(labelKey).resolvedString): \(value.resolvedString)"] }
    }
    nonisolated public func accessibilityCustomContent<V: StringProtocol>(_ labelKey: LocalizedStringKey, _ value: V, importance: AXCustomContentImportance = .default) -> some View {
        _accessibilityChange { $0.customContent = ["\(Text(labelKey).resolvedString): \(value)"] }
    }
    @_disfavoredOverload
    nonisolated public func accessibilityCustomContent<L: StringProtocol, V: StringProtocol>(_ label: L, _ value: V, importance: AXCustomContentImportance = .default) -> some View {
        _accessibilityChange { $0.customContent = ["\(label): \(value)"] }
    }

    // MARK: Rotors

    /// Adds a rotor: a named list of entries assistive technology can navigate (the canvas host
    /// exposes it as a navigation landmark with a link per entry).
    nonisolated public func accessibilityRotor<Content: AccessibilityRotorContent>(_ label: Text, @AccessibilityRotorContentBuilder entries: () -> Content) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: label.resolvedString, entries: entries()._rotorEntries)] }
    }
    nonisolated public func accessibilityRotor<Content: AccessibilityRotorContent>(_ labelKey: LocalizedStringKey, @AccessibilityRotorContentBuilder entries: () -> Content) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: Text(labelKey).resolvedString, entries: entries()._rotorEntries)] }
    }
    @_disfavoredOverload
    nonisolated public func accessibilityRotor<L: StringProtocol, Content: AccessibilityRotorContent>(_ label: L, @AccessibilityRotorContentBuilder entries: () -> Content) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: String(label), entries: entries()._rotorEntries)] }
    }
    nonisolated public func accessibilityRotor<Content: AccessibilityRotorContent>(_ systemRotor: AccessibilitySystemRotor, @AccessibilityRotorContentBuilder entries: () -> Content) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: systemRotor.name, entries: entries()._rotorEntries)] }
    }

    /// Adds a rotor whose entries are `entries`, labelled by `entryLabel`; each entry points at
    /// the view marked `accessibilityRotorEntry(id:in:)` with its id.
    nonisolated public func accessibilityRotor<EntryModel: Identifiable>(_ label: Text, entries: [EntryModel], entryLabel: KeyPath<EntryModel, String>) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: label.resolvedString, entries: entries.map { .init(label: $0[keyPath: entryLabel], id: AnyHashable($0.id), namespace: nil, prepare: nil) })] }
    }
    nonisolated public func accessibilityRotor<EntryModel: Identifiable>(_ labelKey: LocalizedStringKey, entries: [EntryModel], entryLabel: KeyPath<EntryModel, String>) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: Text(labelKey).resolvedString, entries: entries.map { .init(label: $0[keyPath: entryLabel], id: AnyHashable($0.id), namespace: nil, prepare: nil) })] }
    }
    @_disfavoredOverload
    nonisolated public func accessibilityRotor<L: StringProtocol, EntryModel: Identifiable>(_ label: L, entries: [EntryModel], entryLabel: KeyPath<EntryModel, String>) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: String(label), entries: entries.map { .init(label: $0[keyPath: entryLabel], id: AnyHashable($0.id), namespace: nil, prepare: nil) })] }
    }
    nonisolated public func accessibilityRotor<EntryModel: Identifiable>(_ systemRotor: AccessibilitySystemRotor, entries: [EntryModel], entryLabel: KeyPath<EntryModel, String>) -> some View {
        _accessibilityChange { $0.rotors = [_AccessibilityRotor(label: systemRotor.name, entries: entries.map { .init(label: $0[keyPath: entryLabel], id: AnyHashable($0.id), namespace: nil, prepare: nil) })] }
    }

    /// Marks the view as the target of rotor entries with `id` in `namespace`.
    nonisolated public func accessibilityRotorEntry<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        _accessibilityChange { $0.rotorEntry = _RotorEntryKey(id: AnyHashable(id), namespace: namespace) }
    }
}

/// The text of a label view when it is a `Text` or a `Label` (for naming actions).
nonisolated package func _staticText<V: View>(of view: V) -> String? {
    if let text = view as? Text { return text.resolvedString }
    if let titled = view as? any _TitleProviding { return titled._title }
    return nil
}

/// A view whose title is known statically (`Label`).
public protocol _TitleProviding {
    nonisolated var _title: String { get }
}

/// `accessibilityActions`: the buttons in the content become custom actions.
public struct _AccessibilityActionsModifier {
    package let content: AnyView
}

extension _AccessibilityActionsModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AccessibilityActionsNode(context)
    }
}

/// `accessibilityRepresentation` and `accessibilityChildren`: another view's elements stand in
/// for (or under) the view's.
public struct _AccessibilityReplacementModifier {
    package let replacement: AnyView
    /// Whether the view stays an element (a container) above the replacement's elements.
    package let container: Bool
}

extension _AccessibilityReplacementModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AccessibilityReplacementNode(context)
    }
}

// MARK: - Accessibility focus

/// A property wrapper that tracks whether assistive technology has focus on a view (here the
/// overlay element's focus, which is the keyboard focus).
@propertyWrapper
public struct AccessibilityFocusState<Value: Hashable>: DynamicProperty {
    package var box: _FocusStateBox<Value>?
    package let initial: Value

    public init() where Value == Bool { initial = false }
    public init<T: Hashable>() where Value == T? { initial = nil }

    public var wrappedValue: Value {
        get { box?.value ?? initial }
        nonmutating set { box?.set(newValue) }
    }

    public var projectedValue: Binding { Binding(box: box, initial: initial) }

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

// MARK: - Rotors

/// Content of a rotor: entries, built by `AccessibilityRotorContentBuilder`, or a custom type
/// whose `body` is.
@MainActor @preconcurrency
public protocol AccessibilityRotorContent {
    associatedtype Body: AccessibilityRotorContent
    @AccessibilityRotorContentBuilder var body: Body { get }
    /// The resolved entries (primitive content overrides this). Nonisolated as the rotor
    /// modifiers resolve it eagerly; a conformer's `body` is main-actor isolated, like Apple's.
    nonisolated var _rotorEntries: [_AccessibilityRotor.Entry] { get }
}

extension AccessibilityRotorContent {
    nonisolated public var _rotorEntries: [_AccessibilityRotor.Entry] {
        nonisolated(unsafe) let content = self
        return _readOnMainActor { content.body._rotorEntries }
    }
}

extension AccessibilityRotorContent where Body == Never {
    /// Primitive content (entries) has no body; its `_rotorEntries` is the content.
    public var body: Never { return fatalError() }
}

extension Never: AccessibilityRotorContent {
    nonisolated public var _rotorEntries: [_AccessibilityRotor.Entry] { [] }
}

/// One rotor entry: a label and the id of the view it points at (marked with
/// `accessibilityRotorEntry(id:in:)`); `prepare` runs before focus moves there.
public struct AccessibilityRotorEntry<ID: Hashable>: AccessibilityRotorContent {
    public typealias Body = Never
    nonisolated package let label: String
    nonisolated(unsafe) package let id: ID?
    nonisolated package let namespace: Namespace.ID?
    nonisolated(unsafe) package let prepare: (@MainActor () -> Void)?

    public init(_ label: Text, id: ID, in namespace: Namespace.ID? = nil, prepare: @escaping @MainActor () -> Void = {}) {
        self.label = label.resolvedString
        self.id = id
        self.namespace = namespace
        self.prepare = prepare
    }
    public init(_ labelKey: LocalizedStringKey, id: ID, in namespace: Namespace.ID? = nil, prepare: @escaping @MainActor () -> Void = {}) {
        self.init(Text(labelKey), id: id, in: namespace, prepare: prepare)
    }
    @_disfavoredOverload
    public init<L: StringProtocol>(_ label: L, id: ID, in namespace: Namespace.ID? = nil, prepare: @escaping @MainActor () -> Void = {}) {
        self.init(Text(String(label)), id: id, in: namespace, prepare: prepare)
    }
    /// An entry over a text range (accepted; it points at no element).
    public init(_ label: Text, textRange: Range<String.Index>, prepare: @escaping @MainActor () -> Void = {}) where ID == Never {
        self.label = label.resolvedString
        self.id = nil
        self.namespace = nil
        self.prepare = prepare
    }

    nonisolated public var _rotorEntries: [_AccessibilityRotor.Entry] {
        nonisolated(unsafe) let id = id
        return [.init(label: label, id: id.map { AnyHashable($0) }, namespace: namespace, prepare: prepare)]
    }
}

/// Several rotor entries.
public struct _RotorEntries: AccessibilityRotorContent {
    public typealias Body = Never
    nonisolated public let _rotorEntries: [_AccessibilityRotor.Entry]
    nonisolated public init(_rotorEntries: [_AccessibilityRotor.Entry]) { self._rotorEntries = _rotorEntries }
}

@resultBuilder
public struct AccessibilityRotorContentBuilder {
    public static func buildBlock(_ components: any AccessibilityRotorContent...) -> _RotorEntries { _RotorEntries(_rotorEntries: components.flatMap(\._rotorEntries)) }
    public static func buildExpression<C: AccessibilityRotorContent>(_ expression: C) -> any AccessibilityRotorContent { expression }
    public static func buildOptional(_ component: (any AccessibilityRotorContent)?) -> any AccessibilityRotorContent { component ?? _RotorEntries(_rotorEntries: []) }
    public static func buildEither(first component: any AccessibilityRotorContent) -> any AccessibilityRotorContent { component }
    public static func buildEither(second component: any AccessibilityRotorContent) -> any AccessibilityRotorContent { component }
    public static func buildArray(_ components: [any AccessibilityRotorContent]) -> any AccessibilityRotorContent { _RotorEntries(_rotorEntries: components.flatMap(\._rotorEntries)) }
}

/// The system rotors (named after their content).
public struct AccessibilitySystemRotor: Hashable, Sendable {
    package let name: String
    public static let links = AccessibilitySystemRotor(name: "Links")
    public static let visitedLinks = AccessibilitySystemRotor(name: "Visited Links")
    public static let headings = AccessibilitySystemRotor(name: "Headings")
    public static let boldText = AccessibilitySystemRotor(name: "Bold Text")
    public static let italicText = AccessibilitySystemRotor(name: "Italic Text")
    public static let underlineText = AccessibilitySystemRotor(name: "Underlined Text")
    public static let misspelledWords = AccessibilitySystemRotor(name: "Misspelled Words")
    public static let images = AccessibilitySystemRotor(name: "Images")
    public static let textFields = AccessibilitySystemRotor(name: "Text Fields")
    public static let tables = AccessibilitySystemRotor(name: "Tables")
    public static let lists = AccessibilitySystemRotor(name: "Lists")
    public static let landmarks = AccessibilitySystemRotor(name: "Landmarks")
    public static func headings(level: AccessibilityHeadingLevel) -> AccessibilitySystemRotor { AccessibilitySystemRotor(name: "Headings Level \(level.level)") }
}

// MARK: - System accessibility settings

package struct ReduceMotionKey: EnvironmentKey { package static let defaultValue = false }
package struct ReduceTransparencyKey: EnvironmentKey { package static let defaultValue = false }
package struct DifferentiateWithoutColorKey: EnvironmentKey { package static let defaultValue = false }
package struct InvertColorsKey: EnvironmentKey { package static let defaultValue = false }

extension EnvironmentValues {
    /// Whether the system prefers reduced motion (`prefers-reduced-motion` on the web, set by the
    /// host through `Runtime.hostReducesMotion`); views decide what to leave still.
    public var accessibilityReduceMotion: Bool {
        get { self[ReduceMotionKey.self] }
        set { self[ReduceMotionKey.self] = newValue }
    }
    /// Whether the system prefers reduced transparency (never reported by the web hosts).
    public var accessibilityReduceTransparency: Bool {
        get { self[ReduceTransparencyKey.self] }
        set { self[ReduceTransparencyKey.self] = newValue }
    }
    public var accessibilityDifferentiateWithoutColor: Bool {
        get { self[DifferentiateWithoutColorKey.self] }
        set { self[DifferentiateWithoutColorKey.self] = newValue }
    }
    public var accessibilityInvertColors: Bool {
        get { self[InvertColorsKey.self] }
        set { self[InvertColorsKey.self] = newValue }
    }
}

// MARK: - Deprecated `accessibility(…)` spellings

/// The iOS 13 forms, still common in shipping apps; each forwards to its `accessibility…` successor.
extension View {
    nonisolated public func accessibility(hidden: Bool) -> some View { accessibilityHidden(hidden) }
    nonisolated public func accessibility(label: Text) -> some View { accessibilityLabel(label) }
    nonisolated public func accessibility(hint: Text) -> some View { accessibilityHint(hint) }
    nonisolated public func accessibility(value: Text) -> some View { accessibilityValue(value) }
    nonisolated public func accessibility(identifier: String) -> some View { accessibilityIdentifier(identifier) }
    nonisolated public func accessibility(addTraits traits: AccessibilityTraits) -> some View { accessibilityAddTraits(traits) }
    nonisolated public func accessibility(removeTraits traits: AccessibilityTraits) -> some View { accessibilityRemoveTraits(traits) }
    nonisolated public func accessibility(sortPriority: Double) -> some View { accessibilitySortPriority(sortPriority) }
    nonisolated public func accessibility(selectionIdentifier: AnyHashable) -> some View { self }
    nonisolated public func accessibility(activationPoint: UnitPoint) -> some View { self }
    nonisolated public func accessibility(activationPoint: CGPoint) -> some View { self }
}
