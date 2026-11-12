// Rich text (Docs/elements/Text.md, "Rich text"): `Text(AttributedString)` and the SwiftUI
// attribute scope, `Text(Image)`, `Text(_ date:style:)` and `Text(_:format:)`.
import WebFoundation

// MARK: - Attribute scope

// The keys are top-level types (the scope's members alias them) so code built next to Apple's
// SwiftUI overlay, where `AttributeScopes.SwiftUIAttributes` exists twice, can still name ours.
public enum _SwiftUIFontAttribute: AttributedStringKey {
    public typealias Value = Font
    public static let name = "SwiftUI.Font"
}
public enum _SwiftUIForegroundColorAttribute: AttributedStringKey {
    public typealias Value = Color
    public static let name = "SwiftUI.ForegroundColor"
}
public enum _SwiftUIBackgroundColorAttribute: AttributedStringKey {
    public typealias Value = Color
    public static let name = "SwiftUI.BackgroundColor"
}
public enum _SwiftUIUnderlineStyleAttribute: AttributedStringKey {
    public typealias Value = Text.LineStyle
    public static let name = "SwiftUI.UnderlineStyle"
}
public enum _SwiftUIStrikethroughStyleAttribute: AttributedStringKey {
    public typealias Value = Text.LineStyle
    public static let name = "SwiftUI.StrikethroughStyle"
}
public enum _SwiftUIBaselineOffsetAttribute: AttributedStringKey {
    public typealias Value = CGFloat
    public static let name = "SwiftUI.BaselineOffset"
}
public enum _SwiftUIKernAttribute: AttributedStringKey {
    public typealias Value = CGFloat
    public static let name = "SwiftUI.Kern"
}
public enum _SwiftUITrackingAttribute: AttributedStringKey {
    public typealias Value = CGFloat
    public static let name = "SwiftUI.Tracking"
}

extension AttributeScopes {
    /// The attributes SwiftUI reads from an attributed string: font, colour, decorations,
    /// baseline offset and letter spacing.
    public struct SwiftUIAttributes {
        public typealias FontAttribute = _SwiftUIFontAttribute
        public typealias ForegroundColorAttribute = _SwiftUIForegroundColorAttribute
        public typealias BackgroundColorAttribute = _SwiftUIBackgroundColorAttribute
        public typealias UnderlineStyleAttribute = _SwiftUIUnderlineStyleAttribute
        public typealias StrikethroughStyleAttribute = _SwiftUIStrikethroughStyleAttribute
        public typealias BaselineOffsetAttribute = _SwiftUIBaselineOffsetAttribute
        public typealias KernAttribute = _SwiftUIKernAttribute
        public typealias TrackingAttribute = _SwiftUITrackingAttribute

        // Key paths name the keys; the scope is never instantiated.
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let strikethroughStyle: StrikethroughStyleAttribute
        public let baselineOffset: BaselineOffsetAttribute
        public let kern: KernAttribute
        public let tracking: TrackingAttribute
    }

    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T { self[T.self] }
}

// MARK: - Text from attributed strings, images, dates and formats

