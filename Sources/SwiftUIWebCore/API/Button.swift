/// A value that describes the purpose of a button.
public struct ButtonRole: Equatable, Sendable {
    package let name: String
    public static let destructive = ButtonRole(name: "destructive")
    public static let cancel = ButtonRole(name: "cancel")
}

/// Holds a button's action. A class rather than a bare closure field so the runtime's field
/// reflection stays warning-free (the runtime cannot demangle `@MainActor` function types).
package final class _ActionBox: @unchecked Sendable {
    package let run: @MainActor () -> Void
    /// A value link's value (`NavigationLink(value:)`): in a list with a selection it is the
    /// row's selection tag.
    package private(set) var linkValue: AnyHashable?
    package init(_ run: @escaping @MainActor () -> Void) { self.run = run }
    package init(linkValue: AnyHashable?, _ run: @escaping @MainActor () -> Void) {
        self.run = run
        self.linkValue = linkValue
    }
    /// A plain closure, as Apple's `onTapGesture`, `onAppear`, `onSubmit` and the like take
    /// (a Swift 6 app passes a stored `() -> Void` to them); it runs on the main actor.
    package init(plain run: @escaping () -> Void) {
        nonisolated(unsafe) let run = run
        self.run = { run() }
    }
}

/// A control that initiates an action.
public struct Button<Label: View>: View {
    package let action: _ActionBox
    nonisolated(unsafe) package let label: Label
    package let role: ButtonRole?
    @State private var isPressed = false

    /// Creates a button that displays a custom label.
    @preconcurrency nonisolated public init(action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = _ActionBox(action)
        self.label = label()
        self.role = nil
    }

    /// Creates a button with a specified role that displays a custom label.
    @preconcurrency nonisolated public init(role: ButtonRole?, action: @escaping @MainActor () -> Void, @ViewBuilder label: () -> Label) {
        self.action = _ActionBox(action)
        self.label = label()
        self.role = role
    }

    @Environment(\.buttonStyle) private var style
    @Environment(\._primitiveButtonStyle) private var primitiveStyle
    @Environment(\._inMenu) private var inMenu

    public var body: some View {
        if inMenu {
            // A menu item: the label in a row, no button chrome.
            _ButtonHost(action: action, isPressed: $isPressed, label: AnyView(_MenuRowLabel(label: AnyView(label), submenu: false)))
        } else if let primitiveStyle {
            // A primitive style owns the interaction: its body decides when `trigger` runs.
            let configuration = PrimitiveButtonStyleConfiguration(label: PrimitiveButtonStyleConfiguration.Label(AnyView(label)), role: role, action: action)
            primitiveStyle.makeBodyErased(configuration)
                .layoutValue(key: _ButtonRoleKey.self, value: role)
        } else {
            let configuration = ButtonStyleConfiguration(
                label: ButtonStyleConfiguration.Label(AnyView(label)), isPressed: isPressed, role: role)
            // The role travels as a layout value for layouts that order or hide actions by it (iOS alerts).
            _ButtonHost(action: action, isPressed: $isPressed, label: AnyView(style.makeBodyErased(configuration)))
                .layoutValue(key: _ButtonRoleKey.self, value: role)
        }
    }
}

extension Button where Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a button that generates its label from a localized string key and a system image.
    @preconcurrency nonisolated public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { SwiftUIWebCore.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }
    @preconcurrency nonisolated public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { SwiftUIWebCore.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { SwiftUIWebCore.Label(title, systemImage: systemImage) }
    }
    /// Creates a button with a label from a localized string key and a catalog image.
    @preconcurrency nonisolated public init(_ titleKey: LocalizedStringKey, image: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { SwiftUIWebCore.Label(titleKey, image: image) }
    }
    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol>(_ title: S, image: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { SwiftUIWebCore.Label(title, image: image) }
    }
}

extension Button where Label == Text {
    /// Creates a button that generates its label from a localized string key.
    @preconcurrency nonisolated public init(_ titleKey: LocalizedStringKey, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(titleKey) }
    }

    /// Creates a button that generates its label from a string.
    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol>(_ title: S, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { Text(title) }
    }

    @preconcurrency nonisolated public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(titleKey) }
    }

    @_disfavoredOverload
    @preconcurrency nonisolated public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping @MainActor () -> Void) {
        self.init(role: role, action: action) { Text(title) }
    }
}

