/// A control that toggles between on and off states.
///
/// macOS styles, measured in `Docs/elements/Toggle.md`: the default is a 16 pt checkbox 5 pt
/// before a `.body` label, centred on the label's cap height; `.switch` is a 54 × 24 capsule
/// after the label; `.button` is a bordered button that turns prominent when on.
public struct Toggle<Label: View>: View {
    package let isOn: Binding<Bool>
    package let label: Label
    /// `Toggle(sources:)`: whether the sources disagree, read in `body` so a change to any
    /// source re-evaluates it; the checkbox then shows a dash (`isMixed`).
    package var mixed: _MixedCheck?

    /// The live check (a class so the runtime's field reflection ignores it).
    package final class _MixedCheck {
        package let isMixed: @MainActor () -> Bool
        package init(_ isMixed: @escaping @MainActor () -> Bool) { self.isMixed = isMixed }
    }

    /// Creates a toggle that displays a custom label.
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self.isOn = isOn
        self.label = label()
    }

    /// Creates a toggle representing a collection of values: on when every source is on, mixed
    /// when they disagree; a flip writes to every source (a mixed toggle turns on).
    public init<C: RandomAccessCollection>(sources: C, isOn: KeyPath<C.Element, Binding<Bool>>, @ViewBuilder label: () -> Label) {
        let bindings = sources.map { $0[keyPath: isOn] }
        self.isOn = Binding(get: { !bindings.isEmpty && bindings.allSatisfy(\.wrappedValue) },
                            set: { value in for binding in bindings { binding.wrappedValue = value } })
        self.label = label()
        self.mixed = _MixedCheck {
            let values = bindings.map(\.wrappedValue)
            return values.contains(true) && values.contains(false)
        }
    }

    @Environment(\.toggleStyle) private var style
    /// Made from a style's configuration (`Toggle(configuration)` inside `makeBody`): drawn in
    /// the default style, as Apple's, not the style that is building it.
    package var fromConfiguration = false
    @Environment(\._formStyle) private var formStyle
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\._inMenu) private var inMenu

    public var body: some View {
        let isMixed = mixed?.isMixed() == true
        let configuration = ToggleStyleConfiguration(label: ToggleStyleConfiguration.Label(AnyView(label)), isOn: isOn, isMixed: isMixed)
        if inMenu {
            // A menu row with a check mark while on (Docs/elements/Menu.md).
            _ToggleHost(isOn: isOn, content: AnyView(_MenuRowLabel(label: AnyView(label), submenu: false, checked: isOn.wrappedValue)))
        } else if formStyle == .grouped {
            // A grouped form row: the label leading, a switch trailing (Docs/elements/Form.md).
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)),
                            content: AnyView(_ToggleHost(isOn: isOn, content: AnyView(_SwitchControl(isOn: isOn.wrappedValue, small: true)))),
                            mode: .grouped)
        } else {
            _ToggleHost(isOn: isOn, content: AnyView((fromConfiguration ? DefaultToggleStyle() : style).makeBodyErased(configuration)))
        }
    }
}

extension Toggle where Label == Text {
    /// Creates a toggle that generates its label from a localized string key.
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(titleKey) }
    }

    /// Creates a toggle that generates its label from a string.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }

    /// A toggle over several sources, labelled by a key.
    public init<C: RandomAccessCollection>(_ titleKey: LocalizedStringKey, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) {
        self.init(sources: sources, isOn: isOn) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol, C: RandomAccessCollection>(_ title: S, sources: C, isOn: KeyPath<C.Element, Binding<Bool>>) {
        self.init(sources: sources, isOn: isOn) { Text(title) }
    }
}

extension Toggle where Label == SwiftUIWebCore.Label<Text, Image> {
    /// Creates a toggle with a label from a title and an image resource.
    public init(_ titleKey: LocalizedStringKey, image name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(titleKey, image: name) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(title, image: name) }
    }

    /// Creates a toggle with a label from a title and a system symbol (stub symbol).
    public init(_ titleKey: LocalizedStringKey, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(titleKey, systemImage: name) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage name: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { SwiftUIWebCore.Label(title, systemImage: name) }
    }
}

