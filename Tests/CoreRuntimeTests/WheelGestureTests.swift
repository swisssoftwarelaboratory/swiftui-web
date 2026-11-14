// Trackpad swipes as a browser delivers them: wheel events about 16 ms apart, the finger's part
// and then the OS's momentum tail, with no event saying where one ends (new-website#216).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)

@Observable private final class PagerModel { var index = 0 }

/// The pager alone: paging, no position binding.
private struct PlainPager: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.gray.frame(height: 100)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in Text("page \(i)").frame(height: 80).containerRelativeFrame(.horizontal).id(i) }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                Color.gray.frame(height: 900)
            }
        }
    }
}

/// A paged card inside a vertical page, wired like a real app's pager (a position binding kept in
/// step with an index).
private struct PagedCard: View {
    let model: PagerModel
    @State private var position: Int?
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.gray.frame(height: 100)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { i in Text("page \(i)").frame(height: 80).containerRelativeFrame(.horizontal).id(i) }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $position)
                .onAppear { position = model.index }
                .onChange(of: position) { _, new in if let new, new != model.index { model.index = new } }
                .onChange(of: model.index) { _, new in if new != position { position = new } }
                Color.gray.frame(height: 900)
            }
        }
    }
}

@Suite @MainActor struct WheelGestureTests {
    private let size = CGSize(width: 300, height: 600)

    /// Seconds on the test's clock: one frame a sixtieth of a second.
    private final class Clock { var now = 0.0 }

    private func runtime(_ model: PagerModel, clock: Clock = Clock()) -> Runtime {
        let r = Runtime()
        r.wheelClock = { clock.now }
        Self.clock = clock
        r.textEngine = MetricsTextEngine()
        r.mount(PagedCard(model: model))
        for _ in 0..<3 { r.layout(in: size) }
        return r
    }

    private static var clock = Clock()

    private func frame(_ r: Runtime) {
        Self.clock.now += 1.0 / 60
        _ = r.advanceScrollAnimations(elapsed: 1.0 / 60)
        r.layout(in: size)
    }

    /// One gesture over the card: `finger` events of (dx, dy), then a momentum tail decaying by
    /// 0.92 an event, then a second of frames.
    @discardableResult
    private func swipe(_ r: Runtime, dx: CGFloat, dy: CGFloat, finger: Int = 10, at point: CGPoint = CGPoint(x: 150, y: 140),
                       watch: (() -> Void)? = nil) -> Int {
        var event = CGSize(width: dx, height: dy)
        var events = 0
        for _ in 0..<finger { r.scrollWheel(by: event, at: point); frame(r); events += 1; watch?() }
        while abs(event.width) > 0.3 || abs(event.height) > 0.3 {
            event = CGSize(width: event.width * 0.92, height: event.height * 0.92)
            r.scrollWheel(by: event, at: point); frame(r); events += 1; watch?()
        }
        for _ in 0..<12 { frame(r) }   // a pause ends the gesture
        for _ in 0..<48 { frame(r); watch?() }
        return events
    }

    /// The card's offset: how far "page 0" moved left from where it is drawn at rest.
    private func cardOffset(_ r: Runtime) -> Double? {
        for command in r.render(scale: 2).commands.map(\.description) where command.hasPrefix("drawText(\"page 0\"") {
            guard let range = command.range(of: " at "), let x = Double(command[range.upperBound...].split(separator: ",").first ?? "") else { continue }
            return 127.5 - x
        }
        return nil
    }

    /// The vertical page's offset: where the card's "page" texts sit vertically.
    private func pageTop(_ r: Runtime) -> Double? {
        for command in r.render(scale: 2).commands.map(\.description) where command.hasPrefix("drawText(\"page ") {
            guard let range = command.range(of: " at ") else { continue }
            let coordinates = command[range.upperBound...].split(separator: " ").first?.split(separator: ",") ?? []
            if coordinates.count == 2 { return Double(coordinates[1]) }
        }
        return nil
    }

