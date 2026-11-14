/// The way a view changes over time to create a smooth visual transition from one state to
/// another (`Docs/elements/Animation.md`).
///
/// Curves: linear, cubic Bézier easing (`easeIn`/`easeOut`/`easeInOut`, `timingCurve`) and
/// springs (`spring(response:dampingFraction:)`, `spring(duration:bounce:)`, `smooth`,
/// `snappy`, `bouncy`, `interpolatingSpring`); `delay`, `speed`, `repeatCount` and
/// `repeatForever` transform any of them. `value(at:)` maps seconds since the start to the
/// progress 0…1 (springs may overshoot).
public struct Animation: Equatable, Sendable {
    package enum Curve: Equatable, Sendable {
        case linear
        case bezier(Double, Double, Double, Double)
        /// A spring towards the target from rest: natural frequency and damping ratio.
        case spring(omega: Double, zeta: Double, velocity: Double)
    }

    package var curve: Curve
    /// Seconds of one cycle (a spring's settling time).
    package var duration: Double
    package var delay: Double = 0
    package var speed: Double = 1
    /// Cycles to run; 0 repeats forever.
    package var repeatCount: Int = 1
    package var autoreverses = false

    package init(curve: Curve, duration: Double) {
        self.curve = curve
        self.duration = duration
    }

    // MARK: Curves

    /// The default animation (a spring with a 0.55 s response and no bounce).
    public static let `default` = Animation.spring(response: 0.55, dampingFraction: 1)

    public static func linear(duration: Double) -> Animation { Animation(curve: .linear, duration: duration) }
    public static var linear: Animation { .linear(duration: 0.35) }
    public static func easeIn(duration: Double) -> Animation { .timingCurve(0.42, 0, 1, 1, duration: duration) }
    public static var easeIn: Animation { .easeIn(duration: 0.35) }
    public static func easeOut(duration: Double) -> Animation { .timingCurve(0, 0, 0.58, 1, duration: duration) }
    public static var easeOut: Animation { .easeOut(duration: 0.35) }
    public static func easeInOut(duration: Double) -> Animation { .timingCurve(0.42, 0, 0.58, 1, duration: duration) }
    public static var easeInOut: Animation { .easeInOut(duration: 0.35) }

    /// An animation with a cubic Bézier timing curve.
    public static func timingCurve(_ c0x: Double, _ c0y: Double, _ c1x: Double, _ c1y: Double, duration: Double = 0.35) -> Animation {
        Animation(curve: .bezier(c0x, c0y, c1x, c1y), duration: duration)
    }

    /// A persistent spring animation: `response` is the period of the undamped spring,
    /// `dampingFraction` the damping ratio (1 settles without bouncing). `.spring()` with no
    /// arguments is the duration/bounce form, as Apple's resolves it (measured 2026-10-12:
    /// damping 1, response 0.5), so this one is disfavoured.
    @_disfavoredOverload
    public static func spring(response: Double = 0.5, dampingFraction: Double = 0.825, blendDuration: Double = 0) -> Animation {
        let omega = SpringModel(response: max(response, 0.001), dampingFraction: dampingFraction).omega
        // `blendDuration` is accepted: a retargeted animation already starts from the value
        // presented at that moment, which is the blend's effect. (Not stored: a further stored
        // property on `Animation` crashes the wasm build's list/outline page.)
        return Animation(curve: .spring(omega: omega, zeta: max(dampingFraction, 0), velocity: 0), duration: settlingTime(omega: omega, zeta: dampingFraction))
    }

    /// A convenience for a spring that responds quickly to interaction.
    public static func interactiveSpring(response: Double = 0.15, dampingFraction: Double = 0.86, blendDuration: Double = 0.25) -> Animation {
        .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
    }

    public static var spring: Animation { .spring(response: 0.5, dampingFraction: 0.825) }
    public static var interactiveSpring: Animation { .interactiveSpring() }

