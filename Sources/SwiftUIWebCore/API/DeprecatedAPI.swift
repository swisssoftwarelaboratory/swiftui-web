// The deprecated forms apps still carry (sw-app-api-gaps, decision 0021): `NavigationView`
// and its styles, `navigationBarTitle`, `ContentSizeCategory` and `sizeCategory`,
// `accessibilityEnabled`, `colorScheme(_:)`, `EnvironmentalModifier`. Each maps onto the
// current API; Apple's own deprecation messages are kept so Xcode's warnings match.
import WebFoundation

// MARK: - NavigationView

/// A view for presenting a stack of views that represents a visible path in a navigation
/// hierarchy: `NavigationStack` with the deprecated name (the column styles lay out as a stack).
@available(*, deprecated, message: "use NavigationStack or NavigationSplitView instead")
public struct NavigationView<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View { NavigationStack { content } }
}

/// A specification for the appearance and interaction of a navigation view.
public protocol NavigationViewStyle {}
public struct DefaultNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct StackNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct ColumnNavigationViewStyle: NavigationViewStyle { public init() {} }
public struct DoubleColumnNavigationViewStyle: NavigationViewStyle { public init() {} }

extension NavigationViewStyle where Self == DefaultNavigationViewStyle {
    public static var automatic: DefaultNavigationViewStyle { DefaultNavigationViewStyle() }
}
extension NavigationViewStyle where Self == StackNavigationViewStyle {
    public static var stack: StackNavigationViewStyle { StackNavigationViewStyle() }
}
extension NavigationViewStyle where Self == ColumnNavigationViewStyle {
    public static var columns: ColumnNavigationViewStyle { ColumnNavigationViewStyle() }
}

extension View {
    /// Sets the style for navigation views within this view (accepted: every style is the stack).
    @available(*, deprecated, message: "replace styled NavigationView with NavigationStack or NavigationSplitView instead")
    nonisolated public func navigationViewStyle<S: NavigationViewStyle>(_ style: S) -> some View { self }

    // MARK: navigationBarTitle

    /// Sets the title in the navigation bar for this view.
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle(_ title: Text) -> some View { navigationTitle(title) }
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey) -> some View { navigationTitle(titleKey) }
    @_disfavoredOverload
    @available(*, deprecated, renamed: "navigationTitle(_:)")
    nonisolated public func navigationBarTitle<S: StringProtocol>(_ title: S) -> some View { navigationTitle(title) }
    /// Sets the title and display mode in the navigation bar for this view.
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle(_ title: Text, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(displayMode)
    }
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle(_ titleKey: LocalizedStringKey, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(titleKey).navigationBarTitleDisplayMode(displayMode)
    }
    @_disfavoredOverload
    @available(*, deprecated, message: "Use navigationTitle(_:) with navigationBarTitleDisplayMode(_:)")
    nonisolated public func navigationBarTitle<S: StringProtocol>(_ title: S, displayMode: NavigationBarItem.TitleDisplayMode) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(displayMode)
    }

    // MARK: colorScheme

    /// Sets this view's color scheme (the environment's; `preferredColorScheme` sets the window's).
    @available(*, deprecated, renamed: "preferredColorScheme(_:)")
    nonisolated public func colorScheme(_ colorScheme: ColorScheme) -> some View { environment(\.colorScheme, colorScheme) }
}

// MARK: - ContentSizeCategory

/// The sizes that you can specify for content: `DynamicTypeSize` under its old name.
@available(*, deprecated, renamed: "DynamicTypeSize")
public enum ContentSizeCategory: Hashable, CaseIterable, Sendable {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
    case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge, accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge

    /// Whether the category is one of the accessibility sizes.
    public var isAccessibilityCategory: Bool {
        switch self {
        case .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge, .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge: return true
        default: return false
        }
    }

    package var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall: return .xSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .xLarge
        case .extraExtraLarge: return .xxLarge
        case .extraExtraExtraLarge: return .xxxLarge
        case .accessibilityMedium: return .accessibility1
        case .accessibilityLarge: return .accessibility2
        case .accessibilityExtraLarge: return .accessibility3
        case .accessibilityExtraExtraLarge: return .accessibility4
        case .accessibilityExtraExtraExtraLarge: return .accessibility5
        }
    }

    package init(_ size: DynamicTypeSize) {
        switch size {
        case .xSmall: self = .extraSmall
        case .small: self = .small
        case .medium: self = .medium
        case .large: self = .large
        case .xLarge: self = .extraLarge
        case .xxLarge: self = .extraExtraLarge
        case .xxxLarge: self = .extraExtraExtraLarge
        case .accessibility1: self = .accessibilityMedium
        case .accessibility2: self = .accessibilityLarge
        case .accessibility3: self = .accessibilityExtraLarge
        case .accessibility4: self = .accessibilityExtraExtraLarge
        case .accessibility5: self = .accessibilityExtraExtraExtraLarge
        }
    }
}

