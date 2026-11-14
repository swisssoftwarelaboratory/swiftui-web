// SF Symbol variants and rendering modes: `symbolVariant` resolves to the named variant symbol
// (`star` + `.fill` → `star.fill`) when the stand-in table has it; rendering modes are accepted,
// the single-layer stand-ins keep the first foreground colour. Docs/elements/Symbol.md.

/// Variants of a symbol: the enclosing shape, filling and the slash, combinable (`.circle.fill`).
public struct SymbolVariants: Hashable, Sendable {
    package enum Shape: String, Sendable { case circle, square, rectangle }
    package var shape: Shape?
    package var isFilled = false
    package var isSlashed = false

    package init(shape: Shape? = nil, isFilled: Bool = false, isSlashed: Bool = false) {
        self.shape = shape
        self.isFilled = isFilled
        self.isSlashed = isSlashed
    }

    /// No variant: the symbol as named.
    public static let none = SymbolVariants()
    public static let circle = SymbolVariants(shape: .circle)
    public static let square = SymbolVariants(shape: .square)
    public static let rectangle = SymbolVariants(shape: .rectangle)
    public static let fill = SymbolVariants(isFilled: true)
    public static let slash = SymbolVariants(isSlashed: true)

    public var circle: SymbolVariants { var v = self; v.shape = .circle; return v }
    public var square: SymbolVariants { var v = self; v.shape = .square; return v }
    public var rectangle: SymbolVariants { var v = self; v.shape = .rectangle; return v }
    public var fill: SymbolVariants { var v = self; v.isFilled = true; return v }
    public var slash: SymbolVariants { var v = self; v.isSlashed = true; return v }

    /// Whether the variants contain the other's.
    public func contains(_ other: SymbolVariants) -> Bool {
        (other.shape == nil || other.shape == shape) && (!other.isFilled || isFilled) && (!other.isSlashed || isSlashed)
    }

    /// `self` with `other`'s variants added.
    package func union(_ other: SymbolVariants) -> SymbolVariants {
        SymbolVariants(shape: other.shape ?? shape, isFilled: isFilled || other.isFilled, isSlashed: isSlashed || other.isSlashed)
    }

    /// The candidate names for a base symbol, most specific first: `bell.slash.circle.fill`,
    /// then without the fill, the shape and the slash in turn, ending with the base name.
    package func names(for base: String) -> [String] {
        var candidates: [String] = []
        for slashed in (isSlashed ? [true, false] : [false]) {
            for shaped in (shape != nil ? [true, false] : [false]) {
                for filled in (isFilled ? [true, false] : [false]) {
                    var name = base
                    if slashed { name += ".slash" }
                    if shaped, let shape { name += "." + shape.rawValue }
                    if filled { name += ".fill" }
                    if !candidates.contains(name) { candidates.append(name) }
                }
            }
        }
        return candidates
    }
}

/// How a symbol's layers are coloured. The stand-in glyphs have one layer, so every mode draws
/// with the first foreground colour.
public struct SymbolRenderingMode: Hashable, Sendable {
    package let name: String
    public static let monochrome = SymbolRenderingMode(name: "monochrome")
    public static let hierarchical = SymbolRenderingMode(name: "hierarchical")
    public static let palette = SymbolRenderingMode(name: "palette")
    public static let multicolor = SymbolRenderingMode(name: "multicolor")
}

package struct SymbolVariantsKey: EnvironmentKey {
    package static let defaultValue = SymbolVariants.none
}

package struct SymbolRenderingModeKey: EnvironmentKey {
    package static let defaultValue: SymbolRenderingMode? = nil
}

extension EnvironmentValues {
    /// The symbol variants applied to images in this environment.
    public var symbolVariants: SymbolVariants {
        get { self[SymbolVariantsKey.self] }
        set { self[SymbolVariantsKey.self] = newValue }
    }

    /// The symbol rendering mode of this environment.
    public var symbolRenderingMode: SymbolRenderingMode? {
        get { self[SymbolRenderingModeKey.self] }
        set { self[SymbolRenderingModeKey.self] = newValue }
    }
}

extension View {
    /// Makes symbols within the view show a particular variant, added to any set by ancestors;
    /// `.none` resets them.
    nonisolated public func symbolVariant(_ variant: SymbolVariants) -> some View {
        _transformEnvironment("symbolVariant", key: variant) { environment in
            var current = environment.symbolVariants
            defer { environment.symbolVariants = current }
            current = variant == .none ? .none : current.union(variant)
        }
    }

    /// Sets the rendering mode for symbol images within this view.
    nonisolated public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> some View {
        environment(\.symbolRenderingMode, mode)
    }

    /// Sets a primary and secondary style; the stand-in symbols use the primary.
    nonisolated public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        foregroundStyle(primary)
    }

    /// Sets primary, secondary and tertiary styles; the stand-in symbols use the primary.
    nonisolated public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(_ primary: S1, _ secondary: S2, _ tertiary: S3) -> some View {
        foregroundStyle(primary)
    }
}

extension Image {
    /// Sets the rendering mode of this symbol image (accepted; single-layer stand-ins).
    public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Image { self }
}
