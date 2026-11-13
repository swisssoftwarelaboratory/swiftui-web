// Hardware keyboard and the focus system (uk-keyboard). A key from the host becomes a `UIPress`
// sent to the first responder as `pressesBegan`/`pressesEnded` (the defaults forward up the
// responder chain, the application at its end marks it unhandled); before that, the responder
// chain's `keyCommands` are matched and run. `UIFocusSystem` moves keyboard focus with Tab and
// Shift-Tab through the key window's focusable views in reading order (and the arrows through
// a table's rows or a collection's items), paints a focus ring around the focused view and
// activates it with Space or Return.
import WebFoundation   // Foundation everywhere, and the Selector stand-in where ObjectiveC is absent

// MARK: - UICommand and UIKeyCommand

/// A menu element whose action is a selector sent down the responder chain (UIKit's
/// `UICommand`). Selectors are real with the Objective-C runtime (decision 0023) and names
/// without it, where only the closure form of `UIKeyCommand` can run.
@preconcurrency @MainActor
open class UICommand: UIMenuElement {
    public let action: Selector?
    public var propertyList: Any?
    public var alternates: [Any]
    public var discoverabilityTitle: String?
    public var attributes: Attributes
    public var state: State

    public init(title: String = "", image: UIImage? = nil, action: Selector, propertyList: Any? = nil, alternates: [Any] = [],
                discoverabilityTitle: String? = nil, attributes: Attributes = [], state: State = .off) {
        self.action = action
        self.propertyList = propertyList
        self.alternates = alternates
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        super.init(title: title, image: image)
    }

    init(title: String, image: UIImage?, selector: Selector?, propertyList: Any?, alternates: [Any], discoverabilityTitle: String?, attributes: Attributes, state: State) {
        self.action = selector
        self.propertyList = propertyList
        self.alternates = alternates
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        super.init(title: title, image: image)
    }

    public struct Attributes: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let disabled = Attributes(rawValue: 1)
        public static let destructive = Attributes(rawValue: 2)
        public static let hidden = Attributes(rawValue: 4)
    }

    public enum State: Int, Sendable { case off, on, mixed }
}

/// A key combination a responder handles (`UIResponder.keyCommands`), with a selector sent
/// down the responder chain as on iOS, or a closure (this package's form for builds without a
/// runtime).
@preconcurrency @MainActor
public final class UIKeyCommand: UICommand {
    public let input: String
    public let modifierFlags: UIKeyModifierFlags
    /// The closure form's action.
    public let handler: ((UIKeyCommand) -> Void)?
    public var wantsPriorityOverSystemBehavior = false

    public init(title: String = "", image: UIImage? = nil, action: ((UIKeyCommand) -> Void)? = nil, input: String, modifierFlags: UIKeyModifierFlags = [],
                propertyList: Any? = nil, alternates: [Any] = [], discoverabilityTitle: String? = nil, attributes: Attributes = [], state: State = .off) {
        self.input = input
        self.modifierFlags = modifierFlags
        self.handler = action
        super.init(title: title, image: image, selector: nil, propertyList: propertyList, alternates: alternates,
                   discoverabilityTitle: discoverabilityTitle, attributes: attributes, state: state)
    }

    /// UIKit's selector form: the action is sent to the first responder in the chain that
    /// `canPerformAction(_:withSender:)`.
    public init(title: String = "", image: UIImage? = nil, action: Selector, input: String, modifierFlags: UIKeyModifierFlags = [],
                propertyList: Any? = nil, alternates: [Any] = [], discoverabilityTitle: String? = nil, attributes: Attributes = [], state: State = .off) {
        self.input = input
        self.modifierFlags = modifierFlags
        self.handler = nil
        super.init(title: title, image: image, selector: action, propertyList: propertyList, alternates: alternates,
                   discoverabilityTitle: discoverabilityTitle, attributes: attributes, state: state)
    }

    /// `UIKeyCommand(input:modifierFlags:action:)`, the iOS 13 form with a closure in the selector's place.
    public convenience init(input: String, modifierFlags: UIKeyModifierFlags, action: @escaping (UIKeyCommand) -> Void) {
        self.init(action: action, input: input, modifierFlags: modifierFlags)
    }

    /// `UIKeyCommand(input:modifierFlags:action:)` with a selector.
    public convenience init(input: String, modifierFlags: UIKeyModifierFlags, action: Selector) {
        self.init(action: action, input: input, modifierFlags: modifierFlags)
    }

