// Safari's own scroller drives vertical scrolling (new-website#404): the canvas host scrolls an
// invisible native scroll element and moves the scene's scroll view to it every frame. These are
// the scene's side (which view the scroller drives, its furthest offset, setting its offset) and
// the host's gesture sorting; the browser side is checked in a real WebKit.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebGraphics

#if !os(WASI)
@Suite @MainActor struct NativeScrollerTests {
    @Observable final class Model {
        var tab = 0
        var sheet = false
        var rows = 20
        var shown = true
    }

    private struct Changing: View {
        let model: Model
        var body: some View {
            if model.shown {
                ScrollView {
                    VStack(spacing: 0) { ForEach(0..<model.rows, id: \.self) { _ in Color.blue.frame(width: 300, height: 100) } }
                }
            } else {
                Color.red
            }
        }
    }

    private let size = CGSize(width: 393, height: 852)

    private func runtime(_ view: some View) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func rows(_ count: Int, height: CGFloat = 100, probe: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in Color.blue.frame(width: 300, height: height) }
            }
            ._probe(probe)
        }
    }

    @Test func drivesTheScrollViewUnderThePointer() {
        let r = runtime(rows(20, probe: "content"))
        let state = r.nativeScrollTarget(at: CGPoint(x: 196, y: 400), direction: 0)
        #expect(state == NativeScrollState(offset: 0, maximum: CGFloat(1148)))
        r.setNativeScrollOffset(300)
        r.layout(in: size)
        #expect(r.probeFrames["content"]?.minY == -300)
        #expect(r.nativeScrollState?.offset == 300)
        // Past the end it stops there: no bounce.
        r.setNativeScrollOffset(5000)
        r.layout(in: size)
        #expect(r.nativeScrollState?.offset == CGFloat(1148))
    }

    @Test func nothingToDriveWhereNothingScrolls() {
        let r = runtime(VStack { rows(3, probe: "short"); Color.red.frame(height: 400) })
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 100), direction: 1) == nil)
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 700), direction: 1) == nil)
        #expect(r.nativeScrollState == nil)
    }

    /// A scroll that starts at an inner view's end moves the view around it (per gesture).
    @Test func handsOverToTheOuterViewAtAnEnd() {
        let r = runtime(ScrollView {
            VStack(spacing: 0) {
                rows(4, probe: "inner").frame(height: 200)
                Color.green.frame(width: 300, height: 1500)
            }
            ._probe("outer")
        })
        let point = CGPoint(x: 196, y: 100)
        #expect(r.nativeScrollTarget(at: point, direction: 1)?.maximum == 200)
        r.setNativeScrollOffset(200)
        r.layout(in: size)
        #expect(r.probeFrames["inner"]?.minY == -200 && r.probeFrames["outer"]?.minY == 0)
        // The inner view is at its end: the next gesture down the page moves the outer one.
        let outer = r.nativeScrollTarget(at: point, direction: 1)
        #expect(outer == NativeScrollState(offset: 0, maximum: CGFloat(848)))
        r.setNativeScrollOffset(100)
        r.layout(in: size)
        #expect(r.probeFrames["outer"]?.minY == -100)
        // Back up, the inner view can move again and takes the gesture.
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 50), direction: -1) == NativeScrollState(offset: 200, maximum: 200))
    }

    @Test func aSidewaysPagerLeavesTheVerticalScrollToThePageAroundIt() {
        let r = runtime(ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) { ForEach(0..<3, id: \.self) { _ in Color.green.frame(width: 393, height: 300) } }
                }
                .scrollTargetBehavior(.paging)
                Color.blue.frame(width: 300, height: 2000)
            }
        })
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 150), direction: 1)?.maximum == CGFloat(1448))
    }

    @Test func aVerticalPagingViewStaysWithTheWheel() {
        let r = runtime(ScrollView {
            VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in Color.green.frame(width: 393, height: 852) } }
        }.scrollTargetBehavior(.paging))
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 400), direction: 1) == nil)
    }

    @Test func aHiddenTabsScrollViewIsNeverDriven() {
        let model = Model()
        let r = runtime(TabView(selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
            rows(20, probe: "first").tabItem { Text("One") }.tag(0)
            rows(40, probe: "second").tabItem { Text("Two") }.tag(1)
        })
        let point = CGPoint(x: 196, y: 400)
        let first = r.nativeScrollTarget(at: point, direction: 0)
        #expect(first?.maximum ?? 0 > 0)
        r.setNativeScrollOffset(250)
        model.tab = 1
        r.layout(in: size)
        // The second tab's view, at its own offset, with its own (longer) extent.
        let second = r.nativeScrollTarget(at: point, direction: 0)
        #expect(second?.offset == 0)
        #expect((second?.maximum ?? 0) == (first?.maximum ?? 0) + 2000)
    }

    @Test func aSheetTakesItsOwnScrollView() {
        let model = Model()
        let r = runtime(rows(20, probe: "behind").sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            rows(30, probe: "sheet")
        })
        let behind = r.nativeScrollTarget(at: CGPoint(x: 196, y: 600), direction: 0)
        model.sheet = true
        r.layout(in: size)
        for _ in 0..<120 { _ = r.advanceFrame(elapsed: 1.0 / 60); r.layout(in: size) }
        let sheet = r.nativeScrollTarget(at: CGPoint(x: 196, y: 600), direction: 0)
        #expect(sheet != nil && sheet?.maximum != behind?.maximum)
        r.setNativeScrollOffset(120)
        r.layout(in: size)
        #expect(r.probeFrames["sheet"].map { $0.minY } != nil)
        #expect(r.nativeScrollState?.offset == 120)
    }

    @Test func followsContentThatGrowsAndViewsThatGo() {
        let model = Model()
        let r = runtime(Changing(model: model))
        #expect(r.nativeScrollTarget(at: CGPoint(x: 196, y: 400), direction: 0)?.maximum == CGFloat(1148))
        model.rows = 30
        r.layout(in: size)
        #expect(r.nativeScrollState?.maximum == CGFloat(2148))
        model.shown = false
        r.layout(in: size)
        #expect(r.nativeScrollState == nil)
    }

    /// The host picks a view on every quiet frame: that never closes an open menu or popover,
    /// as a press outside it would.
    @Test func pickingLeavesAnOpenPopoverOpen() {
        let model = Model()
        let r = Runtime()
        r.mount(VStack {
            Text("Anchor").popover(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { Text("Inside").frame(width: 120, height: 80) }
            rows(20, probe: "list")
        })
        r.layout(in: size)
        model.sheet = true
        r.layout(in: size)
        #expect(r.presentations.count == 1)
        _ = r.nativeScrollTarget(at: CGPoint(x: 196, y: 800), direction: 0)
        r.layout(in: size)
        #expect(r.presentations.count == 1 && model.sheet)
    }

    // MARK: The host's gesture sorting

    @Test func aGestureKeepsItsAxis() {
        var routing = NativeScrollRouting()
        #expect(routing.wheel(dx: 0, dy: 4, time: 0) == .startsVertical(direction: 1))
        #expect(routing.wheel(dx: 6, dy: 2, time: 0.016) == .continuesVertical)
        // A tenth of a second of quiet starts another gesture, sideways this time.
        #expect(routing.wheel(dx: -5, dy: 1, time: 0.2) == .horizontal)
        #expect(routing.wheel(dx: 1, dy: 3, time: 0.216) == .horizontal)
        // An event wholly along the other axis starts one at once.
        #expect(routing.wheel(dx: 0, dy: -3, time: 0.232) == .startsVertical(direction: -1))
    }

    @Test func atRestAfterTheTail() {
        var routing = NativeScrollRouting()
        _ = routing.wheel(dx: 0, dy: 4, time: 1)
        routing.lastMoveTime = 1.1
        #expect(!routing.isAtRest(at: 1.2))
        #expect(routing.isAtRest(at: 1.3))
    }
}
#endif
