// Widgets and Live Activities as an app's widget extension declares them, loaded into the app
// (new-website#643, shared with #638). On iOS the extension is its own target whose `@main`
// `WidgetBundle` the system runs; here its unchanged sources build as a library target of the
// app's browser package, the entry point renamed `swiftui_web_widgets_main` (the build flag
// `-entry-point-function-name`), and the canvas host calls it once at launch. Running it only
// records the bundle (`WidgetBundle.main()`); the first time the phone needs a widget the
// bundle is made and its configurations listed in `_WidgetHost`. A Live Activity's views are
// the app's own: its `ActivityConfiguration` content closure draws the lock screen card, live,
// in the drawn iPhone. The Dynamic Island's presentations are values nothing shows yet. Apple
// declares `Widget` and `WidgetConfiguration` in SwiftUI; an app names them from files that
// import WidgetKit, so they live here, out of every other app's bundle.
import ActivityKit
import SwiftUI

// MARK: - Widgets and bundles

/// The configuration and content of a widget.
@MainActor @preconcurrency
public protocol Widget {
    associatedtype Body: WidgetConfiguration
    init()
    @WidgetConfigurationBuilder var body: Body { get }
}

/// A widget's configuration.
@MainActor @preconcurrency
public protocol WidgetConfiguration {
    /// The configurations it holds, for the host to list (one for a plain configuration).
    var _configurations: [any WidgetConfiguration] { get }
}

extension WidgetConfiguration {
    public var _configurations: [any WidgetConfiguration] { [self] }
}

/// Builds a widget's configuration from the configurations in its body.
@resultBuilder
public enum WidgetConfigurationBuilder {
    public static func buildBlock<C: WidgetConfiguration>(_ content: C) -> C { content }
    public static func buildExpression<C: WidgetConfiguration>(_ expression: C) -> C { expression }
}

/// The widgets an extension offers; its `@main` runs `main()`.
@MainActor @preconcurrency
public protocol WidgetBundle {
    associatedtype Body: Widget
    init()
    @WidgetBundleBuilder var body: Body { get }
}

extension WidgetBundle {
    /// The extension's entry point: records the bundle for the host. Nothing runs yet, so it is
    /// safe however early the host calls it.
    nonisolated public static func main() {
        _WidgetHost.bundle = { Self().body._widgets }
        _WidgetHost.listed = nil
        _WidgetHost.installActivityHost()
        // Its home and lock screen widgets, made when the phone first shows them (#638).
        _DrawnPhoneSystem.widgetSource = { _WidgetHost.phoneWidgets() }
    }
}

/// The widgets a bundle body lists, as one widget.
public struct _WidgetList: Widget {
    public let widgets: [any Widget]
    public init() { widgets = [] }
    init(_ widgets: [any Widget]) { self.widgets = widgets }
    public var body: _NoConfiguration { _NoConfiguration() }
}

/// The empty configuration of a widget list (its widgets carry their own).
public struct _NoConfiguration: WidgetConfiguration {
    public var _configurations: [any WidgetConfiguration] { [] }
}

extension Widget {
    /// The widgets this stands for: itself, or a list's.
    var _widgets: [any Widget] { (self as? _WidgetList)?.widgets ?? [self] }
}

/// Builds a bundle's body from its widgets.
@resultBuilder
public enum WidgetBundleBuilder {
    public static func buildExpression<W: Widget>(_ widget: W) -> _WidgetList { _WidgetList(widget._widgets) }
    public static func buildBlock(_ parts: _WidgetList...) -> _WidgetList { _WidgetList(parts.flatMap { $0.widgets }) }
    public static func buildOptional(_ part: _WidgetList?) -> _WidgetList { part ?? _WidgetList([]) }
    public static func buildEither(first: _WidgetList) -> _WidgetList { first }
    public static func buildEither(second: _WidgetList) -> _WidgetList { second }
    public static func buildLimitedAvailability(_ part: _WidgetList) -> _WidgetList { part }
}

// MARK: - The host

/// The app's widget extension as the drawn iPhone sees it.
@MainActor
public enum _WidgetHost {
    /// Makes the bundle's widgets (set by `WidgetBundle.main()`).
    nonisolated(unsafe) static var bundle: (@MainActor () -> [any Widget])?

