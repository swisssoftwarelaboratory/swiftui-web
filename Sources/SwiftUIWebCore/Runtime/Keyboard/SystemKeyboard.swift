#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
// The drawn iPhone's keyboard (new-website#619, built in #648): on the iPhone look, a text field
// or editor taking focus slides the iOS 27 keyboard up from the screen's bottom on the critically
// damped spring at ω 18 /s, and it slides down when the focus leaves, each time from where it is
// and how fast it moves. The app moves with it: the keyboard's height is the safe area's
// keyboard region (`Runtime.keyboardInset`), laid out on the same spring, and the host posts
// UIKit's keyboard notifications (`Runtime.onKeyboardFrameChange`).
//
// A press on it is a finger: the key under it dims and its bubble shows above it, the bubble
// follows the finger across the keys, and lifting types the key (off the keys types nothing).
// Holding a letter with accents opens the accent row; holding delete repeats. The viewer's own
// keyboard types into the field as the browser does (umlauts and dead keys included) and holds
// the matching drawn key down with its bubble while the real key is down (`hardwareKeyDown`).

/// What the keyboard asks of the focused field (WebGraphics' `SoftwareKeyboardEdit`).
package typealias SystemKeyboardEdit = SoftwareKeyboardEdit

@MainActor
package final class SystemKeyboard {
    package enum Shift: Equatable, Sendable { case off, on, locked }

    unowned let runtime: Runtime
    package var language: KeyboardLanguage = .usEnglish
    package private(set) var page: KeyboardPage = .letters
    package private(set) var showsEmoji = false
    package private(set) var shift: Shift = .off
    /// How far the keyboard stands above the screen's bottom, in points (0 is away).
    package private(set) var lift = Motion(position: 0, restDistance: 0.05, restSpeed: 1)
    /// Whether the keyboard is on its way up (or up).
    package private(set) var isUp = false
    /// The field the keyboard types into.
    package private(set) var fieldIdentifier: Int?

    /// A finger on the keys.
    package struct Press: Equatable {
        package var key: KeyboardKey?
        package var point: CGPoint
        /// The accent row a long press opened, its frame (keyboard space) and the accent under the finger.
        package var accents: [String]?
        package var accentFrame: CGRect = .zero
        package var pick: Int?
        /// When the long press opens the accents, and when delete repeats next (keyboard clock).
        package var longPressAt: Double?
        package var repeatAt: Double?
    }
    package private(set) var finger: Press?
    /// The drawn key the viewer's own keyboard holds down, and the character its bubble shows.
    package private(set) var hardwareKey: KeyboardKey?
    package private(set) var hardwareLabel: String = ""

    private var clock: Double = 0
    private var lastShiftTap: Double = -10
    private var lastSpace: Double = -10

    /// The spring the keyboard slides on: UIKit's curve 7, critically damped at ω ≈ 18 /s (new-website#261).
    package static let spring = SpringModel.navigation
    package static let longPressDelay = 0.45
    package static let repeatDelay = 0.5
    package static let repeatInterval = 0.1
    package static let doubleTapInterval = 0.35

    init(runtime: Runtime) { self.runtime = runtime }

    // MARK: Geometry

    package var height: CGFloat { KeyboardMetrics.height }
    /// The keyboard's frame in the window (below the window while away).
    package var frame: CGRect {
        let size = runtime.layoutSize
        return CGRect(x: 0, y: size.height - CGFloat(lift.position), width: size.width, height: height)
    }
    package var isVisible: Bool { lift.position > 0.01 }

    /// The keys showing now.
    package var keys: [KeyboardKey] {
        if showsEmoji { return emojiKeys }
        return language.keys(page: page, width: runtime.layoutSize.width)
    }

    /// Whether letters type as capitals now.
    package var capitals: Bool { shift != .off }

    // MARK: Showing

    /// The focused text field changed: up for a field, down for none.
    package func focusChanged(to identifier: Int?) {
        let wasUp = isUp
        fieldIdentifier = identifier
        isUp = identifier != nil
        if isUp && !wasUp {
            page = traits?.startsOnNumbers == true ? .numbers : .letters
            showsEmoji = false
            shift = .off
        }
        if isUp { contextChanged() }
        if isUp != wasUp {
            finger = nil
            hardwareKey = nil
            lift.animate(to: isUp ? Double(height) : 0, spring: Self.spring)
            runtime.keyboardDidMove(up: isUp)
        }
        runtime.setNeedsDisplay()
    }

    /// Advances the slide and the held keys' timers. Returns whether it still needs frames.
    package func advance(elapsed: Double) -> Bool {
        clock += elapsed
        var needsFrames = false
        if lift.isMoving {
            lift.step(elapsed)
            needsFrames = true
            runtime.setNeedsDisplay()
        }
        if var press = finger {
            if let due = press.longPressAt, clock >= due {
                press.longPressAt = nil
                finger = press
                openAccents()
                runtime.setNeedsDisplay()
            }
            if let due = finger?.repeatAt, clock >= due {
                finger?.repeatAt = clock + Self.repeatInterval
                edit(.deleteBackward)
            }
            if finger?.longPressAt != nil || finger?.repeatAt != nil { needsFrames = true }
        }
        return needsFrames
    }

    // MARK: The field

    /// The focused field's keyboard settings.
    package struct Traits: Equatable {
        package var returnKey: UIReturnKeyType = .default
        package var capitalization: UITextAutocapitalizationType = .sentences
        package var startsOnNumbers = false
        package var submitsOnReturn = true
    }

    package var traits: Traits? {
        guard let id = fieldIdentifier, let node = runtime.textInputNode(id) as? ViewNode else { return nil }
        let environment = node.environment
        var traits = Traits()
        traits.returnKey = environment._submitLabel.key
        traits.capitalization = environment._textInputAutocapitalization?.kind ?? .sentences
        switch environment._keyboardType {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad, .numbersAndPunctuation: traits.startsOnNumbers = true
        default: break
        }
        traits.submitsOnReturn = !(node is TextEditorNode)
        return traits
    }

    /// The field's text and selection (UTF-16 offsets), as the keyboard sees them.
    private var editingState: (text: String, selection: Range<Int>)? {
        guard let id = fieldIdentifier else { return nil }
        return runtime.textInputNode(id)?.editingState
    }

    /// The text before the caret.
    private var textBeforeCaret: String {
        guard let state = editingState else { return "" }
        let utf16 = state.text.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: min(state.selection.lowerBound, utf16.count))
        return String(state.text[..<(end.samePosition(in: state.text) ?? state.text.endIndex)])
    }

    /// The text or caret changed: capitals come back at a sentence's start (or a word's, or
    /// always, as the field asks), unless caps lock is on.
    package func contextChanged() {
        guard isUp, shift != .locked else { return }
        let before = textBeforeCaret
        let capitalization = traits?.capitalization ?? .sentences
        let auto: Bool
        switch capitalization {
        case .none: auto = false
        case .allCharacters: auto = true
        case .words: auto = before.isEmpty || before.last?.isWhitespace == true
        case .sentences: auto = Self.isSentenceStart(before)
        }
        let next: Shift = auto ? .on : .off
        if next != shift { shift = next; runtime.setNeedsDisplay() }
    }

    /// Whether typing after `text` starts a sentence: nothing yet, or a full stop, question or
    /// exclamation mark (or a new line) and then spaces.
    package static func isSentenceStart(_ text: String) -> Bool {
        if text.last?.isNewline == true { return true }
        let trimmed = text.reversed().drop { $0 == " " }
        guard let last = trimmed.first else { return true }
        guard trimmed.count < text.count else { return false }
        return last == "." || last == "!" || last == "?" || last.isNewline
    }

    /// The word being typed, for the suggestions band.
    package var currentWord: String {
        String(textBeforeCaret.reversed().prefix { !$0.isWhitespace && !$0.isPunctuation }.reversed())
    }

    private func edit(_ edit: SystemKeyboardEdit) {
        guard let id = fieldIdentifier else { return }
        runtime.applyKeyboardEdit(edit, to: id)
        contextChanged()
        runtime.setNeedsDisplay()
    }

    // MARK: Pressing keys

    /// Types a key as a finger lifting off it.
    package func type(_ key: KeyboardKey) {
        switch key.kind {
        case .character(let character):
            let text = page == .letters && !showsEmoji && capitals ? character.uppercased() : character
            if shift == .on { shift = .off }
            lastShiftTap = -10
            edit(.insert(text))
        case .shift:
            if shift == .locked {
                shift = .off
            } else if clock - lastShiftTap < Self.doubleTapInterval {
                shift = .locked
            } else {
                shift = shift == .off ? .on : .off
            }
            lastShiftTap = clock
        case .delete:
            break   // deleted as the press began
        case .page(let page):
            showsEmoji = false
            self.page = page
        case .emoji:
            showsEmoji = true
        case .accent:
            typeAccent(FrenchAccentKey.mark(after: textBeforeCaret.last))
        case .space:
            let before = textBeforeCaret
            if clock - lastSpace < Self.doubleTapInterval, before.hasSuffix(" "),
               let previous = before.dropLast().last, !previous.isWhitespace, !".!?".contains(previous) {
                edit(.deleteBackward)
                edit(.insert(". "))
                lastSpace = -10
            } else {
                edit(.insert(" "))
                lastSpace = clock
            }
            if page != .letters { page = .letters }
        case .return:
            edit(traits?.submitsOnReturn ?? true ? .submit : .insert("\n"))
        }
        runtime.setNeedsDisplay()
    }

    /// A press at `point` (window coordinates). Returns whether the keyboard took it.
    package func pointerDown(at point: CGPoint) -> Bool {
        guard isVisible, frame.contains(point) else { return false }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        hardwareKey = nil
        var press = Press(key: keyboardKey(at: local, in: keys), point: local)
        if let key = press.key {
            if key.kind == .delete {
                edit(.deleteBackward)
                press.repeatAt = clock + Self.repeatDelay
            }
            if case .character(let c) = key.kind, page == .letters, !showsEmoji, language.accents(for: c) != nil {
                press.longPressAt = clock + Self.longPressDelay
            }
            if key.kind == .accent { press.longPressAt = clock + Self.longPressDelay }
        } else if local.y > KeyboardMetrics.rowTops[3] + KeyboardMetrics.keyHeight, local.x < runtime.layoutSize.width / 2 {
            // The globe: the emoji page and back.
            showsEmoji.toggle()
        }
        finger = press
        runtime.setNeedsDisplay()
        return true
    }

    /// Whether a finger is on the keyboard.
    package var tracksPointer: Bool { finger != nil }

    package func pointerMoved(to point: CGPoint) {
        guard var press = finger else { return }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        press.point = local
        if let accents = press.accents {
            let cell = KeyboardMetrics.accentCell.width
            let index = Int(((local.x - press.accentFrame.minX - KeyboardMetrics.accentPadding) / cell).rounded(.down))
            press.pick = (0..<accents.count).contains(index) && local.y > press.accentFrame.minY - 40 ? index : nil
            finger = press
            runtime.setNeedsDisplay()
            return
        }
        let key = keyboardKey(at: local, in: keys)
        if key != press.key {
            press.key = key
            press.longPressAt = nil
            press.repeatAt = nil
            if let key, case .character(let c) = key.kind, page == .letters, !showsEmoji, language.accents(for: c) != nil {
                press.longPressAt = clock + Self.longPressDelay
            }
        }
        finger = press
        runtime.setNeedsDisplay()
    }

    package func pointerUp(at point: CGPoint, cancelled: Bool = false) {
        guard let press = finger else { return }
        finger = nil
        defer { runtime.setNeedsDisplay() }
        guard !cancelled else { return }
        if let accents = press.accents {
            if let pick = press.pick {
                let accent = accents[pick]
                if press.key?.kind == .accent {
                    typeAccent(accent)
                } else {
                    if shift == .on { shift = .off }
                    edit(.insert(accent))
                }
            }
            return
        }
        if let key = press.key, key.kind != .delete { type(key) }
    }

    /// The accent key's mark: on the letter before the caret when it takes it (e → é), else typed.
    private func typeAccent(_ mark: String) {
        if let previous = textBeforeCaret.last, let combined = FrenchAccentKey.combined(previous, mark: mark) {
            edit(.deleteBackward)
            edit(.insert(combined))
        } else {
            edit(.insert(mark))
        }
    }

    /// The accent key's mark now (it follows the letter before the caret).
    package var accentKeyMark: String { FrenchAccentKey.mark(after: textBeforeCaret.last) }

    private func openAccents() {
        guard var press = finger, let key = press.key else { return }
        var accents: [String]
        if key.kind == .accent {
            accents = ["\u{A8}", "^", "`", "\u{B4}"]
        } else {
            guard case .character(let c) = key.kind, let letters = language.accents(for: c) else { return }
            accents = capitals ? letters.map { $0.uppercased() } : letters
        }
        let cell = KeyboardMetrics.accentCell, pad = KeyboardMetrics.accentPadding
        let width = CGFloat(accents.count) * cell.width + 2 * pad
        let x = min(runtime.layoutSize.width - width - 4, max(4, key.frame.minX - pad))
        press.accents = accents
        press.accentFrame = CGRect(x: x, y: key.frame.minY - cell.height - 2 * pad - 8, width: width, height: cell.height + 2 * pad)
        press.pick = 0
        finger = press
    }

    // MARK: The viewer's own keyboard

    /// A real key went down: the drawn key it matches is held with its bubble. A character on
    /// another page brings that page up first, as a finger would have to.
    package func hardwareKeyDown(key: String) {
        guard isUp else { return }
        var kind: KeyboardKeyKind?
        switch key {
        case "Backspace": kind = .delete
        case "Enter": kind = .return
        case " ": kind = .space
        case "Shift": kind = .shift
        default:
            guard key.count == 1 else { return }
            if showsEmoji, language.page(of: key) != nil { showsEmoji = false }
            if let wanted = language.page(of: key), wanted != page { page = wanted }
            kind = .character(page == .letters ? key.lowercased() : key)
        }
        hardwareKey = keys.first { $0.kind == kind }
        hardwareLabel = key.count == 1 ? key : ""
        runtime.setNeedsDisplay()
    }

    /// Every real key is up.
    package func hardwareKeyUp() {
        guard hardwareKey != nil else { return }
        hardwareKey = nil
        runtime.setNeedsDisplay()
    }

    // MARK: Emoji

    /// A page of common emoji in the viewer's own emoji font, ABC and delete under them.
    private static let emoji = ["😀", "😂", "🥲", "😊", "😍", "😘", "😎", "🤔",
                                "😅", "😢", "😭", "😡", "🥳", "😴", "🤗", "🙃",
                                "👍", "👎", "👏", "🙏", "💪", "👋", "🤝", "✌️",
                                "❤️", "🔥", "✨", "🎉", "✅", "💯", "🏃", "🍎"]
    private var emojiKeys: [KeyboardKey] {
        let width = runtime.layoutSize.width
        let columns = 8, cell = (width - 16) / CGFloat(columns)
        var keys: [KeyboardKey] = []
        for (index, emoji) in Self.emoji.enumerated() {
            let row = index / columns, column = index % columns
            keys.append(KeyboardKey(kind: .character(emoji), frame: CGRect(x: 8 + CGFloat(column) * cell, y: 52 + CGFloat(row) * 46, width: cell, height: 42)))
        }
        let scale = width / KeyboardMetrics.width
        keys.append(KeyboardKey(kind: .page(page), frame: CGRect(x: 8 * scale, y: KeyboardMetrics.rowTops[3] + 8, width: 41.33 * scale, height: 34)))
        keys.append(KeyboardKey(kind: .delete, frame: CGRect(x: 342.33 * scale, y: KeyboardMetrics.rowTops[3] + 8, width: 44.33 * scale, height: 34)))
        return keys
    }
}

