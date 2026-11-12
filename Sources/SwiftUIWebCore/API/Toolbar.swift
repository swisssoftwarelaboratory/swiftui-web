// Toolbars: `toolbar { ToolbarItem { … } }` collects items that hosts painting window chrome show
// in a bar across the top of the window (macOS puts them in the window's unified toolbar, which
// a browser page has to draw itself). Docs/elements/Toolbar.md.

/// Where a toolbar item goes. On macOS every placement but `navigation` and `principal` lands
/// in the trailing group.
public struct ToolbarItemPlacement: Hashable, Sendable {
    package enum Group: Hashable, Sendable { case leading, principal, trailing, hidden, bottom }
    package let group: Group
    package let name: String
    /// iOS puts a cancellation action at the bar's leading end (ios/sheet/nav: Dismiss leads, Add
    /// trails), and a bottom bar item in the navigation stack's bottom toolbar.
    package var iOSGroup: Group {
        switch name {
        case "cancellationAction": .leading
        case "bottomBar": .bottom
        default: group
        }
    }
    /// Whether the item sits in the navigation bar at the top of an iOS screen.
    package var isInIOSNavigationBar: Bool {
        switch iOSGroup {
        case .leading, .principal, .trailing: true
        case .hidden, .bottom: false
        }
    }
    /// iOS bolds the confirmation action's label (ios/sheet/nav: Add, Show sheet).
    package var isProminentOnIOS: Bool { name == "confirmationAction" }

    public static let automatic = ToolbarItemPlacement(group: .trailing, name: "automatic")
    public static let principal = ToolbarItemPlacement(group: .principal, name: "principal")
    public static let navigation = ToolbarItemPlacement(group: .leading, name: "navigation")
    public static let primaryAction = ToolbarItemPlacement(group: .trailing, name: "primaryAction")
    public static let secondaryAction = ToolbarItemPlacement(group: .trailing, name: "secondaryAction")
    public static let status = ToolbarItemPlacement(group: .principal, name: "status")
    public static let confirmationAction = ToolbarItemPlacement(group: .trailing, name: "confirmationAction")
    public static let cancellationAction = ToolbarItemPlacement(group: .trailing, name: "cancellationAction")
    public static let destructiveAction = ToolbarItemPlacement(group: .trailing, name: "destructiveAction")
    public static let keyboard = ToolbarItemPlacement(group: .hidden, name: "keyboard")
    public static let bottomBar = ToolbarItemPlacement(group: .hidden, name: "bottomBar")
    public static let topBarLeading = ToolbarItemPlacement(group: .leading, name: "topBarLeading")
    public static let topBarTrailing = ToolbarItemPlacement(group: .trailing, name: "topBarTrailing")
    public static let navigationBarLeading = ToolbarItemPlacement(group: .leading, name: "navigationBarLeading")
    public static let navigationBarTrailing = ToolbarItemPlacement(group: .trailing, name: "navigationBarTrailing")
}

/// Which bar a toolbar modifier addresses (`toolbar(_:for:)`, `toolbarBackground`).
public struct ToolbarPlacement: Hashable, Sendable {
    package let name: String
    public static let automatic = ToolbarPlacement(name: "automatic")
    public static let windowToolbar = ToolbarPlacement(name: "windowToolbar")
    public static let navigationBar = ToolbarPlacement(name: "navigationBar")
    public static let tabBar = ToolbarPlacement(name: "tabBar")
    public static let bottomBar = ToolbarPlacement(name: "bottomBar")
}

/// One resolved toolbar item.
public struct _ToolbarItemData: @unchecked Sendable {
    public var id: AnyHashable?
    public var placement: ToolbarItemPlacement
    public var view: AnyView
    /// Group contents: each element of the view list gets its own platter.
    public var isGroup: Bool
    /// Whether a customisable toolbar shows the item until the user says otherwise
    /// (`ToolbarItem(id:placement:showsByDefault:)`).
    public var showsByDefault = true
    /// The customisable toolbar the item belongs to (`toolbar(id:)`), if any.
    public var customizationID: String?
    /// The environment where the `toolbar` modifier sits: an item's content reads it wherever
    /// the bar mounts the item (an `environment(\.editMode, …)` outside `toolbar` reaches its
    /// `EditButton`, as in SwiftUI).
    package var environment: EnvironmentValues?
}

