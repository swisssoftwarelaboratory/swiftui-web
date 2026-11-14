// Gesture recognition (API/Gesture.swift): a `GestureNode` is the interactive node for its
// content; the runtime's press events reach its recogniser, which emits typed values to the
// gesture's handlers. Long presses tick on the animation clock through a frame subscription.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// One press event in the node's space, with the host's event time (seconds) and the animation
/// clock at delivery.
public struct GestureEvent: Sendable {
    public var location: CGPoint
    public var time: Double
    public var clock: Double
    /// The node's origin in the window, for global coordinate spaces.
    public var windowOrigin: CGPoint
}

/// One pinch event in the node's space: the cumulative scale and rotation (radians) since the
/// pinch began, its centre, the host's event time and the node's bounds (for anchors).
public struct PinchEvent: Sendable {
    public var location: CGPoint
    public var scale: CGFloat
    public var rotation: Double
    public var time: Double
    public var bounds: CGSize
}

/// A recogniser: receives press (and pinch) events, tracks a phase and emits values. The base
/// class never recognises.
@MainActor
open class _GestureRecognizer<Value> {
    public enum Phase: Sendable { case possible, active, ended, failed }
    public internal(set) var phase: Phase = .possible
    package var changedHandlers: [@MainActor (Value) -> Void] = []
    package var endedHandlers: [@MainActor (Value) -> Void] = []
    package var resetHandlers: [@MainActor () -> Void] = []

    public init() {}

    /// Whether the recogniser needs frames to complete (a long press waiting for its duration).
    open var wantsFrames: Bool { false }
    /// Whether the recogniser takes pinches (magnify and rotate gestures, and composites of them).
    open var recognizesPinch: Bool { false }

    open func began(_ event: GestureEvent) {}
    open func moved(_ event: GestureEvent) {}
    open func ended(_ event: GestureEvent, inside: Bool) { finish() }
    /// The animation clock advanced (only while `wantsFrames`).
    open func tick(clock: Double) {}
    open func pinchBegan(_ event: PinchEvent) {}
    open func pinchChanged(_ event: PinchEvent) {}
    open func pinchEnded(_ event: PinchEvent, cancelled: Bool) {}

    /// Forgets the press without recognising.
    open func cancel() { finish() }

    package func emitChanged(_ value: Value) {
        phase = .active
        for handler in changedHandlers { handler(value) }
    }

    package func emitEnded(_ value: Value) {
        phase = .ended
        for handler in endedHandlers { handler(value) }
        for reset in resetHandlers { reset() }
    }

    package func fail() {
        if phase == .active { for reset in resetHandlers { reset() } }
        phase = .failed
    }

    /// Back to `possible` for the next press.
    package func finish() {
        if phase == .active { for reset in resetHandlers { reset() } }
        phase = .possible
    }
}

/// `TapGesture`: `count` presses released inside within 0.35 s of each other.
@MainActor
final class TapRecognizer: _GestureRecognizer<Void> {
    let count: Int
    private var taps = 0
    private var lastTapTime: Double?
    private var start: CGPoint = .zero

    init(count: Int) { self.count = count }

    override func began(_ event: GestureEvent) {
        if let last = lastTapTime, event.time - last > 0.35 { taps = 0 }
        start = event.location
    }

    override func ended(_ event: GestureEvent, inside: Bool) {
        guard inside, abs(event.location.x - start.x) <= 10, abs(event.location.y - start.y) <= 10 else { taps = 0; finish(); return }
        taps += 1
        lastTapTime = event.time
        if taps >= count {
            taps = 0
            emitEnded(())
        }
        finish()
    }
}

/// `SpatialTapGesture`: a `TapGesture` that reports where the last tap was released.
@MainActor
final class SpatialTapRecognizer: _GestureRecognizer<SpatialTapGesture.Value> {
    private let taps: TapRecognizer
    private let global: Bool
    private var location: CGPoint = .zero

    init(count: Int, global: Bool) {
        taps = TapRecognizer(count: count)
        self.global = global
        super.init()
        taps.endedHandlers.append { [unowned self] _ in self.emitEnded(SpatialTapGesture.Value(location: self.location)) }
    }

