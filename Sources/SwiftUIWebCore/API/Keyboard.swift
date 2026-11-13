// Keyboard input (Docs/elements/Keyboard.md): key equivalents and modifiers, `onKeyPress`, the
// move/exit/delete commands, `keyboardShortcut` and `focusable`. Hosts feed key events to
// `Runtime.keyDown` and `keyUp`; the runtime dispatches them from the focused view outwards
// (Runtime/KeyboardNodes.swift). The responder commands are in Commands.swift.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A key press the user made while a view had focus.
public struct KeyPress: Sendable {
    /// The phases of a key press.
    public struct Phases: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let down = Phases(rawValue: 1)
        public static let `repeat` = Phases(rawValue: 2)
        public static let up = Phases(rawValue: 4)
        public static let all: Phases = [.down, .repeat, .up]
    }

    /// Whether a key press handler consumed the press.
    public enum Result: Sendable {
        case handled
        case ignored
    }

    public let phase: Phases
    public let key: KeyEquivalent
    public let characters: String
    public let modifiers: EventModifiers

    public init(phase: Phases, key: KeyEquivalent, characters: String, modifiers: EventModifiers) {
        self.phase = phase
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
    }
}

/// Directional navigation commands (the arrow keys on a focused view).
public enum MoveCommandDirection: Hashable, Sendable {
    case up, down, left, right
}

/// Keyboard shortcuts that trigger a control anywhere in the window.
public struct KeyboardShortcut: Hashable, Sendable {
    /// Whether a shortcut mirrors in right-to-left layouts (accepted; not applied here).
    public struct Localization: Hashable, Sendable {
        package let kind: Int
        public static let automatic = Localization(kind: 0)
        public static let withoutMirroring = Localization(kind: 1)
        public static let custom = Localization(kind: 2)
    }

    public var key: KeyEquivalent
    public var modifiers: EventModifiers
    public var localization: Localization

    public init(_ key: KeyEquivalent, modifiers: EventModifiers = .command, localization: Localization = .automatic) {
        self.key = key
        self.modifiers = modifiers
        self.localization = localization
    }

    /// The Return key: the default button of a window or presentation.
    public static let defaultAction = KeyboardShortcut(.return, modifiers: [])
    /// The Escape key: the cancel button.
    public static let cancelAction = KeyboardShortcut(.escape, modifiers: [])

    package func matches(_ press: KeyPress) -> Bool {
        press.key == key && press.modifiers.shortcutModifiers == modifiers.shortcutModifiers
    }
}

/// The ways a focusable view can be interacted with (accepted; every focusable view here takes
/// key presses).
public struct FocusInteractions: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let activate = FocusInteractions(rawValue: 1)
    public static let edit = FocusInteractions(rawValue: 2)
    public static let automatic: FocusInteractions = [.activate, .edit]
}

// MARK: - Boxes (plain classes so field reflection ignores them)

package final class _KeyPressBox {
    package let action: @MainActor (KeyPress) -> KeyPress.Result
    package init(_ action: @escaping @MainActor (KeyPress) -> KeyPress.Result) { self.action = action }
}

package final class _MoveCommandBox {
    package let action: @MainActor (MoveCommandDirection) -> Void
    package init(_ action: @escaping @MainActor (MoveCommandDirection) -> Void) { self.action = action }
}

// MARK: - Modifiers

/// `onKeyPress`: runs `action` for key presses on the focused view (or one inside it).
public struct _KeyPressModifier {
    /// The keys that trigger the action; nil for any key.
    package let keys: Set<KeyEquivalent>?
    /// The characters that trigger the action (`onKeyPress(characters:)`); nil for any.
    package let characters: CharacterSet?
    package let phases: KeyPress.Phases
    package let action: _KeyPressBox

    package init(keys: Set<KeyEquivalent>?, characters: CharacterSet? = nil, phases: KeyPress.Phases, action: _KeyPressBox) {
        self.keys = keys
        self.characters = characters
        self.phases = phases
        self.action = action
    }
}

extension _KeyPressModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        KeyPressNode(context)
    }
}