/// Gives a toolbar item the environment captured where its `toolbar` modifier sits, keeping
/// the bar's label context (a `Label` in a bar shows its icon alone).
struct _ToolbarItemEnvironment: ViewModifier, _EnvironmentModifier {
    typealias Body = Never
    let captured: EnvironmentValues?

    @MainActor static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }

    func modifyEnvironment(_ values: inout EnvironmentValues) {
        guard let captured else { return }
        let context = values._automaticLabelContext
        values = captured
        values._automaticLabelContext = context
    }
}

/// Content of a toolbar: items and groups, or a custom type whose `body` is.
@MainActor @preconcurrency
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent
    var body: Body { get }
    /// The resolved items (primitive content overrides this).
    /// Nonisolated as the result builders resolve it eagerly (the conformer's `body` is main-actor
    /// isolated, like Apple's; a toolbar is built from a view body).
    nonisolated var _toolbarItems: [_ToolbarItemData] { get }
}

extension ToolbarContent {
    nonisolated public var _toolbarItems: [_ToolbarItemData] {
        nonisolated(unsafe) let content = self
        return MainActor.assumeIsolated { content.body._toolbarItems }
    }
}

/// Customisable toolbar content (`toolbar(id:content:)`); customisation is not supported.
@MainActor @preconcurrency
public protocol CustomizableToolbarContent: ToolbarContent {}