    /// One configuration the extension offers.
    public struct Entry {
        /// The widget it came from (`StaticConfiguration(kind:)`'s kind for a home screen widget).
        public let widget: any Widget
        public let configuration: any WidgetConfiguration
    }

    nonisolated(unsafe) static var listed: [Entry]?

    /// Every configuration of the extension's widgets, in the bundle's order (none without an
    /// extension).
    public static var entries: [Entry] {
        if let listed { return listed }
        let widgets = bundle?() ?? []
        let entries = widgets.flatMap { widget in widget.body._configurations.map { Entry(widget: widget, configuration: $0) } }
        listed = entries
        return entries
    }

    /// Whether an extension was loaded.
    nonisolated public static var hasExtension: Bool { bundle != nil }

    /// Live Activities run in the drawn iPhone when the extension declares any.
    nonisolated static func installActivityHost() {
        _ActivityKitHost.enabled = { _DrawnPhoneSystem.isPresent && _WidgetHost.bundle != nil }
        _ActivityKitHost.started = { id, attributes, content in
            guard let view = _WidgetHost.activityView(id: id, attributes: attributes, content: content) else { return }
            _DrawnPhoneSystem.startActivity(id: id, view: view)
        }
        _ActivityKitHost.updated = { id, attributes, content in
            guard let view = _WidgetHost.activityView(id: id, attributes: attributes, content: content) else { return }
            _DrawnPhoneSystem.updateActivity(id: id, view: view)
        }
        _ActivityKitHost.ended = { id, immediately in
            // An activity ended with the default policy stays until dismissed; the phone has no
            // swipe to dismiss one yet, so it goes as soon as the app ends it either way.
            _ = immediately
            _DrawnPhoneSystem.endActivity(id: id)
        }
    }

    /// The lock screen view of the activity, from the configuration for its attributes type.
    static func activityView(id: String, attributes: Any, content: Any) -> AnyView? {
        for entry in entries {
            if let configuration = entry.configuration as? any _ActivityViews,
               let view = configuration._lockScreenView(id: id, attributes: attributes, content: content) {
                return view
            }
        }
        return nil
    }
}

/// A configuration that draws Live Activities.
@MainActor
protocol _ActivityViews {
    func _lockScreenView(id: String, attributes: Any, content: Any) -> AnyView?
}

// MARK: - Live Activities

/// A Live Activity's attributes and state, as its views receive them.
public struct ActivityViewContext<Attributes: ActivityAttributes> {
    public let activityID: String
    public let attributes: Attributes
    public let state: Attributes.ContentState
    public let isStale: Bool
}

/// A Live Activity's views on the Lock Screen and in the Dynamic Island.
@MainActor @preconcurrency
public struct ActivityConfiguration<Attributes: ActivityAttributes>: WidgetConfiguration, _ActivityViews {
    let lockScreen: (ActivityViewContext<Attributes>) -> AnyView
    public private(set) var marginsDisabled = false
    public private(set) var supplementalFamilies: [ActivityFamily] = []

    public init<Content: View>(for attributesType: Attributes.Type, @ViewBuilder content: @escaping (ActivityViewContext<Attributes>) -> Content,
                               dynamicIsland: @escaping (ActivityViewContext<Attributes>) -> DynamicIsland) {
        lockScreen = { AnyView(content($0)) }
    }

    public func supplementalActivityFamilies(_ families: [ActivityFamily]) -> ActivityConfiguration<Attributes> {
        var copy = self
        copy.supplementalFamilies = families
        return copy
    }
    public func contentMarginsDisabled() -> ActivityConfiguration<Attributes> {
        var copy = self
        copy.marginsDisabled = true
        return copy
    }

    func _lockScreenView(id: String, attributes: Any, content: Any) -> AnyView? {
        guard let attributes = attributes as? Attributes, let content = content as? ActivityContent<Attributes.ContentState> else { return nil }
        let stale = content.staleDate.map { $0 <= Date() } ?? false
        return lockScreen(ActivityViewContext(activityID: id, attributes: attributes, state: content.state, isStale: stale))
    }
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
    /// The Live Activity's background on the Lock Screen: the card is filled with it.
    nonisolated public func activityBackgroundTint(_ color: Color?) -> some View { background(color ?? Color.clear) }
    /// The colour of the Live Activity's system action (the lock screen draws none).
    nonisolated public func activitySystemActionForegroundColor(_ color: Color?) -> some View { self }
}