    override func began(_ event: GestureEvent) { taps.began(event) }

    override func ended(_ event: GestureEvent, inside: Bool) {
        location = global ? CGPoint(x: event.location.x + event.windowOrigin.x, y: event.location.y + event.windowOrigin.y) : event.location
        taps.ended(event, inside: inside)
        finish()
    }

    override func cancel() {
        taps.cancel()
        finish()
    }
}

/// `LongPressGesture`: reports `true` once the press has been held; ends (recognises) then.
@MainActor
final class LongPressRecognizer: _GestureRecognizer<Bool> {
    let minimumDuration: Double
    let maximumDistance: CGFloat
    private var startClock: Double?
    private var start: CGPoint = .zero
    /// Whether "pressing" was reported and the release must report its end.
    private var reportedPressing = false

    init(minimumDuration: Double, maximumDistance: CGFloat) {
        self.minimumDuration = minimumDuration
        self.maximumDistance = maximumDistance
    }

    override var wantsFrames: Bool { startClock != nil }

    override func began(_ event: GestureEvent) {
        startClock = event.clock
        start = event.location
        // "Pressing" is reported at once, without counting as recognition.
        reportedPressing = true
        for handler in changedHandlers { handler(true) }
        phase = .possible
        tick(clock: event.clock)
    }

    private func reportRelease() {
        guard reportedPressing else { return }
        reportedPressing = false
        for handler in changedHandlers { handler(false) }
    }

    override func moved(_ event: GestureEvent) {
        guard startClock != nil else { return }
        if abs(event.location.x - start.x) > maximumDistance || abs(event.location.y - start.y) > maximumDistance {
            startClock = nil
            reportRelease()
            fail()
        }
    }

    override func tick(clock: Double) {
        guard let startClock else { return }
        if clock - startClock >= minimumDuration {
            self.startClock = nil
            emitEnded(true)
            phase = .ended
        }
    }

    override func ended(_ event: GestureEvent, inside: Bool) {
        // Released before the duration: the press failed; after it: the release still ends "pressing".
        let early = startClock != nil
        startClock = nil
        reportRelease()
        if early { fail() }
        phase = .possible
    }

    override func cancel() {
        startClock = nil
        reportRelease()
        finish()
    }
}

/// `DragGesture`: active once the pointer moved `minimumDistance`; values in the node's space
/// or the window's.
@MainActor
final class DragRecognizer: _GestureRecognizer<DragGesture.Value> {
    let minimumDistance: CGFloat
    let global: Bool
    private var start: GestureEvent?
    private var last: GestureEvent?
    private var velocity: CGSize = .zero
    /// The finger's path, for its speed (`VelocityTracker`, as a scroll view reads it).
    private var tracker = VelocityTracker()

    init(minimumDistance: CGFloat, global: Bool) {
        self.minimumDistance = minimumDistance
        self.global = global
    }

    private func point(_ event: GestureEvent) -> CGPoint {
        global ? CGPoint(x: event.location.x + event.windowOrigin.x, y: event.location.y + event.windowOrigin.y) : event.location
    }

    private func value(_ event: GestureEvent, start: GestureEvent) -> DragGesture.Value {
        DragGesture.Value(time: Date(timeIntervalSince1970: event.time), location: point(event), startLocation: point(start), velocity: velocity)
    }

    override func began(_ event: GestureEvent) {
        start = event
        last = event
        velocity = .zero
        tracker.reset()
        tracker.add(event.location, at: event.time)
        phase = .possible
    }

    override func moved(_ event: GestureEvent) {
        guard let start else { return }
        tracker.add(event.location, at: event.time)
        velocity = tracker.recentVelocity ?? velocity
        last = event
        let dx = event.location.x - start.location.x, dy = event.location.y - start.location.y
        if phase != .active, (dx * dx + dy * dy).squareRoot() < minimumDistance { return }
        emitChanged(value(event, start: start))
    }