extension Never: ToolbarContent {
    public var body: Never { fatalError("Never has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { [] }
}

/// A single item.
public struct ToolbarItem<ID: Hashable, Content: View>: ToolbarContent, CustomizableToolbarContent {
    public typealias Body = Never
    public let id: ID?
    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) where ID == Never {
        id = nil
        self.placement = placement
        self.content = content()
    }

    public init(id: ID, placement: ToolbarItemPlacement = .automatic, showsByDefault: Bool = true, @ViewBuilder content: () -> Content) {
        self.id = id
        self.placement = placement
        self.showsByDefault = showsByDefault
        self.content = content()
    }

    package var showsByDefault = true

    public var body: Never { fatalError("ToolbarItem has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { MainActor.assumeIsolated { [_ToolbarItemData(id: id.map { AnyHashable($0) }, placement: placement, view: AnyView(content), isGroup: false, showsByDefault: showsByDefault)] } }
}

/// A group of items sharing a placement: every view in the group is its own item.
public struct ToolbarItemGroup<Content: View>: ToolbarContent, CustomizableToolbarContent {
    public typealias Body = Never
    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never { fatalError("ToolbarItemGroup has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { MainActor.assumeIsolated { [_ToolbarItemData(id: nil, placement: placement, view: AnyView(content), isGroup: true)] } }
}

/// The builder's list of contents.
public struct _ToolbarContentList: ToolbarContent, CustomizableToolbarContent {
    public typealias Body = Never
    nonisolated public let items: [_ToolbarItemData]
    nonisolated public init(items: [_ToolbarItemData]) { self.items = items }
    public var body: Never { fatalError("_ToolbarContentList has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { items }
}

@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildExpression<C: ToolbarContent>(_ content: C) -> _ToolbarContentList { _ToolbarContentList(items: content._toolbarItems) }
    public static func buildBlock(_ parts: _ToolbarContentList...) -> _ToolbarContentList { _ToolbarContentList(items: parts.flatMap(\.items)) }
    public static func buildOptional(_ part: _ToolbarContentList?) -> _ToolbarContentList { part ?? _ToolbarContentList(items: []) }
    public static func buildEither(first: _ToolbarContentList) -> _ToolbarContentList { first }
    public static func buildEither(second: _ToolbarContentList) -> _ToolbarContentList { second }
    public static func buildArray(_ parts: [_ToolbarContentList]) -> _ToolbarContentList { _ToolbarContentList(items: parts.flatMap(\.items)) }
    public static func buildLimitedAvailability(_ part: _ToolbarContentList) -> _ToolbarContentList { part }
}

/// Registers items with the runtime's toolbar while the content is mounted.
public struct _ToolbarModifier {
    public var items: [_ToolbarItemData]
    nonisolated public init(items: [_ToolbarItemData]) { self.items = items }
    /// A customisable toolbar's items carry its id (`toolbar(id:)`).
    public init(id: String, items: [_ToolbarItemData]) {
        self.items = items.map { var item = $0; item.customizationID = id; return item }
    }
}

extension _ToolbarModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ToolbarNode(context)
    }
}

/// Hides or shows the window toolbar (`toolbar(_:for:)`).
@frozen
public struct _ToolbarVisibilityModifier: Equatable {
    public var visibility: Visibility
    public init(visibility: Visibility) { self.visibility = visibility }
}

extension _ToolbarVisibilityModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ToolbarVisibilityNode(context)
    }
}

/// The role of a toolbar (`toolbarRole`): `.editor` puts the title before the leading items.
public struct ToolbarRole: Hashable, Sendable {
    package let name: String
    public static let automatic = ToolbarRole(name: "automatic")
    public static let editor = ToolbarRole(name: "editor")
    public static let browser = ToolbarRole(name: "browser")
    public static let navigationStack = ToolbarRole(name: "navigationStack")
}

/// How a toolbar shows its title (`toolbarTitleDisplayMode`): on iOS `.large` is the large
/// title, `.inline` and `.inlineLarge` the inline one (`navigationBarTitleDisplayMode`).
public struct ToolbarTitleDisplayMode: Hashable, Sendable {
    package let name: String
    public static let automatic = ToolbarTitleDisplayMode(name: "automatic")
    public static let large = ToolbarTitleDisplayMode(name: "large")
    public static let inline = ToolbarTitleDisplayMode(name: "inline")
    public static let inlineLarge = ToolbarTitleDisplayMode(name: "inlineLarge")
}

extension View {
    /// Populates the window toolbar with the items.
    nonisolated public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> some View {
        modifier(_ToolbarModifier(items: content()._toolbarItems))
    }

    /// Populates a customisable toolbar: items with `showsByDefault: false` stay out until the
    /// user shows them; a secondary click on the bar offers every item to show or hide
    /// (`Runtime.setToolbarItem(_:visible:in:)` keeps the choices for the session).
    /// Puts the views in the toolbar at the automatic placement, each its own item.
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        modifier(_ToolbarModifier(items: [_ToolbarItemData(id: nil, placement: .automatic, view: AnyView(content()), isGroup: true)]))
    }

    nonisolated public func toolbar<C: CustomizableToolbarContent>(id: String, @ToolbarContentBuilder content: () -> C) -> some View {
        modifier(_ToolbarModifier(id: id, items: content()._toolbarItems))
    }

    /// Shows or hides the window toolbar; other bars are accepted without effect.
    nonisolated public func toolbar(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        modifier(_ToolbarVisibilityModifier(visibility: bars.isEmpty || bars.contains(where: { $0 == .automatic || $0 == .windowToolbar || $0 == .navigationBar }) ? visibility : .automatic))
    }

    /// Shows or hides the bars (iOS 18's name for `toolbar(_:for:)`).
    nonisolated public func toolbarVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        modifier(_ToolbarVisibilityModifier(visibility: bars.isEmpty || bars.contains(where: { $0 == .automatic || $0 == .windowToolbar || $0 == .navigationBar }) ? visibility : .automatic))
    }

    /// Fills the bars with the style: the window toolbar's painted chrome, the iOS navigation
    /// bar (a bar behind the title and items instead of iOS 26's bare top), the iOS tab bar's
    /// capsule (the style instead of the glass).
    nonisolated public func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> some View {
        modifier(_ToolbarBackgroundModifier(style: AnyShapeStyle(style), visibility: nil, bars: bars.isEmpty ? [.automatic] : bars))
    }

