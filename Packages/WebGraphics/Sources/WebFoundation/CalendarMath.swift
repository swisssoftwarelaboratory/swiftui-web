// The calendar arithmetic behind `Calendar` on wasm (decision 0017), platform-neutral so the
// tests can hold it to Foundation's calendar. Time values are seconds since 1970 (UTC); the
// civil calendar is proleptic Gregorian (Foundation switches to Julian before 1582; nothing
// here asks about those years), the zone is a `_ZoneRule` (fixed, or named with daylight
// saving), and the other calendar systems (`_CalendarSystem`) convert day counts.

/// The fields of an instant in a fixed-offset zone.
package struct _DateFields: Hashable, Sendable {
    package var era: Int
    package var year: Int, month: Int, day: Int
    package var hour: Int, minute: Int, second: Int, nanosecond: Int
    /// 1 = Sunday … 7 = Saturday.
    package var weekday: Int
    package var dayOfYear: Int
}

/// The units the arithmetic knows.
package enum _CalendarUnit: Hashable, Sendable {
    case era, year, quarter, month, weekOfYear, weekOfMonth, day, weekday, weekdayOrdinal, hour, minute, second, nanosecond, dayOfYear, yearForWeekOfYear
}

package enum _Gregorian {
    package static func isLeap(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    /// The day number (since 1970-01-01) holding a count of seconds since 1970, worked out in
    /// Double: a 32-bit `Int` (wasm32) holds seconds only between 1901 and 2038.
    package static func day(ofSeconds seconds: Double) -> Int { Int((seconds / 86400).rounded(.down)) }

    package static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeap(year) ? 29 : 28
        }
    }

    /// Days since 1970-01-01 of a civil date (Howard Hinnant's `days_from_civil`).
    package static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The civil date of a day count since 1970-01-01 (`civil_from_days`).
    package static func civil(days z: Int) -> (year: Int, month: Int, day: Int) {
        let z = z + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 1 = Sunday … 7 = Saturday; 1970-01-01 was a Thursday.
    package static func weekday(days z: Int) -> Int { (((z + 4) % 7) + 7) % 7 + 1 }

    package static func floorDiv(_ a: Int, _ b: Int) -> Int { a >= 0 ? a / b : -((-a + b - 1) / b) }
    package static func floorMod(_ a: Int, _ b: Int) -> Int { a - floorDiv(a, b) * b }
}

