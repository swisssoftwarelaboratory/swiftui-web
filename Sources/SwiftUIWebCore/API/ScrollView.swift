// ScrollView, ScrollViewReader and the scroll-related modifiers. Layout, clipping, offsets and
// input live in Runtime/ScrollNodes.swift; measured behaviours in Docs/elements/ScrollView.md.

/// A scrollable view.
public struct ScrollView<Content: View> {
    /// The scroll view's content.
    public var content: Content

    /// The scrollable axes of the scroll view.
    public var axes: Axis.Set

    /// A value that indicates whether the scroll view displays the scrollable component of the
    /// content offset, in a way that's suitable for the platform.
    public var showsIndicators: Bool

    /// Creates a new instance that's scrollable in the direction of the given axis and can show
    /// indicators while scrolling.
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content()
    }
}

extension ScrollView: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<ScrollView<Content>>) -> TypedNode<ScrollView<Content>> {
        ScrollNode(context)
    }
}

// MARK: - ScrollViewReader

/// A view that provides programmatic scrolling, by working with a proxy to scroll to known child
/// views.
@frozen
public struct ScrollViewReader<Content: View> {
    /// The reader's content, given a proxy.
    public var content: (ScrollViewProxy) -> Content

    /// Creates an instance that can perform programmatic scrolling of its child scroll views.
    @inlinable
    public init(@ViewBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }
}

extension ScrollViewReader: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<ScrollViewReader<Content>>) -> TypedNode<ScrollViewReader<Content>> {
        ScrollViewReaderNode(context)
    }
}

/// A proxy value that supports programmatic scrolling of the scrollable views within a view
/// hierarchy.
public struct ScrollViewProxy: Sendable {
    /// The reader node; the proxy outlives the reader in escaped closures, hence weak.
    nonisolated(unsafe) package weak var reader: ViewNode?

    package init(reader: ViewNode) {
        self.reader = reader
    }

    /// Scans all scroll views contained by the proxy, then those containing it, for the first
    /// with a child view with identifier `id`, and then scrolls to that view. Without an anchor the view is scrolled
    /// into view with the smallest possible offset change; with one, the anchor of the view is
    /// aligned with the same anchor of the scroll view's visible area.
    @MainActor
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        guard let reader else { return }
        let key = AnyHashable(id)
        for target in reader.descendants(where: { $0 is _ScrollTarget }) {
            if (target as! _ScrollTarget).scrollTo(id: key, anchor: anchor) { return }
        }
        // A reader placed inside its scroll view (`ScrollView { ScrollViewReader { ... } }`)
        // scrolls the scroll views around it, nearest first.
        var node = reader.parent
        while let current = node {
            if let target = current as? _ScrollTarget, target.scrollTo(id: key, anchor: anchor) { return }
            node = current.parent
        }
    }
}

// MARK: - Modifier value types

/// The visibility of scroll indicators of a UI element.
public struct ScrollIndicatorVisibility: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case automatic, visible, hidden, never }
    package let role: Role

    /// Scroll indicator visibility depends on the policies of the component accepting the
    /// visibility configuration.
    public static let automatic = ScrollIndicatorVisibility(role: .automatic)
    /// Show the scroll indicators.
    public static let visible = ScrollIndicatorVisibility(role: .visible)
    /// Hide the scroll indicators.
    public static let hidden = ScrollIndicatorVisibility(role: .hidden)
    /// Scroll indicators should never be visible.
    public static let never = ScrollIndicatorVisibility(role: .never)

    /// Whether indicators may appear at all.
    package var showsIndicators: Bool { role == .automatic || role == .visible }
}

/// The ways that a scrollable view can bounce when it reaches the end of its content.
public struct ScrollBounceBehavior: Hashable, Sendable {
    package enum Role: Hashable, Sendable { case automatic, always, basedOnSize }
    package let role: Role

    /// The automatic behavior.
    public static let automatic = ScrollBounceBehavior(role: .automatic)
    /// The scrollable view always bounces along the specified axis, regardless of content size.
    public static let always = ScrollBounceBehavior(role: .always)
    /// The scrollable view bounces along the specified axis only when the content is larger than
    /// the view.
    public static let basedOnSize = ScrollBounceBehavior(role: .basedOnSize)
}