    /// Hides or shows the bars' backgrounds: a hidden window toolbar paints no ground and no
    /// hairline, a visible iOS navigation bar paints the window colour behind the title.
    nonisolated public func toolbarBackground(_ visibility: Visibility, for bars: ToolbarPlacement...) -> some View {
        modifier(_ToolbarBackgroundModifier(style: nil, visibility: visibility, bars: bars.isEmpty ? [.automatic] : bars))
    }

    /// Sets the toolbar's role: `.editor` leads with the title (macOS), the others keep the
    /// navigation items first.
    nonisolated public func toolbarRole(_ role: ToolbarRole) -> some View {
        modifier(_ToolbarRoleModifier(role: role))
    }

    /// Sets the title's display mode: on iOS `.large` and `.inlineLarge` show the large title,
    /// `.inline` the inline one; the macOS bar's title is inline either way.
    nonisolated public func toolbarTitleDisplayMode(_ mode: ToolbarTitleDisplayMode) -> some View {
        modifier(_NavigationTitleDisplayModeModifier(mode: mode == .inline ? .inline : mode == .automatic ? .automatic : .large))
    }
}

/// `toolbarBackground`: a style or visibility for some bars, registered with the runtime
/// while mounted (`ToolbarBackgroundNode`).
public struct _ToolbarBackgroundModifier {
    package let style: AnyShapeStyle?
    package let visibility: Visibility?
    package let bars: [ToolbarPlacement]
    public init(style: AnyShapeStyle?, visibility: Visibility?, bars: [ToolbarPlacement]) {
        self.style = style
        self.visibility = visibility
        self.bars = bars
    }
}

extension _ToolbarBackgroundModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ToolbarBackgroundNode(context)
    }
}

/// `toolbarRole`: registered with the runtime while mounted (`ToolbarRoleNode`).
public struct _ToolbarRoleModifier {
    package let role: ToolbarRole
    public init(role: ToolbarRole) { self.role = role }
}

extension _ToolbarRoleModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ToolbarRoleNode(context)
    }
}

// MARK: - Spacers and the title menu

/// How a `ToolbarSpacer` sizes itself: flexibly, or at a fixed width.
public struct SpacerSizing: Hashable, Sendable {
    package let isFlexible: Bool
    /// A spacer that grows to fill the space between items.
    public static let flexible = SpacerSizing(isFlexible: true)
    /// A spacer of the platform's fixed width.
    public static let fixed = SpacerSizing(isFlexible: false)
}

/// A standard space item in toolbars, separating the groups around it. The runtime's bar
/// already spaces its leading, principal and trailing groups, so the spacer adds no item.
public struct ToolbarSpacer: ToolbarContent, CustomizableToolbarContent {
    public typealias Body = Never
    package let sizing: SpacerSizing
    package let placement: ToolbarItemPlacement

    /// Creates a toolbar spacer of the given sizing at the given placement.
    public init(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic) {
        self.sizing = sizing
        self.placement = placement
    }

    public var body: Never { fatalError("ToolbarSpacer has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { [] }
}

/// The title menu of a toolbar: actions shown when the navigation title is pressed. The
/// runtime's title is not pressable, so the menu adds no item.
public struct ToolbarTitleMenu<Content: View>: ToolbarContent, CustomizableToolbarContent {
    public typealias Body = Never
    package let content: Content

    /// Creates a toolbar title menu with the given actions.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { fatalError("ToolbarTitleMenu has no body") }
    nonisolated public var _toolbarItems: [_ToolbarItemData] { [] }
}

extension ToolbarTitleMenu where Content == EmptyView {
    /// Creates a toolbar title menu with the system's document actions (none here).
    public init() {
        content = EmptyView()
    }
}

extension View {
    /// Configures the toolbar title menu (see `ToolbarTitleMenu`: the title shows no menu here).
    nonisolated public func toolbarTitleMenu<C: View>(@ViewBuilder content: () -> C) -> some View { self }
}
