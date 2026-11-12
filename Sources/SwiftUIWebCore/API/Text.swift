import WebFoundation

/// The key used to look up an entry in a strings file or strings dictionary file.
@frozen
public struct LocalizedStringKey: Equatable, Sendable, ExpressibleByStringInterpolation {
    package var key: String

    public init(_ value: String) { key = value }
    public init(stringLiteral value: String) { key = value }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.output }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        package var output = ""
        public init(literalCapacity: Int, interpolationCount: Int) { output.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { output += literal }
        public mutating func appendInterpolation(_ string: String) { output += string }
        public mutating func appendInterpolation<S: StringProtocol>(_ string: S) { output += String(string) }
        public mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) { output += value.description }
        public mutating func appendInterpolation<T>(_ value: T) { output += String(describing: value) }
        public mutating func appendInterpolation(_ text: Text) { output += text.resolvedString }
        /// A number written with a printf specifier: `"\(value, specifier: "%.1f")"`.
        public mutating func appendInterpolation<T: CVarArg>(_ value: T, specifier: String) {
            output += String(format: specifier, value)
        }
        /// A value written by a format style: `"\(date, format: .dateTime.year())"`.
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
            output += format.format(input)
        }
        /// A value written by a formatter; nothing when the formatter cannot represent it.
        public mutating func appendInterpolation<Subject: AnyObject>(_ subject: Subject, formatter: Formatter?) {
            output += formatter?.string(for: subject) ?? String(describing: subject)
        }
    }
}

/// An alignment position for text along the horizontal axis.
public enum TextAlignment: Hashable, CaseIterable, Sendable {
    case leading, center, trailing
}

/// A view that displays one or more lines of read-only text.
public struct Text: Equatable, Sendable {
    public typealias TruncationMode = TextTruncationMode
    public typealias Scale = TextScale
    package enum Storage: Equatable, Sendable {
        case verbatim(String)
        /// A literal: its inline markdown is interpreted (`Docs/elements/Text.md`, "Rich text").
        case localized(LocalizedStringKey)
        case concatenated([Text])
        /// An image laid out like a glyph (`Text(Image)`).
        case image(Image)
        /// A date shown by a style, the live ones against the current instant.
        case date(Date, DateStyle)
    }

    /// A style for drawing a line under or through text.
    public struct LineStyle: Hashable, Sendable {
        /// The pattern of the line: continuous, or repeated dots and dashes.
        public enum Pattern: Hashable, Sendable {
            case solid, dot, dash, dashDot, dashDotDot
        }

        public var pattern: Pattern
        /// The colour of the line; `nil` draws it in the text's colour.
        public var color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        /// A solid line in the text's colour.
        public static let single = LineStyle()
    }

    /// A capitalisation applied to text.
    public enum Case: Hashable, CaseIterable, Sendable {
        case uppercase, lowercase
    }

    /// Modifiers applied on the `Text` value itself (they win over the environment). In a
    /// concatenation, a part's own modifiers win over the modifiers of the whole.
    package struct Modifiers: Equatable, Sendable {
        package var font: Font?
        package var weight: Font.Weight?
        package var bold = false
        package var italic = false
        package var foregroundColor: Color?
        /// A gradient foreground style set on the text itself (`Text.foregroundStyle`).
        package var foregroundGradient: _GradientBox?
        /// Decorations: unset (inherit), explicitly off (`.some(nil)`), or a line style.
        package var underline: LineStyle?? = nil
        package var strikethrough: LineStyle?? = nil
        package var baselineOffset: CGFloat?
        package var kerning: CGFloat?
        package var tracking: CGFloat?
        /// Markdown code spans and the `.code` intent: the font's monospaced design.
        package var monospaced = false
        /// `monospacedDigit()`: the font's tabular figures.
        package var monospacedDigit = false
        /// `fontDesign(_:)`: the design of a system font (an explicit design of the font wins).
        package var design: Font.Design?
        /// A link (markdown `[text](url)`, the `link` attribute): accent-coloured, pressable.
        package var link: URL?

        /// `self` applied on top of the enclosing text's modifiers.
        package func inheriting(_ parent: Modifiers) -> Modifiers {
            var result = Modifiers(font: font ?? parent.font, weight: weight ?? parent.weight, bold: bold || parent.bold,
                                   italic: italic || parent.italic, foregroundColor: foregroundColor ?? parent.foregroundColor,
                                   foregroundGradient: foregroundColor != nil ? nil : (foregroundGradient ?? parent.foregroundGradient))
            result.underline = underline ?? parent.underline
            result.strikethrough = strikethrough ?? parent.strikethrough
            result.baselineOffset = baselineOffset ?? parent.baselineOffset
            result.kerning = kerning ?? parent.kerning
            result.tracking = tracking ?? parent.tracking
            result.monospaced = monospaced || parent.monospaced
            result.monospacedDigit = monospacedDigit || parent.monospacedDigit
            result.design = design ?? parent.design
            result.link = link ?? parent.link
            return result
        }
    }

    /// One leaf of a (possibly concatenated) text with every modifier resolved.
    package struct Part: Equatable, Sendable {
        package var string: String
        package var modifiers: Modifiers
        /// An inline image: `string` is one object replacement character standing for it.
        package var image: Image? = nil
    }

    /// The character an inline image occupies in the layout.
    package static let objectReplacement = "\u{FFFC}"

    package let storage: Storage
    /// What assistive technology reads instead of the text, and its heading level (0: a
    /// heading of no level): `Text.accessibilityLabel` and `Text.accessibilityHeading`.
    package var accessibilityLabelOverride: String?
    package var accessibilityHeadingLevel: Int?
    package var modifiers = Modifiers()

    /// Creates a text view that displays a string literal without localization.
    public init(verbatim content: String) {
        storage = .verbatim(content)
    }

