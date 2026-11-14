// Keyboard runtime (Docs/elements/Keyboard.md): general keyboard focus (any interactive or
// `focusable` view, mirrored with the host's focused overlay element), key dispatch from the
// focused view outwards through `onKeyPress` and command modifiers, then the open menu, then
// keyboard shortcuts, then Escape for presentations; the focus ring.

/// A node that takes key presses (lists, `onKeyPress`, commands).
@MainActor
package protocol _KeyHandling: AnyObject {
    /// Returns whether the press was consumed.
    func handleKey(_ press: KeyPress) -> Bool
}

@MainActor
private var nextKeyboardIdentifier = 7_000_000

/// An interactive node whose only business with a press is taking focus from it (`focusable`):
/// the press itself belongs to the nearest interactive ancestor, as a focusable view in
/// SwiftUI does not swallow the drag or tap gesture of the view around it (a 2048 board that
/// is `focusable()` for its arrow keys still takes its swipes).
@MainActor
package protocol _FocusOnly: AnyObject {}

/// A node that takes key releases (`onKeyPress` with the up phase).
@MainActor
package protocol _KeyUpHandling: AnyObject {
    func handleKeyUp(_ press: KeyPress) -> Bool
}

/// `onKeyPress`: transparent to layout; handles presses of its keys on the way out.
@MainActor
package final class KeyPressNode<Content: View>: UnaryLayoutModifierNode<Content, _KeyPressModifier>, _KeyHandling, _KeyUpHandling {
    package func handleKey(_ press: KeyPress) -> Bool {
        guard modifier.phases.contains(press.phase) else { return false }
        if let keys = modifier.keys, !keys.contains(press.key) { return false }
        if let characters = modifier.characters {
            guard !press.characters.isEmpty, press.characters.unicodeScalars.allSatisfy(characters.contains) else { return false }
        }
        return modifier.action.action(press) == .handled
    }

    package func handleKeyUp(_ press: KeyPress) -> Bool { handleKey(press) }
}

/// `onMoveCommand`/`onExitCommand`/`onDeleteCommand`: transparent to layout.
@MainActor
package final class CommandNode<Content: View>: UnaryLayoutModifierNode<Content, _CommandModifier>, _KeyHandling {
    package func handleKey(_ press: KeyPress) -> Bool {
        guard press.modifiers.shortcutModifiers.isEmpty else { return false }
        switch modifier.kind {
        case .move(let box):
            let direction: MoveCommandDirection
            switch press.key {
            case .upArrow: direction = .up
            case .downArrow: direction = .down
            case .leftArrow: direction = .left
            case .rightArrow: direction = .right
            default: return false
            }
            box.action(direction)
        case .exit(let box):
            guard press.key == .escape else { return false }
            box.run()
        case .delete(let box):
            guard press.key == .delete || press.key == .deleteForward else { return false }
            box.run()
        }
        return true
    }
}

/// `keyboardShortcut`: transparent to layout; the runtime asks every shortcut node whether a
/// press matches and activates the first control inside.
@MainActor
package final class KeyboardShortcutNode<Content: View>: UnaryLayoutModifierNode<Content, _KeyboardShortcutModifier> {
    package func matches(_ press: KeyPress) -> Bool {
        guard environment.isEnabled, let shortcut = modifier.shortcut else { return false }
        return shortcut.matches(press)
    }

    package func activate() {
        guard let control = descendants(where: { $0.isInteractiveNode && !($0 is FocusableNode<Content>) }).first as? any _Interactive else { return }
        control.pressBegan()
        control.pressEnded(inside: true)
    }
}

/// `focusable`: transparent to layout; a focusable element in the overlay whose descendants stay
/// their own elements; a press focuses it.
@MainActor
package final class FocusableNode<Content: View>: UnaryLayoutModifierNode<Content, _FocusableModifier>, _Interactive, _FocusOnly {
    package let identifier: Int

    override package init(_ context: _NodeContext<ModifiedContent<Content, _FocusableModifier>>) {
        nextKeyboardIdentifier += 1
        identifier = nextKeyboardIdentifier
        super.init(context)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, modifier.isFocusable else { return }
        runtime.focus(semanticsIdentifier: identifier, keyboard: false)
    }

    package var semantics: SemanticsNode {
        let label = descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        var node = SemanticsNode(role: .group, label: label, frame: frameInRoot, identifier: identifier)
        node.isFocusable = modifier.isFocusable
        return node
    }
    package var exposesChildren: Bool { true }
}

