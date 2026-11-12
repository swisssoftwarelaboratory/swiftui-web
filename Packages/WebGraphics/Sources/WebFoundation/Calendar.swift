// Foundation's `Calendar`, `TimeZone`, `Locale` and `DateComponents` on wasm (decision 0017,
// pf-web-foundation-gaps). The arithmetical calendars (`_CalendarSystem`), named time zones
// answered by the host's `Intl` (`_ZoneRule`), English symbols. `_CalendarMath` does the
// arithmetic.
#if os(WASI)
import FoundationEssentials

public struct TimeZone: Hashable, Sendable, Codable, CustomStringConvertible {
    public let identifier: String
    package let rule: _ZoneRule

    private init(identifier: String, rule: _ZoneRule) {
        self.identifier = identifier
        self.rule = rule
    }

    /// "GMT", "UTC", a fixed offset written "GMT+5", "GMT-05:30", "UTC+0100", or a tz database
    /// name the host knows ("Europe/Berlin": the browser's `Intl` answers for its offsets,
    /// daylight saving included); a name the host does not know is nil.
    public init?(identifier: String) {
        let upper = identifier.uppercased()
        if upper == "GMT" || upper == "UTC" || upper == "ETC/GMT" || upper == "ETC/UTC" || upper == "Z" {
            self.init(identifier: "GMT", rule: .fixed(0))
            return
        }
        if (upper.hasPrefix("GMT") || upper.hasPrefix("UTC")), let sign = upper.dropFirst(3).first, sign == "+" || sign == "-" {
            let digits = upper.dropFirst(4).filter { $0 != ":" }
            guard !digits.isEmpty, digits.count <= 4, digits.allSatisfy(\.isNumber), let value = Int(digits) else { return nil }
            let hours = digits.count <= 2 ? value : value / 100
            let minutes = digits.count <= 2 ? 0 : value % 100
            guard hours <= 18, minutes < 60 else { return nil }
            let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
            self.init(secondsFromGMT: seconds)
            return
        }
        guard _ZoneCache.shared.knows(identifier) else { return nil }
        self.init(identifier: identifier, rule: .named(identifier))
    }

    /// Abbreviations are the fixed forms ("GMT", "UTC+2"); the host's zone names are not
    /// reversible.
    public init?(abbreviation: String) { self.init(identifier: abbreviation) }

    /// A fixed offset, named the way Foundation names it ("GMT+0530", "GMT" for zero).
    public init?(secondsFromGMT seconds: Int) {
        guard abs(seconds) <= 18 * 3600 else { return nil }
        if seconds == 0 { self.init(identifier: "GMT", rule: .fixed(0)); return }
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        let name = "GMT" + (seconds < 0 ? "-" : "+") + (hours < 10 ? "0" : "") + String(hours) + (minutes < 10 ? "0" : "") + String(minutes)
        self.init(identifier: name, rule: .fixed(seconds))
    }

    public static let gmt = TimeZone(identifier: "GMT", rule: .fixed(0))
    /// The browser's zone: its tz name when the host reports one it can answer for
    /// (`_hostIdentifier`), else its fixed offset (`_hostSecondsFromGMT`), else GMT.
    public static var current: TimeZone {
        if let name = _hostIdentifier, let zone = TimeZone(identifier: name) { return zone }
        return _hostSecondsFromGMT.flatMap { TimeZone(secondsFromGMT: $0) } ?? .gmt
    }
    public static var autoupdatingCurrent: TimeZone { current }
    /// Set by the canvas host from the browser's offset at launch.
    nonisolated(unsafe) public static var _hostSecondsFromGMT: Int?
    /// Set by the canvas host from `Intl.DateTimeFormat().resolvedOptions().timeZone`.
    nonisolated(unsafe) public static var _hostIdentifier: String?
    /// The host's offset for a tz name at an instant (seconds since 1970), nil for a name it
    /// does not know; the canvas host answers from `Intl`.
    public static var _hostOffset: (@Sendable (String, Double) -> Int?)? {
        get { _ZoneCache.hostOffset }
        set { _ZoneCache.hostOffset = newValue; _ZoneCache.shared.forget() }
    }
    /// The host's name for a tz zone at an instant, in one of `Intl`'s `timeZoneName` styles
    /// ("short", "long", "shortGeneric", "longGeneric").
    nonisolated(unsafe) public static var _hostName: (@Sendable (String, Double, String) -> String?)?
    /// The host's list of tz names (`Intl.supportedValuesOf("timeZone")`).
    nonisolated(unsafe) public static var _hostKnownIdentifiers: (@Sendable () -> [String])?

