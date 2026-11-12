// Foundation's date formatting on wasm (pf-web-foundation-gaps): `Date.FormatStyle` with its
// date and time styles and field symbols, `Date.ISO8601FormatStyle`, `Date.RelativeFormatStyle`,
// `Date.VerbatimFormatStyle`, `Date.ParseStrategy` and `Date.FormatString`, `DateFormatter`
// and `RelativeDateTimeFormatter`, all over `_DatePattern` (DatePattern.swift) with English
// symbols. FoundationEssentials carries its own `Date.ISO8601FormatStyle` (over its calendar,
// which would pull the library in), so this one is a top-level type the nested name aliases.
#if os(WASI)
import FoundationEssentials

/// Where a formatted string will appear; the English forms do not change with it.
public enum FormatStyleCapitalizationContext: Hashable, Sendable, Codable {
    case unknown, standalone, listItem, beginningOfSentence, middleOfSentence
}

extension Date {
    /// The calendar arithmetic a style uses.
    fileprivate static func math(calendar: Calendar, timeZone: TimeZone) -> _CalendarMath {
        _CalendarMath(zone: timeZone.rule, system: calendar.system, firstWeekday: calendar.firstWeekday, minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek)
    }

    fileprivate static func input(_ date: Date, calendar: Calendar, timeZone: TimeZone) -> _DateFormatInput {
        let math = math(calendar: calendar, timeZone: timeZone)
        return _DateFormatInput(time: date.timeIntervalSince1970, math: math) { style in
            switch style {
            case "identifier": return timeZone.identifier
            case "long": return timeZone.localizedName(for: .standard, locale: nil) ?? timeZone.identifier
            case "shortGeneric": return timeZone.localizedName(for: .shortGeneric, locale: nil) ?? timeZone.identifier
            case "longGeneric": return timeZone.localizedName(for: .generic, locale: nil) ?? timeZone.identifier
            default: return timeZone.abbreviation(for: date) ?? "GMT"
            }
        }
    }

    // MARK: FormatStyle

    /// Dates as text: a date style and a time style, or the fields named one by one.
    public struct FormatStyle: ParseableFormatStyle, Codable, Hashable, Sendable {
        public var locale: Locale
        public var calendar: Calendar
        public var timeZone: TimeZone
        public var capitalizationContext: FormatStyleCapitalizationContext
        var dateStyle: DateStyle?
        var timeStyle: TimeStyle?
        /// The field symbols, as skeleton runs in the order they were added.
        var skeleton: String = ""

        public init(date: DateStyle? = nil, time: TimeStyle? = nil, locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent,
                    timeZone: TimeZone = .autoupdatingCurrent, capitalizationContext: FormatStyleCapitalizationContext = .unknown) {
            self.dateStyle = date
            self.timeStyle = time
            self.locale = locale
            self.calendar = calendar
            self.timeZone = timeZone
            self.capitalizationContext = capitalizationContext
        }

        public struct DateStyle: Codable, Hashable, Sendable {
            let rawValue: Int
            public static let omitted = DateStyle(rawValue: 0)
            public static let numeric = DateStyle(rawValue: 1)
            public static let abbreviated = DateStyle(rawValue: 2)
            public static let long = DateStyle(rawValue: 3)
            public static let complete = DateStyle(rawValue: 4)
        }

        public struct TimeStyle: Codable, Hashable, Sendable {
            let rawValue: Int
            public static let omitted = TimeStyle(rawValue: 0)
            public static let shortened = TimeStyle(rawValue: 1)
            public static let standard = TimeStyle(rawValue: 2)
            public static let complete = TimeStyle(rawValue: 3)
        }

        /// The LDML pattern the style formats with: the symbols' skeleton when any were named,
        /// else the styles (numeric date and shortened time when neither is set).
        package var pattern: String {
            if !skeleton.isEmpty {
                return _DatePattern.hostPattern(locale, _DatePattern.canonical(skeleton)) ?? _DatePattern.pattern(forSkeleton: skeleton)
            }
            let date = dateStyle?.rawValue ?? (timeStyle == nil ? 1 : 0)
            let time = timeStyle?.rawValue ?? (dateStyle == nil ? 1 : 0)
            return _DatePattern.hostPattern(locale, "style:\(date):\(time)") ?? _DatePattern.stylePattern(date: date, time: time)
        }

        public func format(_ value: Date) -> String {
            _DatePattern.format(pattern, Date.input(value, calendar: calendar, timeZone: timeZone), symbols: _DatePattern.symbols(locale))
        }

        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }

