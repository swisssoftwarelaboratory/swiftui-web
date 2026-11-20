// The browser behind the keyboard notifications (decision 0021, uk-app-delegate-adaptor): the
// on-screen keyboard's frame read from `window.visualViewport` against `window.innerHeight`
// while a text input has the focus (`_KeyboardFrameEstimator`: a pinch zoom, a plain resize,
// the URL bar's collapse and a shrink without a focused input are not it), set on
// `UIKitScene.keyboardFrame`, which posts will/did show, hide and change-frame with UIKit's
// user-info keys. Re-read on the visual viewport's `resize` and `scroll`, on `focusin`/
// `focusout` (the keyboard follows the focus), and on the window's `resize`.
//
// What this cannot see: a browser whose keyboard shrinks the layout viewport with the visual
// one (`interactive-widget=resizes-content`; Chrome before 108 and Android WebView by default)
// leaves the two viewports equal — the page itself got shorter, the scene resized, no frame;
// one whose keyboard shrinks neither (`interactive-widget=overlays-content`) reports nothing
// either — a viewport difference cannot see an overlay; and a browser without `visualViewport`
// reports nothing. Chrome's default since 108 (`resizes-visual`) and iOS Safari are the modes
// this reads.
#if os(WASI)
import JavaScriptKit
import UIKitWebCore

@MainActor
enum KeyboardHost {
    nonisolated(unsafe) private static var listeners: [JSClosure] = []
    /// The runtime draws the keyboard and sets the frame itself (new-website#648): the browser's
    /// viewports say nothing then.
    nonisolated(unsafe) static var drawsKeyboard = false

    static func install() {
        let window = JSObject.global
        guard let viewport = window.visualViewport.object else { return }
        let update = JSClosure { _ in
            MainActor.assumeIsolated { apply(reading(window: window, viewport: viewport)) }
            return .undefined
        }
        listeners.append(update)
        _ = viewport.addEventListener?("resize", update)
        _ = viewport.addEventListener?("scroll", update)
        _ = window.addEventListener?("resize", update)
        _ = window.document.object?.addEventListener?("focusin", update)
        _ = window.document.object?.addEventListener?("focusout", update)
        // For probes: the frame the scene holds, and a SYNTHETIC reading applied as if the
        // browser had reported it (a desktop Chromium has no on-screen keyboard; a reading it
        // accepts proves the host→scene→notification path, never the phone's keyboard).
        if let debug = window.__swiftuiwebDebug.object {
            let frame = JSClosure { _ in
                guard let frame = UIKitScene.shared.keyboardFrame else { return .null }
                return .string("\(Int(frame.minY)),\(Int(frame.height))")
            }
            let synthetic = JSClosure { arguments in
                MainActor.assumeIsolated {
                    apply(_ViewportReading(windowHeight: arguments[0].number ?? 0, visualHeight: arguments[1].number ?? 0,
                                           visualOffsetTop: arguments.count > 2 ? arguments[2].number ?? 0 : 0,
                                           scale: arguments.count > 3 ? arguments[3].number ?? 1 : 1,
                                           textInputFocused: arguments.count > 4 ? arguments[4].boolean ?? false : false))
                }
                return .undefined
            }
            listeners.append(frame); listeners.append(synthetic)
            debug.keyboardFrame = .object(frame)
            debug.syntheticKeyboardReading = .object(synthetic)
        }
    }

    /// The viewports and focus as the page has them now.
    static func reading(window: JSObject, viewport: JSObject) -> _ViewportReading {
        let active = window.document.object?.activeElement.object
        let tag = active?.tagName.string?.uppercased() ?? ""
        let editable = active?.isContentEditable.boolean ?? false
        return _ViewportReading(
            windowHeight: window.innerHeight.number ?? 0,
            visualHeight: viewport.height.number ?? 0,
            visualOffsetTop: viewport.offsetTop.number ?? 0,
            scale: viewport.scale.number ?? 1,
            textInputFocused: tag == "INPUT" || tag == "TEXTAREA" || editable)
    }

    /// The screen is the page: a SwiftUI app's canvas fills the window (`UIScreen.main.bounds`
    /// is not kept to the window for a SwiftUI app — recorded under uk-app-delegate-adaptor).
    static func apply(_ reading: _ViewportReading) {
        guard !drawsKeyboard else { return }
        let width = JSObject.global.innerWidth.number ?? 0
        UIKitScene.shared.keyboardFrame = _KeyboardFrameEstimator.frame(for: reading, screenSize: CGSize(width: width, height: reading.windowHeight))
    }
}
#endif
