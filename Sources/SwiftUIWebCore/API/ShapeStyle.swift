#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A color or pattern to use when rendering a shape.
public protocol ShapeStyle: Sendable {}

extension Color: ShapeStyle {}

package struct ForegroundStyleKey: EnvironmentKey {
    package static let defaultValue: Color? = nil
}

package struct ForegroundGradientKey: EnvironmentKey {
    package static let defaultValue: (any _GradientStyle)? = nil
}

extension EnvironmentValues {
    /// The foreground colour set by `foregroundStyle`/`foregroundColor`, if any.
    package var foregroundColor: Color? {
        get { self[ForegroundStyleKey.self] }
        set { self[ForegroundStyleKey.self] = newValue }
    }

    /// A gradient set by `foregroundStyle`: text draws with it (Docs/elements/Gradient.md); a
    /// colour set afterwards clears it.
    package var foregroundGradient: (any _GradientStyle)? {
        get { self[ForegroundGradientKey.self] }
        set { self[ForegroundGradientKey.self] = newValue }
    }
}

/// A shape style that takes its levels from the current foreground style: `.primary` keeps it,
/// the lower levels fade it (approximate: 50 %, 35 %, 25 % and 18 % of its opacity).
public struct HierarchicalShapeStyle: ShapeStyle, Hashable, Sendable {
    package let level: Int
    package init(level: Int) { self.level = level }

    public static let primary = HierarchicalShapeStyle(level: 0)
    public static let secondary = HierarchicalShapeStyle(level: 1)
    public static let tertiary = HierarchicalShapeStyle(level: 2)
    public static let quaternary = HierarchicalShapeStyle(level: 3)
    public static let quinary = HierarchicalShapeStyle(level: 4)

    package var opacity: Double { [1, 0.5, 0.35, 0.25, 0.18][min(level, 4)] }

    /// The colour a level below the first resolves to when no foreground colour is set: the
    /// secondary label, then on macOS the primary faded by the level; on an iPhone the tertiary
    /// and quaternary labels are the secondary at half and 0.3 (ios/color/system: (60, 60, 67)
    /// at 60 %, 30 % and 18 %).
    package func color(foreground: Color?, isIOS: Bool) -> Color {
        if let foreground { return foreground.opacity(opacity) }
        if level == 1 { return Color.secondary }
        if isIOS { return Color.secondary.opacity(level == 2 ? 0.5 : 0.3) }
        return Color.primary.opacity(opacity)
    }
}

/// A background material: the content beneath, blurred, under a tint of the appearance's
/// ground (`ultraThin` … `ultraThick`, and `bar`, the material of a toolbar). The substrate
/// blurs what the view is over (`backdropBlur`); the tint is white in the light appearance and
/// near-black in the dark one, at an alpha that grows with the thickness (iOS 17 measured
/// over black and white: ultra-thin 0.55 / thin 0.7 / regular 0.82 / thick 0.9 / ultra-thick
/// 0.96; the bar is the regular material).
public struct Material: ShapeStyle, Hashable, Sendable {
    package enum Thickness: Hashable, Sendable { case ultraThin, thin, regular, thick, ultraThick, bar }
    package let thickness: Thickness
    package init(thickness: Thickness) { self.thickness = thickness }

    public static let ultraThinMaterial = Material(thickness: .ultraThin)
    public static let thinMaterial = Material(thickness: .thin)
    public static let regularMaterial = Material(thickness: .regular)
    public static let thickMaterial = Material(thickness: .thick)
    public static let ultraThickMaterial = Material(thickness: .ultraThick)
    public static let bar = Material(thickness: .bar)

    package var tintAlpha: Double {
        switch thickness {
        case .ultraThin: return 0.55
        case .thin: return 0.7
        case .regular, .bar: return 0.82
        case .thick: return 0.9
        case .ultraThick: return 0.96
        }
    }
    package var blurRadius: CGFloat {
        switch thickness {
        case .ultraThin: return 12
        case .thin: return 16
        case .regular, .bar: return 20
        case .thick: return 24
        case .ultraThick: return 28
        }
    }

