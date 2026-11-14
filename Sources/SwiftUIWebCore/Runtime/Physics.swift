// One physics for every motion (Docs/elements/Physics.md): springs, decay with friction, the
// rubber band past a scroll view's ends, the finger's speed at a lift, and a moving value that
// keeps its speed when a new target or a new touch interrupts it. Everything is a closed-form
// solution stepped by the real time between frames, so a motion looks the same at 60, 120 or
// 30 frames a second and a late frame lands where it would have been, not further behind.
//
// iOS has two kinds of motion (new-website#261): content coasting after a flick slows by the
// same share every millisecond and never overshoots; everything else (bounce back, paging,
// push, sheets, keyboard, every SwiftUI animation) is a spring started at the speed the finger
// or the previous motion had.

// MARK: - Springs

/// A damped spring of unit mass: natural frequency ω (radians per second) and damping ratio ζ
/// (1 settles without overshoot, below 1 bounces, above 1 creeps).
package struct SpringModel: Equatable, Sendable {
    package var omega: Double
    package var zeta: Double

    package init(omega: Double, zeta: Double) {
        self.omega = max(omega, 0.0001)
        self.zeta = max(zeta, 0)
    }

    /// SwiftUI's `spring(response:dampingFraction:)`: `response` is the period of the undamped
    /// spring, so `stiffness = (2π / response)²`.
    package init(response: Double, dampingFraction: Double) {
        self.init(omega: 2 * Double.pi / max(response, 0.0001), zeta: dampingFraction)
    }

    /// SwiftUI's `spring(duration:bounce:)` and `Spring(duration:bounce:)`: the duration is the
    /// response; `ζ = 1 − bounce` for a bounce of 0 or more, `1 / (1 + bounce)` below.
    package init(duration: Double, bounce: Double) {
        self.init(response: duration, dampingFraction: bounce >= 0 ? 1 - bounce : 1 / (1 + max(bounce, -0.9999)))
    }

    /// A spring given as mass, stiffness and damping (`interpolatingSpring`, `Spring(mass:…)`,
    /// `CASpringAnimation`). Core Animation keeps a spring from creeping unless it is allowed to
    /// overdamp: UIKit's push, pop and keyboard spring (mass 3, stiffness 1000, damping 500) is
    /// ζ ≈ 4.6 on paper and runs as a critical spring at ω ≈ 18.3 /s (new-website#261).
    package init(mass: Double, stiffness: Double, damping: Double, allowsOverdamping: Bool = true) {
        let m = max(mass, 0.0001), k = max(stiffness, 0)
        let zeta = damping / (2 * (k * m).squareRoot())
        self.init(omega: (k / m).squareRoot(), zeta: allowsOverdamping ? zeta : min(zeta, 1))
    }

    /// UIKit's navigation push and pop, and the keyboard's curve 7.
    package static let navigation = SpringModel(mass: 3, stiffness: 1000, damping: 500, allowsOverdamping: false)
    /// Stretched content springing back to the end of a scroll view once the finger lifts:
    /// critical, ω 12.7 /s, fitted to the iOS 27 simulator (new-website#262, `PhysicsTests`).
    package static let rubberBandReturn = SpringModel(omega: 12.7, zeta: 1)

    /// The undamped period in seconds (SwiftUI's `response` and `duration`).
    package var response: Double { 2 * Double.pi / omega }
    /// SwiftUI's bounce: `1 − ζ` up to critical damping, `1/ζ − 1` past it.
    package var bounce: Double { zeta <= 1 ? 1 - zeta : 1 / zeta - 1 }
    package func stiffness(mass: Double = 1) -> Double { omega * omega * mass }
    package func damping(mass: Double = 1) -> Double { 2 * zeta * omega * mass }

    /// The displacement from the target and the velocity `t` seconds after leaving
    /// `displacement` at `velocity` (any unit: points, a 0…1 progress, a colour channel).
    package func state(displacement x0: Double, velocity v0: Double, at t: Double) -> (displacement: Double, velocity: Double) {
        guard t > 0 else { return (x0, v0) }
        let w = omega
        if abs(zeta - 1) < 1e-6 {
            let c = v0 + w * x0, e = _exp(-w * t)
            return ((x0 + c * t) * e, (v0 - w * c * t) * e)
        }
        if zeta < 1 {
            let wd = w * (1 - zeta * zeta).squareRoot(), zw = zeta * w
            let b = (v0 + zw * x0) / wd
            let e = _exp(-zw * t), c = _cos(wd * t), s = _sin(wd * t)
            return (e * (x0 * c + b * s), e * ((b * wd - zw * x0) * c - (x0 * wd + zw * b) * s))
        }
        let root = (zeta * zeta - 1).squareRoot()
        let r1 = -w * (zeta - root), r2 = -w * (zeta + root)
        let b = (v0 - r1 * x0) / (r2 - r1), a = x0 - b
        let e1 = _exp(r1 * t), e2 = _exp(r2 * t)
        return (a * e1 + b * e2, r1 * a * e1 + r2 * b * e2)
    }

    /// Seconds until the motion stays within `epsilon` of the target (and slower than
    /// `epsilon` per frame of 1/60 s), at most 10.
    package func settlingTime(displacement x0: Double, velocity v0: Double, epsilon: Double) -> Double {
        let eps = max(epsilon, 1e-9)
        if zeta < 1 - 1e-6 {
            // The envelope bounds every swing: e^(−ζωt)·√(x₀² + B²), plus the velocity's share.
            let wd = omega * (1 - zeta * zeta).squareRoot(), zw = zeta * omega
            let b = (v0 + zw * x0) / wd
            let amplitude = (x0 * x0 + b * b).squareRoot() * max(1, omega / 60)
            guard amplitude > eps, zw > 0 else { return zw > 0 ? 0 : 10 }
            return min(10, _log(amplitude / eps) / zw)
        }
        // Critical and overdamped motion crosses the target at most once: walk forward.
        let step = 1.0 / 240
        var t = 0.0
        while t < 10 {
            let s = state(displacement: x0, velocity: v0, at: t)
            if abs(s.displacement) < eps, abs(s.velocity) / 60 < eps { return t }
            t += step
        }
        return 10
    }
}