    public func secondsFromGMT(for date: Date = Date()) -> Int { rule.offset(at: date.timeIntervalSince1970) }
    public var secondsFromGMT: Int { secondsFromGMT(for: Date()) }
    /// The zone's abbreviation: the host's short name for a named zone ("CET", "GMT+2"), the
    /// fixed form otherwise.
    public func abbreviation(for date: Date = Date()) -> String? {
        if case .named = rule, let name = Self._hostName?(identifier, date.timeIntervalSince1970, "short") { return name }
        let offset = secondsFromGMT(for: date)
        if offset == 0 { return "GMT" }
        let hours = abs(offset) / 3600, minutes = abs(offset) % 3600 / 60
        return "GMT" + (offset < 0 ? "-" : "+") + String(hours) + (minutes > 0 ? ":" + (minutes < 10 ? "0" : "") + String(minutes) : "")
    }
    public var abbreviation: String? { abbreviation(for: Date()) }
    public func isDaylightSavingTime(for date: Date = Date()) -> Bool { daylightSavingTimeOffset(for: date) != 0 }
    public var isDaylightSavingTime: Bool { isDaylightSavingTime(for: Date()) }
    public func daylightSavingTimeOffset(for date: Date = Date()) -> TimeInterval {
        let time = date.timeIntervalSince1970
        return TimeInterval(rule.offset(at: time) - rule.standardOffset(at: time))
    }
    public var daylightSavingTimeOffset: TimeInterval { daylightSavingTimeOffset(for: Date()) }
    public func nextDaylightSavingTimeTransition(after date: Date) -> Date? {
        rule.nextTransition(after: date.timeIntervalSince1970).map { Date(timeIntervalSince1970: $0) }
    }
    public var nextDaylightSavingTimeTransition: Date? { nextDaylightSavingTimeTransition(after: Date()) }
    /// The host's localized name for a named zone (`Intl`'s long, short and generic names);
    /// the identifier for a fixed one.
    public func localizedName(for style: NameStyle, locale: Locale?) -> String? {
        guard case .named = rule else { return identifier }
        let now = Date().timeIntervalSince1970
        let intl: String
        switch style {
        case .standard, .daylightSaving: intl = "long"
        case .shortStandard, .shortDaylightSaving: intl = "short"
        case .generic: intl = "longGeneric"
        case .shortGeneric: intl = "shortGeneric"
        }
        return Self._hostName?(identifier, now, intl) ?? identifier
    }
    public static var knownTimeZoneIdentifiers: [String] { _hostKnownIdentifiers?() ?? ["GMT"] }
    public static var abbreviationDictionary: [String: String] { ["GMT": "GMT", "UTC": "GMT"] }
    public var description: String { identifier }

    public enum NameStyle: Sendable { case standard, shortStandard, daylightSaving, shortDaylightSaving, generic, shortGeneric }