    /// Creates a text view that displays a stored string without localization.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ content: S) {
        storage = .verbatim(String(content))
    }

    /// Creates a text view that displays localized content identified by a key (looked up in no
    /// table yet: the key shows, its markdown interpreted).
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
        storage = .localized(key)
    }

    /// Creates a text view that displays a localized string resource: the string its table
    /// gives, else its default value.
    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) {
        #if os(WASI) || os(Linux)
        storage = .verbatim(resource.description)
        #else
        storage = .verbatim(String(localized: resource))
        #endif
    }

    /// The displayed string (localization is identity until Phase 3; markdown markup removed).
    package var resolvedString: String {
        switch storage {
        case .verbatim(let s): return s
        case .localized(let key): return _InlineMarkdown.parse(key.key).map(\.text).joined()
        case .concatenated(let parts): return parts.map(\.resolvedString).joined()
        case .image: return ""
        case .date(let date, let style): return _DateText.string(for: date, style: style, context: .current)
        }
    }

    /// Whether the text shows a date that moves with the clock.
    package var isLive: Bool {
        switch storage {
        case .date(_, let style): return style.isLive
        case .concatenated(let parts): return parts.contains(where: \.isLive)
        default: return false
        }
    }

    /// The leaves of this text in order, each with the modifiers that apply to it.
    package func parts(inheriting parent: Modifiers = Modifiers(), context: _TextContext? = nil) -> [Part] {
        let effective = modifiers.inheriting(parent)
        switch storage {
        case .verbatim(let s): return [Part(string: s, modifiers: effective)]
        case .localized(let key):
            return _InlineMarkdown.parse(key.key).map { run in
                var modifiers = effective
                if run.bold { modifiers.bold = true }
                if run.italic { modifiers.italic = true }
                if run.code { modifiers.monospaced = true }
                if run.strikethrough { modifiers.strikethrough = .some(LineStyle()) }
                if let link = run.link, let url = URL(string: link) { modifiers.link = url }
                return Part(string: run.text, modifiers: modifiers)
            }
        case .concatenated(let texts): return texts.flatMap { $0.parts(inheriting: effective, context: context) }
        case .image(let image): return [Part(string: Self.objectReplacement, modifiers: effective, image: image)]
        case .date(let date, let style): return [Part(string: _DateText.string(for: date, style: style, context: context ?? .current), modifiers: effective)]
        }
    }

    // MARK: Text-level modifiers (return Text, as in SwiftUI)

    public func font(_ font: Font?) -> Text { var t = self; t.modifiers.font = font; return t }
    public func fontWeight(_ weight: Font.Weight?) -> Text { var t = self; t.modifiers.weight = weight; return t }
    /// See `Font.bold()`: the bold trait resolves per text style.
    public func bold() -> Text { var t = self; t.modifiers.bold = true; return t }
    public func bold(_ isActive: Bool) -> Text { isActive ? bold() : self }
    public func italic() -> Text { var t = self; t.modifiers.italic = true; return t }
    /// Fixed-width digits (the font's tabular figures), as `Font.monospacedDigit()`.
    public func monospacedDigit() -> Text { var t = self; t.modifiers.monospacedDigit = true; return t }
    /// Sets the font design of the text (rounded, serif, monospaced) when its font is a system
    /// font without a design of its own.
    public func fontDesign(_ design: Font.Design?) -> Text { var t = self; t.modifiers.design = design; return t }
    /// Sets the font width of the text. Stored only: the text engine draws one width.
    public func fontWidth(_ width: Font.Width?) -> Text { self }
    /// The monospaced design (`Font.monospaced()`), for the whole text.
    public func monospaced(_ isActive: Bool = true) -> Text { var t = self; t.modifiers.monospaced = isActive; return t }
    public func italic(_ isActive: Bool) -> Text { isActive ? italic() : self }
    public func foregroundColor(_ color: Color?) -> Text {
        var t = self
        t.modifiers.foregroundColor = color
        t.modifiers.foregroundGradient = nil
        return t
    }

    /// A colour or gradient replaces the text's style; a hierarchical style keeps it (`.primary`)
    /// or fades it; other styles leave it (`View.foregroundStyle`).
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        var t = self
        if let color = style as? Color {
            t.modifiers.foregroundColor = color
            t.modifiers.foregroundGradient = nil
        } else if let level = style as? HierarchicalShapeStyle {
            if level.level > 0 {
                // Resolved for macOS here (a Text carries no environment); an iPhone's tertiary
                // and quaternary differ only as fills and environment styles.
                t.modifiers.foregroundColor = level.color(foreground: t.modifiers.foregroundColor, isIOS: false)
                t.modifiers.foregroundGradient = nil
            }
        } else if let gradient = MainActor.assumeIsolated({ style as? any _GradientStyle }) {
            t.modifiers.foregroundColor = nil
            t.modifiers.foregroundGradient = _GradientBox(gradient)
        }
        return t
    }

    /// Applies an underline to the text.
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        var t = self
        t.modifiers.underline = .some(isActive ? LineStyle(pattern: pattern, color: color) : nil)
        return t
    }

    /// Applies a strikethrough to the text.
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        var t = self
        t.modifiers.strikethrough = .some(isActive ? LineStyle(pattern: pattern, color: color) : nil)
        return t
    }

    /// Sets the vertical offset for the text relative to its baseline (positive raises it).
    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        var t = self
        t.modifiers.baselineOffset = baselineOffset
        return t
    }

    /// Concatenates the text of two text views.
    public static func + (lhs: Text, rhs: Text) -> Text {
        Text(storage: .concatenated([lhs, rhs]))
    }

    package init(storage: Storage) {
        self.storage = storage
    }
}

extension Text: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<Text>) -> TypedNode<Text> {
        TextNode(context)
    }
}

// MARK: - Environment (line limit, alignment, truncation, spacing)

package struct LineLimitKey: EnvironmentKey { package static let defaultValue: Int? = nil }
package struct MinimumLinesKey: EnvironmentKey { package static let defaultValue = 0 }
package struct MultilineTextAlignmentKey: EnvironmentKey { package static let defaultValue = TextAlignment.leading }

