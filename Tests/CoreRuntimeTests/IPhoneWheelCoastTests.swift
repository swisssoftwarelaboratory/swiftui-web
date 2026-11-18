// A trackpad scroll driving a scroll view the iPhone way (`Runtime.wheelCoastsLikeIPhone`,
// new-website#278): the finger one for one, iOS's own coast once Safari's momentum tail begins,
// the tail itself swallowed, and the rubber band at the ends. Fed with real MacBook trackpad
// swipes as Safari delivered them (`recordedTrackpadSwipes`, sideways swipes turned vertical),
// once per frame as the canvas host applies them (`WheelResampler`).
import Foundation
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebGraphics

#if !os(WASI)

private struct Rows: View {
    let count: Int
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in Text("row \(i)").frame(maxWidth: .infinity).frame(height: 50) }
            }
        }
    }
}

@Suite @MainActor struct IPhoneWheelCoastTests {
    private let size = CGSize(width: 300, height: 600)
    private let point = CGPoint(x: 150, y: 300)

    /// The recording's events between `from` and `to` seconds, turned vertical, restarting at 0.
    private static func swipes(from: Double = 0, to: Double = .infinity) -> [[Double]] {
        let picked = recordedTrackpadSwipes.filter { $0[0] >= from && $0[0] < to }
        guard let first = picked.first?[0] else { return [] }
        return picked.map { e in [e[0] - first, abs(e[1]) >= abs(e[2]) ? e[1] : e[2]] }
    }

    /// Plays `events` ([seconds, deltaY]) at 60 frames a second, `after` seconds more, and
    /// returns the scroll view's offset at every frame and its largest offset.
    private func play(_ events: [[Double]], rows: Int, iPhone: Bool = true, startAt: CGFloat? = nil, after: Double = 2) -> (offsets: [CGFloat], maximum: CGFloat) {
        let r = Runtime()
        var now = 0.0
        r.wheelClock = { now }
        r.textEngine = MetricsTextEngine()
        r.wheelCoastsLikeIPhone = iPhone
        r.mount(Rows(count: rows))
        for _ in 0..<3 { r.layout(in: size) }
        guard let node = r.scrollableNodes(at: point).first else {
            Issue.record("no scroll view"); return ([], 0)
        }
        if let startAt {
            r.scrollWheel(by: CGSize(width: 0, height: startAt), at: point, time: -1)
            for _ in 0..<12 { now += 1.0 / 60; _ = r.advanceScrollAnimations(elapsed: 1.0 / 60); r.layout(in: size) }
        }
        let base = now
        var input = WheelResampler()
        var next = 0
        var offsets: [CGFloat] = []
        let end = (events.last?[0] ?? 0) + after
        while now - base < end {
            now += 1.0 / 60
            _ = r.advanceScrollAnimations(elapsed: 1.0 / 60)
            while next < events.count, events[next][0] <= now - base {
                input.add(CGSize(width: 0, height: events[next][1]), at: point, time: base + events[next][0])
                next += 1
            }
            if let frame = input.take(at: now) { r.scrollWheel(by: frame.delta, at: frame.point, time: frame.time, afterPause: frame.afterPause) }
            r.layout(in: size)
            offsets.append(node.contentOffset.y)
        }
        return (offsets, CGFloat(rows * 50) - size.height)
    }

    /// iOS's friction over one 60 Hz frame: 0.998 a millisecond.
    private static let frameDecay = 0.998.pow(1000.0 / 60)

    /// Each of the recording's swipes, on a list long enough never to reach an end: once the
    /// finger has lifted, every frame's step is the one before slowed by iOS's friction, exactly,
    /// whatever Safari's tail does meanwhile, and the content comes to rest.
    @Test(arguments: [(0.0, 1.0), (9.8, 10.75), (10.78, 11.8), (11.82, 12.75), (12.78, 13.93), (13.94, 15.1), (16.3, 17.6), (18.79, 20.1), (20.6, 22)])
    func coastFollowsIOSOnceTheFingerLifts(window: (Double, Double)) {
        let events = Self.swipes(from: window.0, to: window.1)
        let (offsets, _) = play(events, rows: 2000, startAt: 40_000, after: 4)
        let steps = zip(offsets.dropFirst(), offsets).map { Double($0 - $1) }
        // The coast: the last run of frames whose steps shrink by iOS's friction.
        var matched = 0
        for (a, b) in zip(steps, steps.dropFirst()) where abs(a) > 2 && abs(b) > 0.5 {
            if abs(b / a - Self.frameDecay) < 0.002 { matched += 1 }
        }
        #expect(matched >= 10, "only \(matched) frames coasted at iOS's friction: \(steps.map { Int($0.rounded()) })")
        #expect(steps.suffix(10).allSatisfy { $0 == 0 }, "still moving at the end: \(steps.suffix(10))")
    }

    /// Pulling down at the top: the content follows the finger through the rubber band (less
    /// than the finger, never as far as half the view) and springs back to rest exactly at 0.
    @Test func pullPastTheTopBandsAndSpringsBack() {
        let events = Self.swipes(from: 10.78, to: 11.8)   // an upward swipe of about 1,900 pt
        let (offsets, _) = play(events, rows: 200)
        let lowest = offsets.min() ?? 0
        #expect(lowest < -20, "no band: \(lowest)")
        #expect(lowest > -300, "the band let it go too far: \(lowest) \(offsets.map { Int($0) })")
        #expect(offsets.last == 0)
    }

    /// A flick that coasts into the bottom: it overshoots past the end and springs back onto it.
    @Test func coastIntoTheEndBouncesBack() {
        let events = Self.swipes(from: 20.6, to: 22)   // a fast downward swipe of about 3,700 pt
        let (offsets, maximum) = play(events, rows: 60, startAt: 400)
        #expect(maximum == 2400)
        let highest = offsets.max() ?? 0
        #expect(highest > maximum + 5, "no bounce: \(highest)")
        #expect(highest < maximum + 300, "the bounce went too far: \(highest)")
        #expect(offsets.last == maximum)
    }

    /// Without the switch, the same swipe stops dead at the end as before.
    @Test func withoutTheSwitchTheEndsStayHard() {
        let events = Self.swipes(from: 20.6, to: 22)
        let (offsets, maximum) = play(events, rows: 60, iPhone: false, startAt: 400)
        #expect(offsets.allSatisfy { $0 >= 0 && $0 <= maximum })
        #expect(offsets.last == maximum)
    }

    /// Fingers back on the trackpad cut Safari's tail short while it still runs fast; nothing
    /// comes after. The coast stops there, as under a finger landing on the glass.
    @Test func fingersLandingStopTheCoast() {
        // The swipe at 20.6 s, cut 0.25 s after it began, its tail still at 50 pt an event.
        let events = Self.swipes(from: 20.6, to: 20.85)
        let (offsets, _) = play(events, rows: 2000, startAt: 40_000, after: 1)
        let full = play(Self.swipes(from: 20.6, to: 22), rows: 2000, startAt: 40_000, after: 1).offsets
        let cut = offsets.last ?? 0, whole = full.last ?? 0
        #expect(cut < whole - 200, "the coast ran on after the fingers landed: \(cut) against \(whole)")
        #expect(offsets.suffix(30).allSatisfy { $0 == cut })
    }
}

private extension Double {
    func pow(_ exponent: Double) -> Double { Foundation.pow(self, exponent) }
}

#endif
