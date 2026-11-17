#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
import WebGraphics
import JavaScriptKit

/// Safari's own scroller driving the canvas's vertical scrolling (new-website#404, from the
/// prototype Tim judged best in new-website#280: Safari's scroller, no bounce).
///
/// The canvas sits pinned (`position: sticky`) inside one invisible `overflow-y: scroll` box that
/// fills the container, followed by a spacer as tall as the driven scroll view's furthest offset.
/// Vertical trackpad and wheel scrolls reach only the box, so the browser scrolls it with its own
/// momentum and timing, and `overscroll-behavior: none` keeps it from bouncing at the ends or
/// handing the scroll to the page. Each frame the host moves the scene's scroll view to the box's
/// `scrollTop` (CSS pixels, one for one with points), and moves the box when the scene moved the
/// view itself. Being pinned, the canvas never shows an edge, so nothing is drawn beyond it.
@MainActor
final class NativeScroller {
    let box: JSObject
    private let spacer: JSObject
    private var routing = NativeScrollRouting()
    /// Where the pointer last was over the canvas, in points: the view a frame at rest picks.
    var lastPoint: CGPoint?
    /// Whether a scene scroll view is driven by the box now.
    private(set) var isDriving = false
    /// The box position the box and the scene last agreed on.
    private var appliedTop: Double = 0
    private var spacerHeight: Double = -1

    init(document: JSObject, canvas: JSObject) {
        box = document.createElement!("div").object!
        _ = box.setAttribute!("data-swiftuiweb-scroller", "")
        box.style.object!.cssText = .string("position:absolute;left:0;top:0;width:100%;height:100%;"
            + "overflow-x:hidden;overflow-y:scroll;overscroll-behavior:none;scrollbar-width:none")
        let pin = document.createElement!("div").object!
        pin.style.object!.cssText = .string("position:sticky;top:0;width:100%;height:100%")
        spacer = document.createElement!("div").object!
        spacer.style.object!.cssText = .string("height:0")
        _ = pin.appendChild!(canvas)
        _ = box.appendChild!(pin)
        _ = box.appendChild!(spacer)
        // WebKit's own scroll bar would still take room and show while scrolling.
        let style = document.createElement!("style").object!
        style.textContent = .string("[data-swiftuiweb-scroller]::-webkit-scrollbar { display: none; }")
        _ = document.head.object?.appendChild!(style)
    }

    /// A trusted, non-pinch wheel event over the canvas: whether the box takes it (the browser
    /// then scrolls the box). A vertical gesture's first event picks the scene's scroll view it
    /// drives through `pick` (nil: none, and the gesture stays with the scene's wheel handling).
    func takesWheel(dx: Double, dy: Double, time: Double, pick: (CGFloat) -> NativeScrollState?) -> Bool {
        switch routing.wheel(dx: dx, dy: dy, time: time) {
        case .startsVertical(let direction):
            follow(pick(CGFloat(direction)))
            return isDriving
        case .continuesVertical:
            return isDriving
        case .horizontal:
            return false
        }
    }

    /// The box's position when it moved since the box and the scene last agreed; nil otherwise.
    func movedTop(time: Double) -> Double? {
        guard isDriving, let top = box.scrollTop.number, top != appliedTop else { return nil }
        appliedTop = top
        routing.lastMoveTime = time
        return top
    }

    /// Stands the box for `state` (nil: no view, and the box cannot scroll): its spacer sized to
    /// the view's furthest offset, and the box moved to the view's offset unless they agree.
    func follow(_ state: NativeScrollState?) {
        guard let state else {
            isDriving = false
            setSpacer(0)
            return
        }
        isDriving = true
        setSpacer(Double(state.maximum))
        if abs(Double(state.offset) - appliedTop) >= 1 {
            box.scrollTop = .number(Double(state.offset))
            appliedTop = box.scrollTop.number ?? Double(state.offset)
        }
    }

    /// Whether no wheel event came and the box did not move for a while (`restTime`).
    func isIdle(at time: Double) -> Bool { routing.isAtRest(at: time) }

    private func setSpacer(_ height: Double) {
        guard height != spacerHeight else { return }
        spacerHeight = height
        spacer.style.object!.height = .string("\(height)px")
    }
}
#endif