extension Runtime {
    /// The interactive node with a semantics identifier, in the tree or a presentation.
    package func interactiveNode(semanticsIdentifier: Int) -> (ViewNode & _Interactive)? {
        interactiveNodes.first { $0.semantics.identifier == semanticsIdentifier }
    }

    /// Moves keyboard focus to the element with `semanticsIdentifier` (or nowhere). Text fields
    /// take the text-field path (the host focuses their input); `keyboard` says whether the
    /// focus ring shows (a click focuses without one, like `:focus-visible`).
    public func focus(semanticsIdentifier: Int?, keyboard: Bool = true) {
        if let semanticsIdentifier, interactiveNode(semanticsIdentifier: semanticsIdentifier) is TextFieldNode {
            focusTextField(semanticsIdentifier)
            return
        }
        // An element inside a hosted tree: the tree makes it the first responder, and a text
        // field there reports back through `focusTextField`.
        if let semanticsIdentifier, let tree = platformTree(handling: semanticsIdentifier) {
            tree.focus(semanticsIdentifier: semanticsIdentifier)
            if tree.focusedTextFieldIdentifier == semanticsIdentifier { return }
        }
        guard focusedIdentifier != semanticsIdentifier || focusVisible != keyboard || focusedTextFieldIdentifier != nil else { return }
        focusedTextFieldIdentifier = nil
        focusedIdentifier = semanticsIdentifier
        focusVisible = keyboard
        notifyFocusChanged()
        requestRedraw()
    }

    /// The element lost the host's focus.
    public func blur(semanticsIdentifier: Int) {
        platformTree(handling: semanticsIdentifier)?.blur(semanticsIdentifier: semanticsIdentifier)
        if focusedIdentifier == semanticsIdentifier { focus(semanticsIdentifier: nil) }
    }

    /// The elements Tab moves focus through, in paint order: controls, text fields, focusable
    /// views and selectable lists (static text, images and plain groups are skipped), the
    /// topmost presentation's alone while one is up. The elements of a `focusSection` stay
    /// together where the section's first element falls.
    public var focusOrder: [Int] {
        let nodes: [ViewNode & _Interactive]
        if let top = presentations.last, top.isModal {
            nodes = top.interactiveNodes
        } else if let keyWindow, keyWindow.isMounted, presentations.contains(where: { $0 === keyWindow }) {
            // The secondary window a press last landed in keeps the keyboard (sw-windows).
            nodes = keyWindow.interactiveNodes
        } else {
            nodes = interactiveNodes
        }
        let focusable: [(identifier: Int, section: ViewNode?)] = nodes.compactMap { node in
            let semantics = node.semantics
            switch semantics.role {
            case .text, .heading, .image, .group, .list: guard semantics.isFocusable else { return nil }
            default: break
            }
            return (semantics.identifier, node.nearestAncestor(where: { $0 is any _FocusSectionMarking }))
        }
        guard focusable.contains(where: { $0.section != nil }) else { return focusable.map(\.identifier) }
        var order: [Int] = []
        var emitted: [ObjectIdentifier] = []
        for entry in focusable {
            guard let section = entry.section else { order.append(entry.identifier); continue }
            let key = ObjectIdentifier(section)
            guard !emitted.contains(key) else { continue }
            emitted.append(key)
            order += focusable.filter { $0.section === section }.map(\.identifier)
        }
        return order
    }