// MARK: - Decay

/// Coasting with friction: the velocity keeps the same share of itself every millisecond
/// (`UIScrollView.DecelerationRate`, `.normal` 0.998 and `.fast` 0.99), so
/// `v(t) = v₀ · rate^(1000 t)` and the content comes to rest `v₀ / (1000 · −ln rate)` ahead.
package struct DecayModel: Equatable, Sendable {
    /// The share of its velocity a moving value keeps per millisecond.
    package let rate: Double
    /// The exponent per second, `1000 · ln rate` (negative).
    package let exponent: Double

    package init(rate: Double) {
        self.rate = min(max(rate, 0.5), 0.999999)
        exponent = 1000 * _log(self.rate)
    }

    package static let normal = DecayModel(rate: 0.998)
    package static let fast = DecayModel(rate: 0.99)

    /// The distance covered and the velocity `t` seconds after leaving at `velocity`.
    package func state(velocity v0: Double, at t: Double) -> (offset: Double, velocity: Double) {
        guard t > 0 else { return (0, v0) }
        let e = _exp(exponent * t)
        return (v0 * (e - 1) / exponent, v0 * e)
    }

    /// Where a value leaving at `velocity` comes to rest, relative to where it left.
    package func restOffset(velocity v0: Double) -> Double { -v0 / exponent }

    /// Apple's projection of a flick's rest point (WWDC 2018, "Designing Fluid Interfaces"):
    /// `(v / 1000) · rate / (1 − rate)`, the sum of the per-millisecond steps. UIScrollView hands
    /// it to its paging and target logic; it is 0.1 % short of the continuous rest offset.
    package func projectedOffset(velocity v0: Double) -> Double { v0 / 1000 * rate / (1 - rate) }

    /// Seconds until the speed falls to `floor`.
    package func timeToSlow(from v0: Double, to floor: Double) -> Double {
        guard abs(v0) > floor, floor > 0 else { return 0 }
        return _log(floor / abs(v0)) / exponent
    }

    /// Seconds until a value leaving at `velocity` has covered `distance` (same sign as the
    /// velocity), or nil when it comes to rest first.
    package func timeToTravel(_ distance: Double, velocity v0: Double) -> Double? {
        guard v0 != 0, distance * v0 >= 0 else { return distance == 0 ? 0 : nil }
        let inside = 1 + distance * exponent / v0
        guard inside > 0 else { return nil }
        return _log(inside) / exponent
    }
}