    nonisolated public static let inputUpArrow = "UIKeyInputUpArrow"
    nonisolated public static let inputDownArrow = "UIKeyInputDownArrow"
    nonisolated public static let inputLeftArrow = "UIKeyInputLeftArrow"
    nonisolated public static let inputRightArrow = "UIKeyInputRightArrow"
    nonisolated public static let inputEscape = "UIKeyInputEscape"
    nonisolated public static let inputPageUp = "UIKeyInputPageUp"
    nonisolated public static let inputPageDown = "UIKeyInputPageDown"
    nonisolated public static let inputHome = "UIKeyInputHome"
    nonisolated public static let inputEnd = "UIKeyInputEnd"
    nonisolated public static let inputDelete = "\u{08}"
    nonisolated public static let f1 = "UIKeyInputF1"

    /// Whether the command matches a key: exactly its modifiers, and its input string. A letter
    /// input matches the key in either case, as UIKit's does (`UIKeyCommand(input: "N",
    /// modifierFlags: .command)` is ⌘N; Shift is a modifier flag, not a capital letter).
    func matches(_ key: UIKey) -> Bool {
        guard key.modifierFlags == modifierFlags else { return false }
        if key.input == input || key.characters == input { return true }
        return input.count == 1 && key.characters.count == 1 && input.lowercased() == key.characters.lowercased()
    }
}

extension UIKey {
    /// The host's key as `UIKeyCommand` input: the arrow and special inputs, else the characters.
    @MainActor public var input: String {
        switch key {
        case .upArrow: return UIKeyCommand.inputUpArrow
        case .downArrow: return UIKeyCommand.inputDownArrow
        case .leftArrow: return UIKeyCommand.inputLeftArrow
        case .rightArrow: return UIKeyCommand.inputRightArrow
        case .escape: return UIKeyCommand.inputEscape
        case .pageUp: return UIKeyCommand.inputPageUp
        case .pageDown: return UIKeyCommand.inputPageDown
        case .home: return UIKeyCommand.inputHome
        case .end: return UIKeyCommand.inputEnd
        default: return characters
        }
    }
}

// MARK: - The focus system

/// Something keyboard focus can land on (views that `canBecomeFocused`).
@preconcurrency @MainActor
public protocol UIFocusItem: AnyObject {
    var canBecomeFocused: Bool { get }
    var isFocused: Bool { get }
    var frame: CGRect { get }
}

public protocol UIFocusEnvironment: AnyObject {}

/// The views whose focus changed in an update.
@preconcurrency @MainActor
public final class UIFocusUpdateContext {
    public let previouslyFocusedItem: (any UIFocusItem)?
    public let nextFocusedItem: (any UIFocusItem)?
    public var previouslyFocusedView: UIView? { previouslyFocusedItem as? UIView }
    public var nextFocusedView: UIView? { nextFocusedItem as? UIView }
    public let focusHeading: UIFocusHeading
    init(previous: (any UIFocusItem)?, next: (any UIFocusItem)?, heading: UIFocusHeading) {
        previouslyFocusedItem = previous
        nextFocusedItem = next
        focusHeading = heading
    }
}

public struct UIFocusHeading: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let up = UIFocusHeading(rawValue: 1)
    public static let down = UIFocusHeading(rawValue: 2)
    public static let left = UIFocusHeading(rawValue: 4)
    public static let right = UIFocusHeading(rawValue: 8)
    public static let next = UIFocusHeading(rawValue: 16)
    public static let previous = UIFocusHeading(rawValue: 32)
    public static let first = UIFocusHeading(rawValue: 64)
    public static let last = UIFocusHeading(rawValue: 128)
}

/// Animations a focus update runs (none here; the API is accepted).
@preconcurrency @MainActor
public final class UIFocusAnimationCoordinator {
    public func addCoordinatedAnimations(_ animations: (() -> Void)?, completion: (() -> Void)? = nil) {
        animations?()
        completion?()
    }
}

/// The keyboard focus of the host's window scene.
@preconcurrency @MainActor
public final class UIFocusSystem {
    public static func focusSystem(for environment: any UIFocusEnvironment) -> UIFocusSystem? { UIKitScene.shared.focusSystem }