package struct _CalendarMath: Hashable, Sendable {
    /// The zone whose wall clock the fields follow.
    package var zone: _ZoneRule
    /// The calendar system the year, month and day fields belong to.
    package var system: _CalendarSystem
    /// 1 = Sunday.
    package var firstWeekday: Int
    package var minimumDaysInFirstWeek: Int

    package init(zone: _ZoneRule, system: _CalendarSystem = .gregorian, firstWeekday: Int = 1, minimumDaysInFirstWeek: Int = 1) {
        self.zone = zone
        self.system = system
        self.firstWeekday = firstWeekday
        self.minimumDaysInFirstWeek = minimumDaysInFirstWeek
    }

    /// A fixed offset in seconds east of GMT.
    package init(offset: Int, firstWeekday: Int = 1, minimumDaysInFirstWeek: Int = 1) {
        self.init(zone: .fixed(offset), firstWeekday: firstWeekday, minimumDaysInFirstWeek: minimumDaysInFirstWeek)
    }

    /// The local day count and second of day of an instant.
    package func split(_ time: Double) -> (days: Int, secondOfDay: Int, nanosecond: Int) {
        let whole = time.rounded(.down)
        let nanosecond = Int(((time - whole) * 1e9).rounded())
        // In Double: a 32-bit Int (wasm32) holds seconds only from 1901 to 2038.
        let local = whole + Double(zone.offset(at: time))
        let days = _Gregorian.day(ofSeconds: local)
        return (days, Int(local - Double(days) * 86400), nanosecond)
    }

    package func fields(_ time: Double) -> _DateFields {
        let (days, secondOfDay, nanosecond) = split(time)
        let date = system.date(days: days)
        let era = system.era(days: days)
        return _DateFields(era: era, year: date.year, month: date.month, day: date.day,
                           hour: secondOfDay / 3600, minute: secondOfDay % 3600 / 60, second: secondOfDay % 60, nanosecond: nanosecond,
                           weekday: _Gregorian.weekday(days: days),
                           dayOfYear: days - system.days(year: date.year, month: 1, day: 1, era: era) + 1)
    }

    /// The era of an instant (`_CalendarSystem.era`).
    package func era(_ time: Double) -> Int { system.era(days: split(time).days) }

    /// The instant of civil fields; months, days and times past their range carry over.
    package func time(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0, nanosecond: Int = 0, era: Int? = nil) -> Double {
        let days = system.days(year: year, month: month, day: day, era: era)
        let local = Double(days) * 86400 + Double(hour) * 3600 + Double(minute) * 60 + Double(second)
        return zone.utc(forLocal: local) + Double(nanosecond) / 1e9
    }

    /// The instant at the start of the day holding `time`.
    package func startOfDay(_ time: Double) -> Double { zone.utc(forLocal: Double(split(time).days) * 86400) }

    /// The instant with the same wall clock as `time` on local day `days`.
    private func sameClock(_ time: Double, onDay days: Int) -> Double {
        let (_, secondOfDay, _) = split(time)
        let fraction = time - time.rounded(.down)
        return zone.utc(forLocal: Double(days) * 86400 + Double(secondOfDay)) + fraction
    }

    /// `time` plus `value` units; months and years clamp the day to the target month's
    /// length, and days and weeks keep the wall clock across daylight-saving changes.
    package func adding(_ unit: _CalendarUnit, _ value: Int, to time: Double) -> Double {
        let f = fields(time)
        let fraction = time - time.rounded(.down)
        switch unit {
        case .era: return time
        case .year, .month, .quarter:
            let months = unit == .year ? 0 : unit == .quarter ? value * 3 : value
            if system.isGregorianDerived {
                // Civil years, so a step across an era boundary counts on.
                let civil = _CalendarSystem.gregorian.monthsAfter(year: system.civilYear(year: f.year, era: f.era) + (unit == .year ? value : 0), month: f.month, count: months)
                let day = min(f.day, _Gregorian.daysInMonth(year: civil.year, month: civil.month))
                let local = Double(_Gregorian.days(year: civil.year, month: civil.month, day: day)) * 86400 + Double(f.hour * 3600 + f.minute * 60 + f.second)
                return zone.utc(forLocal: local) + fraction
            }
            let (year, month) = unit == .year ? (f.year + value, f.month) : system.monthsAfter(year: f.year, month: f.month, count: months)
            let day = min(f.day, system.daysInMonth(year: year, month: month, era: f.era))
            return self.time(year: year, month: month, day: day, hour: f.hour, minute: f.minute, second: f.second, era: f.era) + fraction
        case .day, .weekday, .dayOfYear: return sameClock(time, onDay: split(time).days + value)
        case .weekOfYear, .weekOfMonth, .weekdayOrdinal, .yearForWeekOfYear: return sameClock(time, onDay: split(time).days + value * 7)
        case .hour: return time + Double(value) * 3600
        case .minute: return time + Double(value) * 60
        case .second: return time + Double(value)
        case .nanosecond: return time + Double(value) / 1e9
        }
    }

    /// `time` plus `value` units with the unit wrapping inside the next larger one (Foundation's
    /// `wrappingComponents`): 23:00 plus two hours is 01:00 the same day, the 31st plus a day
    /// is the 1st of the same month, December plus a month is January of the same year.
    package func addingWrapped(_ unit: _CalendarUnit, _ value: Int, to time: Double) -> Double {
        let f = fields(time)
        let (days, secondOfDay, _) = split(time)
        let fraction = time - time.rounded(.down)
        func clock(hour: Int, minute: Int, second: Int) -> Double {
            zone.utc(forLocal: Double(days) * 86400 + Double(hour * 3600 + minute * 60 + second)) + fraction
        }
        switch unit {
        case .era, .year, .yearForWeekOfYear: return adding(unit, value, to: time)
        case .month, .quarter:
            let months = system.monthsInYear(f.year)
            let month = _Gregorian.floorMod(f.month - 1 + (unit == .quarter ? value * 3 : value), months) + 1
            let day = min(f.day, system.daysInMonth(year: f.year, month: month, era: f.era))
            return self.time(year: f.year, month: month, day: day, hour: f.hour, minute: f.minute, second: f.second, era: f.era) + fraction
        case .day:
            let count = system.daysInMonth(year: f.year, month: f.month, era: f.era)
            let day = _Gregorian.floorMod(f.day - 1 + value, count) + 1
            return sameClock(time, onDay: days + day - f.day)
        case .dayOfYear:
            let count = system.daysInYear(f.year, era: f.era)
            let day = _Gregorian.floorMod(f.dayOfYear - 1 + value, count) + 1
            return sameClock(time, onDay: days + day - f.dayOfYear)
        case .weekday:
            let start = weekStart(days)
            return sameClock(time, onDay: start + _Gregorian.floorMod(days - start + value, 7))
        case .weekdayOrdinal:
            let count = (system.daysInMonth(year: f.year, month: f.month, era: f.era) - f.day) / 7 + (f.day - 1) / 7 + 1
            let ordinal = _Gregorian.floorMod((f.day - 1) / 7 + value, count)
            return sameClock(time, onDay: days + (ordinal - (f.day - 1) / 7) * 7)
        case .weekOfMonth:
            // The week wraps inside the month; a weekday the target week lacks pins to the
            // month's first or last day, as ICU pins it.
            let weeks = weeksInMonth(time)
            let week = weeksInMonthIndex(time)
            let target = weeks.lowerBound + _Gregorian.floorMod(week - weeks.lowerBound + value, weeks.count)
            let first = system.days(year: f.year, month: f.month, day: 1, era: f.era)
            let last = first + system.daysInMonth(year: f.year, month: f.month, era: f.era) - 1
            return sameClock(time, onDay: min(max(days + (target - week) * 7, first), last))
        case .weekOfYear:
            let weeks = weeksInYear(time)
            let week = weekOfYear(time).week
            let target = weeks.lowerBound + _Gregorian.floorMod(week - weeks.lowerBound + value, weeks.count)
            return sameClock(time, onDay: days + (target - week) * 7)
        case .hour: return clock(hour: _Gregorian.floorMod(f.hour + value, 24), minute: f.minute, second: f.second)
        case .minute: return clock(hour: f.hour, minute: _Gregorian.floorMod(f.minute + value, 60), second: f.second)
        case .second: return clock(hour: f.hour, minute: f.minute, second: _Gregorian.floorMod(secondOfDay % 60 + value, 60))
        case .nanosecond:
            let nanos = _Gregorian.floorMod(f.nanosecond + value, 1_000_000_000)
            return time.rounded(.down) + Double(nanos) / 1e9
        }
    }

    /// The day count that starts the week holding `days`.
    private func weekStart(_ days: Int) -> Int { days - _Gregorian.floorMod(_Gregorian.weekday(days: days) - firstWeekday, 7) }

    /// The first day of week 1 of the period starting at `first` (a year's or month's first day).
    private func firstWeekStart(period first: Int) -> Int {
        let start = weekStart(first)
        return 7 - (first - start) >= minimumDaysInFirstWeek ? start : start + 7
    }

    /// The week of the year and the year it belongs to, Foundation's `weekOfYear` and
    /// `yearForWeekOfYear` under `firstWeekday` and `minimumDaysInFirstWeek`.
    package func weekOfYear(_ time: Double) -> (week: Int, year: Int) {
        let days = split(time).days
        let era = system.era(days: days)
        var year = system.date(days: days).year
        var start = firstWeekStart(period: system.days(year: year, month: 1, day: 1, era: era))
        if days < start {
            year -= 1
            start = firstWeekStart(period: system.days(year: year, month: 1, day: 1, era: era))
        } else {
            let next = firstWeekStart(period: system.days(year: year + 1, month: 1, day: 1, era: era))
            if days >= next { year += 1; start = next }
        }
        return ((days - start) / 7 + 1, year)
    }

    private func weeksInMonthIndex(_ time: Double) -> Int {
        let days = split(time).days
        let date = system.date(days: days)
        let start = firstWeekStart(period: system.days(year: date.year, month: date.month, day: 1, era: system.era(days: days)))
        return _Gregorian.floorDiv(days - start, 7) + 1
    }

    package func weekOfMonth(_ time: Double) -> Int { weeksInMonthIndex(time) }

    /// How many weeks the month holding `time` spans (its `weekOfMonth` range).
    package func weeksInMonth(_ time: Double) -> Range<Int> {
        let days = split(time).days
        let date = system.date(days: days), era = system.era(days: days)
        let first = system.days(year: date.year, month: date.month, day: 1, era: era)
        let last = first + system.daysInMonth(year: date.year, month: date.month, era: era) - 1
        let start = firstWeekStart(period: first)
        let low = first < start ? 0 : 1
        return low..<(_Gregorian.floorDiv(last - start, 7) + 2)
    }

    package func weeksInYear(_ time: Double) -> Range<Int> {
        let days = split(time).days
        let year = system.date(days: days).year, era = system.era(days: days)
        let start = firstWeekStart(period: system.days(year: year, month: 1, day: 1, era: era))
        let next = firstWeekStart(period: system.days(year: year + 1, month: 1, day: 1, era: era))
        return 1..<((next - start) / 7 + 1)
    }

    package func range(of smaller: _CalendarUnit, in larger: _CalendarUnit, for time: Double) -> Range<Int>? {
        let f = fields(time)
        switch (smaller, larger) {
        case (.day, .month): return 1..<(system.daysInMonth(year: f.year, month: f.month, era: f.era) + 1)
        case (.day, .year), (.dayOfYear, .year): return 1..<(system.daysInYear(f.year, era: f.era) + 1)
        case (.day, .weekOfYear), (.day, .weekOfMonth), (.weekday, .weekOfYear), (.weekday, .weekOfMonth), (.weekday, .month), (.weekday, .year): return 1..<8
        case (.month, .year): return 1..<(system.monthsInYear(f.year) + 1)
        case (.month, .quarter): return 1..<4
        case (.quarter, .year): return 1..<5
        case (.hour, .day): return 0..<24
        case (.minute, .hour): return 0..<60
        case (.minute, .day): return 0..<1440
        case (.second, .minute): return 0..<60
        case (.second, .hour): return 0..<3600
        case (.second, .day): return 0..<86400
        case (.nanosecond, .second): return 0..<1_000_000_000
        case (.weekOfMonth, .month): return weeksInMonth(time)
        case (.weekOfYear, .year), (.weekOfYear, .yearForWeekOfYear): return weeksInYear(time)
        case (.weekdayOrdinal, .month): return 1..<((system.daysInMonth(year: f.year, month: f.month, era: f.era) + 6) / 7 + 1)
        case (.year, .era): return 1..<144684
        default: return nil
        }
    }

    /// The whole units between two instants, largest first: years and months as calendar
    /// steps from the instant the larger units reached (each step clamped like `adding`, so
    /// Jan 31 + 2 months is Mar 31, as Foundation counts), the rest from the remaining seconds.
    package func difference(from start: Double, to end: Double, units: Set<_CalendarUnit>) -> [_CalendarUnit: Int] {
        var result: [_CalendarUnit: Int] = [:]
        var cursor = start
        let sign = end >= start ? 1 : -1
        for unit in [_CalendarUnit.year, .quarter, .month] where units.contains(unit) {
            var count = 0
            while true {
                let next = adding(unit, count + sign, to: cursor)
                if sign > 0 ? next > end : next < end { break }
                count += sign
            }
            cursor = adding(unit, count, to: cursor)
            result[unit] = count
        }
        var remaining = end - cursor
        for (unit, length) in [(_CalendarUnit.weekOfYear, 604800.0), (.weekOfMonth, 604800.0), (.day, 86400.0), (.hour, 3600.0), (.minute, 60.0), (.second, 1.0)] where units.contains(unit) {
            let count = (remaining / length).rounded(.towardZero)
            result[unit] = Int(count)
            remaining -= count * length
        }
        if units.contains(.nanosecond) { result[.nanosecond] = Int((remaining * 1e9).rounded()) }
        return result
    }
}