extension EnvironmentValues {
    /// Where lines sit in a text's frame, 0 at the left and 1 at the right: `leading` and
    /// `trailing` follow the layout direction (sw-rtl, `layout/rtl-text`).
    package var _resolvedTextAlignment: CGFloat {
        let rightToLeft = layoutDirection == .rightToLeft
        switch multilineTextAlignment {
        case .leading: return rightToLeft ? 1 : 0
        case .center: return 0.5
        case .trailing: return rightToLeft ? 0 : 1
        }
    }
}
package struct TruncationModeKey: EnvironmentKey { package static let defaultValue = Text.TruncationMode.tail }
package struct LineSpacingKey: EnvironmentKey { package static let defaultValue: CGFloat = 0 }
package struct AllowsTighteningKey: EnvironmentKey { package static let defaultValue = false }
package struct MinimumScaleFactorKey: EnvironmentKey { package static let defaultValue: CGFloat = 1 }
package struct TextCaseKey: EnvironmentKey { package static let defaultValue: Text.Case? = nil }
package struct UnderlineStyleKey: EnvironmentKey { package static let defaultValue: Text.LineStyle? = nil }
package struct StrikethroughStyleKey: EnvironmentKey { package static let defaultValue: Text.LineStyle? = nil }
package struct BaselineOffsetKey: EnvironmentKey { package static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    /// The maximum number of lines that text can occupy in a view.
    public var lineLimit: Int? {
        get { self[LineLimitKey.self] }
        set { self[LineLimitKey.self] = newValue }
    }

    /// Lines whose height text reserves even when it is shorter (`lineLimit(_:reservesSpace:)`,
    /// the lower bound of a range limit).
    package var minimumLines: Int {
        get { self[MinimumLinesKey.self] }
        set { self[MinimumLinesKey.self] = newValue }
    }

    /// An environment value that indicates how a text view aligns its lines when the content
    /// wraps or contains newlines.
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }

    /// A value that indicates how the layout truncates the last line of text to fit into the
    /// available space.
    public var truncationMode: Text.TruncationMode {
        get { self[TruncationModeKey.self] }
        set { self[TruncationModeKey.self] = newValue }
    }

    /// The distance in points between the bottom of one line fragment and the top of the next.
    public var lineSpacing: CGFloat {
        get { self[LineSpacingKey.self] }
        set { self[LineSpacingKey.self] = newValue }
    }

    /// Whether inter-character spacing should tighten to fit the text into the available space.
    /// Stored, not applied.
    public var allowsTightening: Bool {
        get { self[AllowsTighteningKey.self] }
        set { self[AllowsTighteningKey.self] = newValue }
    }

    /// The minimum permissible proportion to shrink the font size to fit the text. Stored, not applied.
    public var minimumScaleFactor: CGFloat {
        get { self[MinimumScaleFactorKey.self] }
        set { self[MinimumScaleFactorKey.self] = newValue }
    }

    /// A stylistic override to transform the case of text in this environment (`View.textCase`).
    public var textCase: Text.Case? {
        get { self[TextCaseKey.self] }
        set { self[TextCaseKey.self] = newValue }
    }

    /// The underline of text in this environment (`View.underline`).
    package var _underlineStyle: Text.LineStyle? {
        get { self[UnderlineStyleKey.self] }
        set { self[UnderlineStyleKey.self] = newValue }
    }

    /// The strikethrough of text in this environment (`View.strikethrough`).
    package var _strikethroughStyle: Text.LineStyle? {
        get { self[StrikethroughStyleKey.self] }
        set { self[StrikethroughStyleKey.self] = newValue }
    }

    /// The baseline offset of text in this environment (`View.baselineOffset`).
    package var _baselineOffset: CGFloat {
        get { self[BaselineOffsetKey.self] }
        set { self[BaselineOffsetKey.self] = newValue }
    }

    package var textLayoutOptions: TextLayoutOptions {
        TextLayoutOptions(lineLimit: lineLimit, truncationMode: truncationMode, lineSpacing: lineSpacing, minimumLines: minimumLines,
                          kerning: _kerning, tracking: _tracking, textScale: _textScale, minimumScaleFactor: minimumScaleFactor, allowsTightening: allowsTightening)
    }

    /// The text scale of this environment (`View.textScale`).
    package var _textScale: Text.Scale {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }

    /// Whether text in this environment is selectable (`View.textSelection`).
    package var _textSelectionEnabled: Bool {
        get { self[TextSelectionKey.self] }
        set { self[TextSelectionKey.self] = newValue }
    }

    /// Letter spacing of text in this environment (`View.kerning`, `View.tracking`).
    package var _kerning: CGFloat {
        get { self[KerningKey.self] }
        set { self[KerningKey.self] = newValue }
    }

    package var _tracking: CGFloat {
        get { self[TrackingKey.self] }
        set { self[TrackingKey.self] = newValue }
    }
}

package struct KerningKey: EnvironmentKey {
    package static let defaultValue: CGFloat = 0
}

package struct TextScaleKey: EnvironmentKey {
    package static let defaultValue: Text.Scale = .default
}

package struct TextSelectionKey: EnvironmentKey {
    package static let defaultValue = false
}

/// Whether people can select text (`textSelection`).
public protocol TextSelectability {
    static var allowsSelection: Bool { get }
}

public struct EnabledTextSelectability: TextSelectability {
    public static let allowsSelection = true
}

public struct DisabledTextSelectability: TextSelectability {
    public static let allowsSelection = false
}

extension TextSelectability where Self == EnabledTextSelectability {
    public static var enabled: EnabledTextSelectability { EnabledTextSelectability() }
}

extension TextSelectability where Self == DisabledTextSelectability {
    public static var disabled: DisabledTextSelectability { DisabledTextSelectability() }
}

extension View {
    /// Applies a text scale to the text in this view. The secondary scale draws smaller glyphs
    /// (0.8 of the size up to 17 pt, less for larger fonts, with a weight-dependent tracking) on
    /// the font's own line height; serif and monospaced designs are not scaled.
    nonisolated public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> some View {
        environment(\._textScale, isEnabled ? scale : .default)
    }

    /// Controls whether people can select text in this view. Layout and painting do not change;
    /// the pointer shows an I-beam over selectable text.
    nonisolated public func textSelection<S: TextSelectability>(_ selectability: S) -> some View {
        environment(\._textSelectionEnabled, S.allowsSelection)
    }
}

package struct TrackingKey: EnvironmentKey {
    package static let defaultValue: CGFloat = 0
}

extension Text {
    /// Sets the spacing, or kerning, between characters.
    public func kerning(_ kerning: CGFloat) -> Text {
        var copy = self
        copy.modifiers.kerning = kerning
        return copy
    }

    /// Sets the tracking for the text.
    public func tracking(_ tracking: CGFloat) -> Text {
        var copy = self
        copy.modifiers.tracking = tracking
        return copy
    }
}

extension View {
    /// Sets the spacing, or kerning, between characters for the text in this view.
    nonisolated public func kerning(_ kerning: CGFloat) -> some View {
        environment(\._kerning, kerning)
    }

    /// Sets the tracking for the text in this view.
    nonisolated public func tracking(_ tracking: CGFloat) -> some View {
        environment(\._tracking, tracking)
    }
}

extension View {
    /// Sets the maximum number of lines that text can occupy in this view.
    nonisolated public func lineLimit(_ number: Int?) -> some View {
        environment(\.lineLimit, number).environment(\.minimumLines, 0)
    }

    /// Sets to a partial range the number of lines that text can occupy in this view: the lower
    /// bound reserves that many lines, there is no upper limit.
    nonisolated public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View {
        environment(\.lineLimit, nil).environment(\.minimumLines, limit.lowerBound)
    }

    nonisolated public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View {
        environment(\.lineLimit, limit.upperBound).environment(\.minimumLines, 0)
    }

    /// Sets to a closed range the number of lines text can occupy: the lower bound reserves
    /// lines, the upper bound truncates.
    nonisolated public func lineLimit(_ limit: ClosedRange<Int>) -> some View {
        environment(\.lineLimit, limit.upperBound).environment(\.minimumLines, limit.lowerBound)
    }

    /// Sets a limit for the number of lines text can occupy in this view, optionally reserving
    /// the space of that many lines.
    nonisolated public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View {
        environment(\.lineLimit, limit).environment(\.minimumLines, reservesSpace ? limit : 0)
    }