    override func ended(_ event: GestureEvent, inside: Bool) {
        if phase == .active, let start {
            // A finger that rested before lifting leaves with no speed (UIKit's rule).
            velocity = tracker.velocity(at: event.time)
            if velocity != .zero, let last, event.location != last.location {
                tracker.add(event.location, at: event.time)
                velocity = tracker.recentVelocity ?? velocity
            }
            emitEnded(value(event, start: start))
        }
        start = nil
        last = nil
        tracker.reset()
        phase = .possible
    }
}

/// `MagnifyGesture`: active once the scale moved `minimumScaleDelta` from 1.
@MainActor
final class MagnifyRecognizer: _GestureRecognizer<MagnifyGesture.Value> {
    let minimumScaleDelta: CGFloat
    private var start: PinchEvent?
    private var last: PinchEvent?
    private var velocity: CGFloat = 0

    init(minimumScaleDelta: CGFloat) { self.minimumScaleDelta = minimumScaleDelta }

    override var recognizesPinch: Bool { true }

    private func value(_ event: PinchEvent, start: PinchEvent) -> MagnifyGesture.Value {
        MagnifyGesture.Value(magnification: event.scale, velocity: velocity, startAnchor: _pinchAnchor(start), startLocation: start.location)
    }

    override func pinchBegan(_ event: PinchEvent) {
        start = event
        last = event
        velocity = 0
        phase = .possible
    }

    override func pinchChanged(_ event: PinchEvent) {
        guard let start else { return }
        if let last, event.time > last.time { velocity = (event.scale - last.scale) / (event.time - last.time) }
        last = event
        if phase != .active, abs(event.scale - 1) < minimumScaleDelta { return }
        emitChanged(value(event, start: start))
    }

    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) {
        if phase == .active, let start, !cancelled { emitEnded(value(event, start: start)) }
        start = nil
        last = nil
        finish()
    }

    override func cancel() { start = nil; last = nil; finish() }
}

/// `RotateGesture`: active once the fingers turned `minimumAngleDelta`.
@MainActor
final class RotateRecognizer: _GestureRecognizer<RotateGesture.Value> {
    let minimumAngleDelta: Angle
    private var start: PinchEvent?
    private var last: PinchEvent?
    private var velocity: Double = 0

    init(minimumAngleDelta: Angle) { self.minimumAngleDelta = minimumAngleDelta }

    override var recognizesPinch: Bool { true }

    private func value(_ event: PinchEvent, start: PinchEvent) -> RotateGesture.Value {
        RotateGesture.Value(rotation: .radians(event.rotation), velocity: .radians(velocity), startAnchor: _pinchAnchor(start), startLocation: start.location)
    }

    override func pinchBegan(_ event: PinchEvent) {
        start = event
        last = event
        velocity = 0
        phase = .possible
    }

    override func pinchChanged(_ event: PinchEvent) {
        guard let start else { return }
        if let last, event.time > last.time { velocity = (event.rotation - last.rotation) / (event.time - last.time) }
        last = event
        if phase != .active, abs(event.rotation) < abs(minimumAngleDelta.radians) { return }
        emitChanged(value(event, start: start))
    }

    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) {
        if phase == .active, let start, !cancelled { emitEnded(value(event, start: start)) }
        start = nil
        last = nil
        finish()
    }

    override func cancel() { start = nil; last = nil; finish() }
}

/// The pinch's start as a fraction of the node's bounds.
@MainActor private func _pinchAnchor(_ event: PinchEvent) -> UnitPoint {
    guard event.bounds.width > 0, event.bounds.height > 0 else { return .center }
    return UnitPoint(x: event.location.x / event.bounds.width, y: event.location.y / event.bounds.height)
}

/// `map`: forwards the base recogniser's values through `transform`.
@MainActor
final class MapRecognizer<Base, Value>: _GestureRecognizer<Value> {
    let base: _GestureRecognizer<Base>

    init(base: _GestureRecognizer<Base>, transform: @escaping @MainActor (Base) -> Value) {
        self.base = base
        super.init()
        base.changedHandlers.append { [unowned self] value in self.emitChanged(transform(value)) }
        base.endedHandlers.append { [unowned self] value in self.emitEnded(transform(value)) }
    }

