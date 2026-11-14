// An iOS sheet's motion (new-website#264): it slides up on UIKit's navigation spring when
// presented, follows a finger dragging it down, closes when the finger lets go far or fast
// enough (springing back otherwise), slides off when dismissed, and scroll views inside it take
// touches. Curves measured in the iOS 27 simulator (new-website#262).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SheetMotionTests {
    @Observable final class Model {
        var sheet = false
        var cover = false
        var dismissed = 0
    }

    struct Presenter: View {
        let model: Model
        var scrolls = false
        var body: some View {
            @Bindable var model = model
            Text("Behind")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $model.sheet, onDismiss: { model.dismissed += 1 }) {
                    if scrolls {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(0..<40) { _ in Color.gray.frame(height: 44) }
                            }
                        }
                    } else {
                        Text("Lights out").frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .fullScreenCover(isPresented: $model.cover) { Text("Cover") }
        }
    }

    private let size = CGSize(width: 393, height: 852)

    private func runtime(_ view: some View) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    /// One display frame: the clock advances and the frame is laid out and painted.
    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        _ = r.render(scale: 3)
    }

    private func settle(_ r: Runtime) { for _ in 0..<90 { frame(r) } }

    /// The presented sheet's distance below its resting place.
    private func sheetOffset(_ r: Runtime) -> Double { r.presentations.last?.slide.position ?? .nan }

    /// A touch drag in steps of one display frame; `hold` seconds still before lifting.
    private func drag(_ r: Runtime, from a: CGPoint, to b: CGPoint, duration: Double, hold: Double = 0) {
        var t = 10.0
        r.pointerDown(at: a, type: .touch, time: t)
        let steps = max(1, Int((duration * 60).rounded()))
        for i in 1...steps {
            t += duration / Double(steps)
            let f = Double(i) / Double(steps)
            r.pointerMoved(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), time: t)
            frame(r)
        }
        if hold > 0 { t += hold; frame(r, hold) }
        r.pointerUp(at: b, time: t)
    }

    @Test func aSheetSlidesUpLikeTheSimulators() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        model.sheet = true
        r.layout(in: size)
        // It starts just below the window: the card's top (59) to the bottom.
        #expect(sheetOffset(r) == 852 - 59)
        var curve: [(Double, Double)] = []
        for i in 1...40 {
            frame(r)
            curve.append((Double(i) / 60, sheetOffset(r)))
        }
        #expect(sheetOffset(r) == 0)
        // Against the simulator's Lights out sheet rising: within a few points (rms 4.5, most of
        // it in the first fast frames, where 3 ms is 12 pt).
        var best = Double.infinity
        for shift in stride(from: -0.05, through: 0.05, by: 0.001) {
            let sum = PhysicsTests.sheetOpen.reduce(0.0) { acc, sample in
                let t = sample.0 / 1000 - shift
                let model = SpringModel.navigation.state(displacement: 793, velocity: 0, at: max(0, t)).displacement
                return acc + (model - sample.1) * (model - sample.1)
            }
            best = min(best, (sum / Double(PhysicsTests.sheetOpen.count)).squareRoot())
        }
        #expect(best < 5, "rms \(best)")
        // The browser's frames follow the same spring.
        for (t, offset) in curve {
            #expect(abs(offset - SpringModel.navigation.state(displacement: 793, velocity: 0, at: t).displacement) < 0.5)
        }
    }

    @Test func aSheetThereFromTheFirstFrameDoesNotSlide() {
        let model = Model()
        model.sheet = true
        let r = runtime(Presenter(model: model))
        #expect(sheetOffset(r) == 0)
        #expect(!r.isAnimating)
    }

    @Test func draggingASheetDownFarClosesIt() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        model.sheet = true
        r.layout(in: size)
        settle(r)
        // The simulator's drag: 500 pt down in 1.5 s.
        drag(r, from: CGPoint(x: 196, y: 250), to: CGPoint(x: 196, y: 750), duration: 1.5)
        #expect(!model.sheet && model.dismissed == 1)
        #expect(!r.hasPresentations && r.leavingPresentations.count == 1)
        // It slides on from where the finger left it, then is gone.
        let left = r.leavingPresentations.first?.slide.position ?? 0
        #expect(left > 480)
        frame(r)
        #expect((r.leavingPresentations.first?.slide.position ?? .infinity) > left)
        settle(r)
        #expect(r.leavingPresentations.isEmpty && !r.isAnimating)
    }

    @Test func aFlickClosesAndAShortSlowDragSpringsBack() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        model.sheet = true
        r.layout(in: size)
        settle(r)
        // 120 pt, then the finger rests before lifting: the sheet goes back up.
        drag(r, from: CGPoint(x: 196, y: 300), to: CGPoint(x: 196, y: 420), duration: 0.3, hold: 0.2)
        #expect(model.sheet && r.hasPresentations)
        #expect(sheetOffset(r) > 100)
        settle(r)
        #expect(sheetOffset(r) == 0)
        // 120 pt in a tenth of a second: fast enough to close.
        drag(r, from: CGPoint(x: 196, y: 300), to: CGPoint(x: 196, y: 420), duration: 0.1)
        #expect(!model.sheet)
    }

    @Test func aScrollViewInASheetScrollsAndHandsTheSheetWhatIsPastItsTop() {
        let model = Model()
        let r = runtime(Presenter(model: model, scrolls: true))
        model.sheet = true
        r.layout(in: size)
        settle(r)
        // Up: the rows scroll, the sheet stays.
        drag(r, from: CGPoint(x: 196, y: 600), to: CGPoint(x: 196, y: 400), duration: 0.5, hold: 0.2)
        let scrolled = r.debugScrollViews.last?[5] ?? 0
        #expect(scrolled > 150, "\(r.debugScrollViews)")
        #expect(sheetOffset(r) == 0)
        // Down from there: the rows scroll back to the top first, then the sheet follows (the
        // finger's first 10 pt are the drag's slop, as on iOS).
        drag(r, from: CGPoint(x: 196, y: 300), to: CGPoint(x: 196, y: 300 + scrolled + 90), duration: 0.8, hold: 0.2)
        #expect(r.debugScrollViews.last?[5] == 0)
        #expect(abs(sheetOffset(r) - 80) < 1, "\(sheetOffset(r))")
        #expect(model.sheet)
    }

    @Test func aCoverSlidesUpButIsNotDraggedAway() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        model.cover = true
        r.layout(in: size)
        #expect(sheetOffset(r) == 852)
        settle(r)
        #expect(sheetOffset(r) == 0)
        drag(r, from: CGPoint(x: 196, y: 250), to: CGPoint(x: 196, y: 750), duration: 0.3)
        #expect(model.cover && sheetOffset(r) == 0)
    }

    @Test func dismissingSlidesTheSheetOff() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        model.sheet = true
        r.layout(in: size)
        settle(r)
        model.sheet = false
        r.layout(in: size)
        #expect(!r.hasPresentations && r.leavingPresentations.count == 1)
        // Presses go to the screen behind at once.
        #expect(r.presentationHit(at: CGPoint(x: 196, y: 400)).handled == false)
        frame(r); frame(r)
        #expect((r.leavingPresentations.first?.slide.position ?? 0) > 0)
        settle(r)
        #expect(r.leavingPresentations.isEmpty)
    }
}
#endif
