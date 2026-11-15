// On iOS a mouse or trackpad press-and-drag is the finger, as in Apple's iPhone Simulator on a
// Mac (new-website#283, #288): it drags and flicks lists, swipes pages, pulls sheets down and
// long-presses, along the very path a touch takes; a click is a tap; wheels and two-finger
// scrolls keep scrolling. A Mac app's mouse drag stays a Mac drag.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PressActsAsFingerTests {
    @Observable final class Model {
        var sheet = false
        var taps = 0
        var longPresses = 0
    }

    private struct Rows: View {
        let model: Model
        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<60, id: \.self) { _ in
                        Color.blue.frame(width: 300, height: 40).onTapGesture { model.taps += 1 }
                    }
                }
                ._probe("content")
            }
        }
    }

    private struct Pager: View {
        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in Color.green.frame(width: 393, height: 300) }
                }
                ._probe("pages")
            }
            .scrollTargetBehavior(.paging)
        }
    }

    private struct SheetPresenter: View {
        let model: Model
        var body: some View {
            @Bindable var model = model
            Text("Behind")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $model.sheet) { Text("Sheet").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    private let size = CGSize(width: 393, height: 852)

    private func runtime(_ view: some View, iOS: Bool = true) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
    }

    /// A drag in steps of one display frame with `type`, lifted at speed, then every frame of
    /// what follows; returns the probe's position after each frame.
    private func drag(_ r: Runtime, _ type: PointerType, from a: CGPoint, to b: CGPoint, duration: Double, probe: String, axis: Axis = .vertical, follow: Int = 120) -> [CGFloat] {
        var t = 10.0
        var trace: [CGFloat] = []
        func record() {
            let f = r.probeFrames[probe] ?? .zero
            trace.append(axis == .vertical ? f.minY : f.minX)
        }
        r.pointerDown(at: a, type: type, time: t)
        let steps = max(1, Int((duration * 60).rounded()))
        for i in 1...steps {
            t += duration / Double(steps)
            let f = Double(i) / Double(steps)
            r.pointerMoved(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), time: t)
            frame(r)
            record()
        }
        r.pointerUp(at: b, time: t)
        for _ in 0..<follow { frame(r); record() }
        return trace
    }

    @Test func aPressedDragMovesAListExactlyLikeAFinger() {
        let finger = runtime(Rows(model: Model()))
        let mouse = runtime(Rows(model: Model()))
        let path = (CGPoint(x: 150, y: 600), CGPoint(x: 150, y: 300))
        let touched = drag(finger, .touch, from: path.0, to: path.1, duration: 0.15, probe: "content")
        let pressed = drag(mouse, .mouse, from: path.0, to: path.1, duration: 0.15, probe: "content")
        // It follows from where it left the 10 pt slop, then coasts on well past the lift.
        #expect(abs(pressed[8] - -290) < 0.01)
        #expect(pressed.last! < -600)
        #expect(pressed == touched)
    }

    @Test func aPressedDragSwipesPagesLikeAFinger() {
        let finger = runtime(Pager())
        let mouse = runtime(Pager())
        let path = (CGPoint(x: 300, y: 426), CGPoint(x: 160, y: 426))
        let touched = drag(finger, .touch, from: path.0, to: path.1, duration: 0.15, probe: "pages", axis: .horizontal)
        let pressed = drag(mouse, .mouse, from: path.0, to: path.1, duration: 0.15, probe: "pages", axis: .horizontal)
        #expect(pressed.last == -393)
        #expect(pressed == touched)
    }

    @Test func aPressedDragPullsASheetDownAndClosesIt() {
        let model = Model()
        let r = runtime(SheetPresenter(model: model))
        model.sheet = true
        r.layout(in: size)
        for _ in 0..<90 { frame(r) }
        #expect(r.hasPresentations)
        _ = drag(r, .mouse, from: CGPoint(x: 196, y: 250), to: CGPoint(x: 196, y: 750), duration: 1.5, probe: "none", follow: 0)
        #expect(!model.sheet)
    }

    @Test func aClickIsATapAndAPressWithinTheSlopToo() {
        let model = Model()
        let r = runtime(Rows(model: model))
        r.pointerDown(at: CGPoint(x: 196, y: 20), type: .mouse, time: 0)
        r.pointerUp(at: CGPoint(x: 196, y: 20), time: 0.08)
        #expect(model.taps == 1)
        // A hand that wobbles less than iOS's 10 pt still taps; the list stays put.
        r.pointerDown(at: CGPoint(x: 196, y: 20), type: .mouse, time: 1)
        r.pointerMoved(to: CGPoint(x: 199, y: 26), time: 1.05)
        r.pointerUp(at: CGPoint(x: 199, y: 26), time: 1.1)
        r.layout(in: size)
        #expect(model.taps == 2)
        #expect(r.probeFrames["content"]?.minY == 0)
        // A press dragged past it scrolls and taps nothing.
        r.pointerDown(at: CGPoint(x: 196, y: 20), type: .mouse, time: 2)
        r.pointerMoved(to: CGPoint(x: 196, y: 80), time: 2.05)
        r.pointerUp(at: CGPoint(x: 196, y: 80), time: 2.1)
        #expect(model.taps == 2)
    }

    @Test func aPressHeldStillIsALongPress() {
        let model = Model()
        let r = runtime(ScrollView {
            Color.red.frame(width: 300, height: 100).onLongPressGesture(minimumDuration: 0.5) { model.longPresses += 1 }
            Color.blue.frame(width: 300, height: 2000)
        })
        r.pointerDown(at: CGPoint(x: 150, y: 50), type: .mouse, time: 0)
        r.advanceAnimations(elapsed: 0.6)
        r.pointerUp(at: CGPoint(x: 150, y: 50), time: 0.6)
        #expect(model.longPresses == 1)
    }

    @Test func wheelAndTwoFingerScrollingStillScroll() {
        let r = runtime(Rows(model: Model()))
        r.scrollWheel(by: CGSize(width: 0, height: 120), at: CGPoint(x: 150, y: 300), time: 0)
        r.layout(in: size)
        #expect(r.probeFrames["content"]?.minY == -120)
    }

    @Test func aMacAppsMouseDragDoesNotScroll() {
        let model = Model()
        let r = runtime(Rows(model: model), iOS: false)
        #expect(!r.pressActsAsFinger(.mouse) && r.pressActsAsFinger(.touch))
        r.pointerDown(at: CGPoint(x: 150, y: 600), type: .mouse, time: 0)
        r.pointerMoved(to: CGPoint(x: 150, y: 300), time: 0.1)
        r.pointerUp(at: CGPoint(x: 150, y: 300), time: 0.2)
        r.layout(in: size)
        #expect(r.probeFrames["content"]?.minY == 0)
    }
}
#endif