// MARK: - Styles

/// The properties of a button.
public struct ButtonStyleConfiguration {
    /// A type-erased label of a button.
    public struct Label: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let label: Label
    public let isPressed: Bool
    public let role: ButtonRole?
}

/// A type that applies standard interaction behavior and a custom appearance to all buttons
/// within a view hierarchy.
@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

extension ButtonStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The properties of a button with a primitive style: the label, the role and `trigger()`,
/// which runs the action.
public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let label: Label
    public let role: ButtonRole?
    package let action: _ActionBox

    /// Performs the button's action.
    @MainActor public func trigger() { action.run() }
}

/// A type that applies custom interaction behavior and a custom appearance to all buttons
/// within a view hierarchy: its body decides when the action runs.
@MainActor @preconcurrency
public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

extension PrimitiveButtonStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

package struct PrimitiveButtonStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: (any PrimitiveButtonStyle)? = nil
}

extension EnvironmentValues {
    /// The primitive style set by `buttonStyle(_:)`, taking over from the `ButtonStyle`.
    package var _primitiveButtonStyle: (any PrimitiveButtonStyle)? {
        get { self[PrimitiveButtonStyleKey.self] }
        set { self[PrimitiveButtonStyleKey.self] = newValue }
    }
}

/// The default button style, based on the button's context (bordered on macOS).
public struct DefaultButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension DefaultButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .automatic)
    }
}

/// Picks the platform's look for a style: macOS's bordered buttons, or iOS's (a body-font label
/// in the accent colour, borderless by default, a capsule when bordered; ios/button/basic).
struct _PlatformButtonBody: View {
    enum Kind { case automatic, bordered, prominent, borderless }
    let configuration: ButtonStyleConfiguration
    let kind: Kind
    @Environment(\.platformProfile) private var profile
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if profile.isIOS {
            switch kind {
            case .automatic, .borderless: _IOSBorderlessButtonBody(configuration: configuration, metrics: profile.metrics)
            case .bordered: _IOSBorderedButtonBody(configuration: configuration, metrics: profile.metrics, prominent: false)
            case .prominent: _IOSBorderedButtonBody(configuration: configuration, metrics: profile.metrics, prominent: true)
            }
        } else {
            switch kind {
            case .automatic, .bordered: _MacBorderedButtonBody(configuration: configuration)
            case .prominent: _MacProminentButtonBody(configuration: configuration)
            case .borderless:
                configuration.label
                    .foregroundStyle((_macButtonLabel(configuration.role, enabled: isEnabled, metrics: profile.metrics) ?? Color.accentColor)
                        .opacity(configuration.isPressed ? 0.6 : 1))
            }
        }
    }
}

/// iOS: the label's tint, red for a destructive role, dimmed when disabled.
func _iosButtonTint(_ role: ButtonRole?, enabled: Bool, metrics: PlatformMetricsTable) -> Color {
    guard enabled else { return Color.primary.opacity(metrics.disabledLabelOpacity) }
    let red = metrics.destructiveColor   // components already 0…1
    return role == .destructive ? Color(red: red.red, green: red.green, blue: red.blue) : Color.accentColor
}

/// The geometry a control size gives a bordered button (ios/button/looks; macOS approximate).
struct _ButtonSizeMetrics {
    var font: Font
    var height: CGFloat
    var horizontal: CGFloat
    var vertical: CGFloat

    init(_ size: ControlSize, metrics: PlatformMetricsTable, isIOS: Bool) {
        func systemFont(_ size: CGFloat) -> Font { isIOS && metrics.buttonSmallUsesTextStyle ? .subheadline : .system(size: size) }
        switch size {
        case .mini:
            font = systemFont(metrics.buttonMiniFontSize)
            height = metrics.buttonMiniHeight
            horizontal = metrics.buttonMiniHorizontalPadding
            vertical = metrics.buttonMiniVerticalPadding
        case .small:
            font = systemFont(metrics.buttonSmallFontSize)
            height = metrics.buttonSmallHeight
            horizontal = metrics.buttonSmallHorizontalPadding
            vertical = metrics.buttonSmallVerticalPadding
        case .large, .extraLarge:
            // macOS has no extra large: it is the regular; iOS gives it the large's capsule.
            if size == .extraLarge && !isIOS {
                font = isIOS ? .body : .system(size: metrics.buttonLabelSize)
                height = metrics.buttonHeight
                horizontal = metrics.buttonHorizontalPadding
                vertical = metrics.buttonVerticalPadding
            } else {
                font = isIOS ? .body : .system(size: metrics.buttonLargeFontSize)
                height = metrics.buttonLargeHeight
                horizontal = metrics.buttonLargeHorizontalPadding
                vertical = metrics.buttonLargeVerticalPadding
            }
        case .regular:
            font = isIOS ? .body : .system(size: metrics.buttonLabelSize)
            height = metrics.buttonHeight
            horizontal = metrics.buttonHorizontalPadding
            vertical = metrics.buttonVerticalPadding
        }
    }
}