extension Toggle where Label == ToggleStyleConfiguration.Label {
    /// Creates a toggle based on a toggle style configuration (for custom styles).
    public init(_ configuration: ToggleStyleConfiguration) {
        self.init(isOn: configuration.$isOn) { configuration.label }
        fromConfiguration = true
    }
}

// MARK: - Styles

/// The properties of a toggle instance.
public struct ToggleStyleConfiguration {
    /// A type-erased label of a toggle.
    public struct Label: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let label: Label
    @Binding public var isOn: Bool
    /// Whether the toggle is in a mixed state: `Toggle(sources:isOn:)` over sources that disagree.
    public var isMixed: Bool = false

    package init(label: Label, isOn: Binding<Bool>, isMixed: Bool = false) {
        self.label = label
        self._isOn = isOn
        self.isMixed = isMixed
    }
}

/// The appearance and behavior of a toggle.
@MainActor @preconcurrency
public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
}

extension ToggleStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default toggle style: a checkbox on macOS.
public struct DefaultToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformToggleBody(configuration: configuration, switchStyle: false)
    }
}

/// The platform's look: macOS's checkbox (or switch), iOS's switch row (ios/toggle/basic): the
/// label leading, the switch at the trailing edge of the proposed width, 28 pt tall, and both
/// text baselines at the row's top (an `HStack(alignment: .firstTextBaseline)` hangs the row
/// 18 pt below a neighbouring body text).
struct _PlatformToggleBody: View {
    let configuration: ToggleStyleConfiguration
    let switchStyle: Bool
    @Environment(\.platformProfile) private var profile
    @Environment(\.labelsHidden) private var labelsHidden

    var body: some View {
        if profile.isIOS {
            if labelsHidden {
                _SwitchControl(isOn: configuration.isOn)
            } else {
                HStack(alignment: .center, spacing: profile.metrics.switchLabelSpacing) {
                    _ControlLabel(label: configuration.label)
                    Spacer(minLength: 0)
                    _SwitchControl(isOn: configuration.isOn)
                }
                .frame(maxWidth: .infinity)
                .alignmentGuide(.firstTextBaseline) { _ in 0 }
                .alignmentGuide(.lastTextBaseline) { _ in 0 }
                .modifier(_PlainSpacingModifier())
            }
        } else if switchStyle {
            _SwitchToggleBody(configuration: configuration)
        } else {
            _CheckboxToggleBody(configuration: configuration)
        }
    }
}

/// A toggle style that displays a checkbox followed by its label.
public struct CheckboxToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _CheckboxToggleBody(configuration: configuration)
    }
}

/// A toggle style that displays a leading label and a trailing switch.
public struct SwitchToggleStyle: ToggleStyle {
    private var tint: Color?
    nonisolated public init() {}
    /// A switch whose on track is `tint` (Apple's deprecated form of `.tint(_:)` on the toggle).
    nonisolated public init(tint: Color) { self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View {
        _PlatformToggleBody(configuration: configuration, switchStyle: true)
            .transformEnvironment(\._tint) { [tint] value in if let tint { value = tint } }
    }
}

/// A toggle style that displays as a button with its label as the title.
public struct ButtonToggleStyle: ToggleStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _ButtonToggleBody(configuration: configuration)
    }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}
extension ToggleStyle where Self == CheckboxToggleStyle {
    public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
extension ToggleStyle where Self == ButtonToggleStyle {
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

package struct ToggleStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any ToggleStyle = DefaultToggleStyle()
}

extension EnvironmentValues {
    package var toggleStyle: any ToggleStyle {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for toggles in a view hierarchy.
    nonisolated public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
        environment(\.toggleStyle, style)
    }
}

// MARK: - Style bodies

/// The label a control shows: hidden by `labelsHidden`, dimmed when disabled, in `.body` (macOS:
/// 9 and 11 pt for the mini and small control sizes, toggle/looks).
package struct _ControlLabel<Content: View>: View {
    package let label: Content
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.platformProfile) private var profile
    @Environment(\.controlSize) private var controlSize

    package init(label: Content) { self.label = label }

