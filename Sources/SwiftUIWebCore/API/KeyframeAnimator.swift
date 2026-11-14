// KeyframeAnimator: drives a value along keyframe tracks (linear, cubic, spring and move
// keyframes per animatable property) and rebuilds its content every frame with the value.
// `KeyframeTimeline` exposes the same evaluation for direct use.

/// A view that animates a value through keyframes and renders content with it.
public struct KeyframeAnimator<Value, KeyframePath: Keyframes, Content: View>: View where KeyframePath.Value == Value {
    package let initialValue: Value
    package let trigger: _AnyEquatable?
    package let repeating: Bool
    package let content: (Value) -> Content
    package let keyframes: (Value) -> KeyframePath

    /// Plays the keyframes when the view appears, once or repeatedly.
    public init(initialValue: Value, repeating: Bool = false, @ViewBuilder content: @escaping (Value) -> Content,
                @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath) {
        self.initialValue = initialValue
        self.trigger = nil
        self.repeating = repeating
        self.content = content
        self.keyframes = keyframes
    }

    /// Plays the keyframes each time `trigger` changes.
    public init(initialValue: Value, trigger: some Equatable, @ViewBuilder content: @escaping (Value) -> Content,
                @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath) {
        self.initialValue = initialValue
        self.trigger = _AnyEquatable(trigger)
        self.repeating = false
        self.content = content
        self.keyframes = keyframes
    }

    public var body: Never { fatalError("KeyframeAnimator is a primitive view") }

    public static func _makeNode(_ context: _NodeContext<KeyframeAnimator<Value, KeyframePath, Content>>) -> TypedNode<KeyframeAnimator<Value, KeyframePath, Content>> {
        KeyframeAnimatorNode(context)
    }
}

extension View {
    /// Animates a value through keyframes when the view appears (once or repeatedly), restyling this view with it.
    public func keyframeAnimator<Value, KeyframePath: Keyframes, V: View>(
        initialValue: Value, repeating: Bool = false,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> V,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) -> some View where KeyframePath.Value == Value {
        let placeholder = PlaceholderContentView(self)
        return KeyframeAnimator(initialValue: initialValue, repeating: repeating, content: { content(placeholder, $0) }, keyframes: keyframes)
    }

    /// Animates a value through keyframes whenever `trigger` changes, restyling this view with it.
    public func keyframeAnimator<Value, KeyframePath: Keyframes, V: View>(
        initialValue: Value, trigger: some Equatable,
        @ViewBuilder content: @escaping (PlaceholderContentView<Self>, Value) -> V,
        @KeyframesBuilder<Value> keyframes: @escaping (Value) -> KeyframePath
    ) -> some View where KeyframePath.Value == Value {
        let placeholder = PlaceholderContentView(self)
        return KeyframeAnimator(initialValue: initialValue, trigger: trigger, content: { content(placeholder, $0) }, keyframes: keyframes)
    }
}

// MARK: - Keyframes

/// A set of keyframe tracks over `Value`: each track drives one animatable property.
public protocol Keyframes<Value> {
    associatedtype Value
    var _tracks: [_AnyKeyframeTrack<Value>] { get }
}

/// A keyframe track's content: the keyframes in order.
public protocol KeyframeTrackContent<Value> {
    associatedtype Value: Animatable
    var _segments: [_KeyframeSegment<Value>] { get }
}

/// One keyframe track: the keyframes applied to `keyPath` of the value.
public struct KeyframeTrack<Root, Value: Animatable, Content: KeyframeTrackContent<Value>>: Keyframes {
    package let keyPath: WritableKeyPath<Root, Value>
    package let content: Content

    public init(_ keyPath: WritableKeyPath<Root, Value>, @KeyframeTrackContentBuilder<Value> content: () -> Content) {
        self.keyPath = keyPath
        self.content = content()
    }

    public var _tracks: [_AnyKeyframeTrack<Root>] {
        [_AnyKeyframeTrack(keyPath: keyPath, segments: content._segments)]
    }
}

extension KeyframeTrack where Root == Value {
    /// A track over the value itself.
    public init(@KeyframeTrackContentBuilder<Value> content: () -> Content) {
        self.init(\.self, content: content)
    }
}

/// A group of tracks (the result of `KeyframesBuilder`).
public struct _KeyframeTrackGroup<Value>: Keyframes {
    public let _tracks: [_AnyKeyframeTrack<Value>]
    package init(_ tracks: [_AnyKeyframeTrack<Value>]) { _tracks = tracks }
}

