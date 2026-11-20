// The keyboard notifications (decision 0021, uk-app-delegate-adaptor: the Countries app's
// `SystemEventsHandler` observes `keyboardWillShowNotification` and reads the end frame). A
// host that knows the on-screen keyboard's frame sets `UIKitScene.keyboardFrame`; the
// will/did show and hide notifications follow with UIKit's user-info keys. `NSValue` holds the
// rects (WebGraphics declares it on wasm, where Foundation's is missing); `NSNumber` is
// WebFoundation's there.
import WebFoundation

#if !os(WASI)
/// Foundation's `NSValue` with the geometry accessors UIKit adds to it.
extension NSValue {
    public convenience init(cgRect: CGRect) { self.init(rect: cgRect) }
    public convenience init(cgPoint: CGPoint) { self.init(point: cgPoint) }
    public convenience init(cgSize: CGSize) { self.init(size: cgSize) }
    public var cgRectValue: CGRect { rectValue }
    public var cgPointValue: CGPoint { pointValue }
    public var cgSizeValue: CGSize { sizeValue }
}
#endif

extension UIResponder {
    nonisolated public static let keyboardFrameBeginUserInfoKey = "UIKeyboardFrameBeginUserInfoKey"
    nonisolated public static let keyboardFrameEndUserInfoKey = "UIKeyboardFrameEndUserInfoKey"
    nonisolated public static let keyboardAnimationDurationUserInfoKey = "UIKeyboardAnimationDurationUserInfoKey"
    nonisolated public static let keyboardAnimationCurveUserInfoKey = "UIKeyboardAnimationCurveUserInfoKey"
    nonisolated public static let keyboardIsLocalUserInfoKey = "UIKeyboardIsLocalUserInfoKey"

    nonisolated public static let keyboardWillShowNotification = Notification.Name("UIKeyboardWillShowNotification")
    nonisolated public static let keyboardDidShowNotification = Notification.Name("UIKeyboardDidShowNotification")
    nonisolated public static let keyboardWillHideNotification = Notification.Name("UIKeyboardWillHideNotification")
    nonisolated public static let keyboardDidHideNotification = Notification.Name("UIKeyboardDidHideNotification")
    nonisolated public static let keyboardWillChangeFrameNotification = Notification.Name("UIKeyboardWillChangeFrameNotification")
    nonisolated public static let keyboardDidChangeFrameNotification = Notification.Name("UIKeyboardDidChangeFrameNotification")
}

extension UIKitScene {
    /// The on-screen keyboard's frame in the screen's space, or nil while it is away. A host
    /// sets it (the browser's keyboard shrinks the visual viewport; `nil` on a desktop); the
    /// notifications go out as UIKit posts them, with the begin and end frames (the hidden
    /// keyboard sits just below the screen), the 0.3833 s duration and curve 7 the iOS 27 simulator
    /// reports for its keyboard (new-website#648).
    public var keyboardFrame: CGRect? {
        get { storedKeyboardFrame }
        set {
            let previous = storedKeyboardFrame
            guard previous != newValue else { return }
            storedKeyboardFrame = newValue
            let screen = UIScreen.main.bounds
            let hidden = CGRect(x: 0, y: screen.maxY, width: screen.width, height: previous?.height ?? newValue?.height ?? 0)
            let begin = previous ?? hidden
            let end = newValue ?? hidden
            let info: [AnyHashable: Any] = [
                UIResponder.keyboardFrameBeginUserInfoKey: NSValue(cgRect: begin),
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: end),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.3833),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: 7),
                UIResponder.keyboardIsLocalUserInfoKey: NSNumber(value: true),
            ]
            let center = NotificationCenter.default
            let showing = newValue != nil && previous == nil, hiding = newValue == nil
            center.post(name: UIResponder.keyboardWillChangeFrameNotification, object: nil, userInfo: info)
            if showing { center.post(name: UIResponder.keyboardWillShowNotification, object: nil, userInfo: info) }
            if hiding { center.post(name: UIResponder.keyboardWillHideNotification, object: nil, userInfo: info) }
            if showing { center.post(name: UIResponder.keyboardDidShowNotification, object: nil, userInfo: info) }
            if hiding { center.post(name: UIResponder.keyboardDidHideNotification, object: nil, userInfo: info) }
            center.post(name: UIResponder.keyboardDidChangeFrameNotification, object: nil, userInfo: info)
        }
    }
}
