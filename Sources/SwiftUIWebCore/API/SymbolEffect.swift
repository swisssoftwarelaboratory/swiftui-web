// symbolEffect: animated effects on system symbols. Indefinite effects run while active
// (pulse, scale, variableColor, breathe, rotate, wiggle, bounce), discrete ones play when a
// value changes (bounce, pulse, variableColor, wiggle, rotate, breathe). The stand-in glyphs
// are drawn as one layer, so by-layer variants behave like whole-symbol ones.

/// An effect that can be applied to a symbol image.
public protocol SymbolEffect {
    var _kind: _SymbolEffectKind { get }
}

/// An effect that runs while it is active.
public protocol IndefiniteSymbolEffect: SymbolEffect {}
/// An effect that plays once when a value changes.
public protocol DiscreteSymbolEffect: SymbolEffect {}
/// An effect for symbols appearing or disappearing.
public protocol TransitionSymbolEffect: SymbolEffect {}
/// An effect for a symbol replacing another.
public protocol ContentTransitionSymbolEffect: SymbolEffect {}

public enum _SymbolEffectKind: Hashable, Sendable {
    case bounce(up: Bool)
    case pulse
    case variableColor(reversing: Bool)
    case scale(up: Bool)
    case wiggle(clockwise: Bool?, horizontal: Bool)
    case rotate(clockwise: Bool)
    case breathe
    case appear, disappear, replace
}

public struct BounceSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    package var isUp = true
    public var _kind: _SymbolEffectKind { .bounce(up: isUp) }
    public var up: BounceSymbolEffect { var e = self; e.isUp = true; return e }
    public var down: BounceSymbolEffect { var e = self; e.isUp = false; return e }
    public var byLayer: BounceSymbolEffect { self }
    public var wholeSymbol: BounceSymbolEffect { self }
}

public struct PulseSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    public var _kind: _SymbolEffectKind { .pulse }
    public var byLayer: PulseSymbolEffect { self }
    public var wholeSymbol: PulseSymbolEffect { self }
}

public struct VariableColorSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    package var isReversing = false
    public var _kind: _SymbolEffectKind { .variableColor(reversing: isReversing) }
    public var iterative: VariableColorSymbolEffect { self }
    public var cumulative: VariableColorSymbolEffect { self }
    public var reversing: VariableColorSymbolEffect { var e = self; e.isReversing = true; return e }
    public var nonReversing: VariableColorSymbolEffect { var e = self; e.isReversing = false; return e }
    public var hideInactiveLayers: VariableColorSymbolEffect { self }
    public var dimInactiveLayers: VariableColorSymbolEffect { self }
}

public struct ScaleSymbolEffect: IndefiniteSymbolEffect {
    package var isUp = true
    public var _kind: _SymbolEffectKind { .scale(up: isUp) }
    public var up: ScaleSymbolEffect { var e = self; e.isUp = true; return e }
    public var down: ScaleSymbolEffect { var e = self; e.isUp = false; return e }
    public var byLayer: ScaleSymbolEffect { self }
    public var wholeSymbol: ScaleSymbolEffect { self }
}

public struct WiggleSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    package var turn: Bool? = nil
    package var horizontal = true
    public var _kind: _SymbolEffectKind { .wiggle(clockwise: turn, horizontal: horizontal) }
    public var clockwise: WiggleSymbolEffect { var e = self; e.turn = true; return e }
    public var counterClockwise: WiggleSymbolEffect { var e = self; e.turn = false; return e }
    public var left: WiggleSymbolEffect { var e = self; e.turn = nil; e.horizontal = true; return e }
    public var right: WiggleSymbolEffect { left }
    public var up: WiggleSymbolEffect { var e = self; e.turn = nil; e.horizontal = false; return e }
    public var down: WiggleSymbolEffect { up }
    public var byLayer: WiggleSymbolEffect { self }
    public var wholeSymbol: WiggleSymbolEffect { self }
}

public struct RotateSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    package var isClockwise = true
    public var _kind: _SymbolEffectKind { .rotate(clockwise: isClockwise) }
    public var clockwise: RotateSymbolEffect { var e = self; e.isClockwise = true; return e }
    public var counterClockwise: RotateSymbolEffect { var e = self; e.isClockwise = false; return e }
    public var byLayer: RotateSymbolEffect { self }
    public var wholeSymbol: RotateSymbolEffect { self }
}

public struct BreatheSymbolEffect: IndefiniteSymbolEffect, DiscreteSymbolEffect {
    public var _kind: _SymbolEffectKind { .breathe }
    public var plain: BreatheSymbolEffect { self }
    public var pulse: BreatheSymbolEffect { self }
    public var byLayer: BreatheSymbolEffect { self }
    public var wholeSymbol: BreatheSymbolEffect { self }
}

public struct AppearSymbolEffect: TransitionSymbolEffect {
    public var _kind: _SymbolEffectKind { .appear }
    public var up: AppearSymbolEffect { self }
    public var down: AppearSymbolEffect { self }
    public var byLayer: AppearSymbolEffect { self }
    public var wholeSymbol: AppearSymbolEffect { self }
}

public struct DisappearSymbolEffect: TransitionSymbolEffect {
    public var _kind: _SymbolEffectKind { .disappear }
    public var up: DisappearSymbolEffect { self }
    public var down: DisappearSymbolEffect { self }
    public var byLayer: DisappearSymbolEffect { self }
    public var wholeSymbol: DisappearSymbolEffect { self }
}

public struct ReplaceSymbolEffect: ContentTransitionSymbolEffect {
    public var _kind: _SymbolEffectKind { .replace }
    public var downUp: ReplaceSymbolEffect { self }
    public var upUp: ReplaceSymbolEffect { self }
    public var offUp: ReplaceSymbolEffect { self }
    public var magic: ReplaceSymbolEffect { self }
    public var byLayer: ReplaceSymbolEffect { self }
    public var wholeSymbol: ReplaceSymbolEffect { self }
}

