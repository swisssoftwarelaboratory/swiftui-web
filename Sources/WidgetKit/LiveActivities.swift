// Widgets and Live Activities as an app target declares them (a widget extension's code is
// often shared with the app). A page has no home screen, Lock Screen or Dynamic Island, so a
// configuration is a value nothing shows: the views it would build are not made. Apple declares
// `Widget` and `WidgetConfiguration` in SwiftUI; an app names them from files that import
// WidgetKit, so they live here, out of every other app's bundle. Accepted for source
// compatibility.
import ActivityKit
import SwiftUI

/// The configuration and content of a widget.
@MainActor @preconcurrency
public protocol Widget {
    associatedtype Body: WidgetConfiguration
    init()
    @WidgetConfigurationBuilder var body: Body { get }
}

/// A widget's configuration.
@MainActor @preconcurrency
public protocol WidgetConfiguration {}

/// Builds a widget's configuration from the configurations in its body.
@resultBuilder
public enum WidgetConfigurationBuilder {
    public static func buildBlock<C: WidgetConfiguration>(_ content: C) -> C { content }
    public static func buildExpression<C: WidgetConfiguration>(_ expression: C) -> C { expression }
}

/// The widgets an extension offers.
@MainActor @preconcurrency
public protocol WidgetBundle {
    init()
}

/// A Live Activity's attributes and state, as its views receive them.
public struct ActivityViewContext<Attributes: ActivityAttributes> {
    public let activityID: String
    public let attributes: Attributes
    public let state: Attributes.ContentState
    public let isStale: Bool
}

/// A Live Activity's views on the Lock Screen and in the Dynamic Island (shown nowhere here).
@MainActor @preconcurrency
public struct ActivityConfiguration<Attributes: ActivityAttributes>: WidgetConfiguration {
    public init<Content: View>(for attributesType: Attributes.Type, @ViewBuilder content: @escaping (ActivityViewContext<Attributes>) -> Content,
                               dynamicIsland: @escaping (ActivityViewContext<Attributes>) -> DynamicIsland) {}

    public func supplementalActivityFamilies(_ families: [ActivityFamily]) -> ActivityConfiguration<Attributes> { self }
    public func contentMarginsDisabled() -> ActivityConfiguration<Attributes> { self }
}

/// The sizes a Live Activity takes.
public enum ActivityFamily: Hashable, Sendable { case small, medium }

/// A Live Activity's Dynamic Island presentations.
public struct DynamicIsland {
    public init<Expanded: View, CompactLeading: View, CompactTrailing: View, Minimal: View>(
        @DynamicIslandExpandedContentBuilder expanded: @escaping () -> DynamicIslandExpandedContent<Expanded>,
        @ViewBuilder compactLeading: @escaping () -> CompactLeading,
        @ViewBuilder compactTrailing: @escaping () -> CompactTrailing,
        @ViewBuilder minimal: @escaping () -> Minimal) {}

    public func keylineTint(_ color: Color?) -> DynamicIsland { self }
    public func contentMargins(_ edges: Edge.Set = .all, _ length: CGFloat, for mode: DynamicIslandMode) -> DynamicIsland { self }
    public func widgetURL(_ url: URL?) -> DynamicIsland { self }
}

/// The Dynamic Island's presentations.
public enum DynamicIslandMode: Hashable, Sendable { case compact, minimal, expanded }

/// Where an expanded region sits in the Dynamic Island.
public struct DynamicIslandExpandedRegionPosition: Hashable, Sendable {
    package let name: String
    public static let leading = DynamicIslandExpandedRegionPosition(name: "leading")
    public static let trailing = DynamicIslandExpandedRegionPosition(name: "trailing")
    public static let center = DynamicIslandExpandedRegionPosition(name: "center")
    public static let bottom = DynamicIslandExpandedRegionPosition(name: "bottom")
}

/// One region of the expanded Dynamic Island.
public struct DynamicIslandExpandedRegion<Content: View> {
    public let position: DynamicIslandExpandedRegionPosition
    public init(_ position: DynamicIslandExpandedRegionPosition, priority: Double = 0, @ViewBuilder content: () -> Content) {
        self.position = position
    }
    public func contentMargins(_ edges: Edge.Set = .all, _ length: Double) -> DynamicIslandExpandedRegion<Content> { self }
}

/// The regions of the expanded Dynamic Island.
public struct DynamicIslandExpandedContent<Content: View> {
    package init() {}
}

/// Builds the expanded Dynamic Island from its regions.
@resultBuilder
public enum DynamicIslandExpandedContentBuilder {
    public static func buildPartialBlock<C: View>(first: DynamicIslandExpandedRegion<C>) -> DynamicIslandExpandedContent<EmptyView> { DynamicIslandExpandedContent() }
    public static func buildPartialBlock<C: View>(first: DynamicIslandExpandedContent<C>) -> DynamicIslandExpandedContent<EmptyView> { DynamicIslandExpandedContent() }
    public static func buildPartialBlock<C0: View, C1: View>(accumulated: DynamicIslandExpandedContent<C0>, next: DynamicIslandExpandedRegion<C1>) -> DynamicIslandExpandedContent<EmptyView> { DynamicIslandExpandedContent() }
    public static func buildPartialBlock<C0: View, C1: View>(accumulated: DynamicIslandExpandedContent<C0>, next: DynamicIslandExpandedContent<C1>) -> DynamicIslandExpandedContent<EmptyView> { DynamicIslandExpandedContent() }
}

extension View {
    /// The Live Activity's background tint on the Lock Screen (no Lock Screen here).
    nonisolated public func activityBackgroundTint(_ color: Color?) -> some View { self }
    /// The colour of the Live Activity's system action (no Lock Screen here).
    nonisolated public func activitySystemActionForegroundColor(_ color: Color?) -> some View { self }
}