    /// A spring with the given mass, stiffness and damping.
    public static func interpolatingSpring(mass: Double = 1, stiffness: Double, damping: Double, initialVelocity: Double = 0) -> Animation {
        let model = SpringModel(mass: max(mass, 0.001), stiffness: stiffness, damping: damping)
        let omega = model.omega, zeta = model.zeta
        return Animation(curve: .spring(omega: omega, zeta: zeta, velocity: initialVelocity), duration: settlingTime(omega: omega, zeta: zeta))
    }

    /// A spring described by its perceptual duration and bounce (0 = no bounce).
    public static func spring(duration: Double = 0.5, bounce: Double = 0, blendDuration: Double = 0) -> Animation {
        let model = SpringModel(duration: max(duration, 0.001), bounce: bounce)
        let omega = model.omega, zeta = model.zeta
        return Animation(curve: .spring(omega: omega, zeta: max(zeta, 0), velocity: 0), duration: settlingTime(omega: omega, zeta: zeta))
    }

    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Animation { .spring(duration: duration, bounce: extraBounce) }
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation { .spring(duration: duration, bounce: 0.15 + extraBounce) }
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Animation { .spring(duration: duration, bounce: 0.3 + extraBounce) }
    public static var smooth: Animation { .smooth() }
    public static var snappy: Animation { .snappy() }
    public static var bouncy: Animation { .bouncy() }

    /// Seconds until a spring's envelope is within 0.05 % of the target.
    package static func settlingTime(omega: Double, zeta: Double) -> Double {
        let z = max(zeta, 0.05)
        let base = z < 1 ? 7.6 / (z * omega) : 9.2 / omega
        return min(max(base, 0.05), 10)
    }

    // MARK: Modifiers

    /// Delays the start of the animation by the specified number of seconds.
    public func delay(_ delay: Double) -> Animation { var copy = self; copy.delay += delay; return copy }

    /// Changes the duration of an animation by adjusting its speed.
    public func speed(_ speed: Double) -> Animation { var copy = self; copy.speed *= max(speed, 0.0001); return copy }

    /// Repeats the animation for a specific number of times.
    public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
        var copy = self; copy.repeatCount = max(repeatCount, 1); copy.autoreverses = autoreverses; return copy
    }

    /// Repeats the animation for the lifespan of the view containing the animation.
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        var copy = self; copy.repeatCount = 0; copy.autoreverses = autoreverses; return copy
    }

    // MARK: Evaluation

    /// The progress (0…1, springs may overshoot) `time` seconds after the animation started.
    package func value(at time: Double) -> Double {
        let local = (time - delay) * speed
        if local <= 0 { return curveValue(0) }
        let cycle = max(duration, 0.0001)
        let cycles = (local / cycle).rounded(.down)
        if repeatCount > 0, cycles >= Double(repeatCount) {
            return curveValue(autoreverses && repeatCount % 2 == 0 ? 0 : 1)
        }
        var phase = local - cycles * cycle
        if autoreverses, Int(cycles) % 2 == 1 { phase = cycle - phase }
        return curveValue(phase / cycle)
    }

    /// Whether the animation has run its course `time` seconds after it started.
    package func isFinished(at time: Double) -> Bool {
        guard repeatCount > 0 else { return false }
        return (time - delay) * speed >= Double(repeatCount) * max(duration, 0.0001)
    }

    /// The total time from start to finish, or infinity.
    package var totalDuration: Double { repeatCount > 0 ? delay + Double(repeatCount) * duration / speed : .infinity }

    /// The curve at a normalised cycle position `u` in 0…1.
    private func curveValue(_ u: Double) -> Double {
        switch curve {
        case .linear:
            return u
        case .bezier(let x1, let y1, let x2, let y2):
            return Self.bezier(u, x1, y1, x2, y2)
        case .spring(let omega, let zeta, let velocity):
            return Self.spring(at: u * duration, omega: omega, zeta: zeta, velocity: velocity)
        }
    }

    /// y of the cubic Bézier through (0,0), (x1,y1), (x2,y2), (1,1) where x = `u`.
    private static func bezier(_ u: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        func point(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let mt = 1 - t
            return 3 * mt * mt * t * a + 3 * mt * t * t * b + t * t * t
        }
        // Bisection on t for x(t) = u (monotonic for valid control points).
        var low = 0.0, high = 1.0, t = u
        for _ in 0..<24 {
            t = (low + high) / 2
            if point(t, x1, x2) < u { low = t } else { high = t }
        }
        return point(t, y1, y2)
    }

    /// Unit-step response of a damped spring starting at `velocity` (units of the travel per
    /// second; `interpolatingSpring(initialVelocity:)`), `t` seconds in (`SpringModel`).
    package static func spring(at t: Double, omega: Double, zeta: Double, velocity: Double = 0) -> Double {
        if t <= 0 { return 0 }
        return 1 - SpringModel(omega: omega, zeta: zeta).state(displacement: 1, velocity: -velocity, at: t).displacement
    }

    /// The spring this animation runs on, when it is one.
    package var springModel: SpringModel? {
        if case .spring(let omega, let zeta, _) = curve { return SpringModel(omega: omega, zeta: zeta) }
        return nil
    }

    /// Whether a value animated by this can keep its own velocity (a single, unrepeated spring).
    package var carriesVelocity: Bool { springModel != nil && repeatCount == 1 && !autoreverses }
}