extension Text {
    /// Creates a text view that displays styled attributed content: each run's font, colour,
    /// decorations, baseline offset, link and inline presentation intent (bold, italic, code,
    /// strikethrough) become the part's modifiers. A string literal is a localized key, not an
    /// attributed string.
    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        let characters = attributedContent.characters
        var parts: [Text] = []
        for run in attributedContent.runs {
            var text = Text(verbatim: String(characters[run.range]))
            if let font = run[_SwiftUIFontAttribute.self] { text.modifiers.font = font }
            if let color = run[_SwiftUIForegroundColorAttribute.self] { text.modifiers.foregroundColor = color }
            if let underline = run[_SwiftUIUnderlineStyleAttribute.self] { text.modifiers.underline = .some(underline) }
            if let strikethrough = run[_SwiftUIStrikethroughStyleAttribute.self] { text.modifiers.strikethrough = .some(strikethrough) }
            if let offset = run[_SwiftUIBaselineOffsetAttribute.self] { text.modifiers.baselineOffset = offset }
            if let kern = run[_SwiftUIKernAttribute.self] { text.modifiers.kerning = kern }
            if let tracking = run[_SwiftUITrackingAttribute.self] { text.modifiers.tracking = tracking }
            if let link = run[AttributeScopes.FoundationAttributes.LinkAttribute.self] { text.modifiers.link = link }
            if let intent = run[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] {
                if intent.contains(.stronglyEmphasized) { text.modifiers.bold = true }
                if intent.contains(.emphasized) { text.modifiers.italic = true }
                if intent.contains(.code) { text.modifiers.monospaced = true }
                if intent.contains(.strikethrough) { text.modifiers.strikethrough = .some(LineStyle()) }
            }
            parts.append(text)
        }
        self.init(storage: parts.count == 1 ? parts[0].storage : .concatenated(parts))
        if parts.count == 1 { modifiers = parts[0].modifiers }
    }

    /// Creates an instance that wraps an image: the image is laid out like a glyph on the
    /// text's baseline, sized by the font (`text/inline-image`).
    public init(_ image: Image) {
        self.init(storage: .image(image))
    }

    /// Creates an instance that displays a date, formatted by a style: `date` and `time` show
    /// the instant in the environment's time zone; `relative`, `offset` and `timer` show its
    /// distance from now and keep themselves up to date.
    public init(_ date: Date, style: DateStyle) {
        self.init(storage: .date(date, style))
    }

    /// Creates a timer over an interval: counting down, the time left to its end; counting up,
    /// the time since its start (a live `.timer` text; it does not stop at the bounds or pause).
    public init(timerInterval: ClosedRange<Date>, pauseTime: Date? = nil, countsDown: Bool = true, showsHours: Bool = true) {
        self.init(storage: .date(countsDown ? timerInterval.upperBound : timerInterval.lowerBound, .timer))
    }

    /// Creates a text view that displays the formatted representation of a value.
    public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
        self.init(storage: .verbatim(format.format(input)))
    }

    /// A predefined style used to display a `Date`.
    public struct DateStyle: Hashable, Sendable {
        package enum Kind: Hashable, Sendable { case time, date, relative, offset, timer }
        package let kind: Kind

        /// A style displaying only the time component for a date ("8:26 PM").
        public static let time = DateStyle(kind: .time)
        /// A style displaying a date ("May 28, 2026").
        public static let date = DateStyle(kind: .date)
        /// A style displaying a date as relative to now ("2 hours").
        public static let relative = DateStyle(kind: .relative)
        /// A style displaying a date as offset from now ("+2 hours").
        public static let offset = DateStyle(kind: .offset)
        /// A style displaying a date as timer counting from now ("1:23:45").
        public static let timer = DateStyle(kind: .timer)

        /// Whether the text changes as time passes.
        package var isLive: Bool { kind != .time && kind != .date }
    }
}

/// What a text's parts resolve against: the time zone and calendar for dates, and the current
/// instant for the live styles.
package struct _TextContext: Sendable {
    package var timeZone: TimeZone
    package var calendar: Calendar
    package var now: Date

    package init(timeZone: TimeZone, calendar: Calendar, now: Date = Date()) {
        self.timeZone = timeZone
        self.calendar = calendar
        self.now = now
    }

    package static var current: _TextContext { _TextContext(timeZone: TimeZone.current, calendar: Calendar.current) }
}

/// Formats dates for `Text(_:style:)` in English, as SwiftUI's en_US styles do (`text/dates`).
package enum _DateText {
    package static func string(for date: Date, style: Text.DateStyle, context: _TextContext) -> String {
        var calendar = context.calendar
        calendar.timeZone = context.timeZone
        switch style.kind {
        case .date:
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            return "\(months[max(0, min(11, (parts.month ?? 1) - 1))]) \(parts.day ?? 1), \(parts.year ?? 1)"
        case .time:
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let hour = parts.hour ?? 0, minute = parts.minute ?? 0
            let shown = hour % 12 == 0 ? 12 : hour % 12
            // A narrow no-break space before the period, as Foundation writes it.
            return "\(shown):\(minute < 10 ? "0" : "")\(minute)\u{202F}\(hour < 12 ? "AM" : "PM")"
        case .relative:
            let seconds = date.timeIntervalSince(context.now)
            return unitString(abs(seconds))
        case .offset:
            let seconds = date.timeIntervalSince(context.now)
            return (seconds < 0 ? "-" : "+") + unitString(abs(seconds))
        case .timer:
            let seconds = Int(abs(date.timeIntervalSince(context.now)).rounded(.down))
            let hours = seconds / 3600, minutes = (seconds % 3600) / 60, rest = seconds % 60
            let two = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
            return hours > 0 ? "\(hours):\(two(minutes)):\(two(rest))" : "\(minutes):\(two(rest))"
        }
    }

    /// The largest whole unit of a duration ("45 seconds", "2 hours", "3 days").
    private static func unitString(_ seconds: Double) -> String {
        let units: [(Double, String)] = [(31_536_000, "year"), (2_592_000, "month"), (604_800, "week"), (86_400, "day"), (3600, "hour"), (60, "minute")]
        for (length, name) in units where seconds >= length {
            let count = Int(seconds / length)
            return "\(count) \(name)\(count == 1 ? "" : "s")"
        }
        let count = Int(seconds)
        return "\(count) second\(count == 1 ? "" : "s")"
    }
}