    // Foundation encodes a zone as its identifier.
    public init(from decoder: Decoder) throws {
        let identifier = try decoder.singleValueContainer().decode(String.self)
        self = TimeZone(identifier: identifier) ?? .gmt
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
    public static func == (lhs: TimeZone, rhs: TimeZone) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

/// Foundation's `DateInterval` (a `UICalendarView`'s `availableDateRange`): FoundationEssentials'
/// drags its calendar formatting into the bundle (Counter grew 4 MB raw, 2026-10-08).
public struct DateInterval: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public var start: Date
    public var duration: TimeInterval
    public var end: Date {
        get { start.addingTimeInterval(duration) }
        set { duration = newValue.timeIntervalSince(start) }
    }

    public init() { start = Date(); duration = 0 }
    public init(start: Date, end: Date) {
        self.start = start
        duration = max(0, end.timeIntervalSince(start))
    }
    public init(start: Date, duration: TimeInterval) {
        self.start = start
        self.duration = max(0, duration)
    }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }
    public func intersects(_ other: DateInterval) -> Bool { contains(other.start) || contains(other.end) || other.contains(start) }
    public func intersection(with other: DateInterval) -> DateInterval? {
        guard intersects(other) else { return nil }
        return DateInterval(start: max(start, other.start), end: min(end, other.end))
    }
    public static func < (lhs: DateInterval, rhs: DateInterval) -> Bool {
        lhs.start < rhs.start || (lhs.start == rhs.start && lhs.duration < rhs.duration)
    }
    public var description: String { "\(start) to \(end)" }
}

public struct Locale: Hashable, Sendable, Codable, CustomStringConvertible {
    public let identifier: String
    public init(identifier: String) { self.identifier = identifier }
    /// The browser's language once the host reports it (`navigator.language`, "en-US" becoming
    /// "en_US"), else en_US.
    public static var current: Locale { Locale(identifier: _hostIdentifier.map(Self.normalized) ?? "en_US") }
    public static var autoupdatingCurrent: Locale { current }
    /// Set by the canvas host from `navigator.language`.
    nonisolated(unsafe) public static var _hostIdentifier: String?
    /// Set by the canvas host from `navigator.languages`.
    nonisolated(unsafe) public static var _hostPreferredLanguages: [String]?
    public static var preferredLanguages: [String] { _hostPreferredLanguages ?? [_hostIdentifier ?? "en-US"] }
    /// Set by the canvas host from `Intl.DisplayNames`: the name, in the language of a locale
    /// (BCP 47), of a language, region or script code (`type` is "language", "region" or
    /// "script"); nil for a code it doesn't know.
    nonisolated(unsafe) public static var _hostDisplayName: ((_ locale: String, _ type: String, _ code: String) -> String?)?
    /// Set by the canvas host from `Intl.DateTimeFormat`: the LDML pattern a locale (BCP 47)
    /// formats a canonical skeleton (`"EEEEdMMMM"`) or a style (`"style:<date>:<time>"`, the
    /// `Date.FormatStyle` raw values) with; nil when it can't say, and then the `en` pattern is used.
    nonisolated(unsafe) public static var _hostDatePattern: ((_ locale: String, _ request: String) -> String?)?
    /// Set by the canvas host from `Intl.DateTimeFormat`: a locale's month and weekday names and
    /// day periods.
    nonisolated(unsafe) package static var _hostDateSymbols: ((_ locale: String) -> _DatePattern.Symbols?)?
    private static func normalized(_ tag: String) -> String { String(tag.map { $0 == "-" ? "_" : $0 }) }
    public var languageCode: String? { identifier.split { $0 == "_" || $0 == "-" }.first.map(String.init) }
    public var regionCode: String? {
        let parts = identifier.split { $0 == "_" || $0 == "-" || $0 == "@" }
        return parts.dropFirst().first { $0.count == 2 || ($0.count == 3 && $0.allSatisfy(\.isNumber)) }.map(String.init)
    }
    public var scriptCode: String? { identifier.split { $0 == "_" || $0 == "-" }.dropFirst().first { $0.count == 4 }.map(String.init) }
    public var calendar: Calendar { Calendar(identifier: .gregorian) }
    /// "en-US" for "en_US".
    public func identifier(_ type: IdentifierType) -> String {
        switch type {
        case .bcp47: return String(identifier.map { $0 == "_" ? "-" : $0 })
        case .icu, .cldr: return identifier
        }
    }
    public enum IdentifierType: Sendable { case icu, bcp47, cldr }
    public var description: String { identifier }
}