    /// The tint over the blur, for the appearance.
    package func tint(in environment: EnvironmentValues) -> RGBA {
        environment.colorScheme == .dark ? RGBA(red: 0.12, green: 0.12, blue: 0.12, alpha: tintAlpha) : RGBA(red: 1, green: 1, blue: 1, alpha: tintAlpha)
    }

    /// Paints the material under `path`: the backdrop blurred within it, then the tint.
    @MainActor
    package func _fill(_ path: Path, in bounds: CGRect, environment: EnvironmentValues, into list: inout DisplayList) {
        list.append(.backdropBlur(path, bounds: bounds, radius: blurRadius))
        list.append(.fillPath(path, tint(in: environment), eoFill: false))
    }
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThinMaterial }
    public static var thinMaterial: Material { .thinMaterial }
    public static var regularMaterial: Material { .regularMaterial }
    public static var thickMaterial: Material { .thickMaterial }
    public static var ultraThickMaterial: Material { .ultraThickMaterial }
    public static var bar: Material { .bar }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
    public static var quinary: HierarchicalShapeStyle { .quinary }
}

extension View {
    /// Sets a view's foreground elements to use a given style: a colour or a gradient replaces
    /// the inherited style; a hierarchical style keeps it (`.primary`) or fades it; other styles
    /// (`.foreground`) leave it.
    nonisolated public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        modifier(_ForegroundStyleModifier(style: style))
    }

    /// Sets the color of the foreground elements displayed by this view.
    nonisolated public func foregroundColor(_ color: Color?) -> some View {
        modifier(_ForegroundColorModifier(color: color))
    }
}

/// `foregroundStyle`: a modifier of its own rather than a closure over the environment, so a
/// body evaluated again with the same style compares equal and hands its content the same
/// environment generation (new-website#216: every keystroke re-measured each styled row).
public struct _ForegroundStyleModifier<S: ShapeStyle> {
    package var style: S
}

extension _ForegroundStyleModifier: Equatable where S: Equatable {}

extension _ForegroundStyleModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ environment: inout EnvironmentValues) {
        if let color = style as? Color {
            environment.foregroundColor = color
            environment.foregroundGradient = nil
        } else if let level = style as? HierarchicalShapeStyle {
            if level.level > 0 {
                // Fading a gradient is not supported: the level applies to the colour.
                environment.foregroundColor = level.color(foreground: environment.foregroundColor, isIOS: environment.platformProfile.isIOS)
                environment.foregroundGradient = nil
            }
        } else {
            // Gradient conformances are main-actor isolated; the cast must run there.
            let gradient: (any _GradientStyle)? = MainActor.assumeIsolated { style as? any _GradientStyle }
            if let gradient { environment.foregroundGradient = gradient }
        }
    }

    @MainActor
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

/// `foregroundColor`: equal when the colour is (see `_ForegroundStyleModifier`).
public struct _ForegroundColorModifier: Equatable {
    package var color: Color?
}

extension _ForegroundColorModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ environment: inout EnvironmentValues) {
        environment.foregroundColor = color
        environment.foregroundGradient = nil
    }

    @MainActor
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

/// A gradient style held by a `Text` (a class so the text's modifiers stay `Equatable`).
package final class _GradientBox: Equatable, @unchecked Sendable {
    package let style: any _GradientStyle
    package init(_ style: any _GradientStyle) { self.style = style }
    package static func == (lhs: _GradientBox, rhs: _GradientBox) -> Bool { lhs === rhs }
}

/// The background style: the window's ground (white in the light appearance, black in the
/// dark one on iOS), as `.fill(.background)` paints it.
public struct BackgroundStyle: ShapeStyle, Hashable, Sendable {
    public init() {}
}