        public var parseStrategy: Date.ParseStrategy {
            Date.ParseStrategy(pattern: pattern, locale: locale, timeZone: timeZone, calendar: calendar, isLenient: true, twoDigitStartDate: Date(timeIntervalSince1970: 0))
        }

        // MARK: Symbols

        private func adding(_ run: String) -> Self {
            var copy = self
            copy.skeleton += run
            return copy
        }

        public func era(_ format: Symbol.Era = .abbreviated) -> Self { adding(format.run) }
        public func year(_ format: Symbol.Year = .defaultDigits) -> Self { adding(format.run) }
        public func quarter(_ format: Symbol.Quarter = .abbreviated) -> Self { adding(format.run) }
        public func month(_ format: Symbol.Month = .abbreviated) -> Self { adding(format.run) }
        public func week(_ format: Symbol.Week = .defaultDigits) -> Self { adding(format.run) }
        public func day(_ format: Symbol.Day = .defaultDigits) -> Self { adding(format.run) }
        public func dayOfYear(_ format: Symbol.DayOfYear = .defaultDigits) -> Self { adding(format.run) }
        public func weekday(_ format: Symbol.Weekday = .abbreviated) -> Self { adding(format.run) }
        public func hour(_ format: Symbol.Hour = .defaultDigits(amPM: .abbreviated)) -> Self { adding(format.run) }
        public func minute(_ format: Symbol.Minute = .defaultDigits) -> Self { adding(format.run) }
        public func second(_ format: Symbol.Second = .defaultDigits) -> Self { adding(format.run) }
        public func secondFraction(_ format: Symbol.SecondFraction) -> Self { adding(format.run) }
        public func timeZone(_ format: Symbol.TimeZone = .specificName(.short)) -> Self { adding(format.run) }