    override var wantsFrames: Bool { base.wantsFrames }
    override var recognizesPinch: Bool { base.recognizesPinch }
    override func began(_ event: GestureEvent) { base.began(event) }
    override func moved(_ event: GestureEvent) { base.moved(event) }
    override func ended(_ event: GestureEvent, inside: Bool) { base.ended(event, inside: inside); finish() }
    override func tick(clock: Double) { base.tick(clock: clock) }
    override func pinchBegan(_ event: PinchEvent) { base.pinchBegan(event) }
    override func pinchChanged(_ event: PinchEvent) { base.pinchChanged(event) }
    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) { base.pinchEnded(event, cancelled: cancelled); finish() }
    override func cancel() { base.cancel(); finish() }
}

/// `sequenced`: the first gesture until it ends, then the second within the same press.
@MainActor
final class SequenceRecognizer<F, S>: _GestureRecognizer<_SequenceValue<F, S>> {
    let first: _GestureRecognizer<F>
    let second: _GestureRecognizer<S>
    private var firstValue: F?
    private var pending: GestureEvent?

    init(first: _GestureRecognizer<F>, second: _GestureRecognizer<S>) {
        self.first = first
        self.second = second
        super.init()
        first.changedHandlers.append { [unowned self] value in self.emitChanged(.first(value)) }
        first.endedHandlers.append { [unowned self] value in
            self.firstValue = value
            self.emitChanged(.second(value, nil))
            if let pending = self.pending { self.second.began(pending) }
        }
        second.changedHandlers.append { [unowned self] value in
            if let firstValue = self.firstValue { self.emitChanged(.second(firstValue, value)) }
        }
        second.endedHandlers.append { [unowned self] value in
            if let firstValue = self.firstValue { self.emitEnded(.second(firstValue, value)) }
        }
    }

    override var wantsFrames: Bool { first.wantsFrames || second.wantsFrames }

    override func began(_ event: GestureEvent) {
        firstValue = nil
        pending = event
        first.began(event)
    }

    override func moved(_ event: GestureEvent) {
        if firstValue != nil { second.moved(event) } else { first.moved(event) }
    }

    override func ended(_ event: GestureEvent, inside: Bool) {
        if firstValue != nil { second.ended(event, inside: inside) } else { first.ended(event, inside: inside) }
        firstValue = nil
        pending = nil
        finish()
    }

    override func tick(clock: Double) {
        if firstValue != nil { second.tick(clock: clock) } else { first.tick(clock: clock) }
    }

    override var recognizesPinch: Bool { first.recognizesPinch || second.recognizesPinch }
    override func pinchBegan(_ event: PinchEvent) { if firstValue != nil { second.pinchBegan(event) } else { first.pinchBegan(event) } }
    override func pinchChanged(_ event: PinchEvent) { if firstValue != nil { second.pinchChanged(event) } else { first.pinchChanged(event) } }
    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) {
        if firstValue != nil { second.pinchEnded(event, cancelled: cancelled) } else { first.pinchEnded(event, cancelled: cancelled) }
        firstValue = nil
        pending = nil
        finish()
    }
    override func cancel() { first.cancel(); second.cancel(); firstValue = nil; pending = nil; finish() }
}

/// `simultaneously`: both gestures see every event.
@MainActor
final class SimultaneousRecognizer<F, S>: _GestureRecognizer<_SimultaneousValue<F, S>> {
    let first: _GestureRecognizer<F>
    let second: _GestureRecognizer<S>
    private var firstValue: F?
    private var secondValue: S?

    init(first: _GestureRecognizer<F>, second: _GestureRecognizer<S>) {
        self.first = first
        self.second = second
        super.init()
        first.changedHandlers.append { [unowned self] value in self.firstValue = value; self.emitChanged(.init(first: value, second: self.secondValue)) }
        second.changedHandlers.append { [unowned self] value in self.secondValue = value; self.emitChanged(.init(first: self.firstValue, second: value)) }
        first.endedHandlers.append { [unowned self] value in self.firstValue = value; self.emitEnded(.init(first: value, second: self.secondValue)) }
        second.endedHandlers.append { [unowned self] value in self.secondValue = value; self.emitEnded(.init(first: self.firstValue, second: value)) }
    }