    /// Sets the alignment of a text view that contains multiple lines of text.
    nonisolated public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }

    /// Sets the truncation mode for lines of text that are too long to fit in the available space.
    nonisolated public func truncationMode(_ mode: Text.TruncationMode) -> some View {
        environment(\.truncationMode, mode)
    }

    /// Sets the amount of space between lines of text in this view.
    nonisolated public func lineSpacing(_ lineSpacing: CGFloat) -> some View {
        environment(\.lineSpacing, lineSpacing)
    }

    /// Sets whether text in this view can compress the space between characters when necessary
    /// to fit text in a line. Stored only.
    nonisolated public func allowsTightening(_ flag: Bool) -> some View {
        environment(\.allowsTightening, flag)
    }

    /// Sets the minimum amount that text in this view scales down to fit in the available space.
    /// Stored only.
    nonisolated public func minimumScaleFactor(_ factor: CGFloat) -> some View {
        environment(\.minimumScaleFactor, factor)
    }

    /// Sets a transform for the case of the text contained in this view.
    nonisolated public func textCase(_ textCase: Text.Case?) -> some View {
        environment(\.textCase, textCase)
    }

    /// Applies an underline to the text in this view.
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\._underlineStyle, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }

    /// Applies a strikethrough to the text in this view.
    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        environment(\._strikethroughStyle, isActive ? Text.LineStyle(pattern: pattern, color: color) : nil)
    }

    /// Sets the vertical offset for the text relative to its baseline in this view.
    nonisolated public func baselineOffset(_ baselineOffset: CGFloat) -> some View {
        environment(\._baselineOffset, baselineOffset)
    }
}

// MARK: - Node

