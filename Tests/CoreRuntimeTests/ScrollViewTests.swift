// Phase 2, element 3: ScrollView sizing, offsets, programmatic and user scrolling, clipping.
import Testing
import SwiftUI

@Observable
private final class Target {
    var row: Int? = nil
}

private struct Reader: View {
    let target: Target
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { index in
                        Color.blue.frame(width: 100, height: 20)._probe("row\(index)").id(index)
                    }
                }
            }
            ._probe("scroll")
            .onChange(of: target.row) { _, row in
                if let row { proxy.scrollTo(row, anchor: row == 3 ? .top : nil) }
            }
        }
    }
}

/// The reader inside the scroll view it drives, as many apps place it.
private struct InnerReader: View {
    let target: Target
    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { index in
                        Color.blue.frame(width: 100, height: 20)._probe("row\(index)").id(index)
                    }
                }
                .onChange(of: target.row) { _, row in
                    if let row { proxy.scrollTo(row, anchor: .bottom) }
                }
            }
        }
    }
}

@Observable
private final class ValueBox {
    var value = 0.0
}

@Observable
private final class Counter {
    var value = 0
}

private struct Changing: View {
    let counter: Counter
    let log: (String) -> Void
    var body: some View {
        Color.red
            .onChange(of: counter.value) { old, new in log("\(old)->\(new)") }
            .onChange(of: counter.value, initial: true) { log("any") }
    }
}