    public private(set) weak var focusedItem: (any UIFocusItem)?
    /// Whether the focus ring shows: it appears once the keyboard moves focus and goes with a touch.
    public internal(set) var showsFocusRing = false
    private var pendingItem: (any UIFocusItem)??

    /// Asks for focus to move to `item` on the next update.
    public func requestFocusUpdate(to item: any UIFocusItem) { pendingItem = .some(item) }
    public func updateFocusIfNeeded() {
        guard let pending = pendingItem else { return }
        pendingItem = nil
        move(to: pending, heading: [])
    }

    /// Moves focus to `item` (nil clears it): the views and their controllers hear `didUpdateFocus`.
    public func move(to item: (any UIFocusItem)?, heading: UIFocusHeading) {
        let previous = focusedItem
        guard previous !== item else { return }
        focusedItem = item
        let context = UIFocusUpdateContext(previous: previous, next: item, heading: heading)
        let coordinator = UIFocusAnimationCoordinator()
        for view in [previous as? UIView, item as? UIView].compactMap({ $0 }) {
            view.didUpdateFocus(in: context, with: coordinator)
            var responder: UIResponder? = view.next
            while let current = responder {
                if let controller = current as? UIViewController { controller.didUpdateFocus(in: context, with: coordinator); break }
                responder = current.next
            }
        }
        if let cell = item as? UITableViewCell, let table = cell.closestCollectionContainer as? UITableView, table.selectionFollowsFocus, let path = table.indexPath(for: cell) {
            table.selectRow(at: path, animated: false, scrollPosition: .none)
        }
        if let cell = item as? UICollectionViewCell, let collection = cell.closestCollectionContainer as? UICollectionView, collection.selectionFollowsFocus, let path = collection.indexPath(for: cell) {
            collection.selectItem(at: path, animated: false, scrollPosition: [])
        }
        UIKitScene.shared.setNeedsFrame()
    }

    /// The focusable views of the key window in reading order (top to bottom, leading to
    /// trailing), with each table's or collection's cells included.
    func focusableViews(in window: UIWindow) -> [UIView] {
        var result: [UIView] = []
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if view.canBecomeFocused, view.isFocusable { result.append(view) }
            for subview in view.subviews { walk(subview) }
        }
        walk(window)
        return result.sorted { a, b in
            let fa = a.convert(a.bounds, to: nil), fb = b.convert(b.bounds, to: nil)
            return abs(fa.minY - fb.minY) > 0.5 ? fa.minY < fb.minY : fa.minX < fb.minX
        }
    }

    /// Tab, Shift-Tab and the arrows: returns whether the key moved focus.
    func handleKey(_ key: UIKey, in window: UIWindow) -> Bool {
        let views = focusableViews(in: window)
        guard !views.isEmpty else { return false }
        let current = focusedItem as? UIView
        let index = current.flatMap { view in views.firstIndex { $0 === view } }
        switch key.key {
        case .tab:
            let backwards = key.modifierFlags.contains(.shift)
            let next: Int
            if let index { next = backwards ? (index - 1 + views.count) % views.count : (index + 1) % views.count } else { next = backwards ? views.count - 1 : 0 }
            showsFocusRing = true
            move(to: views[next], heading: backwards ? .previous : .next)
            return true
        case .upArrow, .downArrow, .leftArrow, .rightArrow:
            // Inside a table or collection the arrows walk the cells; elsewhere nothing.
            guard let cell = current, let container = cell.superview?.closestCollectionContainer else { return false }
            let cells = views.filter { $0.superview?.closestCollectionContainer === container }
            guard let position = cells.firstIndex(where: { $0 === cell }) else { return false }
            let forward = key.key == .downArrow || key.key == .rightArrow
            let next = forward ? min(position + 1, cells.count - 1) : max(position - 1, 0)
            showsFocusRing = true
            move(to: cells[next], heading: forward ? .down : .up)
            return true
        case .space, .return:
            guard let control = current as? UIControl, control.isEnabled else { return false }
            control.sendActions(for: [.touchUpInside, .primaryActionTriggered])
            return true
        default:
            return false
        }
    }

    /// Paints the focus ring: a 2 pt system-blue rounded ring 2 pt outside the focused view.
    func paintFocusRing(into list: inout DisplayList, context: PaintContext) {
        guard showsFocusRing, let view = focusedItem as? UIView, let window = view.window, !window.isHidden else { return }
        let frame = view.convert(view.bounds, to: nil).insetBy(dx: -3, dy: -3)
        let radius = view.layer.cornerRadius + 3
        let ring = context.absoluteRect(frame)
        list.append(.strokePath(Path(roundedRect: ring.insetBy(dx: 1, dy: 1), cornerRadius: max(radius, 4)), style: StrokeStyle(lineWidth: 2),
                                RGBA(r: 0, g: 122, b: 255, a: 0.8)))
    }
}