extension SymbolEffect where Self == BounceSymbolEffect { public static var bounce: BounceSymbolEffect { BounceSymbolEffect() } }
extension SymbolEffect where Self == PulseSymbolEffect { public static var pulse: PulseSymbolEffect { PulseSymbolEffect() } }
extension SymbolEffect where Self == VariableColorSymbolEffect { public static var variableColor: VariableColorSymbolEffect { VariableColorSymbolEffect() } }
extension SymbolEffect where Self == ScaleSymbolEffect { public static var scale: ScaleSymbolEffect { ScaleSymbolEffect() } }
extension SymbolEffect where Self == WiggleSymbolEffect { public static var wiggle: WiggleSymbolEffect { WiggleSymbolEffect() } }
extension SymbolEffect where Self == RotateSymbolEffect { public static var rotate: RotateSymbolEffect { RotateSymbolEffect() } }
extension SymbolEffect where Self == BreatheSymbolEffect { public static var breathe: BreatheSymbolEffect { BreatheSymbolEffect() } }
extension SymbolEffect where Self == AppearSymbolEffect { public static var appear: AppearSymbolEffect { AppearSymbolEffect() } }
extension SymbolEffect where Self == DisappearSymbolEffect { public static var disappear: DisappearSymbolEffect { DisappearSymbolEffect() } }
extension SymbolEffect where Self == ReplaceSymbolEffect { public static var replace: ReplaceSymbolEffect { ReplaceSymbolEffect() } }

/// Options for a symbol effect: how often and how fast it plays.
public struct SymbolEffectOptions: Hashable, Sendable {
    /// Repetitions of a discrete effect (nil repeats forever).
    package var repeatCount: Int? = 1
    package var speed: Double = 1

    public static var `default`: SymbolEffectOptions { SymbolEffectOptions() }
    public static var repeating: SymbolEffectOptions { SymbolEffectOptions(repeatCount: nil) }
    public static var nonRepeating: SymbolEffectOptions { SymbolEffectOptions(repeatCount: 1) }
    public static func `repeat`(_ count: Int?) -> SymbolEffectOptions { SymbolEffectOptions(repeatCount: count) }
    public static func speed(_ speed: Double) -> SymbolEffectOptions { SymbolEffectOptions(speed: max(speed, 0.0001)) }

    public var repeating: SymbolEffectOptions { var o = self; o.repeatCount = nil; return o }
    public var nonRepeating: SymbolEffectOptions { var o = self; o.repeatCount = 1; return o }
    public func `repeat`(_ count: Int?) -> SymbolEffectOptions { var o = self; o.repeatCount = count; return o }
    public func speed(_ speed: Double) -> SymbolEffectOptions { var o = self; o.speed = max(speed, 0.0001); return o }
}

/// An effect asked of the symbols in an environment.
public struct _SymbolEffectRequest: Hashable, Sendable {
    package let kind: _SymbolEffectKind
    package let options: SymbolEffectOptions
    /// Indefinite effects: whether they run. Discrete effects: nil.
    package let isActive: Bool?
    /// Discrete effects: bumped on every change of the trigger value.
    package let generation: Int
}

package struct SymbolEffectsKey: EnvironmentKey {
    package static let defaultValue: [_SymbolEffectRequest] = []
}

extension EnvironmentValues {
    package var _symbolEffects: [_SymbolEffectRequest] {
        get { self[SymbolEffectsKey.self] }
        set { self[SymbolEffectsKey.self] = newValue }
    }
}

/// Counts the changes of a value and passes a discrete effect down with the count.
struct _SymbolEffectTrigger<Content: View, V: Equatable>: View {
    let content: Content
    let kind: _SymbolEffectKind
    let options: SymbolEffectOptions
    let value: V
    @State private var generation = 0
    @Environment(\._symbolEffects) private var inherited

    var body: some View {
        content
            .environment(\._symbolEffects, inherited + [_SymbolEffectRequest(kind: kind, options: options, isActive: nil, generation: generation)])
            .onChange(of: value) { generation += 1 }
    }
}

struct _SymbolEffectScope<Content: View>: View {
    let content: Content
    let request: _SymbolEffectRequest
    @Environment(\._symbolEffects) private var inherited

    var body: some View {
        content.environment(\._symbolEffects, inherited + [request])
    }
}

extension View {
    /// Runs `effect` on the symbols in this view while `isActive`.
    public func symbolEffect<T: IndefiniteSymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default, isActive: Bool = true) -> some View {
        _SymbolEffectScope(content: self, request: _SymbolEffectRequest(kind: effect._kind, options: options, isActive: isActive, generation: 0))
    }

    /// Plays `effect` on the symbols in this view whenever `value` changes.
    public func symbolEffect<T: DiscreteSymbolEffect, U: Equatable>(_ effect: T, options: SymbolEffectOptions = .default, value: U) -> some View {
        _SymbolEffectTrigger(content: self, kind: effect._kind, options: options, value: value)
    }

    /// Removes the symbol effects inherited by this view.
    nonisolated public func symbolEffectsRemoved(_ isEnabled: Bool = true) -> some View {
        _transformEnvironment("symbolEffectsRemoved", key: isEnabled) { if isEnabled { $0._symbolEffects = [] } }
    }
}

extension ContentTransition {
    /// A symbol replace effect (a crossfade here).
    public static func symbolEffect<T: ContentTransitionSymbolEffect>(_ effect: T, options: SymbolEffectOptions = .default) -> ContentTransition {
        .symbolEffect
    }
}
