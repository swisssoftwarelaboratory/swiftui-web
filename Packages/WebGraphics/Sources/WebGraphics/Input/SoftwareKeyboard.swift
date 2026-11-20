// The drawn software keyboard's seam (new-website#648): a scene that draws its own on-screen
// keyboard (the SwiftUI runtime on the iPhone look) asks the host to make its edits on the
// focused input element, so the browser's own input path (value, caret, `input` events)
// carries them like typed text; the host tells it which real keys are held, so the drawn key
// answers the viewer's own keyboard.

/// An edit the drawn keyboard makes in the focused text field.
public enum SoftwareKeyboardEdit: Equatable, Sendable {
    /// Replaces the selection with the text, the caret after it.
    case insert(String)
    /// Deletes the selection, or the character before the caret.
    case deleteBackward
    /// Return: a field submits, an editor gets a newline.
    case submit
}

/// The keyboard's frame in the scene (points) as it moves, nil once it is away.
public typealias SoftwareKeyboardFrameHandler = @MainActor @Sendable (_ frame: CGRect?) -> Void

extension HostedScene {
    public var drawsSoftwareKeyboard: Bool {
        get { false }
        set {}
    }
    public var softwareKeyboardEditHandler: (@MainActor @Sendable (SoftwareKeyboardEdit, Int) -> Bool)? {
        get { nil }
        set {}
    }
    public func softwareKeyboardHardwareKeyDown(_ key: String) {}
    public func softwareKeyboardHardwareKeysUp() {}
    public func softwareKeyboardContains(_ point: CGPoint) -> Bool { false }
}