        public enum Symbol: Sendable {
            public struct Era: Hashable, Sendable, Codable {
                let run: String
                public static let abbreviated = Era(run: "G")
                public static let wide = Era(run: "GGGG")
                public static let narrow = Era(run: "GGGGG")
            }
            public struct Year: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Year(run: "y")
                public static let twoDigits = Year(run: "yy")
                public static func padded(_ length: Int) -> Year { Year(run: String(repeating: "y", count: max(1, length))) }
                public static func relatedGregorian(minimumLength: Int = 1) -> Year { Year(run: String(repeating: "y", count: max(1, minimumLength))) }
                public static func extended(minimumLength: Int = 1) -> Year { Year(run: String(repeating: "y", count: max(1, minimumLength))) }
            }
            public struct Quarter: Hashable, Sendable, Codable {
                let run: String
                public static let oneDigit = Quarter(run: "Q")
                public static let twoDigits = Quarter(run: "QQ")
                public static let abbreviated = Quarter(run: "QQQ")
                public static let wide = Quarter(run: "QQQQ")
                public static let narrow = Quarter(run: "QQQQQ")
            }
            public struct Month: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Month(run: "M")
                public static let twoDigits = Month(run: "MM")
                public static let abbreviated = Month(run: "MMM")
                public static let wide = Month(run: "MMMM")
                public static let narrow = Month(run: "MMMMM")
            }
            public struct Week: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Week(run: "w")
                public static let twoDigits = Week(run: "ww")
                public static let weekOfMonth = Week(run: "W")
            }
            public struct Day: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Day(run: "d")
                public static let twoDigits = Day(run: "dd")
                public static let ordinalOfDayInMonth = Day(run: "F")
                public static func julianModified(minimumLength: Int = 1) -> Day { Day(run: String(repeating: "g", count: max(1, minimumLength))) }
            }
            public struct DayOfYear: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = DayOfYear(run: "D")
                public static let twoDigits = DayOfYear(run: "DD")
                public static let threeDigits = DayOfYear(run: "DDD")
            }
            public struct Weekday: Hashable, Sendable, Codable {
                let run: String
                public static let abbreviated = Weekday(run: "EEE")
                public static let wide = Weekday(run: "EEEE")
                public static let narrow = Weekday(run: "EEEEE")
                public static let short = Weekday(run: "EEEEEE")
                public static let oneDigit = Weekday(run: "e")
                public static let twoDigits = Weekday(run: "ee")
            }
            public struct Hour: Hashable, Sendable, Codable {
                let run: String
                public enum AMPMStyle: Hashable, Sendable, Codable { case omitted, narrow, abbreviated, wide }
                static func run(_ digits: String, _ amPM: AMPMStyle) -> String {
                    switch amPM {
                    case .omitted: return String(digits.map { $0 == "h" ? "J" : $0 })   // (no _StringProcessing: it links the Regex engine)
                    case .abbreviated: return digits
                    case .narrow: return digits + "aaaaa"
                    case .wide: return digits + "aaaa"
                    }
                }
                public static func defaultDigits(amPM: AMPMStyle) -> Hour { Hour(run: run("h", amPM)) }
                public static func twoDigits(amPM: AMPMStyle) -> Hour { Hour(run: run("hh", amPM)) }
                public static func conversationalDefaultDigits(amPM: AMPMStyle) -> Hour { Hour(run: run("h", amPM)) }
                public static func conversationalTwoDigits(amPM: AMPMStyle) -> Hour { Hour(run: run("hh", amPM)) }
                public static let defaultDigitsNoAMPM = Hour(run: "J")
                public static let twoDigitsNoAMPM = Hour(run: "JJ")
            }
            public struct Minute: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Minute(run: "m")
                public static let twoDigits = Minute(run: "mm")
            }
            public struct Second: Hashable, Sendable, Codable {
                let run: String
                public static let defaultDigits = Second(run: "s")
                public static let twoDigits = Second(run: "ss")
            }
            public struct SecondFraction: Hashable, Sendable, Codable {
                let run: String
                public static func fractional(_ digits: Int) -> SecondFraction { SecondFraction(run: String(repeating: "S", count: max(1, digits))) }
                public static func milliseconds(_ digits: Int) -> SecondFraction { SecondFraction(run: String(repeating: "A", count: max(1, digits))) }
            }
            public struct TimeZone: Hashable, Sendable, Codable {
                let run: String
                public enum Width: Hashable, Sendable, Codable { case short, long }
                public static func specificName(_ width: Width) -> TimeZone { TimeZone(run: width == .short ? "z" : "zzzz") }
                public static func genericName(_ width: Width) -> TimeZone { TimeZone(run: width == .short ? "v" : "vvvv") }
                public static func iso8601(_ width: Width) -> TimeZone { TimeZone(run: width == .short ? "X" : "XXXXX") }
                public static func localizedGMT(_ width: Width) -> TimeZone { TimeZone(run: width == .short ? "O" : "OOOO") }
                public static func identifier(_ width: Width) -> TimeZone { TimeZone(run: width == .short ? "V" : "VV") }
                public static let exemplarLocation = TimeZone(run: "VVV")
            }
        }
    }

    // MARK: FormatString and verbatim

    /// A pattern written as an interpolated string: `"\(month: .wide) \(day: .defaultDigits)"`.
    public struct FormatString: Hashable, Sendable, ExpressibleByStringInterpolation {
        package var pattern: String

        public init(stringLiteral value: String) { pattern = value.isEmpty ? "" : "'" + value + "'" }
        public init(stringInterpolation: StringInterpolation) { pattern = stringInterpolation.pattern }

        public struct StringInterpolation: StringInterpolationProtocol, Sendable {
            var pattern = ""
            public init(literalCapacity: Int, interpolationCount: Int) {}
            public mutating func appendLiteral(_ literal: String) {
                guard !literal.isEmpty else { return }
                pattern += literal.contains(where: { $0.isLetter || $0 == "'" }) ? "'" + literal.split(separator: "'", omittingEmptySubsequences: false).joined(separator: "''") + "'" : literal
            }
            public mutating func appendInterpolation(era: FormatStyle.Symbol.Era) { pattern += era.run }
            public mutating func appendInterpolation(year: FormatStyle.Symbol.Year) { pattern += year.run }
            public mutating func appendInterpolation(quarter: FormatStyle.Symbol.Quarter) { pattern += quarter.run }
            public mutating func appendInterpolation(month: FormatStyle.Symbol.Month) { pattern += month.run }
            public mutating func appendInterpolation(week: FormatStyle.Symbol.Week) { pattern += week.run }
            public mutating func appendInterpolation(day: FormatStyle.Symbol.Day) { pattern += day.run }
            public mutating func appendInterpolation(dayOfYear: FormatStyle.Symbol.DayOfYear) { pattern += dayOfYear.run }
            public mutating func appendInterpolation(weekday: FormatStyle.Symbol.Weekday) { pattern += weekday.run }
            public mutating func appendInterpolation(hour: FormatStyle.Symbol.Hour) { pattern += hour.run }
            public mutating func appendInterpolation(minute: FormatStyle.Symbol.Minute) { pattern += minute.run }
            public mutating func appendInterpolation(second: FormatStyle.Symbol.Second) { pattern += second.run }
            public mutating func appendInterpolation(secondFraction: FormatStyle.Symbol.SecondFraction) { pattern += secondFraction.run }
            public mutating func appendInterpolation(timeZone: FormatStyle.Symbol.TimeZone) { pattern += timeZone.run }
        }
    }

    /// A date formatted exactly by a pattern.
    public struct VerbatimFormatStyle: ParseableFormatStyle, Hashable, Sendable {
        public var format: FormatString
        public var timeZone: TimeZone
        public var calendar: Calendar
        public var locale: Locale?

        public init(format: FormatString, locale: Locale? = nil, timeZone: TimeZone, calendar: Calendar) {
            self.format = format
            self.locale = locale
            self.timeZone = timeZone
            self.calendar = calendar
        }
        public func format(_ value: Date) -> String { _DatePattern.format(format.pattern, Date.input(value, calendar: calendar, timeZone: timeZone)) }
        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }
        public var parseStrategy: Date.ParseStrategy {
            Date.ParseStrategy(pattern: format.pattern, locale: locale ?? .current, timeZone: timeZone, calendar: calendar, isLenient: true, twoDigitStartDate: Date(timeIntervalSince1970: 0))
        }
    }

    // MARK: Parsing

    /// Reads dates written by a pattern.
    public struct ParseStrategy: Hashable, Sendable, WebFoundation.ParseStrategy {
        package var pattern: String
        public var locale: Locale?
        public var timeZone: TimeZone
        public var calendar: Calendar
        public var isLenient: Bool
        public var twoDigitStartDate: Date

        init(pattern: String, locale: Locale?, timeZone: TimeZone, calendar: Calendar, isLenient: Bool, twoDigitStartDate: Date) {
            self.pattern = pattern
            self.locale = locale
            self.timeZone = timeZone
            self.calendar = calendar
            self.isLenient = isLenient
            self.twoDigitStartDate = twoDigitStartDate
        }

        public init(format: FormatString, locale: Locale? = nil, timeZone: TimeZone, calendar: Calendar = .autoupdatingCurrent,
                    isLenient: Bool = true, twoDigitStartDate: Date = Date(timeIntervalSince1970: 0)) {
            self.init(pattern: format.pattern, locale: locale, timeZone: timeZone, calendar: calendar, isLenient: isLenient, twoDigitStartDate: twoDigitStartDate)
        }

        public func parse(_ value: String) throws -> Date {
            guard let fields = _DatePattern.parse(value, pattern: pattern) else { throw FormatParseError(text: value) }
            return Date(timeIntervalSince1970: fields.time(in: Date.math(calendar: calendar, timeZone: timeZone)))
        }
    }

    public init<T: WebFoundation.ParseStrategy>(_ value: T.ParseInput, strategy: T) throws where T.ParseOutput == Date {
        self = try strategy.parse(value)
    }
    public init(_ value: String, strategy: _ISO8601DateFormatStyle) throws { self = try strategy.parse(value) }

    // MARK: Relative

    /// "2 hours ago", "in 3 days", "yesterday".
    public struct RelativeFormatStyle: WebFoundation.FormatStyle, Hashable, Sendable, Codable {
        public enum Presentation: Hashable, Sendable, Codable { case numeric, named }
        public enum UnitsStyle: Hashable, Sendable, Codable { case wide, spellOut, abbreviated, narrow }

        public var presentation: Presentation
        public var unitsStyle: UnitsStyle
        public var locale: Locale
        public var calendar: Calendar
        public var capitalizationContext: FormatStyleCapitalizationContext
        /// The instant "now" is measured from (the current time when nil; tests fix it).
        public var _reference: Date?

        public init(presentation: Presentation = .numeric, unitsStyle: UnitsStyle = .wide, locale: Locale = .autoupdatingCurrent,
                    calendar: Calendar = .autoupdatingCurrent, capitalizationContext: FormatStyleCapitalizationContext = .unknown) {
            self.presentation = presentation
            self.unitsStyle = unitsStyle
            self.locale = locale
            self.calendar = calendar
            self.capitalizationContext = capitalizationContext
        }

        public func format(_ value: Date) -> String {
            let now = _reference ?? Date()
            let math = Date.math(calendar: calendar, timeZone: calendar.timeZone)
            let components = _RelativeDateText.Components(from: now.timeIntervalSince1970, to: value.timeIntervalSince1970, math: math)
            return _RelativeDateText.text(components, presentation: presentation == .named ? .named : .numeric, unitsStyle: _RelativeDateText.UnitsStyle(unitsStyle))
        }
        public func locale(_ locale: Locale) -> Self { var copy = self; copy.locale = locale; return copy }
    }

    // MARK: Formatting entry points

    public func formatted() -> String { FormatStyle().format(self) }
    public func formatted(date: FormatStyle.DateStyle, time: FormatStyle.TimeStyle) -> String { FormatStyle(date: date, time: time).format(self) }
    public func formatted<F: WebFoundation.FormatStyle>(_ style: F) -> F.FormatOutput where F.FormatInput == Date { style.format(self) }
    /// FoundationEssentials has an ISO 8601 style and a generic `formatted` of its own; this
    /// concrete overload makes `date.formatted(.iso8601)` this module's.
    public func formatted(_ style: _ISO8601DateFormatStyle) -> String { style.format(self) }
}