// MARK: - Environment

package struct IsScrollEnabledKey: EnvironmentKey { package static let defaultValue = true }
package struct HorizontalScrollIndicatorVisibilityKey: EnvironmentKey { package static let defaultValue = ScrollIndicatorVisibility.automatic }
package struct VerticalScrollIndicatorVisibilityKey: EnvironmentKey { package static let defaultValue = ScrollIndicatorVisibility.automatic }
package struct HorizontalScrollBounceBehaviorKey: EnvironmentKey { package static let defaultValue = ScrollBounceBehavior.automatic }
package struct VerticalScrollBounceBehaviorKey: EnvironmentKey { package static let defaultValue = ScrollBounceBehavior.automatic }
package struct DefaultScrollAnchorKey: EnvironmentKey { package static let defaultValue: UnitPoint? = nil }
package struct ScrollClipDisabledKey: EnvironmentKey { package static let defaultValue = false }

extension EnvironmentValues {
    /// A Boolean value that indicates whether any scroll views associated with this environment
    /// allow scrolling to occur.
    public var isScrollEnabled: Bool {
        get { self[IsScrollEnabledKey.self] }
        set { self[IsScrollEnabledKey.self] = newValue }
    }

    /// The visibility to apply to scroll indicators of any horizontally scrollable content.
    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[HorizontalScrollIndicatorVisibilityKey.self] }
        set { self[HorizontalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// The visibility to apply to scroll indicators of any vertically scrollable content.
    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { self[VerticalScrollIndicatorVisibilityKey.self] }
        set { self[VerticalScrollIndicatorVisibilityKey.self] = newValue }
    }

    /// The scroll bounce mode for the horizontal axis of scrollable views.
    public var horizontalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[HorizontalScrollBounceBehaviorKey.self] }
        set { self[HorizontalScrollBounceBehaviorKey.self] = newValue }
    }

    /// The scroll bounce mode for the vertical axis of scrollable views.
    public var verticalScrollBounceBehavior: ScrollBounceBehavior {
        get { self[VerticalScrollBounceBehaviorKey.self] }
        set { self[VerticalScrollBounceBehaviorKey.self] = newValue }
    }

    /// The anchor a scroll view starts at (`defaultScrollAnchor`).
    package var defaultScrollAnchor: UnitPoint? {
        get { self[DefaultScrollAnchorKey.self] }
        set { self[DefaultScrollAnchorKey.self] = newValue }
    }

    /// Whether scroll views paint content outside their bounds (`scrollClipDisabled`).
    package var isScrollClipDisabled: Bool {
        get { self[ScrollClipDisabledKey.self] }
        set { self[ScrollClipDisabledKey.self] = newValue }
    }
}

extension View {
    /// Sets the visibility of scroll indicators within this view.
    nonisolated public func scrollIndicators(_ visibility: ScrollIndicatorVisibility, axes: Axis.Set = [.vertical, .horizontal]) -> some View {
        _transformEnvironment("scrollIndicators", key: [AnyHashable(visibility), AnyHashable(axes.rawValue)]) { environment in
            if axes.contains(.horizontal) { environment.horizontalScrollIndicatorVisibility = visibility }
            if axes.contains(.vertical) { environment.verticalScrollIndicatorVisibility = visibility }
        }
    }

    /// Disables or enables scrolling in scrollable views.
    nonisolated public func scrollDisabled(_ disabled: Bool) -> some View {
        environment(\.isScrollEnabled, !disabled)
    }

    /// Configures the bounce behavior of scrollable views along the specified axis.
    nonisolated public func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View {
        _transformEnvironment("scrollBounceBehavior", key: [AnyHashable(behavior), AnyHashable(axes.rawValue)]) { environment in
            if axes.contains(.horizontal) { environment.horizontalScrollBounceBehavior = behavior }
            if axes.contains(.vertical) { environment.verticalScrollBounceBehavior = behavior }
        }
    }

    /// Sets whether a scroll view clips its content to its bounds.
    nonisolated public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        environment(\.isScrollClipDisabled, disabled)
    }

    /// Associates an anchor to control which part of the scroll view's content should be
    /// rendered by default.
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        environment(\.defaultScrollAnchor, anchor)
    }
}