@Suite @MainActor struct ScrollViewTests {
    private func rows(_ count: Int, width: CGFloat = 100) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in Color.blue.frame(width: width, height: 20) }
        }
        ._probe("content")
    }

    @Test func fillsScrollAxisAndFitsContentAcrossIt() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(5) }._probe("scroll"))
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["scroll"] == CGRect(x: 100, y: 0, width: 100, height: 200))
        #expect(runtime.probeFrames["content"] == CGRect(x: 100, y: 0, width: 100, height: 100))

        let horizontal = Runtime()
        horizontal.mount(ScrollView(.horizontal) { Color.blue.frame(width: 500, height: 40)._probe("content") }._probe("scroll"))
        horizontal.layout(in: CGSize(width: 300, height: 200))
        #expect(horizontal.probeFrames["scroll"] == CGRect(x: 0, y: 80, width: 300, height: 40))
        #expect(horizontal.probeFrames["content"] == CGRect(x: 0, y: 80, width: 500, height: 40))
    }

    @Test func wideContentWidensTheScrollView() {
        let runtime = Runtime()
        runtime.mount(ScrollView { Color.blue.frame(width: 400, height: 400)._probe("content") }._probe("scroll"))
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["scroll"] == CGRect(x: -50, y: 0, width: 400, height: 200))
    }

    @Test func defaultAnchorStartsAtTheEnd() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(20) }.defaultScrollAnchor(.bottom)._probe("scroll"))
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"] == CGRect(x: 100, y: -200, width: 100, height: 400))
    }

    @Test func wheelScrollingClampsAndChains() {
        let runtime = Runtime()
        runtime.mount(
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ScrollView { rows(20) }._probe("inner").frame(width: 100, height: 200)
                    Color.red.frame(width: 400, height: 200)
                }
            }
            ._probe("outer"))
        runtime.layout(in: CGSize(width: 300, height: 200))
        let inside = CGPoint(x: 50, y: 100)
        runtime.scrollWheel(by: CGSize(width: 0, height: 50), at: inside)
        #expect(runtime.needsFrame)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]?.minY == -50)
        #expect(!runtime.layoutRequested)

        // Past the end: the inner clamps at 200 and nothing else moves vertically.
        runtime.scrollWheel(by: CGSize(width: 0, height: 1000), at: inside)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]?.minY == -200)
        #expect(runtime.probeFrames["inner"]?.minX == 0)

        // A horizontal delta over the inner (vertical-only) view chains to the outer.
        runtime.scrollWheel(by: CGSize(width: 120, height: 0), at: inside)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["inner"]?.minX == -120)
        #expect(runtime.probeFrames["content"]?.minY == -200)

        // Negative deltas scroll back and clamp at zero. The inner view moved out from under the
        // point with the outer's content, so only the outer takes the first delta.
        runtime.scrollWheel(by: CGSize(width: -500, height: -500), at: inside)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["inner"]?.minX == 0)
        #expect(runtime.probeFrames["content"]?.minY == -200)
        runtime.scrollWheel(by: CGSize(width: 0, height: -500), at: inside)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]?.minY == 0)
    }

    @Test func scrollDisabledIgnoresInput() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(20) }.scrollDisabled(true))
        runtime.layout(in: CGSize(width: 300, height: 200))
        runtime.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 150, y: 100))
        #expect(!runtime.needsFrame)
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]?.minY == 0)
    }

    @Test func scrollToAlignsOnTheAnchorOrMinimally() {
        let target = Target()
        let runtime = Runtime()
        runtime.mount(Reader(target: target))
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row15"]?.minY == 300)

        target.row = 15                       // below the fold, no anchor: bottom-aligned
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row15"]?.minY == 180)
        #expect(runtime.probeFrames["row0"]?.minY == -120)

        target.row = 3                        // anchor .top
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row3"]?.minY == 0)

        target.row = 0                        // above, no anchor: back to the top
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row0"]?.minY == 0)

        target.row = 99                       // unknown id: nothing moves
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row0"]?.minY == 0)
    }

    @Test func scrollToReachesTheScrollViewAroundTheReader() {
        let target = Target()
        let runtime = Runtime()
        runtime.mount(InnerReader(target: target))
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row15"]?.minY == 300)

        target.row = 15                       // anchor .bottom: the row ends at the bottom edge
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row15"]?.minY == 180)

        target.row = 99                       // unknown id: nothing moves
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["row15"]?.minY == 180)
    }

    @Test func onChangeRunsAfterUpdatesWithOldAndNewValues() {
        let counter = Counter()
        var log: [String] = []
        let runtime = Runtime()
        runtime.mount(Changing(counter: counter, log: { log.append($0) }))
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(log == ["any"])
        counter.value = 2
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(log == ["any", "0->2", "any"])
        counter.value = 2                     // same value: no action
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(log == ["any", "0->2", "any"])
    }

    @Test func paintsClippedContentAtTheOffset() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(3, width: 50) }.frame(width: 50, height: 30))
        runtime.layout(in: CGSize(width: 50, height: 30))
        runtime.scrollWheel(by: CGSize(width: 0, height: 10), at: CGPoint(x: 25, y: 15))
        runtime.layout(in: CGSize(width: 50, height: 30))
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands.prefix(5) == ["save", "clipRect(0, 0, 50, 30)",
                                       "fillRect(0, -10, 50, 20) #0088FF", "fillRect(0, 10, 50, 20) #0088FF", "fillRect(0, 30, 50, 20) #0088FF"])
        #expect(commands[5] == "restore")
        // The indicator shows while scrolling: a 20 pt knob 3 pt from the trailing edge, a third of
        // the way along its 4 pt travel (offset 10 of 30), then it fades.
        #expect(commands.count == 8)
        // The knob: its white halo, then the 7 pt core 2 pt from the trailing edge and 4 pt from the top.
        #expect(commands[6] == "fillRRect(40, 3.5, 9, 22) r=4.5 #FFFFFF@0.15")
        #expect(commands[7] == "fillRRect(41, 4.5, 7, 20) r=3.5 #000000@0.5")
        #expect(runtime.advanceScrollAnimations(elapsed: 0.5))
        #expect(runtime.advanceScrollAnimations(elapsed: 0.5))
        #expect(!runtime.advanceScrollAnimations(elapsed: 0.5))
        runtime.layout(in: CGSize(width: 50, height: 30))
        #expect(runtime.render(scale: 2).commands.count == 6)

        let unclipped = Runtime()
        unclipped.mount(ScrollView { rows(3, width: 50) }.scrollClipDisabled().frame(width: 50, height: 30))
        unclipped.layout(in: CGSize(width: 50, height: 30))
        #expect(unclipped.render(scale: 2).commands.map(\.description).first == "fillRect(0, 0, 50, 20) #0088FF")
    }

    @Test func touchPanScrollsAndDecelerates() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(50) })
        runtime.layout(in: CGSize(width: 300, height: 200))
        runtime.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 0)
        runtime.pointerMoved(to: CGPoint(x: 150, y: 145), time: 0.01)      // within the slop: no pan yet
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]?.minY == 0)
        runtime.pointerMoved(to: CGPoint(x: 150, y: 100), time: 0.02)      // 50 pt in 20 ms
        runtime.layout(in: CGSize(width: 300, height: 200))
        // The content follows from where the finger left the 10 pt slop, as on iOS (a 100 pt
        // drag in the simulator moves a page 90 pt; new-website#216).
        #expect(runtime.probeFrames["content"]?.minY == -40)
        runtime.pointerUp(at: CGPoint(x: 150, y: 100), time: 0.03)
        #expect(runtime.needsFrame)
        // Momentum keeps the content moving, slowing down and stopping on its own.
        #expect(runtime.advanceScrollAnimations(elapsed: 0.016))
        runtime.layout(in: CGSize(width: 300, height: 200))
        let afterOneFrame = runtime.probeFrames["content"]!.minY
        #expect(afterOneFrame < -50)
        var frames = 0
        while runtime.advanceScrollAnimations(elapsed: 0.016) { frames += 1; #expect(frames < 1000) }
        runtime.layout(in: CGSize(width: 300, height: 200))
        #expect(runtime.probeFrames["content"]!.minY < afterOneFrame)
        #expect(runtime.probeFrames["content"]!.minY >= -800)
    }

    @Test func touchDuringDecelerationStopsItAndOwnsTheTouch() {
        let counter = Counter()
        let runtime = Runtime()
        runtime.mount(ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<50, id: \.self) { _ in
                    Button("Row") { counter.value += 1 }.frame(width: 300, height: 20)
                }
            }
            ._probe("content")
        })
        let size = CGSize(width: 300, height: 200)
        runtime.layout(in: size)
        // A flick, then lift: momentum runs.
        runtime.pointerDown(at: CGPoint(x: 150, y: 150), type: .touch, time: 0)
        runtime.pointerMoved(to: CGPoint(x: 150, y: 100), time: 0.02)
        runtime.pointerUp(at: CGPoint(x: 150, y: 100), time: 0.03)
        #expect(runtime.advanceScrollAnimations(elapsed: 0.016))
        runtime.layout(in: size)
        let stoppedAt = runtime.probeFrames["content"]!.minY
        #expect(stoppedAt < -50)
        // A finger landing on the moving content stops it where it is...
        runtime.pointerDown(at: CGPoint(x: 150, y: 100), type: .touch, time: 1)
        _ = runtime.advanceScrollAnimations(elapsed: 0.016)   // only the indicator fade is left
        runtime.layout(in: size)
        #expect(runtime.probeFrames["content"]?.minY == stoppedAt)
        // ...follows it at once, without the slop...
        runtime.pointerMoved(to: CGPoint(x: 150, y: 96), time: 1.02)
        runtime.layout(in: size)
        #expect(runtime.probeFrames["content"]?.minY == stoppedAt - 4)
        // ...and lifting presses nothing (the row under the finger stays untapped).
        runtime.pointerUp(at: CGPoint(x: 150, y: 96), time: 1.5)
        #expect(counter.value == 0)
        // A touch on resting content still taps.
        runtime.pointerDown(at: CGPoint(x: 150, y: 96), type: .touch, time: 2)
        runtime.pointerUp(at: CGPoint(x: 150, y: 96), time: 2.05)
        #expect(counter.value == 1)
    }

    /// A slider inside a vertical scroll view: a finger that sets off sideways drives the knob
    /// and keeps it even when it wanders vertically afterwards; one that sets off vertically
    /// scrolls. A finger that rests on the knob first keeps it whichever way it then moves.
    @Test func sliderInScrollViewKeepsSidewaysTouches() {
        let box = ValueBox()
        let runtime = Runtime()
        runtime.mount(ScrollView {
            VStack(spacing: 0) {
                rows(3)
                Slider(value: Binding(get: { box.value }, set: { box.value = $0 }), in: 0...100)
                    .frame(width: 220)._probe("slider")
                rows(50)
            }
            ._probe("content")
        })
        let size = CGSize(width: 300, height: 200)
        runtime.layout(in: size)
        let track = runtime.probeFrames["slider"]!
        let y = track.midY
        // Sideways past the slop: the value follows the finger, the content stays put...
        runtime.pointerDown(at: CGPoint(x: track.minX + 20, y: y), type: .touch, time: 0)
        let pressed = box.value
        runtime.pointerMoved(to: CGPoint(x: track.minX + 40, y: y + 3), time: 0.02)
        runtime.layout(in: size)
        #expect(box.value > pressed)
        #expect(runtime.probeFrames["content"]?.minY == 0)
        // ...and a vertical wander afterwards still drives the slider, not the scroll view.
        let sideways = box.value
        runtime.pointerMoved(to: CGPoint(x: track.minX + 60, y: y + 60), time: 0.05)
        runtime.layout(in: size)
        #expect(box.value > sideways)
        #expect(runtime.probeFrames["content"]?.minY == 0)
        runtime.pointerUp(at: CGPoint(x: track.minX + 60, y: y + 60), time: 0.06)
        // A finger that sets off vertically scrolls; the slider keeps the value it jumped to.
        let before = box.value
        runtime.pointerDown(at: CGPoint(x: track.minX + 60, y: y), type: .touch, time: 1)
        let jumped = box.value
        runtime.pointerMoved(to: CGPoint(x: track.minX + 63, y: y - 30), time: 1.02)
        runtime.layout(in: size)
        // Past the 10 pt slop along the finger's path (3, -30): the content follows the rest.
        let followed = -30 * (1 - 10 / (3.0 * 3 + 30 * 30).squareRoot())
        #expect(abs((runtime.probeFrames["content"]?.minY ?? 0) - followed) < 0.01)
        #expect(box.value == jumped)
        #expect(before == jumped)
        runtime.pointerUp(at: CGPoint(x: track.minX + 63, y: y - 30), time: 1.5)
        _ = runtime.advanceScrollAnimations(elapsed: 0.016)
        runtime.layout(in: size)
        // A finger that rests on the knob (the content stays scrolled) keeps it even when it
        // then moves vertically.
        let scrolled = runtime.probeFrames["slider"]!
        runtime.pointerDown(at: CGPoint(x: scrolled.minX + 60, y: scrolled.midY), type: .touch, time: 2)
        let held = box.value
        runtime.pointerMoved(to: CGPoint(x: scrolled.minX + 60, y: scrolled.midY + 2), time: 2.1)
        runtime.pointerMoved(to: CGPoint(x: scrolled.minX + 80, y: scrolled.midY + 40), time: 2.3)
        runtime.layout(in: size)
        #expect(box.value > held)
        #expect(abs((runtime.probeFrames["content"]?.minY ?? 0) - followed) < 0.01)
    }

    @Test func mouseInputStillPressesButtons() {
        var taps = 0
        let runtime = Runtime()
        runtime.mount(ScrollView { Button("Tap") { taps += 1 }.frame(width: 100, height: 40) })
        runtime.layout(in: CGSize(width: 300, height: 200))
        runtime.pointerDown(at: CGPoint(x: 150, y: 20))
        runtime.pointerUp(at: CGPoint(x: 150, y: 20))
        #expect(taps == 1)
        // A touch that pans cancels the press instead of activating it.
        runtime.pointerDown(at: CGPoint(x: 150, y: 20), type: .touch, time: 0)
        runtime.pointerMoved(to: CGPoint(x: 150, y: 60), time: 0.05)
        runtime.pointerUp(at: CGPoint(x: 150, y: 60), time: 0.1)
        #expect(taps == 1)
    }
}