struct _IOSBorderlessButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let metrics: PlatformMetricsTable
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        configuration.label
            .font(_ButtonSizeMetrics(controlSize, metrics: metrics, isIOS: true).font)
            .foregroundColor(_iosButtonTint(configuration.role, enabled: isEnabled, metrics: metrics).opacity(configuration.isPressed ? 0.5 : 1))
    }
}

struct _IOSBorderedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let metrics: PlatformMetricsTable
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        let tint = _iosButtonTint(configuration.role, enabled: isEnabled, metrics: metrics)
        let size = _ButtonSizeMetrics(controlSize, metrics: metrics, isIOS: true)
        // A disabled prominent button wears the bordered fill with a faint label (ios/button/looks).
        let label: Color = prominent ? (isEnabled ? Color.white : Color.primary.opacity(metrics.buttonProminentDisabledLabelAlpha)) : tint
        let fill: Color = prominent
            ? (isEnabled ? tint : (metrics.buttonProminentDisabledUsesPlainFill ? metrics.buttonFill : Color.primary.opacity(0.12)))
            : metrics.buttonFill
        configuration.label
            .font(size.font)
            .foregroundColor(label)
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .frame(minHeight: size.height)
            .background(Capsule().fill(fill).opacity(configuration.isPressed ? 0.7 : 1))
            .modifier(_PlainSpacingModifier())
    }
}

/// Gives a view the plain 8 pt spacing to its neighbours whatever its content declares (an iOS
/// bordered button around a text label).
public struct _PlainSpacingModifier: ViewModifier {
    package init() {}
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        PlainSpacingNode(context)
    }
}

/// macOS: the label's colour for a role and state: red for a destructive role (unverified: the
/// inactive window of button/looks shows the label colour), dimmed when disabled.
func _macButtonLabel(_ role: ButtonRole?, enabled: Bool, metrics: PlatformMetricsTable) -> Color? {
    guard enabled else { return Color.primary.opacity(metrics.buttonDisabledLabelAlpha) }
    guard role == .destructive, metrics.buttonDestructiveTintsLabel else { return nil }
    let red = metrics.destructiveColor
    return Color(red: red.red, green: red.green, blue: red.blue)
}

struct _MacBorderedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.platformProfile) private var profile

    var body: some View {
        let size = _ButtonSizeMetrics(controlSize, metrics: profile.metrics, isIOS: false)
        let fill = configuration.isPressed ? PlatformMetrics.buttonPressedFill : PlatformMetrics.buttonFill
        configuration.label
            .font(size.font)
            .foregroundColor(_macButtonLabel(configuration.role, enabled: isEnabled, metrics: profile.metrics))
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .frame(minHeight: size.height)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius, style: .circular)
                    .fill(fill.opacity(isEnabled ? 1 : PlatformMetrics.buttonDisabledFillAlpha)))
    }
}

struct _MacProminentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.platformProfile) private var profile

    var body: some View {
        let size = _ButtonSizeMetrics(controlSize, metrics: profile.metrics, isIOS: false)
        let red = profile.metrics.destructiveColor
        let tint: Color = configuration.role == .destructive ? Color(red: red.red, green: red.green, blue: red.blue) : Color.accentColor
        configuration.label
            .font(size.font)
            .foregroundStyle(isEnabled ? Color.white : Color.primary.opacity(PlatformMetrics.buttonProminentDisabledLabelAlpha))
            .padding(.horizontal, size.horizontal)
            .padding(.vertical, size.vertical)
            .frame(minHeight: size.height)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius, style: .circular)
                    .fill(isEnabled ? tint.opacity(configuration.isPressed ? 0.8 : 1) : PlatformMetrics.buttonFill.opacity(PlatformMetrics.buttonDisabledFillAlpha)))
    }
}

