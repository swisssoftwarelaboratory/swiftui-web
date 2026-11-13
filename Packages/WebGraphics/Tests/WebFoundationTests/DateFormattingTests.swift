// pf-web-foundation-gaps: the date pattern core held to Foundation's en_US output for the
// `Date.FormatStyle` styles and symbols, `DateFormatter`'s styles and patterns, ISO 8601 and
// the relative forms.
import Testing
import Foundation
@testable import WebFoundation

/// Foundation on macOS 26 is the reference (its ICU made the goldens). macOS 15's and Linux's
/// swift-foundation ICU differ in a few places — the zero localized GMT offset as a bare "GMT"
/// (CLDR's zero format), the hour without its period padded to two digits, Amete Alem reported
/// as Gregorian, a 385-day Hebrew 5806 — so those comparisons run only on current systems.
let foundationIsCurrent: Bool = {
    #if os(macOS)
    return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
    #else
    return false
    #endif
}()

@Suite struct DateFormattingTests {
    static let zone = TimeZone(secondsFromGMT: 0)!
    static let locale = Locale(identifier: "en_US")
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        return calendar
    }
    static let math = _CalendarMath(offset: 0)

    /// A spread of instants: every hour of a day, month ends, both halves of the day, 1900–2100.
    static var samples: [Date] {
        var generator = CalendarMathTests.SplitMix(seed: 11)
        var times = (0..<120).map { _ in Double(Int(generator.next() % (200 * 366 * 86400)) - 70 * 365 * 86400) }
        times += [0, 43200, 1_775_000_000, 1_767_225_600, 1_775_912_645.25, 2_000_000_000, 951_782_400, 4_102_444_799]
        return times.map { Date(timeIntervalSince1970: $0.rounded(.down)) }
    }

    /// The pattern core's input, with Foundation's names for the zone (the browser's `Intl`
    /// provides them on wasm; the engine is what is under test).
    static func input(_ date: Date) -> _DateFormatInput {
        _DateFormatInput(time: date.timeIntervalSince1970, math: math) { style in
            switch style {
            case "long": return zone.localizedName(for: .standard, locale: locale) ?? "GMT"
            case "shortGeneric": return zone.localizedName(for: .shortGeneric, locale: locale) ?? "GMT"
            case "longGeneric": return zone.localizedName(for: .generic, locale: locale) ?? "GMT"
            case "identifier": return zone.identifier
            default: return zone.abbreviation(for: date) ?? "GMT"
            }
        }
    }

    @Test func dateAndTimeStylesMatchFoundation() {
        let dates: [(Int?, Date.FormatStyle.DateStyle?)] = [(nil, nil), (0, .omitted), (1, .numeric), (2, .abbreviated), (3, .long), (4, .complete)]
        let times: [(Int?, Date.FormatStyle.TimeStyle?)] = [(nil, nil), (0, .omitted), (1, .shortened), (2, .standard), (3, .complete)]
        for date in Self.samples {
            for (d, dateStyle) in dates {
                for (t, timeStyle) in times {
                    var style = Date.FormatStyle(date: dateStyle, time: timeStyle, locale: Self.locale, calendar: Self.calendar, timeZone: Self.zone)
                    if dateStyle == nil, timeStyle == nil { style = Date.FormatStyle(locale: Self.locale, calendar: Self.calendar, timeZone: Self.zone) }
                    if dateStyle == nil, let timeStyle { style = Date.FormatStyle(time: timeStyle, locale: Self.locale, calendar: Self.calendar, timeZone: Self.zone) }
                    if timeStyle == nil, let dateStyle { style = Date.FormatStyle(date: dateStyle, locale: Self.locale, calendar: Self.calendar, timeZone: Self.zone) }
                    let dateRaw = d ?? (t == nil ? 1 : 0), timeRaw = t ?? (d == nil ? 1 : 0)
                    let pattern = _DatePattern.stylePattern(date: dateRaw, time: timeRaw)
                    // Foundation names the fixed GMT zone "GMT+0" before 1970 while `abbreviation(for:)`
                    // says "GMT"; the engine takes the host's name, so zone forms are compared from 1970.
                    if pattern.contains("z"), date.timeIntervalSince1970 < 0 { continue }
                    #expect(_DatePattern.format(pattern, Self.input(date)) == style.format(date), "date \(String(describing: d)) time \(String(describing: t)) at \(date.timeIntervalSince1970)")
                }
            }
        }
    }

    /// Symbol combinations and the skeletons they are, as `Date.FormatStyle` builds them.
    static let symbolCases: [(String, @Sendable (Date.FormatStyle) -> Date.FormatStyle)] = [
        ("y", { $0.year() }), ("yy", { $0.year(.twoDigits) }), ("MMM", { $0.month() }), ("MMMM", { $0.month(.wide) }), ("M", { $0.month(.defaultDigits) }),
        ("MM", { $0.month(.twoDigits) }), ("MMMMM", { $0.month(.narrow) }), ("d", { $0.day() }), ("dd", { $0.day(.twoDigits) }), ("EEE", { $0.weekday() }),
        ("EEEE", { $0.weekday(.wide) }), ("EEEEE", { $0.weekday(.narrow) }), ("EEEEEE", { $0.weekday(.short) }), ("h", { $0.hour() }), ("J", { $0.hour(.defaultDigits(amPM: .omitted)) }),
        ("JJ", { $0.hour(.twoDigits(amPM: .omitted)) }), ("hh", { $0.hour(.twoDigits(amPM: .abbreviated)) }), ("m", { $0.minute() }), ("mm", { $0.minute(.twoDigits) }), ("s", { $0.second() }),
        ("G", { $0.era() }), ("GGGG", { $0.era(.wide) }), ("QQQ", { $0.quarter() }), ("QQQQ", { $0.quarter(.wide) }), ("Q", { $0.quarter(.oneDigit) }),
        ("D", { $0.dayOfYear() }), ("DDD", { $0.dayOfYear(.threeDigits) }), ("w", { $0.week() }), ("W", { $0.week(.weekOfMonth) }),
        ("yMMMd", { $0.year().month().day() }), ("yMMMMd", { $0.year().month(.wide).day() }), ("yMd", { $0.year().month(.defaultDigits).day() }),
        ("MMMd", { $0.month().day() }), ("Md", { $0.month(.defaultDigits).day() }), ("yMMM", { $0.year().month() }), ("yMMMM", { $0.year().month(.wide) }),
        ("yM", { $0.year().month(.defaultDigits) }), ("hm", { $0.hour().minute() }), ("Jm", { $0.hour(.defaultDigits(amPM: .omitted)).minute() }), ("hms", { $0.hour().minute().second() }),
        ("Jms", { $0.hour(.defaultDigits(amPM: .omitted)).minute().second() }), ("ms", { $0.minute().second() }), ("yMMMEd", { $0.year().month().day().weekday() }),
        ("yMMMMEEEEd", { $0.year().month(.wide).day().weekday(.wide) }), ("MMMEd", { $0.month().day().weekday() }), ("MEd", { $0.month(.defaultDigits).day().weekday() }),
        ("yMEd", { $0.year().month(.defaultDigits).day().weekday() }), ("Ed", { $0.day().weekday() }), ("Ehm", { $0.weekday().hour().minute() }),
        ("yMMMdhm", { $0.year().month().day().hour().minute() }), ("yMMMMdhm", { $0.year().month(.wide).day().hour().minute() }), ("yMdJm", { $0.year().month(.defaultDigits).day().hour(.defaultDigits(amPM: .omitted)).minute() }),
        ("MMMdhms", { $0.month().day().hour().minute().second() }), ("yMMMEdhm", { $0.year().month().day().weekday().hour().minute() }),
        ("yQQQ", { $0.year().quarter() }), ("GyMMMd", { $0.era().year().month().day() }), ("MMMMd", { $0.month(.wide).day() }), ("yyMMdd", { $0.year(.twoDigits).month(.twoDigits).day(.twoDigits) }),
        ("hmz", { $0.hour().minute().timeZone() }), ("hmsz", { $0.hour().minute().second().timeZone() }), ("hmO", { $0.hour().minute().timeZone(.localizedGMT(.short)) }),
    ]

    @Test func symbolSkeletonsMatchFoundation() {
        let base = Date.FormatStyle(locale: Self.locale, calendar: Self.calendar, timeZone: Self.zone)
        for date in Self.samples.prefix(40) {
            for (skeleton, build) in Self.symbolCases {
                if skeleton.contains("z"), date.timeIntervalSince1970 < 0 { continue }
                // Older ICU pads the hour without its period ("J") and names the zero offset "GMT".
                if !foundationIsCurrent, skeleton.contains("J") || skeleton.contains("z") || skeleton.contains("O") { continue }
                let theirs = build(base).format(date)
                let ours = _DatePattern.format(_DatePattern.pattern(forSkeleton: skeleton), Self.input(date))
                #expect(ours == theirs, "\(skeleton) → \(_DatePattern.pattern(forSkeleton: skeleton)) at \(date.timeIntervalSince1970)")
            }
        }
    }

    @Test func formatterStylesAndPatternsMatchFoundation() {
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        formatter.timeZone = Self.zone
        formatter.calendar = Self.calendar
        for date in Self.samples.prefix(30) {
            for dateStyle in 0...4 {
                for timeStyle in 0...4 {
                    formatter.dateStyle = DateFormatter.Style(rawValue: UInt(dateStyle))!
                    formatter.timeStyle = DateFormatter.Style(rawValue: UInt(timeStyle))!
                    formatter.dateFormat = nil
                    let pattern = _DatePattern.formatterPattern(dateStyle: dateStyle, timeStyle: timeStyle)
                    if pattern.contains("z"), date.timeIntervalSince1970 < 0 { continue }
                    #expect(_DatePattern.format(pattern, Self.input(date)) == formatter.string(from: date), "styles \(dateStyle) \(timeStyle) at \(date.timeIntervalSince1970)")
                }
            }
            for pattern in ["yyyy-MM-dd'T'HH:mm:ssZ", "EEEE, d MMMM yyyy", "h 'o''clock' a", "yyyy.MM.dd G 'at' HH:mm:ss zzz", "EEE, MMM d, ''yy", "hh:mm:ss a, zzzz", "K:mm a, z", "yyyyy.MMMMM.dd GGG hh:mm aaa",
                            "D/w/W F", "QQQQ yyyy", "u-MM-dd", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "xx x xxx", "ZZZZ ZZZZZ", "OOOO O", "e ee c cc EEEEEE", "L LL LLL LLLL", "k kk", "A"] {
                if !foundationIsCurrent, pattern.contains("O") || pattern.contains("ZZZZ") { continue }   // older ICU: a bare "GMT" at zero
                formatter.dateFormat = pattern
                if (pattern.contains("z") || pattern.contains("v")), date.timeIntervalSince1970 < 0 { continue }
                #expect(_DatePattern.format(pattern, Self.input(date)) == formatter.string(from: date), "\(pattern) at \(date.timeIntervalSince1970)")
            }
        }
    }

    @Test func templatesMatchFoundation() {
        for template in ["yMMMd", "MMMd", "yMMMMEEEEd", "Hm", "hm", "yMd", "MMMMd", "yMMM", "Md", "yQQQ", "hms", "Ehm", "yMEd", "y", "d", "MMM"] {
            #expect(_DatePattern.pattern(forSkeleton: template) == DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: Self.locale), Comment(rawValue: template))
        }
    }

    @Test func parsingReadsWhatFormattingWrote() {
        for date in Self.samples.prefix(40) {
            for pattern in ["M/d/y, h:mm:ss\u{202F}a", "MMMM d, y 'at' h:mm\u{202F}a", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "EEEE, MMMM d, y", "MMM d, y", "d MMM yyyy HH:mm", "yyyy-MM-dd HH:mm:ss.SSS"] {
                let text = _DatePattern.format(pattern, Self.input(date))
                let fields = _DatePattern.parse(text, pattern: pattern)
                #expect(fields != nil, "\(pattern): \(text)")
                guard let fields else { continue }
                // Patterns without a time read midnight; those without seconds drop them.
                var expected = date.timeIntervalSince1970
                let hasTime = pattern.contains("H") || pattern.contains("h"), hasSeconds = pattern.contains("s")
                if !hasTime { expected = Self.math.startOfDay(expected) } else if !hasSeconds { expected -= Double(Self.math.fields(expected).second) }
                #expect(fields.time(in: Self.math) == expected, "\(pattern): \(text)")
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Self.locale
        formatter.timeZone = Self.zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm Z"
        for text in ["2026-10-09 15:04 +0200", "1999-12-31 23:59 -0530", "2000-02-29 00:00 +0000"] {
            #expect(_DatePattern.parse(text, pattern: formatter.dateFormat)?.time(in: Self.math) == formatter.date(from: text)?.timeIntervalSince1970, Comment(rawValue: text))
        }
        #expect(_DatePattern.parse("not a date", pattern: "yyyy-MM-dd") == nil && _DatePattern.parse("2026-13-45 extra", pattern: "yyyy-MM-dd") == nil)
    }

    @Test func iso8601MatchesFoundation() {
        for date in Self.samples.prefix(40) {
            #expect(_DatePattern.format("yyyy-MM-dd'T'HH:mm:ssXXXX", Self.input(date)) == date.formatted(.iso8601), "iso at \(date.timeIntervalSince1970)")
            #expect(_DatePattern.format("yyyy-MM-dd", Self.input(date)) == date.formatted(.iso8601.year().month().day()), "iso date at \(date.timeIntervalSince1970)")
            #expect(_DatePattern.format("yyyy-MM-dd'T'HH:mm:ss.SSSXXXX", Self.input(date)) == date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)), "iso fractional at \(date.timeIntervalSince1970)")
            #expect(_DatePattern.format("yyyy-MM-dd'T'HH:mm:ssXXXXX", Self.input(date)) == date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .colon)), "iso colon at \(date.timeIntervalSince1970)")
            #expect(_DatePattern.format("yyyy-MM-dd HH:mm:ss", Self.input(date)) == date.formatted(.iso8601.year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: false)), "iso space at \(date.timeIntervalSince1970)")
        }
    }

    @Test func relativeFormsMatchFoundation() {
        let offsets: [Double] = [-5, -59, -60, -119, -3599, -3600, -7200, -86399, -86400, -172800, -604800, -1_209_600, -2_592_000, -5_184_000, -31_536_000, -63_072_000,
                                 5, 59, 60, 3600, 7200, 86400, 172800, 604800, 2_592_000, 31_536_000, 63_072_000, 0]
        var calendar = Self.calendar
        calendar.timeZone = Self.zone
        #if _runtime(_ObjC)
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Self.locale
        formatter.calendar = calendar
        #endif
        for offset in offsets {
            // The style measures from the current time; the reference is taken just before each call.
            // Thirty and sixty days are "4 weeks" or "1 month" depending on the calendar date the
            // test runs on (month lengths, the DST change): those offsets are compared against the
            // formatter at a fixed reference below instead (CI at 00:04 UTC on 2026-10-12 saw
            // Foundation say "in 1 month" where an hour earlier it said "in 4 weeks").
            let dateDependent = abs(offset) == 2_592_000 || abs(offset) == 5_184_000
            for (presentation, theirPresentation) in [(_RelativeDateText.Presentation.numeric, Date.RelativeFormatStyle.Presentation.numeric), (.named, .named)] where !dateDependent {
                for (units, theirUnits) in [(_RelativeDateText.UnitsStyle.wide, Date.RelativeFormatStyle.UnitsStyle.wide), (.abbreviated, .abbreviated), (.narrow, .narrow), (.spellOut, .spellOut)] {
                    let now = Date()
                    let date = now.addingTimeInterval(offset)
                    let style = Date.RelativeFormatStyle(presentation: theirPresentation, unitsStyle: theirUnits, locale: Self.locale, calendar: calendar)
                    let theirs = style.format(date)
                    let components = _RelativeDateText.Components(from: now.timeIntervalSince1970, to: date.timeIntervalSince1970, math: Self.math)
                    let ours = _RelativeDateText.text(components, presentation: presentation, unitsStyle: units)
                    #expect(ours == theirs, "\(offset) \(presentation) \(units)")
                }
            }
            #if _runtime(_ObjC)   // corelibs Foundation has no RelativeDateTimeFormatter
            // The formatter keeps whole units (no rounding) and maps full and spellOut to the style's,
            // short to abbreviated, abbreviated to narrow.
            let now = Date(timeIntervalSince1970: 1_775_000_000)
            let date = now.addingTimeInterval(offset)
            let components = _RelativeDateText.Components(from: now.timeIntervalSince1970, to: date.timeIntervalSince1970, math: Self.math)
            for (theirUnits, units) in [(RelativeDateTimeFormatter.UnitsStyle.full, _RelativeDateText.UnitsStyle.wide), (.spellOut, .spellOut), (.short, .abbreviated), (.abbreviated, .narrow)] {
                formatter.unitsStyle = theirUnits
                formatter.dateTimeStyle = .numeric
                let ours = _RelativeDateText.text(components, presentation: .numeric, unitsStyle: units, rounding: false)
                #expect(ours == formatter.localizedString(for: date, relativeTo: now), "formatter \(offset) \(theirUnits)")
            }
            #endif
        }
        // Calendar months, not thirty-day spans: a month after the 15th is the 15th (one month),
        // thirty days after the 11th of October is the 10th of November (four weeks).
        let october = Date(timeIntervalSince1970: 1_791_763_200)   // 2026-10-11 00:00Z
        let thirtyDays = _RelativeDateText.Components(from: october.timeIntervalSince1970, to: october.timeIntervalSince1970 + 2_592_000, math: Self.math)
        #expect(_RelativeDateText.text(thirtyDays, presentation: .numeric, unitsStyle: .wide) == "in 4 weeks")
        let september = Date(timeIntervalSince1970: 1_789_171_200)   // 2026-09-11 00:00Z
        let thirtyFromSeptember = _RelativeDateText.Components(from: september.timeIntervalSince1970, to: september.timeIntervalSince1970 + 2_592_000, math: Self.math)
        #expect(_RelativeDateText.text(thirtyFromSeptember, presentation: .numeric, unitsStyle: .wide) == "in 1 month")
        #expect(_RelativeDateText.text(.init(minutes: 59, seconds: 59), presentation: .numeric, unitsStyle: .wide) == "in 1 hour")
        #expect(_RelativeDateText.text(.init(hours: -23, minutes: -59), presentation: .named, unitsStyle: .wide) == "yesterday")
        #expect(_RelativeDateText.text(.init(years: 1, months: 11), presentation: .numeric, unitsStyle: .wide) == "in 2 years")
    }
}