extension UIView {
    /// `canBecomeFocused` and enabled, in a window.
    var isFocusable: Bool {
        if let control = self as? UIControl { return control.isEnabled && window != nil }
        return window != nil
    }
    public var isFocused: Bool { UIKitScene.shared.focusSystem.focusedItem === self }
    public func setNeedsFocusUpdate() { UIKitScene.shared.setNeedsFrame() }
    public func updateFocusIfNeeded() { UIKitScene.shared.focusSystem.updateFocusIfNeeded() }
    /// The table or collection holding this view's cells, from a cell's superview.
    var closestCollectionContainer: UIView? {
        var view: UIView? = self
        while let current = view {
            if current is UITableView || current is UICollectionView { return current }
            view = current.superview
        }
        return nil
    }
}

extension UIView: UIFocusItem, UIFocusEnvironment {}


// MARK: - The scene's keys

extension UIKitScene {
    /// Where a key starts down the responder chain: the first responder, else the focused view,
    /// else the key window's frontmost controller (UIKit's default responder), else the window.
    var keyResponder: UIResponder? {
        if let responder = firstResponder { return responder }
        if let focused = focusSystem.focusedItem as? UIView, focused.window != nil { return focused }
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller ?? window
    }

    /// Runs a command: its closure, else its selector sent to the first responder from `start`
    /// up the chain (the application, then the app delegate, at the end) that handles it.
    @discardableResult
    func perform(_ command: UICommand, from start: UIResponder?) -> Bool {
        if let keyCommand = command as? UIKeyCommand, let handler = keyCommand.handler {
            handler(keyCommand)
            return true
        }
        #if _runtime(_ObjC)
        guard let action = command.action else { return false }
        var responder = start
        while let current = responder {
            if current.canPerformAction(action, withSender: command) {
                current._send(action, passing: command)
                return true
            }
            responder = current.next
        }
        if let delegate = UIApplication.shared.delegate as? UIResponder, delegate.canPerformAction(action, withSender: command) {
            delegate._send(action, passing: command)
            return true
        }
        #endif
        return false
    }

    /// A key from the host: the responder chain's key commands first, then the main menu's
    /// (`UIMenuSystem.main`), then `pressesBegan` from the first responder (or the key window),
    /// then the focus system's navigation.
    func dispatchKeyDown(_ event: KeyEvent) -> Bool {
        let key = UIKey(characters: event.characters, modifierFlags: UIKeyModifierFlags(event.modifiers), key: event.key)
        let start = keyResponder
        var responder = start
        while let current = responder {
            if let command = current.keyCommands?.first(where: { $0.matches(key) && !$0.attributes.contains(.disabled) }), perform(command, from: start) {
                setNeedsFrame()
                return true
            }
            responder = current.next
        }
        if let command = UIMenuSystem.main.keyCommands.first(where: { $0.matches(key) && !$0.attributes.contains(.disabled) }), perform(command, from: start) {
            setNeedsFrame()
            return true
        }
        let press = UIPress(phase: .began, key: key)
        activePresses[event.key] = press
        pressUnhandled = false
        start?.pressesBegan([press], with: UIPressesEvent(presses: [press], timestamp: event.time))
        if !pressUnhandled { setNeedsFrame(); return true }
        if let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first, focusSystem.handleKey(key, in: window) { return true }
        return false
    }

    func dispatchKeyUp(_ event: KeyEvent) -> Bool {
        guard let began = activePresses.removeValue(forKey: event.key) else { return false }
        let press = UIPress(phase: .ended, key: began.key)
        pressUnhandled = false
        let start = keyResponder
        start?.pressesEnded([press], with: UIPressesEvent(presses: [press], timestamp: event.time))
        return !pressUnhandled
    }
}

extension UIKeyModifierFlags {
    init(_ modifiers: EventModifiers) {
        var flags: UIKeyModifierFlags = []
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.alternate) }
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.capsLock) { flags.insert(.alphaShift) }
        self = flags
    }
}