/// A button style that applies standard border artwork based on the button's context.
///
/// Geometry from `button/basic` goldens (macOS 26.2): 24 pt tall, 12 pt horizontal padding,
/// label in the 13 pt point-size font (16 pt line), 6 pt corner radius, fill black at 7.5 %.
public struct BorderedButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension BorderedButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .bordered)
    }
}

/// A button style that applies standard border prominent artwork based on the button's context.
public struct BorderedProminentButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension BorderedProminentButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .prominent)
    }
}

/// A button style that doesn't apply a border. On macOS the label uses the accent colour
/// (approximate: Apple's ImageRenderer cannot draw this AppKit-backed style).
public struct BorderlessButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension BorderlessButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformButtonBody(configuration: configuration, kind: .borderless)
    }
}

/// A button style that doesn't style or decorate its content while idle.
public struct PlainButtonStyle {
    @preconcurrency nonisolated public init() {}
}

extension PlainButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _PlainButtonBody(configuration: configuration)
    }
}

/// The plain style: the label, at 70 % while pressed and 50 % while disabled (ios/button/looks
/// `disabledPlain` reads (127) for the black label; button/looks the same on macOS).
struct _PlainButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : PlatformMetrics.buttonPlainDisabledAlpha))
    }
}

extension ButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}
extension ButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension ButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}
extension ButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}

package struct ButtonStyleKey: EnvironmentKey {
    // `ButtonStyle` is not Sendable (as in SwiftUI); the default is an immutable value type.
    package nonisolated(unsafe) static let defaultValue: any ButtonStyle = DefaultButtonStyle()
}

extension EnvironmentValues {
    package var buttonStyle: any ButtonStyle {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for buttons within this view to a button style with a custom appearance
    /// and standard interaction behavior.
    nonisolated public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        // Keyed by the style, so a body evaluated again with the same style keeps the labels'
        // sizes (new-website#216: every row of a search under `.buttonStyle(PressStyle())`).
        _transformEnvironment("buttonStyle", key: _equalityKey(style)) { environment in
            environment.buttonStyle = style
            environment._primitiveButtonStyle = nil
        }
    }

    /// Sets the style for buttons within this view to a primitive style, which owns the
    /// interaction as well as the look.
    nonisolated public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        _transformEnvironment("primitiveButtonStyle", key: _equalityKey(style)) { $0._primitiveButtonStyle = style }
    }
}

// MARK: - Interaction host

/// Primitive that owns a button's press state and activation. Transparent to layout.
public struct _ButtonHost: View {
    package let action: _ActionBox
    package let isPressed: Binding<Bool>
    package let label: AnyView

    package init(action: _ActionBox, isPressed: Binding<Bool>, label: AnyView) {
        self.action = action
        self.isPressed = isPressed
        self.label = label
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ButtonHost>) -> TypedNode<_ButtonHost> {
        ButtonHostNode(context)
    }
}

/// Runs an action on tap. Transparent to layout.
public struct _TapGestureModifier {
    package let count: Int
    package let action: _ActionBox
}

extension _TapGestureModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TapGestureNode(context)
    }
}

extension View {
    /// Adds an action to perform when this view recognizes a tap gesture.
    nonisolated public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        modifier(_TapGestureModifier(count: count, action: _ActionBox(plain: action)))
    }

    /// Adds an action to perform with the tap's location when this view recognizes a tap
    /// (a `SpatialTapGesture` in the coordinate space).
    nonisolated public func onTapGesture(count: Int = 1, coordinateSpace: some CoordinateSpaceProtocol = .local, perform action: @escaping (CGPoint) -> Void) -> some View {
        nonisolated(unsafe) let action = action
        let space = coordinateSpace.coordinateSpace
        let gesture = MainActor.assumeIsolated {
            SpatialTapGesture(count: count, coordinateSpace: space).onEnded { action($0.location) }
        }
        return modifier(_GestureModifier(gesture: gesture, priority: .normal, mask: .all))
    }
}
