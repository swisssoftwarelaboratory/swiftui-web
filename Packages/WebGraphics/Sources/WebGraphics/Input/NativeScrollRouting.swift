// Which trackpad and wheel events a host's own native scroller takes (new-website#404): the
// browser scrolls a real scroll element with its own momentum, and the scene's scroll view
// follows it every frame. This is the part of that decision that needs no browser.

/// Sorts wheel events into gestures, as `Runtime`'s wheel gestures do: a gesture keeps to the
/// axis it started along, so a vertical swipe never turns a sideways pager halfway through and a
/// sideways one never scrolls the page. Browsers give wheel events no phase, so a gesture starts
/// after a tenth of a second without events, or with an event wholly along the other axis.
public struct NativeScrollRouting: Sendable {
    /// What a wheel event is to the native scroller.
    public enum Decision: Equatable, Sendable {
        /// It starts a vertical gesture moving the content along `direction` (positive: up):
        /// the host picks the scroll view the gesture drives.
        case startsVertical(direction: Double)
        /// It goes on with the vertical gesture in flight.
        case continuesVertical
        /// It belongs to a sideways gesture, which stays with the scene's own wheel handling.
        case horizontal
    }

    /// The quiet time that ends a gesture, in seconds.
    public static let gestureGap = 0.1
    /// How long after the last event or move the scroller counts as at rest, in seconds: long
    /// enough to ride over the 100 ms gaps at the end of a momentum tail.
    public static let restTime = 0.15

    public private(set) var lastWheelTime = -Double.infinity
    /// When the native scroll element last moved (the host reports it).
    public var lastMoveTime = -Double.infinity
    public private(set) var isVertical = true

    public init() {}

    /// Sorts a wheel event with deltas `dx`, `dy` (any unit: only their signs and sizes against
    /// each other count) arriving at `time` seconds.
    public mutating func wheel(dx: Double, dy: Double, time: Double) -> Decision {
        let quiet = time - lastWheelTime >= Self.gestureGap
        lastWheelTime = time
        let whollyOther = isVertical ? (dy == 0 && dx != 0) : (dx == 0 && dy != 0)
        if quiet || whollyOther {
            // Along the larger delta; as far one way as the other keeps the last axis.
            if abs(dy) != abs(dx) { isVertical = abs(dy) > abs(dx) }
            return isVertical ? .startsVertical(direction: dy == 0 ? 0 : dy > 0 ? 1 : -1) : .horizontal
        }
        return isVertical ? .continuesVertical : .horizontal
    }

    /// Whether neither a wheel event nor a move came for `restTime` before `time`.
    public func isAtRest(at time: Double) -> Bool {
        time - lastWheelTime >= Self.restTime && time - lastMoveTime >= Self.restTime
    }
}