// MARK: - Implicit animation and transaction modifiers

/// `animation(_:value:)`: animates the changes below it that follow a change of `value`.
public struct _AnimationModifier<Value: Equatable> {
    package let animation: Animation?
    package let value: Value?
    package init(animation: Animation?, value: Value?) {
        self.animation = animation
        self.value = value
    }
}

extension _AnimationModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AnimationScopeNode(context)
    }
}

/// `transaction(_:)`: transforms the transaction of the changes below it.
public struct _TransactionModifier {
    package let transform: (inout Transaction) -> Void
    package init(transform: @escaping (inout Transaction) -> Void) { self.transform = transform }
}

extension _TransactionModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TransactionScopeNode(context)
    }
}

extension View {
    /// Applies the given animation to this view when the specified value changes.
    nonisolated public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(_AnimationModifier(animation: animation, value: value))
    }

    /// Applies the given animation to all animatable values within this view.
    @available(*, deprecated, message: "Use withAnimation or animation(_:value:) instead.")
    nonisolated public func animation(_ animation: Animation?) -> some View {
        modifier(_AnimationModifier<Int>(animation: animation, value: nil))
    }

    /// Applies the given transaction mutation function to all animations used within the view.
    nonisolated public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(_TransactionModifier(transform: transform))
    }
}

// MARK: - Transitions

/// A type-erased transition: how a view enters and leaves the tree under an animation.
public struct AnyTransition: Sendable {
    package indirect enum Kind: Sendable {
        case identity
        case opacity
        case move(Edge)
        case offset(CGFloat, CGFloat)
        case scale(CGFloat, UnitPoint)
        case combined(Kind, Kind)
        case asymmetric(insertion: Kind, removal: Kind)
    }

    package let kind: Kind
    /// An animation attached with `animation(_:)`, taking precedence over the transaction's.
    package var animation: Animation?

    package init(kind: Kind, animation: Animation? = nil) {
        self.kind = kind
        self.animation = animation
    }