public struct DateComponents: Hashable, Sendable, Codable, CustomStringConvertible {
    public var calendar: Calendar?
    public var timeZone: TimeZone?
    public var era: Int?
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var second: Int?
    public var nanosecond: Int?
    public var weekday: Int?
    public var weekdayOrdinal: Int?
    public var quarter: Int?
    public var weekOfMonth: Int?
    public var weekOfYear: Int?
    public var yearForWeekOfYear: Int?
    public var dayOfYear: Int?
    public var isLeapMonth: Bool?

    public init(calendar: Calendar? = nil, timeZone: TimeZone? = nil, era: Int? = nil, year: Int? = nil, month: Int? = nil, day: Int? = nil,
                hour: Int? = nil, minute: Int? = nil, second: Int? = nil, nanosecond: Int? = nil, weekday: Int? = nil, weekdayOrdinal: Int? = nil,
                quarter: Int? = nil, weekOfMonth: Int? = nil, weekOfYear: Int? = nil, yearForWeekOfYear: Int? = nil) {
        self.calendar = calendar; self.timeZone = timeZone; self.era = era; self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second; self.nanosecond = nanosecond; self.weekday = weekday
        self.weekdayOrdinal = weekdayOrdinal; self.quarter = quarter; self.weekOfMonth = weekOfMonth; self.weekOfYear = weekOfYear
        self.yearForWeekOfYear = yearForWeekOfYear
    }

    /// The date, when a calendar is set (Foundation's rule).
    public var date: Date? { calendar?.date(from: self) }
    public var isValidDate: Bool { calendar.map { isValidDate(in: $0) } ?? false }
    public func isValidDate(in calendar: Calendar) -> Bool {
        guard let date = calendar.date(from: self) else { return false }
        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return (year ?? back.year) == back.year && (month ?? back.month) == back.month && (day ?? back.day) == back.day
            && (hour ?? back.hour) == back.hour && (minute ?? back.minute) == back.minute && (second ?? back.second) == back.second
    }

    public func value(for component: Calendar.Component) -> Int? {
        switch component {
        case .era: return era
        case .year: return year
        case .month: return month
        case .day: return day
        case .hour: return hour
        case .minute: return minute
        case .second: return second
        case .nanosecond: return nanosecond
        case .weekday: return weekday
        case .weekdayOrdinal: return weekdayOrdinal
        case .quarter: return quarter
        case .weekOfMonth: return weekOfMonth
        case .weekOfYear: return weekOfYear
        case .yearForWeekOfYear: return yearForWeekOfYear
        case .dayOfYear: return dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return nil
        }
    }

    public mutating func setValue(_ value: Int?, for component: Calendar.Component) {
        switch component {
        case .era: era = value
        case .year: year = value
        case .month: month = value
        case .day: day = value
        case .hour: hour = value
        case .minute: minute = value
        case .second: second = value
        case .nanosecond: nanosecond = value
        case .weekday: weekday = value
        case .weekdayOrdinal: weekdayOrdinal = value
        case .quarter: quarter = value
        case .weekOfMonth: weekOfMonth = value
        case .weekOfYear: weekOfYear = value
        case .yearForWeekOfYear: yearForWeekOfYear = value
        case .dayOfYear: dayOfYear = value
        case .calendar, .timeZone, .isLeapMonth: break
        }
    }

    public var description: String {
        var parts: [String] = []
        if let calendar { parts.append("calendar: \(calendar)") }
        if let timeZone { parts.append("timeZone: \(timeZone)") }
        for (name, value) in [("era", era), ("year", year), ("month", month), ("day", day), ("hour", hour), ("minute", minute), ("second", second),
                              ("nanosecond", nanosecond), ("weekday", weekday), ("weekdayOrdinal", weekdayOrdinal), ("quarter", quarter),
                              ("weekOfMonth", weekOfMonth), ("weekOfYear", weekOfYear), ("yearForWeekOfYear", yearForWeekOfYear)] {
            if let value { parts.append("\(name): \(value)") }
        }
        return parts.joined(separator: " ")
    }
}