/// `onMoveCommand`, `onExitCommand`, `onDeleteCommand`.
public struct _CommandModifier {
    package enum Kind {
        case move(_MoveCommandBox)
        case exit(_ActionBox)
        case delete(_ActionBox)
    }
    package let kind: Kind
}

extension _CommandModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        CommandNode(context)
    }
}

/// `keyboardShortcut`: the shortcut activates the first control in the view.
public struct _KeyboardShortcutModifier {
    package let shortcut: KeyboardShortcut?
}

extension _KeyboardShortcutModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        KeyboardShortcutNode(context)
    }
}

/// `focusable`: the view becomes a focus target (a focusable element in the accessibility
/// overlay) that receives key presses.
public struct _FocusableModifier {
    package let isFocusable: Bool
}

extension _FocusableModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusableNode(context)
    }
}

extension View {
    /// Performs an action when the user presses `key` while the view has focus.
    nonisolated public func onKeyPress(_ key: KeyEquivalent, action: @escaping @MainActor () -> KeyPress.Result) -> some View {
        nonisolated(unsafe) let action = action   // Swift 5 mode (decision 0027)
        return modifier(_KeyPressModifier(keys: [key], phases: [.down, .repeat], action: _KeyPressBox { _ in action() }))
    }

    /// Performs an action for the given phases of a press of `key` while the view has focus.
    nonisolated public func onKeyPress(_ key: KeyEquivalent, phases: KeyPress.Phases, action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: [key], phases: phases, action: _KeyPressBox(action)))
    }

    /// Performs an action for the given phases of any key press while the view has focus.
    nonisolated public func onKeyPress(phases: KeyPress.Phases, action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: nil, phases: phases, action: _KeyPressBox(action)))
    }

    /// Performs an action for any key press while the view has focus.
    nonisolated public func onKeyPress(action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: nil, phases: [.down, .repeat], action: _KeyPressBox(action)))
    }

    /// Performs an action for presses whose characters are all in `characters` while the view
    /// has focus.
    nonisolated public func onKeyPress(characters: CharacterSet, phases: KeyPress.Phases = [.down, .repeat],
                                       action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: nil, characters: characters, phases: phases, action: _KeyPressBox(action)))
    }

    /// Performs an action for presses of any of `keys` while the view has focus.
    nonisolated public func onKeyPress(keys: Set<KeyEquivalent>, phases: KeyPress.Phases = [.down, .repeat],
                                       action: @escaping @MainActor (KeyPress) -> KeyPress.Result) -> some View {
        modifier(_KeyPressModifier(keys: keys, phases: phases, action: _KeyPressBox(action)))
    }

    /// Performs an action for the arrow keys while the view has focus.
    nonisolated public func onMoveCommand(perform action: @escaping @MainActor (MoveCommandDirection) -> Void) -> some View {
        modifier(_CommandModifier(kind: .move(_MoveCommandBox(action))))
    }

    /// Performs an action for the Escape key while the view has focus.
    nonisolated public func onExitCommand(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(_CommandModifier(kind: .exit(_ActionBox(action))))
    }

    /// Performs an action for the Delete key while the view has focus.
    nonisolated public func onDeleteCommand(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(_CommandModifier(kind: .delete(_ActionBox(action))))
    }

    /// Assigns a keyboard shortcut to the control in this view.
    nonisolated public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        modifier(_KeyboardShortcutModifier(shortcut: KeyboardShortcut(key, modifiers: modifiers)))
    }

    nonisolated public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers, localization: KeyboardShortcut.Localization) -> some View {
        modifier(_KeyboardShortcutModifier(shortcut: KeyboardShortcut(key, modifiers: modifiers, localization: localization)))
    }

    nonisolated public func keyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        modifier(_KeyboardShortcutModifier(shortcut: shortcut))
    }

    nonisolated public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
        modifier(_KeyboardShortcutModifier(shortcut: shortcut))
    }

    /// Makes the view a focus target that can take key presses.
    nonisolated public func focusable(_ isFocusable: Bool = true) -> some View {
        modifier(_FocusableModifier(isFocusable: isFocusable))
    }

    nonisolated public func focusable(_ isFocusable: Bool = true, interactions: FocusInteractions) -> some View {
        modifier(_FocusableModifier(isFocusable: isFocusable))
    }
}