// MARK: - Rubber band

/// UIScrollView's rubber band: content dragged `x` points past its end moves
/// `(1 − 1 / (x · c / d + 1)) · d`, with `d` the scroll view's size along the axis and
/// `c` = 0.55. A 190 pt pull on an 852 pt tall view moves 93 pt (measured, new-website#262).
package enum RubberBand {
    package static let constant = 0.55

    /// The distance the content moves for a pull of `overshoot` past the end (signed).
    package static func offset(forOvershoot overshoot: Double, dimension: Double, constant: Double = constant) -> Double {
        guard dimension > 0 else { return 0 }
        let x = abs(overshoot)
        let banded = (1 - 1 / (x * constant / dimension + 1)) * dimension
        return overshoot < 0 ? -banded : banded
    }

    /// The pull that moves the content `offset` past the end: where a finger landing on
    /// stretched content picks it up.
    package static func overshoot(forOffset offset: Double, dimension: Double, constant: Double = constant) -> Double {
        guard dimension > 0, constant > 0 else { return 0 }
        let b = min(abs(offset), dimension * 0.999)
        let x = b * dimension / (constant * (dimension - b))
        return offset < 0 ? -x : x
    }
}

// MARK: - The finger's speed

/// The finger's velocity from its recent path, as UIKit reads it at a lift: over the last
/// `window` seconds, steady whatever the frames' spacing (a smoothed step-to-step speed runs
/// low on uneven frames, new-website#216), and zero once the finger rested `restInterval`.
package struct VelocityTracker: Sendable {
    package var window: Double
    package var restInterval: Double
    package private(set) var samples: [(time: Double, point: CGPoint)] = []

    package init(window: Double = 0.05, restInterval: Double = 0.1) {
        self.window = window
        self.restInterval = restInterval
    }

    package mutating func add(_ point: CGPoint, at time: Double) {
        if let last = samples.last, time < last.time { samples.removeAll() }
        samples.append((time, point))
        // A finger resting longer than `restInterval` has no speed left to measure.
        samples.removeAll { time - $0.time > restInterval }
    }

    package mutating func reset() { samples.removeAll() }

    /// Points per second over the window ending at the last sample, nil without two samples
    /// far enough apart.
    package var recentVelocity: CGSize? {
        guard let last = samples.last, samples.count >= 2 else { return nil }
        // The window reaches back to the previous sample at least: a late frame must not leave
        // the last move alone in it.
        var first = samples.first(where: { last.time - $0.time <= window }) ?? samples[samples.count - 2]
        if last.time - first.time <= 0.004 { first = samples[samples.count - 2] }
        let dt = last.time - first.time
        guard dt > 0.004 else { return nil }
        return CGSize(width: (last.point.x - first.point.x) / dt, height: (last.point.y - first.point.y) / dt)
    }

    /// The velocity at `time` (a lift): zero when the finger stopped before it.
    package func velocity(at time: Double) -> CGSize {
        guard let last = samples.last, time - last.time < restInterval else { return .zero }
        return recentVelocity ?? .zero
    }
}

// MARK: - A moving value