extension _RelativeDateText.UnitsStyle {
    init(_ style: Date.RelativeFormatStyle.UnitsStyle) {
        switch style {
        case .wide: self = .wide
        case .spellOut: self = .spellOut
        case .abbreviated: self = .abbreviated
        case .narrow: self = .narrow
        }
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    public static var dateTime: Date.FormatStyle { Date.FormatStyle() }
}
extension FormatStyle where Self == Date.RelativeFormatStyle {
    public static func relative(presentation: Date.RelativeFormatStyle.Presentation, unitsStyle: Date.RelativeFormatStyle.UnitsStyle = .wide) -> Date.RelativeFormatStyle {
        Date.RelativeFormatStyle(presentation: presentation, unitsStyle: unitsStyle)
    }
}
extension FormatStyle where Self == Date.VerbatimFormatStyle {
    public static func verbatim(_ format: Date.FormatString, locale: Locale? = nil, timeZone: TimeZone, calendar: Calendar) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: format, locale: locale, timeZone: timeZone, calendar: calendar)
    }
}
extension FormatStyle where Self == _ISO8601DateFormatStyle {
    public static var iso8601: _ISO8601DateFormatStyle { _ISO8601DateFormatStyle() }
}

// MARK: - ISO 8601

/// ISO 8601 dates: "2026-10-09T15:04:05Z" by default, or the fields asked for.
public struct _ISO8601DateFormatStyle: ParseableFormatStyle, WebFoundation.ParseStrategy, Hashable, Sendable {
    public enum DateSeparator: String, Hashable, Sendable, Codable { case dash = "-", omitted = "" }
    public enum DateTimeSeparator: String, Hashable, Sendable, Codable { case space = " ", standard = "'T'" }
    public enum TimeSeparator: String, Hashable, Sendable, Codable { case colon = ":", omitted = "" }
    public enum TimeZoneSeparator: String, Hashable, Sendable, Codable { case colon = ":", omitted = "" }