/// Lays out a text run with the runtime's text engine.
@MainActor
package final class TextNode: LeafNode<Text>, _HoverTracking, _PointerStyled, _Interactive {
    /// The pointer over a link shows the hand; selectable text the I-beam.
    package var pointerStyle: PointerStyle? {
        if let point = hoverPoint, link(at: point) != nil { return .link }
        return environment._textSelectionEnabled ? .horizontalText : nil
    }
    private var hoverPoint: CGPoint?
    package func hoverChanged(inside: Bool, at point: CGPoint) {
        hoverPoint = inside ? point : nil
    }

    // MARK: Links (markdown `[text](url)`, the `link` attribute)

    /// Whether any part is a link: links and selectable text take presses.
    package var hasLinks: Bool { parts.contains { $0.modifiers.link != nil } }
    package var isInteractive: Bool { hasLinks || environment._textSelectionEnabled }

    // MARK: Selection (`textSelection(.enabled)`, sw-text-selection)

    /// The selected characters of the joined string, dragged out with the pointer.
    package private(set) var selection: Range<String.Index>?
    private var selectionAnchor: String.Index?

    /// The joined string the layout's line ranges index.
    package var joinedString: String { styledRuns.runs.map(\.string).joined() }

    /// The selected text, if any.
    package var selectedText: String? {
        guard let selection, !selection.isEmpty else { return nil }
        let joined = joinedString
        guard selection.upperBound <= joined.endIndex else { return nil }
        return String(joined[selection])
    }

    package func clearSelection() {
        guard selection != nil || selectionAnchor != nil else { return }
        selection = nil
        selectionAnchor = nil
        runtime.setNeedsDisplay()
    }

    /// The width of `prefix` in the run's font (the engine's layout at the text's scale). A
    /// layout drops a final line's trailing spaces, so a prefix ending in one is measured with a
    /// sentinel after it.
    private func prefixWidth(_ prefix: Substring, run: Int, runs: [StyledRun], scale: CGFloat) -> CGFloat {
        guard !prefix.isEmpty else { return 0 }
        let font = runs.indices.contains(run) ? runs[run].font : resolvedFont
        func width(_ text: String) -> CGFloat { runtime.textEngine.layout(text, font: font, width: nil).size.width }
        guard prefix.last == " " else { return width(String(prefix)) * scale }
        return (width(String(prefix) + "|") - width("|")) * scale
    }

    /// The character boundary nearest `point` (the node's coordinates): the line under the
    /// point (the first above it, the last below), then the boundary whose x is closest.
    package func characterIndex(at point: CGPoint) -> String.Index {
        let joined = joinedString
        let (runs, _) = styledRuns
        let layout = textLayout(width: frame.width, height: frame.height)
        guard let first = layout.lines.first else { return joined.startIndex }
        let alignment = environment._resolvedTextAlignment
        let shiftUp = baselineShift.up
        var chosen = first
        for line in layout.lines {
            let font = runs.indices.contains(line.fragments.first?.run ?? 0) ? runs[line.fragments.first?.run ?? 0].font : resolvedFont
            let metrics = environment.platformProfile.systemFontMetrics(for: font)
            let top = line.baseline + shiftUp - metrics.baseline
            chosen = line
            if point.y < top + metrics.lineHeight { break }
        }
        let line = chosen
        let lineX = (frame.width - line.inkWidth) * alignment
        guard line.range.upperBound <= joined.endIndex, line.range.lowerBound <= line.range.upperBound else { return joined.startIndex }
        let x = point.x - lineX
        if x <= 0 { return line.range.lowerBound }
        // Walk the line's characters by their prefix widths (one run per fragment).
        var index = line.range.lowerBound
        var fragmentStart = line.range.lowerBound
        for fragment in line.fragments {
            let fragmentEnd = joined.index(fragmentStart, offsetBy: fragment.text.count, limitedBy: line.range.upperBound) ?? line.range.upperBound
            if x >= fragment.x + fragment.width {
                index = fragmentEnd
                fragmentStart = fragmentEnd
                continue
            }
            var previousEdge = fragment.x
            var cursor = fragmentStart
            while cursor < fragmentEnd {
                let next = joined.index(after: cursor)
                let edge = fragment.x + prefixWidth(joined[fragmentStart..<next], run: fragment.run, runs: runs, scale: layout.scale)
                if x < (previousEdge + edge) / 2 { return cursor }
                previousEdge = edge
                cursor = next
            }
            return fragmentEnd
        }
        return index
    }

    /// The selection's highlight rects, per line (the node's coordinates).
    package func selectionRects() -> [CGRect] {
        guard let selection, !selection.isEmpty else { return [] }
        let joined = joinedString
        let (runs, _) = styledRuns
        let layout = textLayout(width: frame.width, height: frame.height)
        let alignment = environment._resolvedTextAlignment
        let shiftUp = baselineShift.up
        var rects: [CGRect] = []
        for line in layout.lines where line.range.upperBound <= joined.endIndex {
            let start = max(selection.lowerBound, line.range.lowerBound), end = min(selection.upperBound, line.range.upperBound)
            guard start < end else { continue }
            let font = runs.indices.contains(line.fragments.first?.run ?? 0) ? runs[line.fragments.first?.run ?? 0].font : resolvedFont
            let metrics = environment.platformProfile.systemFontMetrics(for: font)
            let top = line.baseline + shiftUp - metrics.baseline
            let lineX = (frame.width - line.inkWidth) * alignment
            func xOf(_ index: String.Index) -> CGFloat {
                var fragmentStart = line.range.lowerBound
                for fragment in line.fragments {
                    let fragmentEnd = joined.index(fragmentStart, offsetBy: fragment.text.count, limitedBy: line.range.upperBound) ?? line.range.upperBound
                    if index <= fragmentEnd {
                        return fragment.x + prefixWidth(joined[fragmentStart..<max(fragmentStart, index)], run: fragment.run, runs: runs, scale: layout.scale)
                    }
                    fragmentStart = fragmentEnd
                }
                return line.fragments.last.map { $0.x + $0.width } ?? 0
            }
            rects.append(CGRect(x: lineX + xOf(start), y: top, width: xOf(end) - xOf(start), height: metrics.lineHeight))
        }
        return rects
    }

    /// What the text resolves its parts against (dates in the environment's time zone).
    package var textContext: _TextContext { _TextContext(timeZone: environment.timeZone, calendar: environment.calendar) }

    /// The parts and styled runs for the current view and environment, kept until the next
    /// update: a paint reads them several times over, and a scroll frame paints every text.
    private var cachedParts: [Text.Part]?
    private var cachedStyledRuns: (runs: [StyledRun], colors: [Color?])?
    private func forgetParts() { cachedParts = nil; cachedStyledRuns = nil }
    package var parts: [Text.Part] {
        if let cachedParts { return cachedParts }
        let parts = view.parts(context: textContext)
        cachedParts = parts
        return parts
    }

    /// The link under `point` (the node's coordinates), if any.
    package func link(at point: CGPoint) -> URL? {
        let parts = self.parts
        guard parts.contains(where: { $0.modifiers.link != nil }) else { return nil }
        let (runs, _) = styledRuns
        let layout = textLayout(width: frame.width, height: frame.height)
        let alignment = environment._resolvedTextAlignment
        let shiftUp = baselineShift.up
        for line in layout.lines {
            let font = runs.indices.contains(line.fragments.first?.run ?? 0) ? runs[line.fragments.first?.run ?? 0].font : resolvedFont
            let metrics = environment.platformProfile.systemFontMetrics(for: font)
            let top = line.baseline + shiftUp - metrics.baseline, bottom = top + metrics.lineHeight
            guard point.y >= top, point.y < bottom else { continue }
            let lineX = (frame.width - line.inkWidth) * alignment
            for fragment in line.fragments where parts.indices.contains(fragment.run) {
                if point.x >= lineX + fragment.x, point.x < lineX + fragment.x + fragment.width { return parts[fragment.run].modifiers.link }
            }
        }
        return nil
    }

    private var pressedLink: URL?
    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        pressedLink = link(at: point)
        guard environment._textSelectionEnabled, pressedLink == nil else { return }
        // A press starts a new selection here (any other text's selection goes).
        runtime.textSelectionOwner = self
        selectionAnchor = characterIndex(at: point)
        if selection != nil { selection = nil; runtime.requestRepaint() }   // the selection is paint alone
    }
    package func pressMoved(to point: CGPoint) {
        guard let anchor = selectionAnchor else { return }
        let focus = characterIndex(at: point)
        let range = min(anchor, focus)..<max(anchor, focus)
        guard range != selection else { return }
        selection = range
        runtime.requestRepaint()
    }
    package func pressEnded(inside: Bool) { pressedLink = nil; selectionAnchor = nil }
    package func pressEnded(inside: Bool, at point: CGPoint) {
        defer { pressedLink = nil; selectionAnchor = nil }
        guard inside, environment.isEnabled, let pressed = pressedLink, link(at: point) == pressed else { return }
        environment.openURL(pressed)
    }

    package var semantics: SemanticsNode {
        SemanticsNode(role: .link, label: view.resolvedString, frame: frameInRoot, identifier: ObjectIdentifier(self).hashValue & 0x7fffffff)
    }

    // MARK: Live dates

    private var liveWake: Task<Void, Never>?

    /// A text with a relative, offset or timer date re-resolves every second.
    private func scheduleLiveRefresh() {
        guard view.isLive else {
            liveWake?.cancel(); liveWake = nil
            return
        }
        guard liveWake == nil else { return }
        liveWake = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.liveWake = nil
            self.invalidate()
            self.runtime.requestLayout()
        }
    }

    override package func unmount() {
        liveWake?.cancel()
        liveWake = nil
        super.unmount()
    }

    /// The previous text while a content transition runs: painted fading out (and rolling,
    /// for numeric text) as the new one fades in. The node's presentation opacity tween holds
    /// the progress so the runtime keeps animating it.
    package struct OutgoingText {
        package var view: Text
        package var environment: EnvironmentValues
        package var transition: ContentTransition
    }
    package private(set) var outgoing: OutgoingText?

    override package func update(view: Text, environment: EnvironmentValues, force: Bool) {
        let previousView = self.view, previousEnvironment = self.environment
        let previousRuns = styledRuns.runs
        super.update(view: view, environment: environment, force: force)
        forgetParts()
        scheduleLiveRefresh()
        let transition = environment.contentTransition
        guard transition.fades, styledRuns.runs != previousRuns,
              let animation = runtime.effectiveUpdateAnimation(for: self) else { return }
        outgoing = OutgoingText(view: previousView, environment: previousEnvironment,
                                transition: transition.resolved(from: previousEnvironment.contentTransition))
        let presentation = self.presentation ?? NodePresentation()
        presentation.opacity = Tween(from: [0], to: [1], animation: animation, start: runtime.animationClock)
        self.presentation = presentation
        runtime.register(animating: self)
    }

    /// Progress of the running content transition (1 when none).
    package var contentTransitionProgress: Double {
        guard outgoing != nil, let tween = presentation?.opacity else { outgoing = nil; return 1 }
        let value = tween.value(at: runtime.animationClock)[0]
        if tween.isFinished(at: runtime.animationClock) { outgoing = nil; return 1 }
        return value
    }

    package func resolveFont(_ modifiers: Text.Modifiers) -> ResolvedFont {
        let font = modifiers.font ?? environment.font ?? environment.platformProfile.defaultFont
        var resolved = font.resolve(in: environment)
        if let weight = modifiers.weight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if modifiers.bold {
            resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        } else if let weight = environment._fontWeight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if environment._boldTrait {
            resolved.weight = environment.platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        }
        if modifiers.italic || environment._italicTrait { resolved.italic = true }
        if resolved.family == "system", let design = modifiers.design ?? environment._fontDesign {
            resolved.family = Font.Design._familyName(design)
        }
        if modifiers.monospaced || environment._monospacedTrait, resolved.family.hasPrefix("system") { resolved.family = "system-monospaced" }
        if modifiers.monospacedDigit || environment._monospacedDigitTrait { resolved.tabularDigits = true }
        return resolved
    }

    /// The font of the text as a whole (its own modifiers over the environment); parts of a
    /// concatenation may differ.
    package var resolvedFont: ResolvedFont { resolveFont(view.modifiers) }

    /// The text's leaves as the engine sees them, with each part's colour; an inline image is a
    /// run one replacement character long measuring the symbol's width at the font.
    package var styledRuns: (runs: [StyledRun], colors: [Color?]) {
        if let cachedStyledRuns { return cachedStyledRuns }
        let parts = self.parts
        let result = (parts.map { part -> StyledRun in
            let font = resolveFont(part.modifiers)
            if let image = part.image {
                let size = inlineSymbol(for: image, font: font)?.size
                return StyledRun(part.string, font: font, inlineWidth: size?.width ?? 0, inlineHeight: size?.height)
            }
            return StyledRun(cased(part.string), font: font)
        }, parts.map(\.modifiers.foregroundColor))
        cachedStyledRuns = result
        return result
    }

    /// The glyph and size of an inline system image at `font` (`Image(systemName:)` only; other
    /// images take no space).
    package func inlineSymbol(for image: Image, font: ResolvedFont) -> (glyph: (glyph: SymbolGlyph, outline: SymbolGlyphOutline)?, size: SystemSymbolMetrics.Size)? {
        guard case .system(let base) = image.source else { return nil }
        let candidates = environment.symbolVariants.names(for: base)
        let legacy = environment.platformProfile.isIOS
        func measure(_ name: String) -> SystemSymbolMetrics.Size? {
            SystemSymbolMetrics.size(named: name, pointSize: font.size, weight: font.weight, scale: environment.imageScale, legacy: legacy, extended: runtime.extendedSymbolMetrics)
        }
        let name = candidates.first { SystemSymbolGlyphs.glyph(named: $0) != nil && measure($0) != nil }
            ?? candidates.first { SystemSymbolGlyphs.glyph(named: $0) != nil } ?? candidates.first { measure($0) != nil } ?? base
        let glyph = SystemSymbolGlyphs.glyph(named: name) ?? (measure(name) != nil ? SystemSymbolGlyphs.glyph(named: "square.dashed") : nil)
        if let size = measure(name) { return (glyph, size) }
        let star = SystemSymbolMetricsTable.values(named: "star", legacy: legacy) ?? []
        let size = star.count >= 36 ? SystemSymbolMetrics.size(values: star, pointSize: font.size, weight: font.weight, scale: environment.imageScale) : SystemSymbolMetrics.fallback
        return (glyph, size)
    }

    /// `string` with the environment's `textCase` applied.
    package func cased(_ string: String) -> String {
        switch environment.textCase {
        case nil: return string
        case .uppercase: return string.uppercased()
        case .lowercase: return string.lowercased()
        }
    }

    /// Each part's own gradient, if it has one.
    package var runGradients: [(any _GradientStyle)?] { parts.map { $0.modifiers.foregroundGradient?.style } }

    /// The environment's layout options with the text's own kerning and tracking.
    package var layoutOptions: TextLayoutOptions {
        var options = environment.textLayoutOptions
        if let kerning = view.modifiers.kerning { options.kerning = kerning }
        if let tracking = view.modifiers.tracking { options.tracking = tracking }
        return options
    }

    package func textLayout(width: CGFloat?) -> TextLayout {
        if environment._usesPlaceholderLayout { return placeholderLayout(width: width) }
        return runtime.layoutText(styledRuns.runs, options: layoutOptions, width: width)
    }

    /// The layout under a height proposal: a text proposed less height than its lines need keeps
    /// `floor(height / line pitch)` lines, at least one, and truncates the last (measured on
    /// `pressure/heights` and `pressure/alone*`, 2026-09-05). A zero proposal is a stack's
    /// minimum-size probe and yields one line; that probe only needs the height, so it trims the
    /// natural layout arithmetically rather than asking the text engine for another layout.
    package func textLayout(width: CGFloat?, height: CGFloat?) -> TextLayout {
        let natural = textLayout(width: width)
        guard let height, height.isFinite, height >= 0, width.map({ $0 > 0 }) ?? true,
              natural.size.height > height + 0.001, let font = styledRuns.runs.first?.font else { return natural }
        // The first line is the line height, each further one the line pitch (they differ where a
        // style's pitch exceeds its line: iOS body at xSmall is 20.5 on a 22.5 pitch, measured on
        // `ios/text/dynamic-xsmall`, whose paragraph keeps one line in 41.5).
        let metrics = environment.platformProfile.systemFontMetrics(for: font)
        let first = metrics.lineHeight
        let pitch = (metrics.linePitch > 0 ? metrics.linePitch : metrics.lineHeight) + layoutOptions.lineSpacing
        guard pitch > 0, first > 0 else { return natural }
        // A multi-line height is the unrounded line plus the pitches, rounded up to the half point,
        // as SwiftUI reports it (two lines of iOS body at xxxLarge are 67: 32.71 + 34.25 → 67, not
        // 33 + 34.25), so a text proposed its own two-line height keeps two lines.
        let unrounded = font.sizeCategory != nil && metrics.unroundedLineHeight > 0 ? metrics.unroundedLineHeight : first
        func heightOf(_ count: Int) -> CGFloat { count == 1 ? first : ((unrounded + CGFloat(count - 1) * pitch) * 2 - 1e-9).rounded(.up) / 2 }
        let lines = 1 + Int(((natural.size.height - first) / pitch).rounded())
        var kept = 1
        while kept < lines, heightOf(kept + 1) <= height + 0.001 { kept += 1 }
        guard lines > 1, kept < lines else { return natural }
        if height == 0 || environment._usesPlaceholderLayout {
            var trimmed = natural
            if natural.lines.count >= kept {
                trimmed.lines = Array(natural.lines.prefix(kept))
                trimmed.lastBaseline = trimmed.lines.last?.baseline ?? natural.firstBaseline
            }
            trimmed.size.height = natural.size.height - CGFloat(lines - kept) * pitch
            return trimmed
        }
        var options = layoutOptions
        options.lineLimit = min(options.lineLimit ?? kept, kept)
        return runtime.layoutText(styledRuns.runs, options: options, width: width)
    }

    /// The layout under `redacted(reason: .placeholder)`: the same words wrapped at the
    /// placeholder advances (`_Placeholder`), so line counts and single-line widths match
    /// SwiftUI's; letter spacing does not apply.
    package func placeholderLayout(width: CGFloat?) -> TextLayout {
        let profile = environment.platformProfile
        let layouter = TextLayouter(measure: { text, font in _Placeholder.width(of: text, font: font) },
                                    metrics: { profile.systemFontMetrics(for: $0) })
        let runs = styledRuns.runs.map { StyledRun(String(repeating: _Placeholder.character, count: $0.string.count), font: $0.font) }
        var layout = layouter.layout(runs, options: layoutOptions.withoutLetterSpacing, width: width)
        // A wrapped placeholder spans its proposal: every bar but the last runs the full width.
        if let width, layout.lines.count > 1 { layout.size.width = width }
        return layout
    }

    /// Redaction: one bar per line over the line's ink, on the baseline (`_Placeholder`).
    private func paintPlaceholders(_ layout: TextLayout, runs: [StyledRun], into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let alignment = environment._resolvedTextAlignment
        let color = environment._placeholderColor
        let shiftUp = baselineShift.up
        // A placeholder layout stretches every wrapped line's bar to the frame; the last line
        // (and a privacy bar over a plain layout) keeps its own width.
        let stretched = environment._usesPlaceholderLayout
        for (index, line) in layout.lines.enumerated() where line.inkWidth > 0 {
            let width = stretched && index < layout.lines.count - 1 ? frame.width : line.inkWidth
            let lineX = bounds.minX + (frame.width - width) * alignment
            let run = line.fragments.first.map { min(max($0.run, 0), max(runs.count - 1, 0)) } ?? 0
            let font = runs.indices.contains(run) ? runs[run].font : resolvedFont
            let bar = _Placeholder.bar(lineX: lineX, baseline: bounds.minY + line.baseline + shiftUp, width: width, font: font, profile: environment.platformProfile)
            list.append(.fillRRect(bar.rect, cornerRadius: bar.radius, color))
        }
    }

    /// Each part's baseline offset (its own, else the environment's).
    package var baselineOffsets: [CGFloat] {
        parts.map { $0.modifiers.baselineOffset ?? environment._baselineOffset }
    }

    /// How far the text grows above and below for baseline offsets: a raised part adds what its
    /// ascent plus the offset reaches above the line's ascent, a dropped part what its descent
    /// plus the drop reaches below the line's descent (`textstyle/baseline`: a text 16 high with
    /// offset 6 is 22 high, with −4 it is 20; `text/attributed`: a 13 pt part raised 4 next to a
    /// title stays within the title's line).
    package var baselineShift: (up: CGFloat, down: CGFloat) {
        let offsets = baselineOffsets
        guard offsets.contains(where: { $0 != 0 }) else { return (0, 0) }
        let runs = styledRuns.runs
        let profile = environment.platformProfile
        let metrics = runs.map { profile.systemFontMetrics(for: $0.font) }
        let lineAscent = metrics.map(\.baseline).max() ?? 0
        let lineDescent = metrics.map { $0.lineHeight - $0.baseline }.max() ?? 0
        var up: CGFloat = 0, down: CGFloat = 0
        for (index, offset) in offsets.enumerated() where metrics.indices.contains(index) {
            up = max(up, metrics[index].baseline + offset - lineAscent)
            down = max(down, metrics[index].lineHeight - metrics[index].baseline - offset - lineDescent)
        }
        return (max(0, up), max(0, down))
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        // Text wraps at the proposed width; an unspecified or infinite width means one line.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        var size = textLayout(width: width, height: proposal.height).size
        let shift = baselineShift
        size.height += shift.up + shift.down
        return size
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let layout = textLayout(width: width, height: proposal.height)
        let shift = baselineShift
        return ViewDimensions(size: CGSize(width: layout.size.width, height: layout.size.height + shift.up + shift.down), explicit: [
            VerticalAlignment.firstTextBaseline.key: layout.firstBaseline + shift.up,
            VerticalAlignment.lastTextBaseline.key: layout.lastBaseline + shift.up,
            // A text as a label's icon aligns half a cap height above its baseline, like the
            // title (label/corners `textIcon`: the same top as the title, not its centre).
            VerticalAlignment._iconCenter.key: layout.firstBaseline + shift.up - environment._halfCapHeight,
        ])
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let progress = contentTransitionProgress
        guard let outgoing, progress < 1 else {
            paintText(alpha: 1, dy: 0, into: &list, context: context)
            return
        }
        // The old text fades out (rolling away for numeric text) while the new fades in.
        let roll = outgoing.transition.roll * frame.height
        let current = (view, environment)
        view = outgoing.view; environment = outgoing.environment
        forgetParts()
        paintText(alpha: 1 - progress, dy: -roll * CGFloat(progress), into: &list, context: context)
        view = current.0; environment = current.1
        forgetParts()
        paintText(alpha: progress, dy: roll * CGFloat(1 - progress), into: &list, context: context)
    }

    /// Paints the text at `alpha`, shifted down by `dy`.
    private func paintText(alpha: Double, dy: CGFloat, into list: inout DisplayList, context: PaintContext) {
        guard alpha > 0 else { return }
        if alpha < 1 { list.append(.beginGroup(opacity: alpha)) }
        defer { if alpha < 1 { list.append(.endGroup) } }
        let (runs, colors) = styledRuns
        let layout = textLayout(width: frame.width, height: frame.height)
        if environment._drawsPlaceholders {
            paintPlaceholders(layout, runs: runs, into: &list, context: context)
            return
        }
        let inherited = (environment.foregroundColor ?? .primary)
        let parts = self.parts
        // A link without a colour of its own takes the accent (text/markdown `link`).
        let resolvedColors = colors.indices.map { index in
            context.foregroundOverride ?? (colors[index] ?? (parts.indices.contains(index) && parts[index].modifiers.link != nil ? Color.accentColor : inherited)).resolve(in: environment)
        }
        let spacing = TextLayouter.letterSpacing(layoutOptions) + layout.tightening
        let secondary = layoutOptions.textScale == .secondary
        let fonts = runs.map { run -> DisplayFont in
            if secondary, let scaled = run.font.secondaryScaled {
                return DisplayFont(scaled.font.scaled(by: layout.scale), letterSpacing: (spacing + scaled.tracking) * layout.scale)
            }
            return DisplayFont(run.font.scaled(by: layout.scale), letterSpacing: spacing * layout.scale)
        }
        let bounds = absoluteBounds(context)
        // The selection's highlight under the glyphs (the field's selection colour).
        for rect in selectionRects() {
            list.append(.fillRect(context.absoluteRect(rect), PlatformMetrics.textSelectionColor))
        }
        // A gradient foreground style (the text's own or the environment's) fills the runs
        // without a colour of their own.
        let runGradients = runGradients
        let inheritedGradient = environment.foregroundGradient?._resolveGradient(in: bounds, environment: environment)
        let alignment = environment._resolvedTextAlignment
        let offsets = baselineOffsets
        let shiftUp = baselineShift.up
        for line in layout.lines {
            let lineX = bounds.minX + (frame.width - line.inkWidth) * alignment
            for fragment in line.fragments where !fragment.text.isEmpty {
                let run = min(max(fragment.run, 0), max(runs.count - 1, 0))
                let font = fonts.indices.contains(run) ? fonts[run] : DisplayFont(resolvedFont)
                let offset = offsets.indices.contains(run) ? offsets[run] : 0
                let origin = CGPoint(x: lineX + fragment.x, y: bounds.minY + line.baseline + shiftUp - offset + dy)
                let own = runGradients.indices.contains(run) ? runGradients[run]?._resolveGradient(in: bounds, environment: environment) : nil
                let color = resolvedColors.indices.contains(run) ? resolvedColors[run] : inherited.resolve(in: environment)
                if parts.indices.contains(run), let image = parts[run].image {
                    // An inline image sits on the baseline by its descent, as wide as its advance.
                    if let symbol = inlineSymbol(for: image, font: runs[run].font), let glyph = symbol.glyph {
                        let rect = CGRect(x: origin.x, y: origin.y + symbol.size.descent - symbol.size.height, width: fragment.width, height: symbol.size.height)
                        _SymbolPainter.paint(glyph, in: rect, weight: runs[run].font.weight.value, color: color, into: &list)
                    }
                    continue
                }
                if let gradient = own ?? inheritedGradient, colors.indices.contains(run) ? colors[run] == nil : true {
                    list.append(.drawTextGradient(fragment.text, font, origin: origin, gradient))
                } else {
                    list.append(.drawText(fragment.text, font, origin: origin, color))
                }
                if parts.indices.contains(run) {
                    let modifiers = parts[run].modifiers
                    let underline = modifiers.underline ?? environment._underlineStyle
                    let strikethrough = modifiers.strikethrough ?? environment._strikethroughStyle
                    if underline != nil || strikethrough != nil {
                        let metrics = environment.platformProfile.textDecorationMetrics(for: runs[run].font)
                        if let underline {
                            paintDecoration(underline, centre: origin.y + metrics.underlineOffset, thickness: metrics.thickness,
                                            from: origin.x, to: origin.x + fragment.width, textColor: color, context: context, into: &list)
                        }
                        if let strikethrough {
                            paintDecoration(strikethrough, centre: origin.y - metrics.xHeight / 2, thickness: metrics.thickness,
                                            from: origin.x, to: origin.x + fragment.width, textColor: color, context: context, into: &list)
                        }
                    }
                }
            }
        }
    }

    /// Draws one underline or strikethrough: the line snaps to whole device pixels (its top
    /// rounded, its thickness rounded up, its ends rounded inwards), and patterns repeat in
    /// multiples of the snapped thickness (`Docs/elements/TextStyle.md`).
    private func paintDecoration(_ style: Text.LineStyle, centre: CGFloat, thickness: CGFloat, from x0: CGFloat, to x1: CGFloat,
                                 textColor: RGBA, context: PaintContext, into list: inout DisplayList) {
        let scale = context.scale
        let thicknessPixels = max(1, (thickness * scale).rounded(.up))
        let snapped = thicknessPixels / scale
        let top = (centre * scale - thicknessPixels / 2).rounded(.toNearestOrAwayFromZero) / scale
        let start = (x0 * scale).rounded(.up) / scale, end = (x1 * scale).rounded(.down) / scale
        guard end > start else { return }
        let color = style.color?.resolve(in: environment) ?? textColor
        let dashes: [CGFloat]
        switch style.pattern {
        case .solid: dashes = []
        case .dot: dashes = [3, 3]
        case .dash: dashes = [10, 5]
        case .dashDot: dashes = [10, 3, 3, 3]
        case .dashDotDot: dashes = [10, 3, 3, 3, 3, 3]
        }
        if dashes.isEmpty {
            list.append(.fillRect(CGRect(x: start, y: top, width: end - start, height: snapped), color))
        } else {
            var path = Path()
            path.move(to: CGPoint(x: start, y: top + snapped / 2))
            path.addLine(to: CGPoint(x: end, y: top + snapped / 2))
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: snapped, dash: dashes.map { $0 * snapped }), color))
        }
    }

    /// Text declares no default category vertically: its distances to neighbours come from the
    /// font (fixtures text/vstack-spacing*). Horizontally it behaves like any view (8 points).
    override package var layoutSpacing: ViewSpacing {
        let metrics = runtime.textEngine.metrics(for: styledRuns.runs.first?.font ?? resolvedFont)
        return ViewSpacing.text(metrics)
    }
}