    override var wantsFrames: Bool { first.wantsFrames || second.wantsFrames }
    override func began(_ event: GestureEvent) { firstValue = nil; secondValue = nil; first.began(event); second.began(event) }
    override func moved(_ event: GestureEvent) { first.moved(event); second.moved(event) }
    override func ended(_ event: GestureEvent, inside: Bool) { first.ended(event, inside: inside); second.ended(event, inside: inside); finish() }
    override func tick(clock: Double) { first.tick(clock: clock); second.tick(clock: clock) }
    override var recognizesPinch: Bool { first.recognizesPinch || second.recognizesPinch }
    override func pinchBegan(_ event: PinchEvent) { firstValue = nil; secondValue = nil; first.pinchBegan(event); second.pinchBegan(event) }
    override func pinchChanged(_ event: PinchEvent) { first.pinchChanged(event); second.pinchChanged(event) }
    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) { first.pinchEnded(event, cancelled: cancelled); second.pinchEnded(event, cancelled: cancelled); finish() }
    override func cancel() { first.cancel(); second.cancel(); finish() }
}

/// `exclusively`: the first gesture to become active wins; the other is cancelled.
@MainActor
final class ExclusiveRecognizer<F, S>: _GestureRecognizer<_ExclusiveValue<F, S>> {
    let first: _GestureRecognizer<F>
    let second: _GestureRecognizer<S>
    private var winner: Int?

    init(first: _GestureRecognizer<F>, second: _GestureRecognizer<S>) {
        self.first = first
        self.second = second
        super.init()
        // A gesture wins once it is active (a long press's initial "pressing" report is not).
        first.changedHandlers.append { [unowned self] value in
            if self.winner == nil, self.first.phase == .active { self.winner = 1; self.second.cancel() }
            if self.winner == 1 { self.emitChanged(.first(value)) }
        }
        second.changedHandlers.append { [unowned self] value in
            if self.winner == nil, self.second.phase == .active { self.winner = 2; self.first.cancel() }
            if self.winner == 2 { self.emitChanged(.second(value)) }
        }
        first.endedHandlers.append { [unowned self] value in if self.winner != 2 { self.winner = 1; self.emitEnded(.first(value)) } }
        second.endedHandlers.append { [unowned self] value in if self.winner != 1 { self.winner = 2; self.emitEnded(.second(value)) } }
    }

    override var wantsFrames: Bool { first.wantsFrames || second.wantsFrames }
    override func began(_ event: GestureEvent) { winner = nil; first.began(event); second.began(event) }
    override func moved(_ event: GestureEvent) { if winner != 2 { first.moved(event) }; if winner != 1 { second.moved(event) } }
    override func ended(_ event: GestureEvent, inside: Bool) {
        if winner != 2 { first.ended(event, inside: inside) }
        if winner != 1 { second.ended(event, inside: inside) }
        finish()
    }
    override func tick(clock: Double) { if winner != 2 { first.tick(clock: clock) }; if winner != 1 { second.tick(clock: clock) } }
    override var recognizesPinch: Bool { first.recognizesPinch || second.recognizesPinch }
    override func pinchBegan(_ event: PinchEvent) { winner = nil; first.pinchBegan(event); second.pinchBegan(event) }
    override func pinchChanged(_ event: PinchEvent) { if winner != 2 { first.pinchChanged(event) }; if winner != 1 { second.pinchChanged(event) } }
    override func pinchEnded(_ event: PinchEvent, cancelled: Bool) {
        if winner != 2 { first.pinchEnded(event, cancelled: cancelled) }
        if winner != 1 { second.pinchEnded(event, cancelled: cancelled) }
        finish()
    }
    override func cancel() { first.cancel(); second.cancel(); winner = nil; finish() }
}

/// A gesture node that takes pinches (`Runtime.pinch`).
@MainActor
package protocol _PinchTarget: AnyObject {
    var acceptsPinch: Bool { get }
    /// Whether the node's gesture runs alongside its subviews' (`simultaneousGesture`).
    var isSimultaneousGesture: Bool { get }
    func pinchBegan(_ event: PinchEvent)
    func pinchChanged(_ event: PinchEvent)
    func pinchEnded(_ event: PinchEvent, cancelled: Bool)
}

