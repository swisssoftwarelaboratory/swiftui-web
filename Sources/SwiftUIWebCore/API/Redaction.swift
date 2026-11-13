// Redaction: `redacted(reason:)` replaces text and images with placeholders, `privacySensitive`
// marks views the privacy reason hides, `unredacted` opts out. Docs/elements/Redaction.md.

/// The reasons a view is redacted; the environment's `redactionReasons`.
public struct RedactionReasons: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Text and images become placeholder bars.
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
    /// Views marked `privacySensitive` become placeholders.
    public static let privacy = RedactionReasons(rawValue: 1 << 1)
    /// The data is stale; SwiftUI draws it as it is, and so does this.
    public static let invalidated = RedactionReasons(rawValue: 1 << 2)
}

package struct RedactionReasonsKey: EnvironmentKey {
    package static let defaultValue = RedactionReasons()
}

package struct PrivacySensitiveKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// The reasons to apply redaction to content.
    public var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }

    package var _isPrivacySensitive: Bool {
        get { self[PrivacySensitiveKey.self] }
        set { self[PrivacySensitiveKey.self] = newValue }
    }

    /// Whether text lays out as a placeholder (every character at the placeholder advance,
    /// spaces at their own): the placeholder reason on content that is not privacy-sensitive
    /// (measured: a `privacySensitive` text under `.placeholder` alone draws as itself).
    package var _usesPlaceholderLayout: Bool {
        redactionReasons.contains(.placeholder) && !_isPrivacySensitive
    }

    /// Whether text and images draw as placeholder bars: the placeholder layout, or the privacy
    /// reason on privacy-sensitive content (which keeps its plain layout under the bars).
    package var _drawsPlaceholders: Bool {
        _usesPlaceholderLayout || (redactionReasons.contains(.privacy) && _isPrivacySensitive)
    }

    /// The placeholder's ink: 13.7 % black (light) or white (dark), measured on
    /// `redacted/placeholder`.
    package var _placeholderColor: RGBA { _ink(0.137) }
}

extension View {
    /// Adds the given reasons to the environment's redaction reasons.
    nonisolated public func redacted(reason: RedactionReasons) -> some View {
        _transformEnvironment("redacted", key: reason.rawValue) { $0.redactionReasons.formUnion(reason) }
    }

    /// Removes any redaction applied by an ancestor.
    nonisolated public func unredacted() -> some View {
        environment(\.redactionReasons, RedactionReasons())
    }

    /// Marks the view as containing sensitive data, redacted under the privacy reason.
    nonisolated public func privacySensitive(_ sensitive: Bool = true) -> some View {
        environment(\._isPrivacySensitive, sensitive)
    }
}

/// The placeholder bar for one text line: the font's cap height rounded up to the half point,
/// standing on the baseline, with corners a fifth of that height (measured 2026-09-04: 9.5 pt
/// at 13 pt, 16 pt at the 22 pt title).
package enum _Placeholder {
    /// The advance every character takes in a placeholder layout, spaces included, measured
    /// per point size (`redacted/widths`, 2026-09-04; SF's optical sizes make it no fixed
    /// fraction of the size); sizes in between interpolate, beyond the ends scale.
    private static let advances: [(size: CGFloat, glyph: CGFloat, space: CGFloat)] = [
        (11, 5.45, 5.45), (13, 6.30, 6.30), (17, 7.90, 7.90), (22, 10.50, 10.50), (26, 12.95, 12.95),
    ]

    /// The character a placeholder layout is made of: one per character of the text, with no
    /// break opportunities, so lines wrap by character as SwiftUI's do.
    package static let character: Character = "\u{2588}"

    private typealias Advance = (size: CGFloat, glyph: CGFloat, space: CGFloat)

    private static func interpolate(_ size: CGFloat, _ value: (Advance) -> CGFloat) -> CGFloat {
        if size <= advances[0].size { return value(advances[0]) * size / advances[0].size }
        for i in 1..<advances.count where size <= advances[i].size {
            let a = advances[i - 1], b = advances[i]
            let t = (size - a.size) / (b.size - a.size)
            return value(a) + (value(b) - value(a)) * t
        }
        let last = advances[advances.count - 1]
        return value(last) * size / last.size
    }

    package static func advance(for font: ResolvedFont) -> CGFloat { interpolate(font.size) { $0.glyph } }
    package static func spaceAdvance(for font: ResolvedFont) -> CGFloat { interpolate(font.size) { $0.space } }

    /// The width a string takes in a placeholder layout: one advance per character, rounded to
    /// the nearest half point (nine characters at 6.3 make 56.5, not the 57 the layouter's
    /// rounding of measured text would give).
    package static func width(of text: String, font: ResolvedFont) -> CGFloat {
        ((CGFloat(text.count) * advance(for: font)) * 2).rounded() / 2
    }

    package static func barHeight(for font: ResolvedFont, profile: PlatformProfile) -> CGFloat {
        let measured = profile.systemFontMetrics(for: font).capHeight
        let capHeight = measured > 0 ? measured : font.size * 0.7046
        return (capHeight * 2).rounded(.up) / 2
    }

    package static func bar(lineX: CGFloat, baseline: CGFloat, width: CGFloat, font: ResolvedFont, profile: PlatformProfile) -> (rect: CGRect, radius: CGFloat) {
        let height = barHeight(for: font, profile: profile)
        return (CGRect(x: lineX, y: baseline - height, width: width, height: height), height / 5)
    }
}