// MARK: - View-level weight

package struct FontWeightKey: EnvironmentKey {
    package static let defaultValue: Font.Weight? = nil
}

package struct BoldTraitKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// A font weight applied to text and symbols in this environment (`View.fontWeight`).
    package var _fontWeight: Font.Weight? {
        get { self[FontWeightKey.self] }
        set { self[FontWeightKey.self] = newValue }
    }

    /// Whether text and symbols in this environment take the bold trait (`View.bold`).
    package var _boldTrait: Bool {
        get { self[BoldTraitKey.self] }
        set { self[BoldTraitKey.self] = newValue }
    }

    /// The environment's font with its weight overrides applied (text and symbol images).
    package var _resolvedFont: ResolvedFont {
        var resolved = (font ?? platformProfile.defaultFont).resolve(profile: platformProfile, dynamicTypeSize: dynamicTypeSize)
        if let weight = _fontWeight {
            resolved.weight = weight; resolved.weightOverridden = true
        } else if _boldTrait {
            resolved.weight = platformProfile.boldTraitWeight(for: resolved.textStyle); resolved.weightOverridden = true
        }
        return resolved
    }
}

package struct FontDesignKey: EnvironmentKey {
    package static let defaultValue: Font.Design? = nil
}

package struct ItalicTraitKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct MonospacedTraitKey: EnvironmentKey {
    package static let defaultValue = false
}