/// The node behind `gesture`/`highPriorityGesture`/`simultaneousGesture`.
@MainActor
package final class GestureNode<Content: View, G: Gesture>: UnaryLayoutModifierNode<Content, _GestureModifier<G>>, _Interactive, _FrameSubscriber, _PinchTarget {
    private var recognizer: _GestureRecognizer<G.Value>
    private var pressing = false
    private let identifier: Int

    override package init(_ context: _NodeContext<ModifiedContent<Content, _GestureModifier<G>>>) {
        recognizer = context.view.modifier.gesture._makeRecognizer()
        identifier = _nextGestureIdentifier()
        super.init(context)
    }

    override package func update(view: ModifiedContent<Content, _GestureModifier<G>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        // A press in flight keeps its recogniser (and the handlers it captured).
        if !pressing { recognizer = view.modifier.gesture._makeRecognizer() }
    }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    private func event(_ point: CGPoint) -> GestureEvent {
        GestureEvent(location: point, time: runtime.lastPointerTime, clock: runtime.animationClock, windowOrigin: frameInRoot.origin)
    }

    /// The mask's `.gesture` bit: without it the node's own gesture never runs.
    private var takesEvents: Bool { modifier.mask.contains(.gesture) }

    package func pressBegan() {}

    package func pressBegan(at point: CGPoint) {
        guard takesEvents else { return }
        pressing = true
        recognizer.began(event(point))
        if recognizer.wantsFrames { runtime.subscribeFrames(self) }
    }

    package func pressMoved(to point: CGPoint) {
        guard pressing else { return }
        recognizer.moved(event(point))
        if !recognizer.wantsFrames { runtime.unsubscribeFrames(self) }
    }

    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard pressing else { return }
        recognizer.ended(event(point), inside: inside)
        pressing = false
        runtime.unsubscribeFrames(self)
        // Handlers may have changed state that needs a frame.
        runtime.requestLayout()
    }

    package func frameDidAdvance() {
        recognizer.tick(clock: runtime.animationClock)
        if !recognizer.wantsFrames { runtime.unsubscribeFrames(self) }
    }

    // MARK: Pinches

    package var acceptsPinch: Bool { takesEvents && recognizer.recognizesPinch }
    package var isSimultaneousGesture: Bool { modifier.priority == .simultaneous }

    private func pinchEvent(_ event: PinchEvent) -> PinchEvent {
        var local = event
        local.bounds = frame.size
        return local
    }

    package func pinchBegan(_ event: PinchEvent) {
        pressing = true
        recognizer.pinchBegan(pinchEvent(event))
    }

    package func pinchChanged(_ event: PinchEvent) {
        recognizer.pinchChanged(pinchEvent(event))
        runtime.requestLayout()
    }

    package func pinchEnded(_ event: PinchEvent, cancelled: Bool) {
        recognizer.pinchEnded(pinchEvent(event), cancelled: cancelled)
        pressing = false
        runtime.requestLayout()
    }

    /// A high-priority gesture takes the press before its subviews' controls; so does a mask
    /// without `.subviews` (the subviews' gestures and controls are not offered the press).
    override package var capturesHitTesting: Bool { modifier.priority == .high || !modifier.mask.contains(.subviews) }

    /// A content shape beneath the gesture decides where it is hit (sw-shape-shortcuts).
    override package func contains(_ point: CGPoint) -> Bool { _contentShapeContains(point) ?? super.contains(point) }
    /// A mask without `.gesture` leaves the presses to the subviews (`.none` takes them and
    /// drops them, as `capturesHitTesting` keeps the subviews from them too).
    package var isInteractive: Bool { takesEvents || !modifier.mask.contains(.subviews) }

    package var semantics: SemanticsNode { SemanticsNode(role: .group, label: "", frame: frameInRoot, identifier: identifier) }
    package var exposesChildren: Bool { true }
}