    public var timeZone: TimeZone
    public var includingFractionalSeconds: Bool
    public var dateSeparator: DateSeparator
    public var dateTimeSeparator: DateTimeSeparator
    public var timeSeparator: TimeSeparator
    public var timeZoneSeparator: TimeZoneSeparator
    var fields: Set<String> = []
    var includesTime = false, includesZone = false, weekBased = false

    public init(dateSeparator: DateSeparator = .dash, dateTimeSeparator: DateTimeSeparator = .standard, timeSeparator: TimeSeparator = .colon,
                timeZoneSeparator: TimeZoneSeparator = .omitted, includingFractionalSeconds: Bool = false, timeZone: TimeZone = .gmt) {
        self.dateSeparator = dateSeparator
        self.dateTimeSeparator = dateTimeSeparator
        self.timeSeparator = timeSeparator
        self.timeZoneSeparator = timeZoneSeparator
        self.includingFractionalSeconds = includingFractionalSeconds
        self.timeZone = timeZone
    }

    private func with(_ change: (inout Self) -> Void) -> Self { var copy = self; change(&copy); return copy }
    public func year() -> Self { with { $0.fields.insert("y") } }
    public func month() -> Self { with { $0.fields.insert("M") } }
    public func day() -> Self { with { $0.fields.insert("d") } }
    public func weekOfYear() -> Self { with { $0.fields.insert("w"); $0.weekBased = true } }
    public func time(includingFractionalSeconds: Bool) -> Self { with { $0.includesTime = true; $0.includingFractionalSeconds = includingFractionalSeconds } }
    public func timeZone(separator: TimeZoneSeparator) -> Self { with { $0.includesZone = true; $0.timeZoneSeparator = separator } }
    public func dateSeparator(_ separator: DateSeparator) -> Self { with { $0.dateSeparator = separator } }
    public func dateTimeSeparator(_ separator: DateTimeSeparator) -> Self { with { $0.dateTimeSeparator = separator } }
    public func timeSeparator(_ separator: TimeSeparator) -> Self { with { $0.timeSeparator = separator } }
    public func locale(_ locale: Locale) -> Self { self }