package struct MonospacedDigitTraitKey: EnvironmentKey {
    package static let defaultValue = false
}

extension EnvironmentValues {
    /// The design applied to system fonts in this environment (`View.fontDesign`).
    package var _fontDesign: Font.Design? {
        get { self[FontDesignKey.self] }
        set { self[FontDesignKey.self] = newValue }
    }

    /// Whether text in this environment is italic (`View.italic`).
    package var _italicTrait: Bool {
        get { self[ItalicTraitKey.self] }
        set { self[ItalicTraitKey.self] = newValue }
    }

    /// Whether text in this environment takes the monospaced design (`View.monospaced`).
    package var _monospacedTrait: Bool {
        get { self[MonospacedTraitKey.self] }
        set { self[MonospacedTraitKey.self] = newValue }
    }

    /// Whether text in this environment uses fixed-width digits (`View.monospacedDigit`).
    package var _monospacedDigitTrait: Bool {
        get { self[MonospacedDigitTraitKey.self] }
        set { self[MonospacedDigitTraitKey.self] = newValue }
    }
}

extension Font.Design {
    /// The text engine's family for a system font of this design.
    package static func _familyName(_ design: Font.Design) -> String {
        switch design {
        case .default: return "system"
        case .rounded: return "system-rounded"
        case .serif: return "system-serif"
        case .monospaced: return "system-monospaced"
        }
    }
}

