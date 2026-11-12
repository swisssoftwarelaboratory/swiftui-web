// contentTransition: how a Text whose content changes under an animation moves from the old
// text to the new one. Opacity and interpolate crossfade; numericText also rolls the old
// text out and the new one in vertically (up for a rising value, down when counting down).

/// A transition between the old and new content of a view.
public struct ContentTransition: Hashable, Sendable {
    package enum Kind: Hashable, Sendable {
        case identity, opacity, interpolate, numericText(countsDown: Bool), symbolEffect
        /// `numericText(value:)`: rolls up or down by how `value` changed (`direction(from:)`).
        case numericValue(Double)
    }
    package let kind: Kind

    /// The new content replaces the old one at once.
    public static let identity = ContentTransition(kind: .identity)
    /// The old content fades out as the new one fades in.
    public static let opacity = ContentTransition(kind: .opacity)
    /// Interpolates between the contents (a crossfade here).
    public static let interpolate = ContentTransition(kind: .interpolate)
    /// A crossfade that rolls numbers up (or down) as they change.
    public static func numericText(countsDown: Bool = false) -> ContentTransition {
        ContentTransition(kind: .numericText(countsDown: countsDown))
    }
    /// A numeric roll for a text showing `value`: up when the value grows, down when it shrinks,
    /// as Apple's picks it.
    public static func numericText(value: Double) -> ContentTransition {
        ContentTransition(kind: .numericValue(value))
    }

    /// The transition a text runs when it changes under `self`, the transition it last showed
    /// with being `previous`: a value-driven roll takes its direction from the two values (up
    /// when nothing earlier is known or the value is the same).
    package func resolved(from previous: ContentTransition) -> ContentTransition {
        guard case .numericValue(let value) = kind else { return self }
        if case .numericValue(let old) = previous.kind { return .numericText(countsDown: value < old) }
        return .numericText()
    }
    /// A symbol effect (a crossfade here).
    public static let symbolEffect = ContentTransition(kind: .symbolEffect)

    /// Whether the transition crossfades (everything but identity).
    package var fades: Bool { kind != .identity }
    /// The vertical roll, as a fraction of the text's height: outgoing text moves by `-roll`,
    /// incoming starts at `+roll`.
    package var roll: CGFloat {
        if case .numericText(let countsDown) = kind { return countsDown ? -0.5 : 0.5 }
        if case .numericValue = kind { return 0.5 }
        return 0
    }
}

package struct ContentTransitionKey: EnvironmentKey {
    package static let defaultValue = ContentTransition.identity
}

extension EnvironmentValues {
    /// The transition text in this environment uses when its content changes (`View.contentTransition`).
    public var contentTransition: ContentTransition {
        get { self[ContentTransitionKey.self] }
        set { self[ContentTransitionKey.self] = newValue }
    }
}

extension View {
    /// Sets how text in this view moves from its old content to new content when the change is animated.
    nonisolated public func contentTransition(_ transition: ContentTransition) -> some View {
        environment(\.contentTransition, transition)
    }
}