    private var font: Font {
        guard !profile.isIOS else { return .body }
        switch controlSize {
        case .mini: return .system(size: PlatformMetrics.controlMiniFontSize)
        case .small: return .system(size: PlatformMetrics.controlSmallFontSize)
        default: return .body
        }
    }

    package var body: some View {
        if !labelsHidden {
            // macOS dims a disabled control's label; an iPhone keeps a toggle's or stepper's
            // label black (ios/toggle/basic, ios/stepper/basic `disabled`).
            _IconAlignedTitle(content: label)
                .font(font)
                .foregroundColor(isEnabled || profile.isIOS ? nil : Color.primary.opacity(PlatformMetrics.disabledLabelOpacity))
        }
    }
}

struct _CheckboxToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(alignment: ._iconCenter, spacing: PlatformMetrics.checkboxLabelSpacing) {
            _CheckboxControl(isOn: configuration.isOn, isMixed: configuration.isMixed, size: controlSize)
            _ControlLabel(label: configuration.label)
        }
    }
}

struct _SwitchToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        HStack(alignment: .center, spacing: PlatformMetrics.switchLabelSpacing) {
            _ControlLabel(label: configuration.label)
            _SwitchControl(isOn: configuration.isOn, size: controlSize)
        }
    }
}

struct _ButtonToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let on = configuration.isOn
        configuration.label
            .font(.system(size: PlatformMetrics.buttonLabelSize))
            .foregroundColor(on ? Color.white : (isEnabled ? nil : Color.primary.opacity(PlatformMetrics.disabledLabelOpacity)))
            .padding(.horizontal, PlatformMetrics.buttonHorizontalPadding)
            .padding(.vertical, PlatformMetrics.buttonVerticalPadding)
            .frame(minHeight: PlatformMetrics.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: PlatformMetrics.buttonCornerRadius, style: .circular)
                    .fill(on ? Color.accentColor : PlatformMetrics.buttonFill))
    }
}

// MARK: - Primitives

/// Owns a toggle's activation: a press released inside flips the binding. Transparent to layout.
public struct _ToggleHost: View {
    package let isOn: Binding<Bool>
    package let content: AnyView

    package init(isOn: Binding<Bool>, content: AnyView) {
        self.isOn = isOn
        self.content = content
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_ToggleHost>) -> TypedNode<_ToggleHost> {
        ToggleHostNode(context)
    }
}

/// The 16 × 16 macOS checkbox (12, 14 and 18 for the mini, small and large sizes).
public struct _CheckboxControl: View {
    package let isOn: Bool
    package let isMixed: Bool
    package let size: ControlSize
    package init(isOn: Bool, isMixed: Bool = false, size: ControlSize = .regular) {
        self.isOn = isOn
        self.isMixed = isMixed
        self.size = size
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_CheckboxControl>) -> TypedNode<_CheckboxControl> {
        CheckboxNode(context)
    }
}

/// The 54 × 24 macOS switch (or the small one grouped forms use; the mini and small control sizes).
public struct _SwitchControl: View {
    package let isOn: Bool
    package let small: Bool
    package let size: ControlSize
    package init(isOn: Bool, small: Bool = false, size: ControlSize = .regular) {
        self.isOn = isOn
        self.small = small
        self.size = size
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_SwitchControl>) -> TypedNode<_SwitchControl> {
        SwitchNode(context)
    }
}

// MARK: - Environment: labelsHidden, isEnabled

package struct LabelsHiddenKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct IsEnabledKey: EnvironmentKey {
    package static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether controls in this environment hide their labels.
    package var labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }

    /// Whether the view associated with this environment allows user interaction.
    public var isEnabled: Bool {
        get { self[IsEnabledKey.self] }
        set { self[IsEnabledKey.self] = newValue }
    }
}

extension View {
    /// Hides the labels of any controls contained within this view.
    nonisolated public func labelsHidden() -> some View {
        environment(\.labelsHidden, true)
    }

    /// Adds a condition that controls whether users can interact with this view.
    nonisolated public func disabled(_ disabled: Bool) -> some View {
        _transformEnvironment("disabled", key: disabled) { $0.isEnabled = $0.isEnabled && !disabled }
    }
}