extension ShapeStyle where Self == BackgroundStyle {
    /// The current background style.
    nonisolated public static var background: BackgroundStyle { BackgroundStyle() }
}

package struct BackgroundStyleKey: EnvironmentKey {
    package static let defaultValue: AnyShapeStyle? = nil
}

extension EnvironmentValues {
    /// The style `.background` resolves to below a `backgroundStyle(_:)` (the window's ground
    /// when unset).
    package var _backgroundStyle: AnyShapeStyle? {
        get { self[BackgroundStyleKey.self] }
        set { self[BackgroundStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the specified style to render backgrounds within the view: `.background` in it
    /// resolves to the style.
    nonisolated public func backgroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        environment(\._backgroundStyle, AnyShapeStyle(style))
    }
}

/// An overlay fill style for filling shapes: the system fill, a translucent grey (iOS
/// `systemFill`: (120, 120, 128) at 20 % in the light appearance, 36 % in the dark one).
public struct FillShapeStyle: ShapeStyle, _ModifiedStyle {
    public init() {}
    package var _alpha: Double { 1 }
    package func _resolveBaseColor(in environment: EnvironmentValues) -> RGBA {
        if environment.platformProfile.isIOS {
            return RGBA(r: 120, g: 120, b: 128, a: environment._isDark ? 0.36 : 0.2)
        }
        return environment._ink(0.1)
    }
}

extension ShapeStyle where Self == FillShapeStyle {
    /// An overlay fill style for filling shapes.
    nonisolated public static var fill: FillShapeStyle { FillShapeStyle() }
}

/// A style appropriate for foreground separator or border lines (iOS `separator`: (60, 60, 67)
/// at 29 % in the light appearance, (84, 84, 88) at 60 % in the dark one).
public struct SeparatorShapeStyle: ShapeStyle, _ModifiedStyle {
    public init() {}
    package var _alpha: Double { 1 }
    package func _resolveBaseColor(in environment: EnvironmentValues) -> RGBA {
        if environment.platformProfile.isIOS {
            return environment._isDark ? RGBA(r: 84, g: 84, b: 88, a: 0.6) : RGBA(r: 60, g: 60, b: 67, a: 0.29)
        }
        return environment._ink(0.1)
    }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
    /// A style appropriate for foreground separator or border lines.
    nonisolated public static var separator: SeparatorShapeStyle { SeparatorShapeStyle() }
}

/// A shadow a shape style casts: dropped behind the shape, or inside its edge.
public struct ShadowStyle: Equatable, Sendable {
    package enum Kind: Equatable, Sendable { case drop, inner }
    package let kind: Kind
    package let color: Color
    package let radius: CGFloat
    package let x: CGFloat
    package let y: CGFloat

    /// A shadow behind the shape.
    public static func drop(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle {
        ShadowStyle(kind: .drop, color: color, radius: radius, x: x, y: y)
    }

    /// A shadow inside the shape's edge.
    public static func inner(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.55), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> ShadowStyle {
        ShadowStyle(kind: .inner, color: color, radius: radius, x: x, y: y)
    }
}

/// A style with a shadow (`.white.shadow(.drop(radius: 2))`). The shape paints in the base
/// style; the shadow is kept for the painter but not drawn yet (Docs/elements/Shape.md).
public struct _ShadowShapeStyle<Base: ShapeStyle>: ShapeStyle, _ModifiedStyle {
    package let base: Base
    package let shadow: ShadowStyle
    package var _alpha: Double { 1 }
    package func _resolveBaseColor(in environment: EnvironmentValues) -> RGBA { base.resolveColor(in: environment) }
}

extension ShapeStyle {
    /// The style with a shadow.
    nonisolated public func shadow(_ style: ShadowStyle) -> _ShadowShapeStyle<Self> {
        _ShadowShapeStyle(base: self, shadow: style)
    }
}