extension View {
    /// Sets the font weight of the text and symbol images in this view.
    nonisolated public func fontWeight(_ weight: Font.Weight?) -> some View {
        environment(\._fontWeight, weight)
    }

    /// Sets the font design of the text in this view (system fonts without a design of their own).
    nonisolated public func fontDesign(_ design: Font.Design?) -> some View {
        environment(\._fontDesign, design)
    }

    /// Sets the font width of the text in this view. Stored only: the text engine draws one width.
    nonisolated public func fontWidth(_ width: Font.Width?) -> some View { self }

    /// Applies italics to the text in this view.
    nonisolated public func italic(_ isActive: Bool = true) -> some View {
        environment(\._italicTrait, isActive)
    }

    /// Modifies the fonts of the text in this view to use the monospaced design.
    nonisolated public func monospaced(_ isActive: Bool = true) -> some View {
        environment(\._monospacedTrait, isActive)
    }

    /// Modifies the fonts of the text in this view to use fixed-width digits.
    nonisolated public func monospacedDigit() -> some View {
        environment(\._monospacedDigitTrait, true)
    }

    /// Applies a bold font weight to the text and symbol images in this view.
    nonisolated public func bold(_ isActive: Bool = true) -> some View {
        environment(\._boldTrait, isActive)
    }
}

extension Text {
    /// The text's characters without styling (tooltips, accessibility).
    package var _plainString: String { parts().map(\.string).joined() }
}