    /// The pattern: every field when none was asked for.
    package var pattern: String {
        let all = fields.isEmpty && !includesTime && !includesZone
        var date: [String] = []
        if all || fields.contains("y") { date.append(weekBased ? "YYYY" : "yyyy") }
        if weekBased, all || fields.contains("w") { date.append("'W'ww") }
        if !weekBased, all || fields.contains("M") { date.append("MM") }
        if all || fields.contains("d") { date.append(weekBased ? "ee" : "dd") }
        var pattern = date.joined(separator: dateSeparator.rawValue)
        if all || includesTime {
            let time = ["HH", "mm", "ss"].joined(separator: timeSeparator.rawValue) + (includingFractionalSeconds ? ".SSS" : "")
            pattern += (pattern.isEmpty ? "" : dateTimeSeparator.rawValue) + time
        }
        if all || includesZone { pattern += timeZoneSeparator == .colon ? "XXXXX" : "XXXX" }
        return pattern
    }

    public func format(_ value: Date) -> String {
        _DatePattern.format(pattern, Date.input(value, calendar: Calendar(identifier: .iso8601), timeZone: timeZone))
    }

    public func parse(_ value: String) throws -> Date {
        let math = _CalendarMath(zone: timeZone.rule, system: .gregorian, firstWeekday: 2, minimumDaysInFirstWeek: 4)
        // The text's own fields decide: a zone, fractional seconds or a time may be present or not.
        for candidate in Self.parsePatterns(for: value, separators: self) {
            if let fields = _DatePattern.parse(value, pattern: candidate) { return Date(timeIntervalSince1970: fields.time(in: math)) }
        }
        throw FormatParseError(text: value)
    }

    private static func parsePatterns(for text: String, separators: Self) -> [String] {
        let dash = separators.dateSeparator.rawValue, colon = separators.timeSeparator.rawValue
        let date = "yyyy\(dash)MM\(dash)dd"
        var patterns = [date]
        for dateTime in ["'T'", " "] {
            for seconds in ["\(colon)ss.SSS", "\(colon)ss", ""] {
                let time = "HH\(colon)mm" + seconds
                patterns.append(date + dateTime + time + "XXXXX")
                patterns.append(date + dateTime + time + "XXXX")
                patterns.append(date + dateTime + time)
            }
        }
        return patterns
    }

    public var parseStrategy: Self { self }
}

// `Date.ISO8601FormatStyle` stays FoundationEssentials' (an alias here would make the name
// ambiguous); `.iso8601` and `Date.ISO8601Style()` are this module's.
public typealias ISO8601DateFormatStyle = _ISO8601DateFormatStyle
extension Date {
    public typealias ISO8601Style = _ISO8601DateFormatStyle
}

// MARK: - DateFormatter

/// Foundation's `DateFormatter` on wasm: the date and time styles, a pattern, or a template.
open class DateFormatter: Formatter {
    public enum Style: UInt, Sendable { case none = 0, short, medium, long, full }

    open var dateStyle: Style = .none
    open var timeStyle: Style = .none
    /// The LDML pattern; set, it takes over from the styles.
    open var dateFormat: String! {
        get { explicitFormat ?? stylePattern }
        set { explicitFormat = newValue }
    }
    private var explicitFormat: String?
    open var locale: Locale! = .autoupdatingCurrent
    open var timeZone: TimeZone! = .autoupdatingCurrent
    open var calendar: Calendar! = .autoupdatingCurrent
    open var isLenient = false
    open var doesRelativeDateFormatting = false
    open var defaultDate: Date?
    open var twoDigitStartDate: Date? = Date(timeIntervalSince1970: 0)
    open var formattingContext: Context = .unknown
    public enum Context: Int, Sendable { case unknown = 0, dynamic, standalone, listItem, beginningOfSentence, middleOfSentence }

    open var amSymbol = "AM"
    open var pmSymbol = "PM"
    open var monthSymbols = _DatePattern.monthNames
    open var shortMonthSymbols = _DatePattern.shortMonthNames
    open var standaloneMonthSymbols = _DatePattern.monthNames
    open var shortStandaloneMonthSymbols = _DatePattern.shortMonthNames
    open var veryShortMonthSymbols = _DatePattern.monthNames.map { String($0.prefix(1)) }
    open var veryShortStandaloneMonthSymbols = _DatePattern.monthNames.map { String($0.prefix(1)) }
    open var weekdaySymbols = _DatePattern.weekdayNames
    open var shortWeekdaySymbols = _DatePattern.shortWeekdayNames
    open var standaloneWeekdaySymbols = _DatePattern.weekdayNames
    open var shortStandaloneWeekdaySymbols = _DatePattern.shortWeekdayNames
    open var veryShortWeekdaySymbols = _DatePattern.weekdayNames.map { String($0.prefix(1)) }
    open var veryShortStandaloneWeekdaySymbols = _DatePattern.weekdayNames.map { String($0.prefix(1)) }
    open var eraSymbols = ["BC", "AD"]
    open var longEraSymbols = ["Before Christ", "Anno Domini"]
    open var quarterSymbols = ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"]
    open var shortQuarterSymbols = ["Q1", "Q2", "Q3", "Q4"]
    open var standaloneQuarterSymbols = ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"]
    open var shortStandaloneQuarterSymbols = ["Q1", "Q2", "Q3", "Q4"]

