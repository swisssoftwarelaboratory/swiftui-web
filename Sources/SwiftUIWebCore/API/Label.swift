/// A standard label for user interface items, consisting of an icon with a title.
///
/// The icon is centred on the title's cap height (half the environment font's cap height above
/// the first baseline), 8 pt before the title (`Docs/elements/Label.md`).
public struct Label<Title: View, Icon: View>: View {
    nonisolated(unsafe) package let title: Title
    nonisolated(unsafe) package let icon: Icon

    /// Creates a label with a custom title and icon.
    nonisolated public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    @Environment(\.labelStyle) private var style

    public var body: some View {
        // The icon is decoration beside the title, in every style (a custom one composes the
        // same icon): a label reads as its title — VoiceOver says "Sign In" for
        // `Label("Sign In", systemImage:)`, not the symbol's name first. The icon-only styles
        // show it again, reading as the title.
        let configuration = LabelStyleConfiguration(
            title: LabelStyleConfiguration.Title(AnyView(title)), icon: LabelStyleConfiguration.Icon(AnyView(icon.accessibilityHidden(true))))
        style.makeBodyErased(configuration)
    }
}

extension Label where Title == Text, Icon == Image {
    /// Creates a label with an icon image and a title generated from a localized string.
    nonisolated public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(name) })
    }

    /// Creates a label with an icon image and a title generated from a string.
    @_disfavoredOverload
    nonisolated public init<S: StringProtocol>(_ title: S, image name: String) {
        self.init(title: { Text(title) }, icon: { Image(name) })
    }

    /// Creates a label with a system symbol image and a title generated from a localized string
    /// (the symbol is a stub until the icon table lands: it draws nothing and has no size).
    nonisolated public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
        self.init(title: { Text(titleKey) }, icon: { Image(systemName: name) })
    }

    @_disfavoredOverload
    nonisolated public init<S: StringProtocol>(_ title: S, systemImage name: String) {
        self.init(title: { Text(title) }, icon: { Image(systemName: name) })
    }
}

// MARK: - Styles

/// The properties of a label.
public struct LabelStyleConfiguration {
    /// A type-erased title view of a label.
    public struct Title: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    /// A type-erased icon view of a label.
    public struct Icon: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let title: Title
    public let icon: Icon
}

/// A type that applies a custom appearance to all labels within a view.
@MainActor @preconcurrency
public protocol LabelStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

extension LabelStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default label style: icon and title, side by side.
public struct DefaultLabelStyle: LabelStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _AutomaticLabelBody(configuration: configuration)
    }
}

/// The automatic style resolved by context: a label in a toolbar shows its icon alone (the
/// title is its help), anywhere else the title and icon (Apple's documented behaviour; a
/// toolbar is window chrome outside the goldens).
struct _AutomaticLabelBody: View {
    let configuration: LabelStyleConfiguration
    @Environment(\._automaticLabelContext) private var context

    var body: some View {
        if context == .toolbar {
            if let title = (configuration.title.content.storage as? AnyViewStorage<Text>)?.view {
                configuration.icon.help(title).accessibilityHidden(false).accessibilityLabel(title)
            } else {
                configuration.icon.accessibilityHidden(false)
            }
        } else if context == .menu {
            // An iOS menu row: the icon centred in its own column in the tint, the title after it.
            HStack(spacing: PlatformMetrics.menuLabelIconGap) {
                configuration.icon
                    .foregroundStyle(Color.accentColor)
                    .frame(width: PlatformMetrics.menuLabelIconSlot)
                configuration.title
            }
        } else {
            TitleAndIconLabelStyle().makeBody(configuration: configuration)
        }
    }
}

/// Where a label sits, for the automatic style.
package enum _AutomaticLabelContext: Sendable { case toolbar, menu }

package struct AutomaticLabelContextKey: EnvironmentKey { package static let defaultValue: _AutomaticLabelContext? = nil }

extension EnvironmentValues {
    package var _automaticLabelContext: _AutomaticLabelContext? {
        get { self[AutomaticLabelContextKey.self] }
        set { self[AutomaticLabelContextKey.self] = newValue }
    }
}

/// A label style that shows both the title and icon of the label using a system-standard layout.
public struct TitleAndIconLabelStyle: LabelStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _TitleAndIconLabel(configuration: configuration)
    }
}