@resultBuilder
public enum KeyframesBuilder<Value> {
    public static func buildExpression<K: Keyframes>(_ expression: K) -> _KeyframeTrackGroup<Value> where K.Value == Value {
        _KeyframeTrackGroup(expression._tracks)
    }
    public static func buildBlock(_ components: _KeyframeTrackGroup<Value>...) -> _KeyframeTrackGroup<Value> {
        _KeyframeTrackGroup(components.flatMap(\._tracks))
    }
    public static func buildOptional(_ component: _KeyframeTrackGroup<Value>?) -> _KeyframeTrackGroup<Value> {
        component ?? _KeyframeTrackGroup([])
    }
    public static func buildEither(first component: _KeyframeTrackGroup<Value>) -> _KeyframeTrackGroup<Value> { component }
    public static func buildEither(second component: _KeyframeTrackGroup<Value>) -> _KeyframeTrackGroup<Value> { component }
    public static func buildArray(_ components: [_KeyframeTrackGroup<Value>]) -> _KeyframeTrackGroup<Value> {
        _KeyframeTrackGroup(components.flatMap(\._tracks))
    }
    public static func buildFinalResult(_ component: _KeyframeTrackGroup<Value>) -> _KeyframeTrackGroup<Value> { component }
}

/// The keyframes of a track (the result of `KeyframeTrackContentBuilder`).
public struct _KeyframeList<Value: Animatable>: KeyframeTrackContent {
    public let _segments: [_KeyframeSegment<Value>]
    package init(_ segments: [_KeyframeSegment<Value>]) { _segments = segments }
}

@resultBuilder
public enum KeyframeTrackContentBuilder<Value: Animatable> {
    public static func buildExpression<K: KeyframeTrackContent>(_ expression: K) -> _KeyframeList<Value> where K.Value == Value {
        _KeyframeList(expression._segments)
    }
    public static func buildBlock(_ components: _KeyframeList<Value>...) -> _KeyframeList<Value> {
        _KeyframeList(components.flatMap(\._segments))
    }
    public static func buildOptional(_ component: _KeyframeList<Value>?) -> _KeyframeList<Value> { component ?? _KeyframeList([]) }
    public static func buildEither(first component: _KeyframeList<Value>) -> _KeyframeList<Value> { component }
    public static func buildEither(second component: _KeyframeList<Value>) -> _KeyframeList<Value> { component }
    public static func buildArray(_ components: [_KeyframeList<Value>]) -> _KeyframeList<Value> { _KeyframeList(components.flatMap(\._segments)) }
    public static func buildFinalResult(_ component: _KeyframeList<Value>) -> _KeyframeList<Value> { component }
}

// MARK: Keyframe kinds

/// One keyframe: the value to reach, how long it takes and how it gets there.
public struct _KeyframeSegment<Value: Animatable> {
    package enum Kind {
        case linear(UnitCurve)
        case cubic(startVelocity: Value.AnimatableData?, endVelocity: Value.AnimatableData?)
        case spring(Spring, startVelocity: Value.AnimatableData?)
        case move
    }
    package var to: Value
    package var duration: Double
    package var kind: Kind
}

/// Interpolates linearly (through `timingCurve`) to the value.
public struct LinearKeyframe<Value: Animatable>: KeyframeTrackContent {
    package let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: Double, timingCurve: UnitCurve = .linear) {
        segment = _KeyframeSegment(to: to, duration: duration, kind: .linear(timingCurve))
    }
    public var _segments: [_KeyframeSegment<Value>] { [segment] }
}

/// A smooth cubic curve through the value, with velocities derived from the neighbours unless given.
public struct CubicKeyframe<Value: Animatable>: KeyframeTrackContent {
    package let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: Double, startVelocity: Value? = nil, endVelocity: Value? = nil) {
        segment = _KeyframeSegment(to: to, duration: duration,
                                   kind: .cubic(startVelocity: startVelocity?.animatableData, endVelocity: endVelocity?.animatableData))
    }
    public var _segments: [_KeyframeSegment<Value>] { [segment] }
}

/// A spring motion to the value: the spring's settling time unless a duration is given.
public struct SpringKeyframe<Value: Animatable>: KeyframeTrackContent {
    package let segment: _KeyframeSegment<Value>
    public init(_ to: Value, duration: Double? = nil, spring: Spring = .smooth, startVelocity: Value? = nil) {
        segment = _KeyframeSegment(to: to, duration: duration ?? spring.settlingDuration,
                                   kind: .spring(spring, startVelocity: startVelocity?.animatableData))
    }
    public var _segments: [_KeyframeSegment<Value>] { [segment] }
}

