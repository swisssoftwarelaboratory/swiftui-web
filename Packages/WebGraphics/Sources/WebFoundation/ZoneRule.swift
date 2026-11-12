// Time zone offsets behind `TimeZone` and `Calendar` on wasm (pf-web-foundation-gaps): a fixed
// offset, or a named zone whose offsets the host answers (the browser's `Intl` knows the tz
// database the bundle does not carry). Named zones are learnt a year at a time: the year is
// sampled weekly and every change bisected to the second, so daylight-saving transitions land
// where the host puts them. Platform-neutral so the tests can hold it to Foundation's zones.

/// Where a zone's offsets come from.
package enum _ZoneRule: Hashable, Sendable {
    /// Seconds east of GMT, always.
    case fixed(Int)
    /// A tz database identifier the host answers for (`_ZoneCache.hostOffset`).
    case named(String)

    /// Seconds east of GMT at a UTC instant.
    package func offset(at utc: Double) -> Int {
        switch self {
        case .fixed(let offset): return offset
        case .named(let identifier): return _ZoneCache.shared.offset(identifier, at: utc)
        }
    }

    /// The UTC instant whose local wall clock reads `local` (seconds since 1970 as if UTC).
    /// A wall-clock time that happens twice (the autumn overlap) is its first occurrence; one
    /// that never happens (the spring gap) moves forward by the gap, as Foundation's does.
    package func utc(forLocal local: Double) -> Double {
        switch self {
        case .fixed(let offset): return local - Double(offset)
        case .named:
            // The offsets a day either side of the wall clock (read as UTC) bracket any transition.
            let before = offset(at: local - 86400)
            let after = offset(at: local + 86400)
            var candidates: [Double] = []
            for candidate in Set([before, after]) {
                let utc = local - Double(candidate)
                if offset(at: utc) == candidate { candidates.append(utc) }
            }
            if let first = candidates.min() { return first }
            return local - Double(before)
        }
    }

    /// The zone's standard offset around `utc`: the smaller of its offsets at the start and
    /// the middle of that UTC year (daylight saving only ever adds).
    package func standardOffset(at utc: Double) -> Int {
        switch self {
        case .fixed(let offset): return offset
        case .named:
            let year = _Gregorian.civil(days: _Gregorian.day(ofSeconds: utc)).year
            let january = Double(_Gregorian.days(year: year, month: 1, day: 1)) * 86400
            let july = Double(_Gregorian.days(year: year, month: 7, day: 1)) * 86400
            return min(offset(at: january), offset(at: july))
        }
    }

    /// The next instant the offset changes after `utc`, within the following two years.
    package func nextTransition(after utc: Double) -> Double? {
        guard case .named(let identifier) = self else { return nil }
        let cache = _ZoneCache.shared
        let startYear = _Gregorian.civil(days: _Gregorian.day(ofSeconds: utc)).year
        for year in startYear...(startYear + 2) {
            if let next = cache.transitions(identifier, year: year).first(where: { $0.time > utc }) { return next.time }
        }
        return nil
    }
}

/// The offsets learnt so far for every named zone.
package final class _ZoneCache: @unchecked Sendable {
    package static let shared = _ZoneCache()

    package struct Transition: Hashable, Sendable {
        /// The UTC instant from which `offset` holds.
        package var time: Double
        package var offset: Int
    }

    /// The host's answer for a zone identifier at a UTC instant, nil for a name it does not
    /// know. The canvas host installs the browser's `Intl`; the tests install Foundation's.
    nonisolated(unsafe) package static var hostOffset: (@Sendable (String, Double) -> Int?)?

    /// Per identifier, per UTC year: the offset at the year's start and the transitions in it.
    private var years: [String: [Int: (base: Int, transitions: [Transition])]] = [:]

    private init() {}

    /// Whether the host answers for `identifier` (asked once; a miss is remembered as nil).
    package func knows(_ identifier: String) -> Bool {
        guard let hostOffset = Self.hostOffset else { return false }
        if years[identifier] != nil { return true }
        return hostOffset(identifier, 0) != nil
    }

    package func forget() { years = [:] }

    package func offset(_ identifier: String, at utc: Double) -> Int {
        let year = _Gregorian.civil(days: _Gregorian.day(ofSeconds: utc)).year
        let entry = learn(identifier, year: year)
        var offset = entry.base
        for transition in entry.transitions where transition.time <= utc { offset = transition.offset }
        return offset
    }

    package func transitions(_ identifier: String, year: Int) -> [Transition] { learn(identifier, year: year).transitions }

    private func learn(_ identifier: String, year: Int) -> (base: Int, transitions: [Transition]) {
        if let known = years[identifier]?[year] { return known }
        let ask: (Double) -> Int = { time in Self.hostOffset?(identifier, time) ?? 0 }
        let start = Double(_Gregorian.days(year: year, month: 1, day: 1)) * 86400
        let end = Double(_Gregorian.days(year: year + 1, month: 1, day: 1)) * 86400
        let base = ask(start)
        var transitions: [Transition] = []
        var previousTime = start, previousOffset = base
        var time = start + 7 * 86400
        while previousTime < end {
            let probe = min(time, end)
            let offset = ask(probe)
            if offset != previousOffset {
                // Bisect to the second the offset changed.
                var low = previousTime, high = probe
                while high - low > 1 {
                    let middle = ((low + high) / 2).rounded(.down)
                    if ask(middle) == previousOffset { low = middle } else { high = middle }
                }
                transitions.append(Transition(time: high, offset: offset))
                previousOffset = offset
            }
            previousTime = probe
            time += 7 * 86400
        }
        years[identifier, default: [:]][year] = (base, transitions)
        return (base, transitions)
    }
}