    private func pages(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).compactMap { command in
            guard command.hasPrefix("drawText(\"page "), let range = command.range(of: " at ") else { return nil }
            let x = Double(command[range.upperBound...].split(separator: ",").first ?? "") ?? -1
            return x >= 0 && x < 300 ? String(command.dropFirst(10).prefix(6)) : nil
        }
    }

    @Test func eachSwipeTurnsOnePageItsWay() {
        let model = PagerModel()
        let r = runtime(model)
        #expect(pages(r) == ["page 0"])
        swipe(r, dx: 14, dy: 0)
        #expect(model.index == 1, "\(pages(r))")
        swipe(r, dx: 14, dy: 0)
        #expect(model.index == 2, "\(pages(r))")
        swipe(r, dx: -14, dy: 0)
        #expect(model.index == 1, "\(pages(r))")
        #expect(pages(r) == ["page 1"])
    }

    /// The page is reached within about 0.35 s of the momentum starting, not after its tail.
    @Test func aSwipeSettlesAsTheFingerLifts() {
        let model = PagerModel()
        let r = runtime(model)
        var settledAt: Int?
        var frames = 0
        swipe(r, dx: 14, dy: 0) {
            frames += 1
            if settledAt == nil, let offset = self.cardOffset(r), abs(offset - 300) < 0.5 { settledAt = frames }
        }
        #expect(model.index == 1)
        // 10 finger events, then about 0.35 s of settling: well before the 60-event tail ends.
        #expect((settledAt ?? 999) < 10 + 3 + 30, "settled after \(settledAt.map(String.init) ?? "never") frames")
    }

    /// A swipe mostly down scrolls the page and leaves the card; one mostly sideways turns the
    /// card and leaves the page.
    @Test func aSwipeKeepsToItsAxis() {
        let model = PagerModel()
        let r = runtime(model)
        let top = pageTop(r)
        swipe(r, dx: 4, dy: 12)
        #expect(model.index == 0)
        #expect(cardOffset(r) == 0, "the card moved sideways: \(String(describing: cardOffset(r)))")
        #expect((pageTop(r) ?? 0) < (top ?? 0) - 50, "the page did not scroll")
        let topAfter = pageTop(r)
        // Back down so the card is under the pointer again.
        swipe(r, dx: 0, dy: -30)
        let restored = pageTop(r)
        swipe(r, dx: 14, dy: 5, at: CGPoint(x: 150, y: restored.map { $0 + 10 } ?? 140))
        #expect(model.index == 1)
        #expect(pageTop(r) == restored, "the page scrolled during a sideways swipe")
        _ = topAfter
    }

    /// A busy page handles the momentum tail late (a pause of 0.2 s in it): the settled card
    /// keeps its page, the tail does not drag it on.
    @Test func aPauseInTheTailKeepsTheSettledPage() {
        let model = PagerModel()
        let r = runtime(model)
        let point = CGPoint(x: 150, y: 140)
        var event = CGSize(width: 14, height: 0)
        for _ in 0..<10 { r.scrollWheel(by: event, at: point); frame(r) }
        for step in 0..<50 {
            event.width *= 0.92
            if step == 8 { Self.clock.now += 0.2 }
            r.scrollWheel(by: event, at: point); frame(r)
        }
        for _ in 0..<60 { frame(r) }
        #expect(model.index == 1)
        #expect(cardOffset(r) == 300, "\(String(describing: cardOffset(r)))")
    }

    /// A real swipe's shape: the finger speeds up and eases off unevenly, the OS's momentum starts
    /// a little faster than the finger's last event, and the tail has small bumps. One page,
    /// and it stays (it used to page on with the tail and then settle back).
    @Test func anUnevenSwipeTurnsExactlyOnePage() {
        let model = PagerModel()
        let r = runtime(model)
        let point = CGPoint(x: 150, y: 140)
        var indices: [Int] = []
        for dx in [2.0, 6, 11, 15, 13, 14, 9, 7] { r.scrollWheel(by: CGSize(width: dx, height: 0), at: point); frame(r); indices.append(model.index) }
        var tail = 10.0
        for step in 0..<70 {
            tail *= 0.93
            let bump = step % 7 == 3 ? 1.08 : 1.0
            r.scrollWheel(by: CGSize(width: max(0.1, tail * bump), height: 0), at: point); frame(r); indices.append(model.index)
        }
        for _ in 0..<60 { frame(r); indices.append(model.index) }
        #expect(model.index == 1, "\(indices)")
        #expect(Set(indices).isSubset(of: [0, 1]), "it went past the next page: \(indices)")
        #expect(cardOffset(r) == 300)
    }

    /// A second swipe while the card still settles from the first goes on to the page after,
    /// counted from the page it was settling to.
    @Test func aSwipeDuringASettleGoesOn() {
        let model = PagerModel()
        let r = runtime(model)
        let point = CGPoint(x: 150, y: 140)
        func flick() {
            var event = 14.0
            for _ in 0..<6 { r.scrollWheel(by: CGSize(width: event, height: 0), at: point); frame(r) }
            for _ in 0..<8 { event *= 0.9; r.scrollWheel(by: CGSize(width: event, height: 0), at: point); frame(r) }
        }
        flick()
        for _ in 0..<12 { frame(r) }   // a pause, the card still settling
        flick()
        for _ in 0..<12 { frame(r) }
        for _ in 0..<60 { frame(r) }
        #expect(model.index == 2, "\(String(describing: cardOffset(r)))")
        #expect(pages(r) == ["page 2"], "\(pages(r))")
    }

    /// A finger drag follows the finger: the card's offset equals the distance dragged (past the
    /// pan slop) on every frame until the finger lifts, then it settles on one page.
    @Test func aTouchDragFollowsTheFinger() {
        let model = PagerModel()
        let r = runtime(model)
        let start = CGPoint(x: 200, y: 140)
        r.pointerDown(at: start, type: .touch, time: Self.clock.now)
        var rows: [String] = []
        for step in 1...25 {
            frame(r)
            let x = start.x - Double(step) * 10   // 10 pt a frame, 600 pt/s
            r.pointerMoved(to: CGPoint(x: x, y: start.y), time: Self.clock.now)
            r.layout(in: size)
            rows.append("\(step * 10):\(cardOffset(r).map { String(format: "%.0f", $0) } ?? "-")")
            // Past the 10 pt slop the card is exactly where the finger is (it used to slide back
            // after a sixth of a second: the pan's first move was read as a wheel's).
            if step > 1 { #expect(cardOffset(r) == Double(step * 10 - 10), "\(rows)") }
        }
        r.pointerUp(at: CGPoint(x: start.x - 250, y: start.y), time: Self.clock.now)
        for _ in 0..<60 { frame(r) }
        #expect(model.index == 1)
    }

    @Test func aTouchDragFollowsTheFingerWithoutABinding() {
        let r = Runtime()
        r.textEngine = MetricsTextEngine()
        r.mount(PlainPager())
        for _ in 0..<3 { r.layout(in: size) }
        let start = CGPoint(x: 200, y: 140)
        r.pointerDown(at: start, type: .touch, time: 0)
        var rows: [String] = []
        var t = 0.0
        for step in 1...25 {
            t += 1.0 / 60
            _ = r.advanceScrollAnimations(elapsed: 1.0 / 60)
            r.pointerMoved(to: CGPoint(x: start.x - Double(step) * 10, y: start.y), time: t)
            r.layout(in: size)
            rows.append("\(step * 10):\(cardOffset(r).map { String(format: "%.0f", $0) } ?? "-")")
            if step > 1 { #expect(cardOffset(r) == Double(step * 10 - 10), "\(rows)") }
        }
    }

    /// A real trackpad's minute of sideways swipes, replayed with its own timing: every swipe
    /// turns at most one page, the way it moved, and the card rests on a page at the end (one
    /// swipe used to run to the last page and then settle back to the second).
    @Test func recordedSwipesTurnOnePageEach() {
        let model = PagerModel()
        let r = runtime(model)
        let point = CGPoint(x: 150, y: 140)
        let base = Self.clock.now
        var turns: [Int] = []
        var startIndex = model.index
        var gestureCount = 0
        func closeGesture() { if model.index != startIndex || gestureCount > 0 { turns.append(model.index - startIndex) } }
        for event in recordedTrackpadSwipes {
            while Self.clock.now - base + 1.0 / 60 < event[0] { frame(r) }
            let previous = r.wheelGesture
            r.scrollWheel(by: CGSize(width: event[1], height: event[2]), at: point, time: base + event[0])
            // A new gesture began with this event: the last one's turn is final once its settle ends.
            if let g = r.wheelGesture, previous == nil || g.lastTime != previous!.lastTime, g.recentMagnitudes.isEmpty {
                if gestureCount > 0 { turns.append(model.index - startIndex) }
                startIndex = model.index
                gestureCount += 1
            }
            #expect(abs(model.index - startIndex) <= 1, "a swipe from page \(startIndex) reached \(model.index) at \(event[0]) s")
        }
        for _ in 0..<90 { frame(r) }
        turns.append(model.index - startIndex)
        // The sideways swipes in the recording, in order: right, right, left, right, right,
        // then a few small sideways nudges inside a scroll down.
        #expect(Array(turns.filter { $0 != 0 }.prefix(5)) == [1, 1, -1, 1, 1], "\(turns)")
        #expect(pages(r).count == 1, "the card rests between pages: \(pages(r))")
    }

    /// Touch drags at a steady speed, then a lift, against what iOS 27 does with the same drags
    /// in the simulator (the card is 300 pt here, 361 there; distances are scaled to it).
    /// (distance on iOS's 361 pt card, lift speed pt/s, pages turned), measured in the simulator.
    nonisolated static let iosDrags: [(Double, Double, Int)] = [
        (100, 300, 0), (60, 330, 0), (100, 360, 0), (150, 200, 0),
        (60, 400, 1), (30, 800, 1), (120, 2000, 1), (220, 200, 1), (250, 600, 1), (300, 3000, 1),
    ]

    @Test(arguments: WheelGestureTests.iosDrags)
    func touchDragsPageAsIOS(drag: (Double, Double, Int)) {
        let (iosDistance, speed, pages) = drag
        let fraction = iosDistance / 361
        let model = PagerModel()
        let r = runtime(model)
        let start = CGPoint(x: 250, y: 140)
        let distance = fraction * 300 + 10   // past the 10 pt pan slop, as the finger moves on the glass
        r.pointerDown(at: start, type: .touch, time: Self.clock.now)
        var moved = 0.0
        while moved < distance {
            frame(r)
            moved = min(distance, moved + speed / 60)
            r.pointerMoved(to: CGPoint(x: start.x - moved, y: start.y), time: Self.clock.now)
        }
        r.pointerUp(at: CGPoint(x: start.x - moved, y: start.y), time: Self.clock.now)
        for _ in 0..<60 { frame(r) }
        #expect(model.index == pages, "\(Int(fraction * 361)) pt at \(Int(speed)) pt/s")
    }
}
#endif