/// Jumps to the value.
public struct MoveKeyframe<Value: Animatable>: KeyframeTrackContent {
    package let segment: _KeyframeSegment<Value>
    public init(_ to: Value) { segment = _KeyframeSegment(to: to, duration: 0, kind: .move) }
    public var _segments: [_KeyframeSegment<Value>] { [segment] }
}

// MARK: Evaluation

/// A track with its key path erased: evaluates one property of `Root` at a time.
public struct _AnyKeyframeTrack<Root> {
    package let duration: Double
    package let apply: (inout Root, Double) -> Void

    package init<Value: Animatable>(keyPath: WritableKeyPath<Root, Value>, segments: [_KeyframeSegment<Value>]) {
        let duration = segments.reduce(0) { $0 + $1.duration }
        self.duration = duration
        apply = { root, time in
            let start = root[keyPath: keyPath]
            root[keyPath: keyPath] = Self.evaluate(segments, from: start, at: time)
        }
    }

    /// The value at `time` along `segments` starting from `initial` (SwiftUI's rule: a value
    /// past the end holds the last keyframe).
    package static func evaluate<Value: Animatable>(_ segments: [_KeyframeSegment<Value>], from initial: Value, at time: Double) -> Value {
        guard !segments.isEmpty else { return initial }
        // Keyframe times and values along the track.
        var times: [Double] = [0]
        var values: [Value.AnimatableData] = [initial.animatableData]
        for segment in segments {
            times.append(times.last! + segment.duration)
            values.append(segment.to.animatableData)
        }
        if time >= times.last! { return segments.last!.to }
        if time <= 0 { return initial }
        var index = 0
        while index + 1 < segments.count, time >= times[index + 1] { index += 1 }
        let segment = segments[index]
        let from = values[index], to = values[index + 1]
        let span = max(segment.duration, 1e-9)
        let u = min(1, max(0, (time - times[index]) / span))
        var result: Value.AnimatableData
        switch segment.kind {
        case .move:
            result = u >= 1 ? to : from
        case .linear(let curve):
            result = lerp(from, to, curve.value(at: u))
        case .spring(let spring, let startVelocity):
            let animation = spring.animation
            let factor = animation.value(at: u * animation.duration)
            result = lerp(from, to, factor)
            if let v = startVelocity {
                // The initial velocity adds a decaying displacement.
                var kick = v
                kick.scale(by: u * (1 - u) * (1 - u) * span)
                result += kick
            }
        case .cubic(let startVelocity, let endVelocity):
            // Catmull-Rom velocities from the neighbouring keyframes unless given.
            func velocity(at k: Int) -> Value.AnimatableData {
                let before = max(0, k - 1), after = min(values.count - 1, k + 1)
                let dt = times[after] - times[before]
                guard dt > 0 else { return .zero }
                var v = values[after] - values[before]
                v.scale(by: 1 / dt)
                return v
            }
            let m0 = startVelocity ?? velocity(at: index)
            let m1 = endVelocity ?? velocity(at: index + 1)
            result = hermite(from, to, m0, m1, u: u, span: span)
        }
        var value = initial
        value.animatableData = result
        return value
    }

    static func lerp<V: VectorArithmetic>(_ a: V, _ b: V, _ t: Double) -> V {
        var delta = b - a
        delta.scale(by: t)
        return a + delta
    }

    static func hermite<V: VectorArithmetic>(_ p0: V, _ p1: V, _ m0: V, _ m1: V, u: Double, span: Double) -> V {
        let u2 = u * u, u3 = u2 * u
        var a = p0; a.scale(by: 2 * u3 - 3 * u2 + 1)
        var b = m0; b.scale(by: (u3 - 2 * u2 + u) * span)
        var c = p1; c.scale(by: -2 * u3 + 3 * u2)
        var d = m1; d.scale(by: (u3 - u2) * span)
        return a + b + c + d
    }
}

/// Evaluates keyframes directly: the value at a time or progress.
public struct KeyframeTimeline<Value> {
    package let initialValue: Value
    package let tracks: [_AnyKeyframeTrack<Value>]

    public init<K: Keyframes>(initialValue: Value, @KeyframesBuilder<Value> content: () -> K) where K.Value == Value {
        self.initialValue = initialValue
        self.tracks = content()._tracks
    }

    package init(initialValue: Value, tracks: [_AnyKeyframeTrack<Value>]) {
        self.initialValue = initialValue
        self.tracks = tracks
    }

    /// The longest track's duration.
    public var duration: Double { tracks.map(\.duration).max() ?? 0 }