public struct Calendar: Hashable, Sendable, Codable, CustomStringConvertible {
    public enum Identifier: String, Sendable, Codable, CaseIterable {
        case gregorian, buddhist, chinese, coptic, ethiopicAmeteMihret, ethiopicAmeteAlem, hebrew, iso8601, indian,
             islamic, islamicCivil, islamicTabular, islamicUmmAlQura, japanese, persian, republicOfChina
    }

    public enum Component: Hashable, Sendable, Codable, CaseIterable {
        case era, year, month, day, hour, minute, second, weekday, weekdayOrdinal, quarter, weekOfMonth, weekOfYear,
             yearForWeekOfYear, nanosecond, calendar, timeZone, isLeapMonth, dayOfYear
    }

    public let identifier: Identifier
    public var timeZone: TimeZone
    public var locale: Locale?
    /// 1 = Sunday.
    public var firstWeekday: Int = 1
    public var minimumDaysInFirstWeek: Int = 1

    public init(identifier: Identifier) {
        self.identifier = identifier
        timeZone = .current
        locale = .current
        if identifier == .iso8601 { firstWeekday = 2; minimumDaysInFirstWeek = 4 }
    }
    public static var current: Calendar { Calendar(identifier: .gregorian) }
    public static var autoupdatingCurrent: Calendar { current }

    /// The arithmetic behind the identifier. The Chinese calendar has no arithmetical form
    /// and reports Gregorian fields; `islamic` and `islamicUmmAlQura` use the tabular civil
    /// calendar (Foundation's follow astronomical tables and can differ by a day).
    package var system: _CalendarSystem {
        switch identifier {
        case .gregorian, .iso8601, .chinese: return .gregorian
        case .buddhist: return .buddhist
        case .japanese: return .japanese
        case .republicOfChina: return .republicOfChina
        case .islamic, .islamicCivil, .islamicUmmAlQura: return .islamicCivil
        case .islamicTabular: return .islamicTabular
        case .persian: return .persian
        case .hebrew: return .hebrew
        case .coptic: return .coptic
        case .ethiopicAmeteMihret: return .ethiopicAmeteMihret
        case .ethiopicAmeteAlem: return .ethiopicAmeteAlem
        case .indian: return .indian
        }
    }

    private var math: _CalendarMath { math(in: nil) }
    private func math(in zone: TimeZone?) -> _CalendarMath {
        _CalendarMath(zone: (zone ?? timeZone).rule, system: system, firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek)
    }

    private static func unit(_ component: Component) -> _CalendarUnit? {
        switch component {
        case .era: return .era
        case .year: return .year
        case .month: return .month
        case .day: return .day
        case .hour: return .hour
        case .minute: return .minute
        case .second: return .second
        case .weekday: return .weekday
        case .weekdayOrdinal: return .weekdayOrdinal
        case .quarter: return .quarter
        case .weekOfMonth: return .weekOfMonth
        case .weekOfYear: return .weekOfYear
        case .yearForWeekOfYear: return .yearForWeekOfYear
        case .nanosecond: return .nanosecond
        case .dayOfYear: return .dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return nil
        }
    }

    public func component(_ component: Component, from date: Date) -> Int {
        let math = math
        let time = date.timeIntervalSince1970
        let f = math.fields(time)
        switch component {
        case .era: return math.era(time)
        case .year: return f.year
        case .month: return f.month
        case .day: return f.day
        case .hour: return f.hour
        case .minute: return f.minute
        case .second: return f.second
        case .nanosecond: return f.nanosecond
        case .weekday: return f.weekday
        case .weekdayOrdinal: return (f.day - 1) / 7 + 1
        case .quarter: return (f.month - 1) / 3 + 1
        case .weekOfMonth: return math.weekOfMonth(time)
        case .weekOfYear: return math.weekOfYear(time).week
        case .yearForWeekOfYear: return math.weekOfYear(time).year
        case .dayOfYear: return f.dayOfYear
        case .calendar, .timeZone, .isLeapMonth: return 0
        }
    }