    /// Moves keyboard focus to the next (or previous) element in `focusOrder`, wrapping (focus
    /// entering a `focusScope` lands on its preferred default); returns whether anything took
    /// focus.
    @discardableResult
    public func moveFocus(forward: Bool = true) -> Bool {
        let order = focusOrder
        guard !order.isEmpty else { return false }
        let current = focusedIdentifier.flatMap { order.firstIndex(of: $0) }
        let next: Int
        if let current {
            next = (current + (forward ? 1 : order.count - 1)) % order.count
        } else {
            next = forward ? 0 : order.count - 1
        }
        focus(semanticsIdentifier: focusTarget(entering: order[next], from: focusedIdentifier), keyboard: true)
        return true
    }

    /// A key came up: `onKeyPress` handlers with the up phase on the focused view and its
    /// ancestors. Returns whether one consumed it.
    @discardableResult
    public func keyUp(_ event: KeyEvent) -> Bool {
        lastKeyTime = event.time
        let press = KeyPress(phase: .up, key: event.key, characters: event.characters, modifiers: event.modifiers)
        guard let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) else { return false }
        var current: ViewNode? = focused
        while let node = current {
            if let handler = node as? any _KeyUpHandling, handler.handleKeyUp(press) {
                setNeedsDisplay()
                return true
            }
            current = node.parent
        }
        return false
    }

    /// A key went down. Dispatch: the focused view and its ancestors (`onKeyPress`, the move/
    /// exit/delete commands, list navigation), the open menu, keyboard shortcuts, then Escape
    /// dismissing the topmost presentation. Returns whether the press was consumed (hosts then
    /// prevent the browser's default).
    @discardableResult
    public func keyDown(_ event: KeyEvent) -> Bool {
        lastKeyTime = event.time
        let press = KeyPress(phase: event.isRepeat ? .repeat : .down, key: event.key, characters: event.characters, modifiers: event.modifiers)
        if let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) {
            var current: ViewNode? = focused
            while let node = current {
                if let handler = node as? any _KeyHandling, handler.handleKey(press) {
                    setNeedsDisplay()
                    return true
                }
                current = node.parent
            }
        }
        // Escape runs the focused element's escape accessibility action.
        if press.key == .escape, press.modifiers.shortcutModifiers.isEmpty, let focusedIdentifier,
           performAccessibilityAction(semanticsIdentifier: focusedIdentifier, kind: .escape) {
            setNeedsDisplay()
            return true
        }
        // The edit keys as responder commands (`onCommand`, `onCopyCommand` and the like), then
        // ⌘C / ⌘X / ⌘V for copyable, cuttable and paste destinations around the focused node.
        if let selector = standardSelector(for: press), performCommand(selector) { return true }
        if handlePasteboardKey(press) { setNeedsDisplay(); return true }
        // An open menu takes the keys next; then Tab moves focus and Space or Return activates the
        // focused control (a consumed press keeps a browser overlay button from clicking as well).
        if let top = presentations.last, top.kind.isMenu, top.handleKey(press) { return true }
        // Arrows adjust a focused slider or stepper (Up/Right increment, Down/Left decrement), or
        // an element with an adjustable accessibility action.
        if press.modifiers.shortcutModifiers.isEmpty, let focusedIdentifier {
            let increment: Bool?
            switch press.key {
            case .upArrow, .rightArrow: increment = true
            case .downArrow, .leftArrow: increment = false
            default: increment = nil
            }
            if let increment {
                if performAdjustableAction(semanticsIdentifier: focusedIdentifier, increment: increment) { setNeedsDisplay(); return true }
                if let adjustable = interactiveNode(semanticsIdentifier: focusedIdentifier) as? any _Adjustable {
                    adjustable.adjust(increment: increment)
                    setNeedsDisplay()
                    return true
                }
            }
        }
        if press.key == .tab, press.modifiers.shortcutModifiers.isSubset(of: [.shift]) {
            return moveFocus(forward: !press.modifiers.contains(.shift))
        }
        if press.key == .space || press.key == .return, press.modifiers.shortcutModifiers.isEmpty,
           let focusedIdentifier, focusedTextFieldIdentifier == nil, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) {
            switch focused.semantics.role {
            case .text, .heading, .image, .group, .list, .slider, .stepper: break
            default:
                focused.pressBegan()
                focused.pressEnded(inside: true)
                setNeedsDisplay()
                return true
            }
        }
        // Shortcuts in presented content (a sheet's default and cancel buttons) come before
        // Escape closing the presentation, which comes before the window's shortcuts.
        let shortcuts = shortcutNodes
        if activateShortcut(in: shortcuts.presented, for: press) { return true }
        if press.key == .escape, press.modifiers.shortcutModifiers.isEmpty, dismissTopmostPresentation() { return true }
        if activateShortcut(in: shortcuts.window, for: press) { return true }
        // ⌘[ (the macOS Back command) and Escape pop the navigation stack around the focused
        // node, else the first stack with a pushed screen.
        if (press.key == KeyEquivalent("[") && press.modifiers.shortcutModifiers == [.command])
            || (press.key == .escape && press.modifiers.shortcutModifiers.isEmpty), popNavigationStack() {
            setNeedsDisplay()
            return true
        }
        // ⌃⌘S toggles the sidebar of a navigation split view (the macOS View menu command).
        if press.key == KeyEquivalent("s"), press.modifiers.shortcutModifiers == [.control, .command], toggleSidebar() {
            setNeedsDisplay()
            return true
        }
        return false
    }

    /// Pops the innermost navigation stack with a pushed screen around the focused node, else
    /// the first such stack in the tree; false when none has anything to pop.
    private func popNavigationStack() -> Bool {
        var candidates: [NavigationStackNode] = []
        if let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) {
            var current: ViewNode? = focused
            while let node = current {
                if let stack = node as? NavigationStackNode { candidates.append(stack) }
                current = node.parent
            }
        }
        candidates += root.descendants(where: { $0 is NavigationStackNode }).compactMap { $0 as? NavigationStackNode }
        guard let stack = candidates.first(where: { !$0.entries.isEmpty }) else { return false }
        return stack.pop()
    }

    private func activateShortcut(in nodes: [any _ShortcutMatching], for press: KeyPress) -> Bool {
        guard let node = nodes.first(where: { $0.matches(press) }) else { return false }
        node.activate()
        setNeedsDisplay()
        return true
    }

    private var shortcutNodes: (presented: [any _ShortcutMatching], window: [any _ShortcutMatching]) {
        // The window's own shortcuts, then the app's menu commands' (`Scene.commands`).
        var window = root.descendants(where: { $0 is any _ShortcutMatching }).compactMap { $0 as? any _ShortcutMatching }
        for commandsRoot in commandsRoots { window += commandsRoot.descendants(where: { $0 is any _ShortcutMatching }).compactMap { $0 as? any _ShortcutMatching } }
        var presented: [any _ShortcutMatching] = []
        for presentation in presentations.reversed() {
            for child in presentation.structuralChildren {
                presented += child.descendants(where: { $0 is any _ShortcutMatching }).compactMap { $0 as? any _ShortcutMatching }
            }
        }
        return (presented, window)
    }

    /// The focus ring around the focused element when focus came from the keyboard: a 3 pt
    /// band of the keyboard focus indicator colour at 50 % outside the element (measured, see
    /// PlatformMetrics); text fields paint their own, lists show their selection in the accent
    /// colour.
    package func paintFocusRing(into list: inout DisplayList, context: PaintContext) {
        guard focusVisible, let focusedIdentifier, focusedTextFieldIdentifier == nil,
              let node = interactiveNode(semanticsIdentifier: focusedIdentifier), !(node is any _KeyHandling) else { return }
        let frame = (node as? any _FocusRingProviding)?.focusRingFrame ?? node.frameInRoot
        let ring = context.absoluteRect(frame).insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
        list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.focusRingCornerRadius, style: .circular),
                                style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                PlatformMetrics.focusRingColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: node.environment)))
    }
}

/// A focusable node whose ring goes around part of it (a toggle's control, not its label).
@MainActor
package protocol _FocusRingProviding: AnyObject {
    var focusRingFrame: CGRect { get }
}

/// Type-erased access to shortcut nodes.
@MainActor
package protocol _ShortcutMatching: AnyObject {
    func matches(_ press: KeyPress) -> Bool
    func activate()
}

extension KeyboardShortcutNode: _ShortcutMatching {}