    public override init() { super.init() }

    /// The `en` patterns of the styles: short "10/9/26, 3:04 PM", medium "Oct 9, 2026",
    /// long "October 9, 2026 at 3:04:05 PM GMT", full "Friday, October 9, 2026 at 3:04:05 PM
    /// Greenwich Mean Time".
    private var stylePattern: String {
        _DatePattern.hostPattern(locale, "formatter:\(dateStyle.rawValue):\(timeStyle.rawValue)")
            ?? _DatePattern.formatterPattern(dateStyle: Int(dateStyle.rawValue), timeStyle: Int(timeStyle.rawValue))
    }

    /// Sets the pattern from a skeleton ("yMMMd" becomes "MMM d, y").
    open func setLocalizedDateFormatFromTemplate(_ template: String) { explicitFormat = Self.dateFormat(fromTemplate: template, options: 0, locale: locale) }

    public class func dateFormat(fromTemplate template: String, options: Int, locale: Locale?) -> String? {
        _DatePattern.hostPattern(locale, _DatePattern.canonical(template)) ?? _DatePattern.pattern(forSkeleton: template)
    }

    public class func localizedString(from date: Date, dateStyle: Style, timeStyle: Style) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    open func string(from date: Date) -> String {
        var symbols = _DatePattern.symbols(locale)
        if _DatePattern.isEnglishUS(locale) {
            // The formatter's own words, which an app may have set.
            symbols = _DatePattern.Symbols(months: monthSymbols, shortMonths: shortMonthSymbols, standaloneMonths: standaloneMonthSymbols,
                                           shortStandaloneMonths: shortStandaloneMonthSymbols, weekdays: weekdaySymbols, shortWeekdays: shortWeekdaySymbols,
                                           shortestWeekdays: _DatePattern.shortestWeekdayNames, narrowWeekdays: veryShortWeekdaySymbols, am: amSymbol, pm: pmSymbol)
        }
        return _DatePattern.format(dateFormat ?? "", Date.input(date, calendar: calendar, timeZone: timeZone), symbols: symbols)
    }

    /// The date in `string`, read by the pattern; nil when it does not fit.
    open func date(from string: String) -> Date? {
        guard let fields = _DatePattern.parse(string, pattern: dateFormat ?? "") else { return nil }
        let math = Date.math(calendar: calendar, timeZone: timeZone)
        return Date(timeIntervalSince1970: fields.time(in: math, reference: defaultDate?.timeIntervalSince1970))
    }

    open override func string(for obj: Any?) -> String? { (obj as? Date).map(string(from:)) }
    open override func value(from string: String) -> Any? { date(from: string) }
}