    /// A transition that returns the input view, unmodified, as the output view.
    public static let identity = AnyTransition(kind: .identity)
    /// A transition from transparent to opaque on insertion, and from opaque to transparent on removal.
    public static let opacity = AnyTransition(kind: .opacity)
    /// A transition that inserts by moving in from the leading edge and removes by moving out towards the trailing edge.
    public static let slide = AnyTransition(kind: .asymmetric(insertion: .move(.leading), removal: .move(.trailing)))
    /// Returns a transition that moves the view away, towards the specified edge of the view.
    public static func move(edge: Edge) -> AnyTransition { AnyTransition(kind: .move(edge)) }
    /// Moves the view in from `edge` as it fades in, and out towards the opposite edge as it
    /// fades out.
    public static func push(from edge: Edge) -> AnyTransition {
        let opposite: Edge
        switch edge {
        case .top: opposite = .bottom
        case .bottom: opposite = .top
        case .leading: opposite = .trailing
        case .trailing: opposite = .leading
        }
        return .asymmetric(insertion: .move(edge: edge).combined(with: .opacity),
                           removal: .move(edge: opposite).combined(with: .opacity))
    }
    /// Returns a transition that offsets the view by the specified amount.
    public static func offset(_ offset: CGSize) -> AnyTransition { AnyTransition(kind: .offset(offset.width, offset.height)) }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition { AnyTransition(kind: .offset(x, y)) }
    /// Returns a transition that scales the view (about its centre).
    public static let scale = AnyTransition(kind: .scale(0, .center))
    public static func scale(_ scale: Double, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition(kind: .scale(CGFloat(scale), anchor)) }
    /// Returns a transition that scales the view by the factor about the anchor (FoodTruck's box lid).
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition { AnyTransition(kind: .scale(scale, anchor)) }
    /// Provides a composite transition that uses a different transition for insertion versus removal.
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .asymmetric(insertion: insertion.kind, removal: removal.kind), animation: insertion.animation ?? removal.animation)
    }

    /// Combines this transition with another, returning a new transition that is the result of
    /// both transitions being applied.
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(kind: .combined(kind, other.kind), animation: animation ?? other.animation)
    }

    /// Attaches an animation to this transition.
    public func animation(_ animation: Animation?) -> AnyTransition {
        AnyTransition(kind: kind, animation: animation)
    }

    /// Returns a transition defined between an active modifier and an identity modifier
    /// (accepted: transitions paint as fades, moves and scales, decision 0021; the modifiers
    /// are not applied, the view appears and disappears with the identity transition).
    public static func modifier<E: ViewModifier>(active: E, identity: E) -> AnyTransition { AnyTransition(kind: .identity) }

    /// What the transition does at its "removed" end: fade, and an offset in units of the
    /// view's size plus points.
    package struct Effects: Sendable {
        package var fades = false
        package var fraction = CGSize.zero
        package var points = CGSize.zero
        /// The scale at the removed end (1 = none), about `scaleAnchor`.
        package var scale: CGFloat = 1
        package var scaleAnchor: UnitPoint = .center
        package var isIdentity: Bool { !fades && fraction == .zero && points == .zero && scale == 1 }
    }

    package func effects(insertion: Bool) -> Effects {
        var effects = Effects()
        func add(_ kind: Kind) {
            switch kind {
            case .identity: break
            case .opacity: effects.fades = true
            case .move(let edge):
                switch edge {
                case .leading: effects.fraction.width -= 1
                case .trailing: effects.fraction.width += 1
                case .top: effects.fraction.height -= 1
                case .bottom: effects.fraction.height += 1
                }
            case .offset(let x, let y):
                effects.points.width += x
                effects.points.height += y
            case .scale(let s, let anchor):
                effects.scale = s
                effects.scaleAnchor = anchor
            case .combined(let a, let b):
                add(a); add(b)
            case .asymmetric(let insertionKind, let removalKind):
                add(insertion ? insertionKind : removalKind)
            }
        }
        add(kind)
        return effects
    }
}

/// `transition(_:)`: records the transition for the view it modifies (`TransitionNode`).
public struct _TransitionModifier {
    package let transition: AnyTransition
    package init(transition: AnyTransition) { self.transition = transition }
}

extension _TransitionModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TransitionNode(context)
    }
}

extension View {
    /// Associates a transition with the view.
    nonisolated public func transition(_ t: AnyTransition) -> some View {
        modifier(_TransitionModifier(transition: t))
    }
}
