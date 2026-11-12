// The phone's own chrome around an app: a page draws no status bar, and scroll edges carry no
// iOS 26 edge effect, so these settings have nothing to change (accepted, as on a device
// without them).

/// The style of the effect at a scroll view's edges (iOS 26).
public struct ScrollEdgeEffectStyle: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case automatic, hard, soft }
    package let role: Role

    public static let automatic = ScrollEdgeEffectStyle(role: .automatic)
    public static let hard = ScrollEdgeEffectStyle(role: .hard)
    public static let soft = ScrollEdgeEffectStyle(role: .soft)
}

extension View {
    /// Hides or shows the status bar: the page has none to hide.
    nonisolated public func statusBarHidden(_ hidden: Bool = true) -> some View { self }

    /// Sets the scroll edge effect at the edges: none is drawn here.
    nonisolated public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> some View { self }

    /// Hides the scroll edge effect at the edges: none is drawn here.
    nonisolated public func scrollEdgeEffectHidden(_ hidden: Bool = true, for edges: Edge.Set = .all) -> some View { self }
}