/// How a container lays out the icons of its labels: `List` gives them a fixed-width slot the
/// icon is centred in (overflowing it when larger) and the accent tint (`Docs/elements/List.md`).
package struct _LabelIconLayout: Equatable {
    package var iconWidth: CGFloat
    package var spacing: CGFloat
    package var tint: Color
    /// The image scale the icon takes (iOS list rows: large), or the environment's.
    package var scale: Image.Scale?

    package init(iconWidth: CGFloat, spacing: CGFloat, tint: Color, scale: Image.Scale? = nil) {
        self.iconWidth = iconWidth
        self.spacing = spacing
        self.tint = tint
        self.scale = scale
    }
}

package struct LabelIconLayoutKey: EnvironmentKey {
    package static let defaultValue: _LabelIconLayout? = nil
}

extension EnvironmentValues {
    package var _labelIconLayout: _LabelIconLayout? {
        get { self[LabelIconLayoutKey.self] }
        set { self[LabelIconLayoutKey.self] = newValue }
    }
}

/// The icon and title side by side; inside a list the icon takes the container's slot and tint.
package struct _TitleAndIconLabel: View {
    package let configuration: LabelStyleConfiguration
    @Environment(\._labelIconLayout) private var iconLayout

    package init(configuration: LabelStyleConfiguration) { self.configuration = configuration }

    package var body: some View {
        let icon = configuration.icon
        if let iconLayout {
            HStack(alignment: ._iconCenter, spacing: iconLayout.spacing) {
                if let scale = iconLayout.scale {
                    icon.imageScale(scale).foregroundStyle(iconLayout.tint).frame(width: iconLayout.iconWidth)
                } else {
                    icon.foregroundStyle(iconLayout.tint).frame(width: iconLayout.iconWidth)
                }
                _IconAlignedTitle(content: configuration.title)
            }
        } else {
            HStack(alignment: ._iconCenter, spacing: PlatformMetrics.labelIconSpacing) {
                icon
                _IconAlignedTitle(content: configuration.title)
            }
        }
    }
}

/// A label style that only displays the title of the label.
public struct TitleOnlyLabelStyle: LabelStyle {
    nonisolated public init() {}
    public func makeBody(configuration: Configuration) -> some View { configuration.title }
}

/// A label style that only displays the icon of the label.
public struct IconOnlyLabelStyle: LabelStyle {
    nonisolated public init() {}
    /// The icon alone, reading as the title (SwiftUI keeps the title as the accessibility label:
    /// Scrumdinger's icon-only "Add Attendee" button).
    public func makeBody(configuration: Configuration) -> some View {
        if let title = (configuration.title.content.storage as? AnyViewStorage<Text>)?.view {
            configuration.icon.accessibilityHidden(false).accessibilityLabel(title)
        } else {
            configuration.icon.accessibilityHidden(false)
        }
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    public static var automatic: DefaultLabelStyle { DefaultLabelStyle() }
}
extension LabelStyle where Self == TitleAndIconLabelStyle {
    public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() }
}
extension LabelStyle where Self == TitleOnlyLabelStyle {
    public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() }
}
extension LabelStyle where Self == IconOnlyLabelStyle {
    public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() }
}

package struct LabelStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any LabelStyle = DefaultLabelStyle()
}

extension EnvironmentValues {
    package var labelStyle: any LabelStyle {
        get { self[LabelStyleKey.self] }
        set { self[LabelStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for labels within this view.
    nonisolated public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
        environment(\.labelStyle, style)
    }
}

// MARK: - Icon alignment

extension VerticalAlignment {
    package enum _IconCenter: AlignmentID {
        package static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    /// The guide icons and checkboxes centre on: their own centre, and for text the middle of the
    /// first line's cap height (`Label`, `Toggle`).
    package static let _iconCenter = VerticalAlignment(_IconCenter.self)
}

extension EnvironmentValues {
    /// Half the cap height of the environment's font (the fallback 0.7046 em is SF's ratio).
    package var _halfCapHeight: CGFloat {
        let resolved = (font ?? platformProfile.defaultFont).resolve(in: self)
        let capHeight = platformProfile.systemFontMetrics(for: resolved).capHeight
        return (capHeight > 0 ? capHeight : resolved.size * 0.7046) / 2
    }
}

/// A title whose `_iconCenter` guide sits half a cap height above its first baseline.
package struct _IconAlignedTitle<Content: View>: View {
    package let content: Content
    @Environment(\.self) private var environment

    package init(content: Content) { self.content = content }

    package var body: some View {
        let half = environment._halfCapHeight
        content.alignmentGuide(._iconCenter) { $0[.firstTextBaseline] - half }
    }
}

extension Label: _TitleProviding where Title == Text {
    /// Views are built on the main actor; the title is read there.
    nonisolated public var _title: String { MainActor.assumeIsolated { title.resolvedString } }
}