/// Foundation's `ISO8601DateFormatter` on wasm: RFC 3339 text in GMT by default
/// ("2026-10-31T12:00:00Z"), with the same options for the fields and separators.
open class ISO8601DateFormatter: Formatter, @unchecked Sendable {
    public struct Options: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withYear = Options(rawValue: 1 << 0)
        public static let withMonth = Options(rawValue: 1 << 1)
        public static let withWeekOfYear = Options(rawValue: 1 << 2)
        public static let withDay = Options(rawValue: 1 << 4)
        public static let withTime = Options(rawValue: 1 << 5)
        public static let withTimeZone = Options(rawValue: 1 << 6)
        public static let withSpaceBetweenDateAndTime = Options(rawValue: 1 << 7)
        public static let withDashSeparatorInDate = Options(rawValue: 1 << 8)
        public static let withColonSeparatorInTime = Options(rawValue: 1 << 9)
        public static let withColonSeparatorInTimeZone = Options(rawValue: 1 << 10)
        public static let withFractionalSeconds = Options(rawValue: 1 << 11)
        public static let withFullDate: Options = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        public static let withFullTime: Options = [.withTime, .withColonSeparatorInTime, .withTimeZone, .withColonSeparatorInTimeZone]
        public static let withInternetDateTime: Options = [.withFullDate, .withFullTime]
    }

    open var formatOptions: Options = .withInternetDateTime
    open var timeZone: TimeZone! = .gmt

    public override init() { super.init() }

    /// The LDML pattern the options describe.
    var pattern: String {
        let options = formatOptions
        let week = options.contains(.withWeekOfYear)
        var date: [String] = []
        if options.contains(.withYear) { date.append(week ? "YYYY" : "yyyy") }
        if week { date.append("'W'ww") } else if options.contains(.withMonth) { date.append("MM") }
        if options.contains(.withDay) { date.append(week ? "ee" : "dd") }
        var pattern = date.joined(separator: options.contains(.withDashSeparatorInDate) ? "-" : "")
        if options.contains(.withTime) {
            let time = ["HH", "mm", "ss"].joined(separator: options.contains(.withColonSeparatorInTime) ? ":" : "")
                + (options.contains(.withFractionalSeconds) ? ".SSS" : "")
            pattern += (pattern.isEmpty ? "" : options.contains(.withSpaceBetweenDateAndTime) ? " " : "'T'") + time
        }
        if options.contains(.withTimeZone) { pattern += options.contains(.withColonSeparatorInTimeZone) ? "XXXXX" : "XXXX" }
        return pattern
    }

    open func string(from date: Date) -> String {
        _DatePattern.format(pattern, Date.input(date, calendar: Calendar(identifier: .iso8601), timeZone: timeZone ?? .gmt))
    }

    /// The date in `string`, read by the options' pattern; nil when it does not fit.
    open func date(from string: String) -> Date? {
        guard let fields = _DatePattern.parse(string, pattern: pattern) else { return nil }
        return Date(timeIntervalSince1970: fields.time(in: Date.math(calendar: Calendar(identifier: .iso8601), timeZone: timeZone ?? .gmt)))
    }

    open class func string(from date: Date, timeZone: TimeZone, formatOptions: Options = []) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = formatOptions
        return formatter.string(from: date)
    }

    open override func string(for obj: Any?) -> String? { (obj as? Date).map(string(from:)) }
    open override func value(from string: String) -> Any? { date(from: string) }
}

/// Foundation's `RelativeDateTimeFormatter` on wasm: "2 hours ago", "in 3 days".
open class RelativeDateTimeFormatter: Formatter {
    public enum DateTimeStyle: Int, Sendable { case numeric = 0, named }
    public enum UnitsStyle: Int, Sendable { case full = 0, spellOut, short, abbreviated }

    open var dateTimeStyle: DateTimeStyle = .numeric
    open var unitsStyle: UnitsStyle = .full
    open var locale: Locale! = .autoupdatingCurrent
    open var calendar: Calendar! = .autoupdatingCurrent
    open var formattingContext: DateFormatter.Context = .unknown

    public override init() { super.init() }

    private var style: Date.RelativeFormatStyle {
        var style = Date.RelativeFormatStyle(presentation: dateTimeStyle == .named ? .named : .numeric, locale: locale, calendar: calendar)
        switch unitsStyle {
        case .full: style.unitsStyle = .wide
        case .spellOut: style.unitsStyle = .spellOut
        case .short: style.unitsStyle = .abbreviated
        case .abbreviated: style.unitsStyle = .narrow
        }
        return style
    }

    open func localizedString(for date: Date, relativeTo referenceDate: Date) -> String {
        let style = self.style
        let calendar = self.calendar ?? .current
        let math = _CalendarMath(zone: calendar.timeZone.rule, system: calendar.system, firstWeekday: calendar.firstWeekday, minimumDaysInFirstWeek: calendar.minimumDaysInFirstWeek)
        let components = _RelativeDateText.Components(from: referenceDate.timeIntervalSince1970, to: date.timeIntervalSince1970, math: math)
        return _RelativeDateText.text(components, presentation: style.presentation == .named ? .named : .numeric,
                                      unitsStyle: _RelativeDateText.UnitsStyle(style.unitsStyle), rounding: false)
    }

    open func localizedString(fromTimeInterval timeInterval: TimeInterval) -> String {
        localizedString(for: Date(timeIntervalSince1970: timeInterval), relativeTo: Date(timeIntervalSince1970: 0))
    }

    open func localizedString(from dateComponents: DateComponents) -> String {
        let calendar = self.calendar ?? .current
        let now = Date()
        guard let date = calendar.date(byAdding: dateComponents, to: now) else { return "" }
        return localizedString(for: date, relativeTo: now)
    }

    open override func string(for obj: Any?) -> String? { (obj as? Date).map { style.format($0) } }
}
#endif