    public func dateComponents(_ components: Set<Component>, from date: Date) -> DateComponents {
        var result = DateComponents()
        for component in components {
            switch component {
            case .calendar: result.calendar = self
            case .timeZone: result.timeZone = timeZone
            case .isLeapMonth: result.isLeapMonth = false
            default: result.setValue(self.component(component, from: date), for: component)
            }
        }
        return result
    }

    public func dateComponents(in zone: TimeZone, from date: Date) -> DateComponents {
        var calendar = self
        calendar.timeZone = zone
        var result = calendar.dateComponents(Set(Component.allCases), from: date)
        result.calendar = self
        result.timeZone = zone
        return result
    }

    public func dateComponents(_ components: Set<Component>, from start: Date, to end: Date) -> DateComponents {
        let units = Set(components.compactMap(Self.unit))
        let difference = math.difference(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970, units: units)
        var result = DateComponents()
        for component in components {
            if let unit = Self.unit(component), let value = difference[unit] { result.setValue(value, for: component) }
        }
        return result
    }

    public func dateComponents(_ components: Set<Component>, from start: DateComponents, to end: DateComponents) -> DateComponents {
        guard let a = date(from: start), let b = date(from: end) else { return DateComponents() }
        return dateComponents(components, from: a, to: b)
    }

    /// The date of the components: year, month and day default to 1, the time to midnight;
    /// values past their range carry over. Week and weekday fields are not used.
    public func date(from components: DateComponents) -> Date? {
        let math = math(in: components.timeZone)
        let time = math.time(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1,
                             hour: components.hour ?? 0, minute: components.minute ?? 0, second: components.second ?? 0,
                             nanosecond: components.nanosecond ?? 0, era: components.era)
        return Date(timeIntervalSince1970: time)
    }

