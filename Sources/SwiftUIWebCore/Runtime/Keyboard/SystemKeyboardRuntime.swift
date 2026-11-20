#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
// The drawn keyboard in the runtime (new-website#648): focus brings it up, frames move it,
// presses on it are its own, it paints over everything, and its edits reach the focused field
// through the host's input element (or straight into the field without a host).

extension Runtime {
    /// Whether the drawn keyboard is in use: the host asked for it on the iPhone look.
    package var usesSystemKeyboard: Bool { drawsSoftwareKeyboard && rootEnvironment.platformProfile.isIOS }

    /// The keyboard's layout from the app's language: the app's first localization the viewer
    /// prefers, else the viewer's own first language.
    package var keyboardLanguageIdentifier: String {
        softwareKeyboardLanguage ?? Bundle.main.preferredLocalizations.first(where: { $0 != "Base" }) ?? Locale.preferredLanguages.first ?? "en"
    }

    /// The keyboard's region of the safe area: its height above the screen's bottom.
    package var keyboardSafeAreaInsets: EdgeInsets { EdgeInsets(top: 0, leading: 0, bottom: keyboardInset, trailing: 0) }

    /// The root's safe area: the device's, and the keyboard's where it reaches further.
    package var effectiveSafeAreaInsets: EdgeInsets {
        var insets = safeAreaInsets
        insets.bottom = max(insets.bottom, keyboardInset)
        return insets
    }

    /// The focused text field changed (`focusTextField`).
    package func systemKeyboardFocusChanged() {
        guard usesSystemKeyboard || systemKeyboard.isUp else { return }
        let field = usesSystemKeyboard ? focusedTextFieldIdentifier : nil
        if field != nil, !systemKeyboard.isUp { systemKeyboard.language = KeyboardLanguage(languageIdentifier: keyboardLanguageIdentifier) }
        systemKeyboard.focusChanged(to: field)
    }

    /// The keyboard started up or down: the app's keyboard safe area follows on the keyboard's
    /// own spring, and the host hears its frame for UIKit's notifications.
    package func keyboardDidMove(up: Bool) {
        let height = systemKeyboard.height
        let spring = SystemKeyboard.spring
        pendingAnimation = .spring(response: 2 * Double.pi / spring.omega, dampingFraction: min(1, spring.zeta))
        keyboardInset = up ? height : 0
        let size = layoutSize
        onKeyboardFrameChange?(up ? CGRect(x: 0, y: size.height - height, width: size.width, height: height) : nil)
    }

    /// Makes an edit of the drawn keyboard in the field: through the host's input element when
    /// it has one, else in the field directly.
    package func applyKeyboardEdit(_ edit: SoftwareKeyboardEdit, to identifier: Int) {
        if let handler = softwareKeyboardEditHandler, handler(edit, identifier) { return }
        if case .submit = edit {
            textFieldDidSubmit(identifier)
            return
        }
        guard let node = textInputNode(identifier), let state = node.editingState else { return }
        let utf16 = Array(state.text.utf16)
        var range = max(0, min(state.selection.lowerBound, utf16.count))..<max(0, min(state.selection.upperBound, utf16.count))
        var inserted: [UInt16] = []
        switch edit {
        case .insert(let text): inserted = Array(text.utf16)
        case .deleteBackward:
            if range.isEmpty {
                // One character (a whole grapheme, an emoji or an accented letter) before the caret.
                let prefix = String(decoding: utf16[..<range.lowerBound], as: UTF16.self)
                guard let last = prefix.last else { return }
                range = (range.lowerBound - String(last).utf16.count)..<range.lowerBound
            }
        case .submit: return
        }
        let result = utf16[..<range.lowerBound] + inserted + utf16[range.upperBound...]
        node.setText(String(decoding: Array(result), as: UTF16.self))
        let caret = range.lowerBound + inserted.count
        node.setSelection(start: caret, end: caret)
    }

    // MARK: HostedScene

    public func softwareKeyboardHardwareKeyDown(_ key: String) {
        guard usesSystemKeyboard else { return }
        systemKeyboard.hardwareKeyDown(key: key)
    }

    public func softwareKeyboardHardwareKeysUp() { systemKeyboard.hardwareKeyUp() }

    public func softwareKeyboardContains(_ point: CGPoint) -> Bool {
        systemKeyboard.isVisible && systemKeyboard.frame.contains(point)
    }
}

extension _TextInputNode {
    package var editingState: (text: String, selection: Range<Int>)? { nil }
}

extension TextFieldNode {
    package var editingState: (text: String, selection: Range<Int>)? {
        let text = displayText
        return (text, selection ?? text.utf16.count..<text.utf16.count)
    }
}

extension TextEditorNode {
    package var editingState: (text: String, selection: Range<Int>)? {
        let text = view.value
        let end = text.utf16.count
        guard let host = hostSelection else { return (text, end..<end) }
        return (text, min(host.start, end)..<min(max(host.start, host.end), end))
    }
}