/// One value moving on one axis: held by a finger, carried by a spring towards a target, or
/// coasting with friction and bouncing off its bounds. Every change of plan starts from the
/// current position and velocity, so nothing jumps or jerks when interrupted (WWDC 2023,
/// "Animate with springs"), and `step` is exact for any frame time.
package struct Motion: Sendable {
    package enum Driver: Equatable, Sendable {
        /// Still, or following a finger (whose velocity it remembers for the hand-off).
        case held
        case spring(SpringModel, target: Double)
        /// Coasting; past `bounds` it springs back to the nearer end on `edge`.
        case decay(DecayModel, bounds: ClosedRange<Double>?, edge: SpringModel)
    }

    package private(set) var position: Double
    package private(set) var velocity: Double
    package private(set) var driver: Driver = .held
    /// A spring is at rest closer than this to its target (and slower than this per 1/60 s).
    package var restDistance: Double
    /// Coasting stops below this speed (units per second).
    package var restSpeed: Double

    package init(position: Double, velocity: Double = 0, restDistance: Double = 0.1, restSpeed: Double = 5) {
        self.position = position
        self.velocity = velocity
        self.restDistance = restDistance
        self.restSpeed = restSpeed
    }

    package var isMoving: Bool { driver != .held }

    /// The value follows a finger: placed where it is, moving at the finger's speed.
    package mutating func hold(at position: Double, velocity: Double = 0) {
        self.position = position
        self.velocity = velocity
        driver = .held
    }

    /// Stops where it is.
    package mutating func stop() {
        velocity = 0
        driver = .held
    }

    /// Springs towards `target` from the current position at the current velocity: a new target
    /// mid-flight keeps the speed it had.
    package mutating func animate(to target: Double, spring: SpringModel, velocity handOff: Double? = nil) {
        if let handOff { velocity = handOff }
        driver = .spring(spring, target: target)
        if abs(position - target) < restDistance, abs(velocity) / 60 < restDistance { settle(at: target) }
    }

    /// Coasts from the current velocity; past `bounds` (now or later) it springs back on `edge`.
    package mutating func coast(_ decay: DecayModel = .normal, within bounds: ClosedRange<Double>? = nil, edge: SpringModel, velocity handOff: Double? = nil) {
        if let handOff { velocity = handOff }
        if let bounds, !bounds.contains(position) {
            driver = .spring(edge, target: min(max(position, bounds.lowerBound), bounds.upperBound))
            return
        }
        driver = abs(velocity) < restSpeed ? .held : .decay(decay, bounds: bounds, edge: edge)
        if driver == .held { velocity = 0 }
    }

    /// Advances `dt` seconds. Returns whether it still moves.
    @discardableResult
    package mutating func step(_ dt: Double) -> Bool {
        var remaining = max(0, dt)
        // A coast that reaches a bound hands over to the edge spring within the same step.
        while remaining > 0 {
            switch driver {
            case .held:
                return false
            case .spring(let spring, let target):
                let s = spring.state(displacement: position - target, velocity: velocity, at: remaining)
                position = target + s.displacement
                velocity = s.velocity
                if abs(s.displacement) < restDistance, abs(s.velocity) / 60 < restDistance { settle(at: target) }
                remaining = 0
            case .decay(let decay, let bounds, let edge):
                if let bounds, velocity != 0 {
                    let end = velocity > 0 ? bounds.upperBound : bounds.lowerBound
                    if let hit = decay.timeToTravel(end - position, velocity: velocity), hit <= remaining {
                        velocity = decay.state(velocity: velocity, at: hit).velocity
                        position = end
                        driver = .spring(edge, target: end)
                        remaining -= hit
                        continue
                    }
                }
                let s = decay.state(velocity: velocity, at: remaining)
                position += s.offset
                velocity = s.velocity
                if abs(velocity) < restSpeed { stop() }
                remaining = 0
            }
        }
        return isMoving
    }

    private mutating func settle(at target: Double) {
        position = target
        velocity = 0
        driver = .held
    }
}