    public func date(byAdding component: Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
        guard let unit = Self.unit(component) else { return nil }
        let time = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: wrappingComponents ? math.addingWrapped(unit, value, to: time) : math.adding(unit, value, to: time))
    }

    public func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
        var time = date.timeIntervalSince1970
        let math = math
        for component in [Component.era, .year, .quarter, .month, .weekOfYear, .weekOfMonth, .day, .hour, .minute, .second, .nanosecond] {
            if let value = components.value(for: component), let unit = Self.unit(component) {
                time = wrappingComponents ? math.addingWrapped(unit, value, to: time) : math.adding(unit, value, to: time)
            }
        }
        return Date(timeIntervalSince1970: time)
    }

    /// The date on the same day at the time (WebFoundationFormats adds the form that takes the
    /// search policies).
    public func date(bySettingHour hour: Int, minute: Int, second: Int, of date: Date) -> Date? {
        let f = math.fields(date.timeIntervalSince1970)
        return Date(timeIntervalSince1970: math.time(year: f.year, month: f.month, day: f.day, hour: hour, minute: minute, second: second, era: f.era))
    }

    public func date(bySetting component: Component, value: Int, of date: Date) -> Date? {
        var components = dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        switch component {
        case .year, .month, .day, .hour, .minute, .second, .nanosecond: components.setValue(value, for: component)
        default: return nil
        }
        return self.date(from: components)
    }

    public func range(of smaller: Component, in larger: Component, for date: Date) -> Range<Int>? {
        guard let s = Self.unit(smaller), let l = Self.unit(larger) else { return nil }
        return math.range(of: s, in: l, for: date.timeIntervalSince1970)
    }

    public func startOfDay(for date: Date) -> Date { Date(timeIntervalSince1970: math.startOfDay(date.timeIntervalSince1970)) }

    public func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool {
        math.split(date1.timeIntervalSince1970).days == math.split(date2.timeIntervalSince1970).days
    }
    public func isDateInToday(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date()) }
    public func isDateInYesterday(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date(timeIntervalSinceNow: -86400)) }
    public func isDateInTomorrow(_ date: Date) -> Bool { isDate(date, inSameDayAs: Date(timeIntervalSinceNow: 86400)) }
    public func isDateInWeekend(_ date: Date) -> Bool {
        let weekday = component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    public func compare(_ date1: Date, to date2: Date, toGranularity component: Component) -> ComparisonResult {
        let a = date1.timeIntervalSince1970, b = date2.timeIntervalSince1970
        let math = math
        func key(_ t: Double) -> [Int] {
            let f = math.fields(t)
            switch component {
            case .era: return [math.era(t)]
            case .year: return [math.era(t), f.year]
            case .quarter: return [f.year, (f.month - 1) / 3]
            case .month: return [f.year, f.month]
            case .weekOfYear, .yearForWeekOfYear: let w = math.weekOfYear(t); return [w.year, w.week]
            case .weekOfMonth: return [f.year, f.month, math.weekOfMonth(t)]
            case .day, .weekday, .weekdayOrdinal, .dayOfYear: return [f.year, f.month, f.day]
            case .hour: return [f.year, f.month, f.day, f.hour]
            case .minute: return [f.year, f.month, f.day, f.hour, f.minute]
            case .second: return [f.year, f.month, f.day, f.hour, f.minute, f.second]
            case .nanosecond: return [f.year, f.month, f.day, f.hour, f.minute, f.second, f.nanosecond]
            case .calendar, .timeZone, .isLeapMonth: return []
            }
        }
        let ka = key(a), kb = key(b)
        return ka.lexicographicallyPrecedes(kb) ? .orderedAscending : ka == kb ? .orderedSame : .orderedDescending
    }
    public func isDate(_ date1: Date, equalTo date2: Date, toGranularity component: Component) -> Bool {
        compare(date1, to: date2, toGranularity: component) == .orderedSame
    }

    /// Days and weekdays counted from the start of the larger unit, one-based.
    public func ordinality(of smaller: Component, in larger: Component, for date: Date) -> Int? {
        let f = math.fields(date.timeIntervalSince1970)
        switch (smaller, larger) {
        case (.day, .year): return f.dayOfYear
        case (.day, .month): return f.day
        case (.month, .year): return f.month
        case (.day, .weekOfYear), (.day, .weekOfMonth): return _Gregorian.floorMod(f.weekday - firstWeekday, 7) + 1
        case (.weekday, .month): return (f.day - 1) / 7 + 1
        case (.hour, .day): return f.hour + 1
        case (.minute, .hour): return f.minute + 1
        case (.second, .minute): return f.second + 1
        case (.quarter, .year): return (f.month - 1) / 3 + 1
        default: return nil
        }
    }

    public var monthSymbols: [String] { ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"] }
    public var shortMonthSymbols: [String] { ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"] }
    public var veryShortMonthSymbols: [String] { ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"] }
    public var standaloneMonthSymbols: [String] { monthSymbols }
    public var shortStandaloneMonthSymbols: [String] { shortMonthSymbols }
    public var veryShortStandaloneMonthSymbols: [String] { veryShortMonthSymbols }
    public var weekdaySymbols: [String] { ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] }
    public var shortWeekdaySymbols: [String] { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] }
    public var veryShortWeekdaySymbols: [String] { ["S", "M", "T", "W", "T", "F", "S"] }
    public var standaloneWeekdaySymbols: [String] { weekdaySymbols }
    public var shortStandaloneWeekdaySymbols: [String] { shortWeekdaySymbols }
    public var veryShortStandaloneWeekdaySymbols: [String] { veryShortWeekdaySymbols }
    public var quarterSymbols: [String] { ["1st quarter", "2nd quarter", "3rd quarter", "4th quarter"] }
    public var shortQuarterSymbols: [String] { ["Q1", "Q2", "Q3", "Q4"] }
    public var eraSymbols: [String] { ["BC", "AD"] }
    public var longEraSymbols: [String] { ["Before Christ", "Anno Domini"] }
    public var amSymbol: String { "AM" }
    public var pmSymbol: String { "PM" }

    public var description: String { identifier.rawValue }
}

extension Locale {
    /// A day of the week (Foundation's, as AlarmKit's weekly recurrence and `Locale.firstDayOfWeek` name it).
    public enum Weekday: String, Codable, Hashable, Sendable, CaseIterable {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday
    }
}
#endif