    public func value(time: Double) -> Value {
        var value = initialValue
        for track in tracks { track.apply(&value, time) }
        return value
    }

    public func value(progress: Double) -> Value { value(time: progress * duration) }
}

// MARK: Spring and UnitCurve

/// A spring's shape, for keyframes.
public struct Spring: Hashable, Sendable {
    public var duration: Double
    public var bounce: Double

    public init(duration: Double = 0.5, bounce: Double = 0) {
        self.duration = duration
        self.bounce = bounce
    }

    public static var smooth: Spring { Spring(duration: 0.5, bounce: 0) }
    public static var snappy: Spring { Spring(duration: 0.5, bounce: 0.15) }
    public static var bouncy: Spring { Spring(duration: 0.5, bounce: 0.3) }
    public static func smooth(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: extraBounce) }
    public static func snappy(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: 0.15 + extraBounce) }
    public static func bouncy(duration: Double = 0.5, extraBounce: Double = 0) -> Spring { Spring(duration: duration, bounce: 0.3 + extraBounce) }

    /// The animation with this spring's curve.
    package var animation: Animation { .spring(duration: duration, bounce: bounce) }
    /// How long the spring takes to settle.
    public var settlingDuration: Double { animation.duration }

    /// The physics behind it (`SpringModel`, one for every motion).
    package var model: SpringModel { SpringModel(duration: duration, bounce: bounce) }

    /// A spring with the given response and damping ratio.
    public init(response: Double, dampingRatio: Double) {
        self.init(duration: response, bounce: SpringModel(response: response, dampingFraction: dampingRatio).bounce)
    }

    /// A spring with the given mass, stiffness and damping (as a unit-mass spring of the same
    /// motion).
    public init(mass: Double = 1, stiffness: Double, damping: Double, allowOverDamping: Bool = false) {
        let model = SpringModel(mass: mass, stiffness: stiffness, damping: damping, allowsOverdamping: allowOverDamping)
        self.init(duration: model.response, bounce: model.bounce)
    }

    public var response: Double { duration }
    public var dampingRatio: Double { model.zeta }
    public var mass: Double { 1 }
    public var stiffness: Double { model.stiffness() }
    public var damping: Double { model.damping() }

    /// The value `time` seconds into a change of `target` from zero, leaving at `initialVelocity`.
    public func value<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: Double) -> V {
        let fromStart = model.state(displacement: 1, velocity: 0, at: time), fromKick = model.state(displacement: 0, velocity: 1, at: time)
        return target - target.scaled(by: fromStart.displacement) + initialVelocity.scaled(by: fromKick.displacement)
    }

    /// The velocity `time` seconds into a change of `target` from zero, leaving at `initialVelocity`.
    public func velocity<V: VectorArithmetic>(target: V, initialVelocity: V = .zero, time: Double) -> V {
        let fromStart = model.state(displacement: 1, velocity: 0, at: time), fromKick = model.state(displacement: 0, velocity: 1, at: time)
        return initialVelocity.scaled(by: fromKick.velocity) - target.scaled(by: fromStart.velocity)
    }
}

/// A timing curve over the unit interval.
public struct UnitCurve: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        case linear
        case bezier(Double, Double, Double, Double)
    }
    package let kind: Kind

    public static let linear = UnitCurve(kind: .linear)
    public static let easeIn = UnitCurve(kind: .bezier(0.42, 0, 1, 1))
    public static let easeOut = UnitCurve(kind: .bezier(0, 0, 0.58, 1))
    public static let easeInOut = UnitCurve(kind: .bezier(0.42, 0, 0.58, 1))
    public static let circularEaseIn = UnitCurve(kind: .bezier(0.55, 0, 1, 0.45))
    public static let circularEaseOut = UnitCurve(kind: .bezier(0, 0.55, 0.45, 1))
    public static let circularEaseInOut = UnitCurve(kind: .bezier(0.85, 0, 0.15, 1))

    public static func bezier(startControlPoint: UnitPoint, endControlPoint: UnitPoint) -> UnitCurve {
        UnitCurve(kind: .bezier(startControlPoint.x, startControlPoint.y, endControlPoint.x, endControlPoint.y))
    }

    /// The curve's value at `progress`.
    public func value(at progress: Double) -> Double {
        switch kind {
        case .linear: return min(1, max(0, progress))
        case .bezier(let x1, let y1, let x2, let y2):
            return Animation.timingCurve(x1, y1, x2, y2, duration: 1).value(at: min(1, max(0, progress)))
        }
    }
}