@available(*, deprecated)
extension ContentSizeCategory: Comparable {
    public static func < (a: ContentSizeCategory, b: ContentSizeCategory) -> Bool { a.dynamicTypeSize < b.dynamicTypeSize }
}

extension EnvironmentValues {
    /// The size category: `dynamicTypeSize` under its old name.
    @available(*, deprecated, renamed: "dynamicTypeSize")
    public var sizeCategory: ContentSizeCategory {
        get { ContentSizeCategory(dynamicTypeSize) }
        set { dynamicTypeSize = newValue.dynamicTypeSize }
    }

    /// Whether the user has enabled an assistive technology (unknown in a browser: false).
    public var accessibilityEnabled: Bool {
        get { self[AccessibilityEnabledKey.self] }
        set { self[AccessibilityEnabledKey.self] = newValue }
    }
}

private struct AccessibilityEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

// MARK: - EnvironmentalModifier

/// A modifier that must resolve to a concrete modifier in an environment before use.
public protocol EnvironmentalModifier: ViewModifier where Body == Never {
    associatedtype ResolvedModifier: ViewModifier
    /// Resolve to a concrete modifier using the given environment.
    nonisolated func resolve(in environment: EnvironmentValues) -> ResolvedModifier
}

extension EnvironmentalModifier {
    @MainActor public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentalModifierNode(context)
    }
}

/// Applies the modifier resolved in the node's environment, resolving again when it changes.
@MainActor
package final class EnvironmentalModifierNode<Content: View, Modifier: EnvironmentalModifier>: LayoutNode<ModifiedContent<Content, Modifier>> {
    private var child: TypedNode<ModifiedContent<Content, Modifier.ResolvedModifier>>!

    package init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = ModifiedContent<Content, Modifier.ResolvedModifier>._makeNode(_NodeContext(view: resolved(context.view, context.environment), parent: self, environment: context.environment))
    }

    private func resolved(_ view: ModifiedContent<Content, Modifier>, _ environment: EnvironmentValues) -> ModifiedContent<Content, Modifier.ResolvedModifier> {
        ModifiedContent(content: view.content, modifier: view.modifier.resolve(in: environment))
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: resolved(view, environment), environment: environment, force: force)
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "EnvironmentalModifier" }
}

// MARK: - Alert and ActionSheet

/// A representation of an alert presentation: the alert modifiers that take a title, actions
/// and a message, given as a value (Apple's soft deprecation: no warning yet).
public struct Alert {
    /// A button in an alert or action sheet.
    public struct Button {
        enum Style { case `default`, cancel, destructive }

        /// The button's parts, boxed (see `_LegacyAlertStorage`).
        final class Storage {
            let style: Style
            let label: Text
            let action: (() -> Void)?

            init(style: Style, label: Text, action: (() -> Void)?) {
                self.style = style
                self.label = label
                self.action = action
            }
        }

        let storage: Storage
        var style: Style { storage.style }
        var label: Text { storage.label }
        var action: (() -> Void)? { storage.action }

        init(style: Style, label: Text, action: (() -> Void)?) {
            storage = Storage(style: style, label: label, action: action)
        }

        /// A button with the default style.
        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
            Alert.Button(style: .default, label: label, action: action)
        }

        /// A button that cancels the presentation.
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
            Alert.Button(style: .cancel, label: label, action: action)
        }

        /// A button that cancels the presentation, labelled with the system's "Cancel".
        public static func cancel(_ action: (() -> Void)? = {}) -> Alert.Button {
            Alert.Button(style: .cancel, label: Text("Cancel"), action: action)
        }

        /// A button that does something destructive.
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Alert.Button {
            Alert.Button(style: .destructive, label: label, action: action)
        }
    }

    let storage: _LegacyAlertStorage

    /// An alert with one button: `dismissButton`, or "OK" when there is none.
    public init(title: Text, message: Text? = nil, dismissButton: Alert.Button? = nil) {
        storage = _LegacyAlertStorage(title: title, message: message, buttons: [dismissButton ?? .default(Text("OK"))])
    }

    /// An alert with two buttons.
    public init(title: Text, message: Text? = nil, primaryButton: Alert.Button, secondaryButton: Alert.Button) {
        storage = _LegacyAlertStorage(title: title, message: message, buttons: [primaryButton, secondaryButton])
    }
}

