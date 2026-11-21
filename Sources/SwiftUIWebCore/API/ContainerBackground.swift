// `containerBackground(_:for:)` (sw-modifiers): the background a container shows behind its
// content (a navigation stack, a tab view, a widget, a subscription store). Here the background
// is painted behind the view the modifier is on, which is the container's content area.

/// The kind of container a `containerBackground` modifier is for.
public struct ContainerBackgroundPlacement: Sendable {
    package let name: String
    package init(_ name: String) { self.name = name }

    /// The background of a navigation stack or split view's columns.
    public static let navigation = ContainerBackgroundPlacement("navigation")
    /// The background of a navigation split view.
    public static let navigationSplitView = ContainerBackgroundPlacement("navigationSplitView")
    /// The background of a tab view's pages.
    public static let tabView = ContainerBackgroundPlacement("tabView")
}

/// A widget's container background, as its view sets it (`containerBackground(for: .widget)`):
/// the widget's host draws it behind the whole widget, under the content margins
/// (new-website#638).
public struct _WidgetContainerBackgroundKey: PreferenceKey {
    public static var defaultValue: AnyView? { nil }
    public static func reduce(value: inout AnyView?, nextValue: () -> AnyView?) {
        if let next = nextValue() { value = next }
    }
}

extension View {
    /// Sets the container background of the enclosing container using a view.
    @ViewBuilder
    nonisolated public func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center,
                                                         @ViewBuilder content: () -> V) -> some View {
        if container.name == "widget" {
            preference(key: _WidgetContainerBackgroundKey.self, value: AnyView(ZStack(alignment: alignment) { content() }))
        } else {
            background(alignment: alignment, content: content)
        }
    }

    /// Sets the container background of the enclosing container using a style.
    @ViewBuilder
    nonisolated public func containerBackground<S: ShapeStyle>(_ style: S, for container: ContainerBackgroundPlacement) -> some View {
        if container.name == "widget" {
            preference(key: _WidgetContainerBackgroundKey.self, value: AnyView(Rectangle().fill(style)))
        } else {
            background(style)
        }
    }
}
