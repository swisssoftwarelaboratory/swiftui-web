#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// Wheel input applied once per display frame, at where the input was a frame ago
/// (new-website#279).
///
/// UIKit hands an app its touches once per display frame. A browser hands a page wheel events
/// whenever they come: in Safari on a Mac a trackpad sends one every 4 to 9 ms, in whole points
/// that alternate (2, 4, 2, 4), so a 60 Hz frame gets two events or three, and moving the content
/// by what arrived made every third frame or so jump by half again or stand still. Measured on
/// real Safari trackpad sessions, a frame's step differed from its neighbours' by about half its
/// size on average.
///
/// Here every event's distance is spread over the time since the event before it (a frame at
/// most), and a frame shows the input as it was `delay` before the frame, averaged over
/// `smoothing`. On the same sessions that halves the unevenness and leaves no empty frames, for
/// about 12 ms of delay. Nothing is lost: once the frames have passed the last event, everything
/// it carried has been handed out.
public struct WheelResampler {
    /// How far behind the frame the input is sampled (seconds). At least the gap between two
    /// events, so the sample falls between events the page already has.
    public var delay: Double
    /// The width of the average around the sample time (seconds).
    public var smoothing: Double
    /// An event's distance is spread over the gap since the last event, at most this long.
    public var maxSpread: Double

    private struct Event {
        var time: Double
        var spread: Double
        var delta: CGSize
    }

    /// Events not yet wholly handed out, oldest first.
    private var events: [Event] = []
    /// What the events in `events` have already been handed out of.
    private var handedOut = CGSize.zero
    private var lastTime: Double?
    /// Where the last event was (the scroll views under it take the movement).
    public private(set) var point = CGPoint.zero

    public init(delay: Double = 1.0 / 60, smoothing: Double = 1.0 / 60, maxSpread: Double = 1.0 / 60) {
        self.delay = delay
        self.smoothing = smoothing
        self.maxSpread = maxSpread
    }

    /// Whether some input has not been handed out yet (the host keeps asking for frames).
    public var isPending: Bool { !events.isEmpty }

    /// A wheel event: `delta` in points at `time` (seconds, the event's own time stamp).
    public mutating func add(_ delta: CGSize, at point: CGPoint, time: Double) {
        self.point = point
        // Out-of-order stamps count as simultaneous with the last event.
        let time = max(time, lastTime ?? time)
        let spread = lastTime.map { min(maxSpread, time - $0) } ?? maxSpread
        lastTime = time
        events.append(Event(time: time, spread: spread, delta: delta))
    }

    /// The movement for the frame at `now`: what the sampled input moved since the last frame,
    /// with the input time it stands for. Nil when nothing moves this frame.
    public mutating func take(at now: Double) -> (delta: CGSize, point: CGPoint, time: Double)? {
        guard !events.isEmpty else { return nil }
        let sampleTime = now - delay
        let samples = 5
        var sum = CGSize.zero
        for k in 0..<samples {
            let t = sampleTime - smoothing / 2 + smoothing * Double(k) / Double(samples - 1)
            let c = cumulative(at: t)
            sum.width += c.width
            sum.height += c.height
        }
        var target = CGSize(width: sum.width / CGFloat(samples), height: sum.height / CGFloat(samples))
        let windowEnd = sampleTime + smoothing / 2
        let allPast = windowEnd >= events[events.count - 1].time
        if allPast { target = total }
        let delta = CGSize(width: target.width - handedOut.width, height: target.height - handedOut.height)
        handedOut = target
        // Events wholly behind the window are done with.
        let windowStart = sampleTime - smoothing / 2
        while let first = events.first, first.time <= windowStart || allPast {
            handedOut.width -= first.delta.width
            handedOut.height -= first.delta.height
            events.removeFirst()
        }
        if events.isEmpty { handedOut = .zero }
        guard delta.width != 0 || delta.height != 0 else { return nil }
        return (delta, point, sampleTime)
    }

    private var total: CGSize {
        events.reduce(into: CGSize.zero) { $0.width += $1.delta.width; $0.height += $1.delta.height }
    }

    /// The input handed in up to `t`, each event's distance ramping in over its spread.
    private func cumulative(at t: Double) -> CGSize {
        var x: CGFloat = 0, y: CGFloat = 0
        for e in events {
            let f: Double
            if t >= e.time { f = 1 } else if e.spread <= 0 || t <= e.time - e.spread { f = 0 } else { f = (t - (e.time - e.spread)) / e.spread }
            if f == 0 { break }
            x += e.delta.width * CGFloat(f)
            y += e.delta.height * CGFloat(f)
        }
        return CGSize(width: x, height: y)
    }
}
