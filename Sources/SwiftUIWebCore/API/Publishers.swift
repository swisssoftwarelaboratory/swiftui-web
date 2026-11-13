// `onReceive` over WebCombine's publishers (decision 0021): the Combine-free `Publisher`,
// `Just`, the subjects, `Timer.publish`, `NotificationCenter.publisher`, `objectWillChange`
// and `$published` live in Packages/WebGraphics' WebCombine, which SwiftUI re-exports (and
// `import Combine` names on wasm).
import WebCombine

// MARK: - onReceive

/// `onReceive`: the action runs with every value the publisher delivers while the view is mounted.
public struct _OnReceiveModifier {
    /// Subscribes the action (called on the main actor, where the node mounts).
    package let subscribe: () -> AnyCancellable
    package init(subscribe: @escaping () -> AnyCancellable) { self.subscribe = subscribe }
}

extension _OnReceiveModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        OnReceiveNode(context)
    }
}

extension View {
    /// Adds an action to perform when this view detects data emitted by the given publisher.
    /// The subscription is made when the view appears and ends when it disappears.
    nonisolated public func onReceive<P: Publisher>(_ publisher: P, perform action: @escaping @MainActor (P.Output) -> Void) -> some View where P.Failure == Never {
        // The publisher is used on the main actor only (the node subscribes when it mounts).
        nonisolated(unsafe) let held = publisher
        nonisolated(unsafe) let action = action   // WebCombine takes a `Sendable` one; Swift 5 mode (decision 0027)
        return modifier(_OnReceiveModifier(subscribe: { MainActor.assumeIsolated { held._subscribe({ action($0) }) } }))
    }
}