/// The title, message and buttons of an `Alert` or `ActionSheet`, boxed. On wasm every type's
/// value witnesses ship in every bundle; a struct holding `Text`s gets its own (~45 KB for these
/// two and `Alert.Button`, decision 0006's budget), while a struct holding one class reference
/// shares the runtime's.
final class _LegacyAlertStorage {
    let title: Text
    let message: Text?
    let buttons: [Alert.Button]

    init(title: Text, message: Text?, buttons: [Alert.Button]) {
        self.title = title
        self.message = message
        self.buttons = buttons
    }
}

/// A representation of an action sheet presentation: a confirmation dialog given as a value.
public struct ActionSheet {
    public typealias Button = Alert.Button

    let storage: _LegacyAlertStorage

    public init(title: Text, message: Text? = nil, buttons: [ActionSheet.Button] = [.cancel()]) {
        storage = _LegacyAlertStorage(title: title, message: message, buttons: buttons)
    }
}

extension Alert.Button {
    fileprivate var role: ButtonRole? {
        switch style {
        case .default: nil
        case .cancel: .cancel
        case .destructive: .destructive
        }
    }
}

/// A button's action, carried into the button's main-actor action (alert actions run there).
private struct _LegacyAlertAction: @unchecked Sendable {
    let run: (() -> Void)?
}

/// The value buttons as SwiftUI buttons with the matching roles. A function, not a view type:
/// on wasm a type's `View` conformance keeps its body in every bundle (~65 KB here, decision
/// 0006's budget), while a function's code goes only into the apps that call it.
private func _legacyAlertButtons(_ buttons: [Alert.Button]) -> AnyView {
    AnyView(ForEach(0..<buttons.count, id: \.self) { index -> Button<Text> in
        let button = buttons[index]
        let action = _LegacyAlertAction(run: button.action)
        return Button(role: button.role, action: { action.run?() }) { button.label }
    })
}

extension Alert {
    fileprivate var view: AnyView {
        AnyView(_AlertContent(title: storage.title, message: AnyView(storage.message), actions: _legacyAlertButtons(storage.buttons)))
    }
}

extension ActionSheet {
    fileprivate var view: AnyView {
        AnyView(_DialogContent(title: storage.title, message: AnyView(storage.message), actions: _legacyAlertButtons(storage.buttons)))
    }
}

extension View {
    /// Presents an alert to the user while `isPresented` is true.
    nonisolated public func alert(isPresented: Binding<Bool>, content: @escaping () -> Alert) -> some View {
        modifier(_PresentationModifier(kind: .alert, isPresented: isPresented, onDismiss: nil) { content().view })
    }

    /// Presents an alert built from `item` while it is not nil.
    nonisolated public func alert<Item: Identifiable>(item: Binding<Item?>, content: @escaping (Item) -> Alert) -> some View {
        modifier(_PresentationModifier(kind: .alert, isPresented: _itemBinding(item), onDismiss: nil) {
            item.wrappedValue.map { content($0).view } ?? AnyView(EmptyView())
        })
    }

    /// Presents an action sheet while `isPresented` is true.
    nonisolated public func actionSheet(isPresented: Binding<Bool>, content: @escaping () -> ActionSheet) -> some View {
        modifier(_PresentationModifier(kind: .dialog, isPresented: isPresented, onDismiss: nil) { content().view })
    }

    /// Presents an action sheet built from `item` while it is not nil.
    nonisolated public func actionSheet<T: Identifiable>(item: Binding<T?>, content: @escaping (T) -> ActionSheet) -> some View {
        modifier(_PresentationModifier(kind: .dialog, isPresented: _itemBinding(item), onDismiss: nil) {
            item.wrappedValue.map { content($0).view } ?? AnyView(EmptyView())
        })
    }

    // MARK: Renamed modifiers

    /// Hides the navigation bar: the toolbar visibility for `.navigationBar`.
    nonisolated public func navigationBarHidden(_ hidden: Bool) -> some View {
        toolbar(hidden ? .hidden : .automatic, for: .navigationBar)
    }

    /// Turns autocorrection off for text input in this view (`nil` leaves it as it is).
    nonisolated public func disableAutocorrection(_ disable: Bool?) -> some View {
        autocorrectionDisabled(disable ?? false)
    }
}
