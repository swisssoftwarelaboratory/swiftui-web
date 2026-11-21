// The iOS wheel date picker (Docs/elements/DatePicker.md, new-website#665): its columns follow the
// locale as on iOS 27 (en_GB and de_CH a 24-hour "05 | 30", en_US "5 | 30 | AM"; dates day first
// outside the US, "13." in German; the date and time together as "Tue 13 Oct | 05 | 30"), and a
// finger turns a column the way UIPickerView does: it follows the drag, coasts, and lands on a row.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

@MainActor
private var nextWheelIdentifier = 9_500_000

/// iOS's wheel picker (ios/datepicker/wheel): columns on a cylinder with the selected row on a
/// band across the middle. Inside the band the rows are drawn full size and black; outside it
/// they are narrower, squashed as they turn away and grey, so a row crossing the band's edge is
/// split between the two, as on iOS. Hours, minutes, months and days go round; years and the
/// period do not.
package final class WheelDateNode: LeafNode<_WheelDateHost>, _Interactive, _FrameSubscriber {
    private let identifier: Int
    private var calendar: Calendar { environment._gregorian }

    override package init(_ context: _NodeContext<_WheelDateHost>) {
        nextWheelIdentifier += 1
        identifier = nextWheelIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { view.panelSize ?? PlatformMetrics.wheelSize }
    override package var layoutSpacing: ViewSpacing { .plainControl }
    package var dragAxes: Axis.Set { .vertical }

    // MARK: Columns

    /// What a column turns.
    package enum Kind: Equatable {
        case month, day, year, hour, minute, period
        /// The date and time picker's first column: one row a day ("Tue 13 Oct", "Today").
        case date
    }

    /// One column: its texts line up on `anchor` (their leading or trailing edge, from the
    /// wheel's left) and, off the band, shrink towards `pivot`. Measured on iOS 27 (iPhone 16).
    package struct Column: Equatable {
        package var kind: Kind
        package var trailing: Bool
        package var anchor: CGFloat
        package var pivot: CGFloat
    }

    /// How the locale writes the wheel: hour cycle, day before month, the day's dot, its names.
    package struct Style: Equatable {
        package var language: String
        package var twentyFourHour: Bool
        package var monthFirst: Bool

        package init(locale: Locale) {
            let parts = locale.identifier.split { $0 == "_" || $0 == "-" }.map(String.init)
            language = parts.first?.lowercased() ?? "en"
            let region = parts.dropFirst().first?.uppercased()
            // The US and the regions that follow it write the month first and a 12-hour clock.
            let american = language == "en" && (region == nil || ["US", "CA", "PH"].contains(region!))
            monthFirst = american
            twentyFourHour = !(american || (language == "en" && ["AU", "NZ", "IN"].contains(region ?? "")))
        }

        package var dayDot: Bool { ["de", "da", "nb", "fi", "cs"].contains(language) }

        package var monthNames: [String] {
            switch language {
            case "de": return ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
            case "fr": return ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
            case "it": return ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"]
            default: return _DateMath.monthNames
            }
        }

        /// The date and time picker's day: "Tue 13 Oct" (en_GB), "Tue Oct 13" (en_US).
        package func dayText(_ parts: _DateParts, isToday: Bool) -> String {
            switch language {
            case "de":
                if isToday { return "Heute" }
                let days = ["So.", "Mo.", "Di.", "Mi.", "Do.", "Fr.", "Sa."]
                let months = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."]
                return "\(days[parts.weekday - 1]) \(parts.day). \(months[parts.month - 1])"
            case "fr":
                if isToday { return "Aujourd’hui" }
                let days = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
                let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
                return "\(days[parts.weekday - 1]) \(parts.day) \(months[parts.month - 1])"
            default:
                if isToday { return "Today" }
                let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let month = _DateMath.monthAbbreviations[parts.month - 1]
                return monthFirst ? "\(days[parts.weekday - 1]) \(month) \(parts.day)" : "\(days[parts.weekday - 1]) \(parts.day) \(month)"
            }
        }
    }

    package var style: Style { Style(locale: environment.locale) }

    private var showsDate: Bool { view.components.contains(.date) }
    private var showsTime: Bool { view.components.contains(.hourAndMinute) }

    /// The columns for the components and the locale (iOS 27 on an iPhone 16: the wheel 320 wide,
    /// anchors at the ink of the selected row, pivots where the other rows shrink to).
    package var columns: [Column] {
        let style = style
        switch (showsDate, showsTime) {
        case (true, true):
            return style.twentyFourHour
                ? [Column(kind: .date, trailing: true, anchor: 158.5, pivot: 158),
                   Column(kind: .hour, trailing: false, anchor: 177, pivot: 189),
                   Column(kind: .minute, trailing: false, anchor: 243.5, pivot: 255)]
                : [Column(kind: .date, trailing: true, anchor: 133, pivot: 134),
                   Column(kind: .hour, trailing: true, anchor: 178.5, pivot: 170),
                   Column(kind: .minute, trailing: false, anchor: 213.5, pivot: 225),
                   Column(kind: .period, trailing: false, anchor: 264.5, pivot: 282)]
        case (false, true):
            return style.twentyFourHour
                ? [Column(kind: .hour, trailing: false, anchor: 104, pivot: 110.5),
                   Column(kind: .minute, trailing: false, anchor: 179.5, pivot: 188.5)]
                : [Column(kind: .hour, trailing: true, anchor: 97.5, pivot: 76),
                   Column(kind: .minute, trailing: false, anchor: 142.5, pivot: 152.5),
                   Column(kind: .period, trailing: false, anchor: 200.8, pivot: 221.5)]
        default:
            if style.monthFirst {
                return [Column(kind: .month, trailing: false, anchor: 28.2, pivot: 89.5),
                        Column(kind: .day, trailing: true, anchor: 192.5, pivot: 166.5),
                        Column(kind: .year, trailing: false, anchor: 230.5, pivot: 250)]
            }
            if style.dayDot {
                return [Column(kind: .day, trailing: false, anchor: 25.2, pivot: 39),
                        Column(kind: .month, trailing: false, anchor: 93.2, pivot: 109),
                        Column(kind: .year, trailing: false, anchor: 232.5, pivot: 248.5)]
            }
            return [Column(kind: .day, trailing: false, anchor: 32.5, pivot: 35),
                    Column(kind: .month, trailing: false, anchor: 91.2, pivot: 106),
                    Column(kind: .year, trailing: false, anchor: 230.5, pivot: 250)]
        }
    }

    // MARK: Values

    /// The date `rows` rows along a column from `date` (nil past a column's ends: the period).
    package func date(_ kind: Kind, by rows: Int, from date: Date) -> Date? {
        guard rows != 0 else { return date }
        var parts = _DateMath.parts(of: date, calendar: calendar)
        func wrap(_ value: Int, _ count: Int) -> Int { ((value % count) + count) % count }
        switch kind {
        case .month: parts.month = wrap(parts.month - 1 + rows, 12) + 1
        case .day: parts.day = wrap(parts.day - 1 + rows, _DateMath.daysInMonth(year: parts.year, month: parts.month, calendar: calendar)) + 1
        case .year: parts.year += rows
        // A 12-hour column goes round the whole day, so passing 11 to 12 turns the period over, as on iOS.
        case .hour: parts.hour = wrap(parts.hour + rows, 24)
        case .minute: parts.minute = wrap(parts.minute + rows, 60)
        case .period:
            let period = (parts.hour < 12 ? 0 : 1) + rows
            guard period == 0 || period == 1 else { return nil }
            parts.hour = period == 0 ? parts.hour % 12 : parts.hour % 12 + 12
        case .date:
            return _DateMath.adding(.day, rows, to: date, calendar: calendar)
        }
        parts.day = min(parts.day, _DateMath.daysInMonth(year: parts.year, month: parts.month, calendar: calendar))
        return _DateMath.date(from: parts, calendar: calendar)
    }

    /// A column's text `offset` rows from the selection (nil past its ends).
    package func text(for kind: Kind, offset: Int) -> String? {
        guard let date = date(kind, by: offset, from: view.date) else { return nil }
        let parts = _DateMath.parts(of: date, calendar: calendar)
        let style = style
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        switch kind {
        case .month: return style.monthNames[parts.month - 1]
        case .day: return style.dayDot ? "\(parts.day)." : "\(parts.day)"
        case .year: return "\(parts.year)"
        case .hour: return style.twentyFourHour ? two(parts.hour) : "\(parts.hour % 12 == 0 ? 12 : parts.hour % 12)"
        case .minute: return two(parts.minute)
        case .period: return parts.hour < 12 ? "AM" : "PM"
        case .date:
            let today = _DateMath.parts(of: Date(), calendar: calendar)
            return style.dayText(parts, isToday: today.year == parts.year && today.month == parts.month && today.day == parts.day)
        }
    }

    // MARK: Motion

    /// Each column's turn in points (positive: later rows move up into the band).
    private var turns: [Kind: Motion] = [:]
    private var lastFrame: Double?
    private var dragColumn: Kind?
    private var dragStart: CGPoint = .zero
    private var dragOrigin: Double = 0
    private var dragged = false
    private var tracker = VelocityTracker()

    /// How far a finger moves a column for one row (the first row's distance from the centre).
    private var pitch: Double { Double(PlatformMetrics.wheelRowOffsets[1]) }

    /// A column's turn, in rows.
    private func turn(of kind: Kind) -> Double { (turns[kind]?.position ?? 0) / pitch }

    /// The rows a column can turn by: the period only to the other half of the day.
    private func bounds(of kind: Kind) -> ClosedRange<Double>? {
        guard kind == .period else { return nil }
        let pm = _DateMath.parts(of: view.date, calendar: calendar).hour >= 12
        return pm ? -pitch...0 : 0...pitch
    }

    /// UIPickerView lands a coast on a row: the projected rest rounded to the nearest row, reached
    /// by friction tuned to stop there (its scroll view's target offset); a slow release springs.
    private func release(_ kind: Kind, velocity: Double) {
        var motion = turns[kind] ?? Motion(position: 0)
        let projected = motion.position + DecayModel.normal.projectedOffset(velocity: velocity)
        var target = (projected / pitch).rounded() * pitch
        if let bounds = bounds(of: kind) { target = min(max(target, bounds.lowerBound), bounds.upperBound) }
        let distance = target - motion.position
        if abs(velocity) > 50, distance * velocity > 0, abs(distance) > 1 {
            // v₀ / (1000 · −ln rate) = distance.
            let rate = _exp(-velocity / distance / 1000)
            motion.coast(DecayModel(rate: rate), within: nil, edge: Self.settle, velocity: velocity)
            motion.restSpeed = 20
        } else {
            motion.animate(to: target, spring: Self.settle, velocity: velocity)
        }
        turns[kind] = motion
        runFrames()
        settleIfStill(kind)
    }

    /// The spring that brings a column onto its row (UIKit's critical ω 18 /s, as the keyboard).
    private static let settle = SpringModel(omega: 18, zeta: 1)

    private func runFrames() {
        lastFrame = nil
        runtime.subscribeFrames(self)
        runtime.requestRepaint()
    }

    package func frameDidAdvance() {
        let now = runtime.animationClock
        defer { lastFrame = now }
        guard let last = lastFrame else { return }
        var moving = false
        for kind in Array(turns.keys) where kind != dragColumn {
            guard var motion = turns[kind], motion.isMoving else { continue }
            motion.step(now - last)
            turns[kind] = motion
            if motion.isMoving {
                moving = true
            } else {
                // A coast that ran out between rows springs onto the nearest.
                let row = (motion.position / pitch).rounded() * pitch
                if abs(motion.position - row) > 0.5 {
                    motion.animate(to: row, spring: Self.settle)
                    turns[kind] = motion
                    moving = true
                } else {
                    settleIfStill(kind)
                }
            }
        }
        runtime.requestRepaint()
        if !moving, dragColumn == nil { runtime.unsubscribeFrames(self) }
    }

    /// A column at rest on a row hands the new date to the binding (UIDatePicker's value
    /// changes when the wheel stops) and starts again from it.
    private func settleIfStill(_ kind: Kind) {
        guard let motion = turns[kind], !motion.isMoving, kind != dragColumn else { return }
        let rows = Int((motion.position / pitch).rounded())
        turns[kind] = nil
        guard rows != 0, let next = date(kind, by: rows, from: view.date) else { runtime.setNeedsDisplay(); return }
        view.binding.set(next)
        // Re-read so a binding nobody observes still shows the new date (and a clamped one its bound).
        view = _WheelDateHost(date: view.binding.get(), binding: view.binding, components: view.components, panelSize: view.panelSize)
        runtime.setNeedsDisplay()
    }

    // MARK: Painting

    /// A row `d` rows from the band's centre (fractional while turning): its distance, its height
    /// and its fade, from the measured rows on either side.
    private static func row(at d: Double) -> (offset: CGFloat, scaleY: CGFloat, alpha: Double)? {
        let a = abs(d)
        let offsets = PlatformMetrics.wheelRowOffsets, scales = PlatformMetrics.wheelRowScalesY, alphas = PlatformMetrics.wheelRowAlphas
        let last = offsets.count - 1
        guard a < Double(last) + 0.5 else { return nil }
        let i = min(Int(a), last - 1), f = CGFloat(a - Double(i))
        let offset: CGFloat, scale: CGFloat, alpha: Double
        if a <= Double(last) {
            offset = offsets[i] + (offsets[i + 1] - offsets[i]) * f
            scale = scales[i] + (scales[i + 1] - scales[i]) * f
            alpha = i == 0 ? alphas[1] : alphas[i] + (alphas[i + 1] - alphas[i]) * Double(f)
        } else {
            // The last half row slides out of the wheel's top and bottom as it fades.
            let t = a - Double(last)
            offset = offsets[last] + (offsets[last] - offsets[last - 1]) * CGFloat(t) * 0.5
            scale = scales[last] * CGFloat(1 - t)
            alpha = alphas[last] * (1 - t * 2)
        }
        return (d < 0 ? -offset : offset, scale, alpha)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        list.append(.save)
        list.append(.clipRect(bounds))
        let inset = view.panelSize == nil ? PlatformMetrics.wheelBandInset : PlatformMetrics.timePopoverBandInset
        let band = CGRect(x: bounds.minX + inset, y: bounds.midY - PlatformMetrics.wheelBandHeight / 2,
                          width: bounds.width - 2 * inset, height: PlatformMetrics.wheelBandHeight)
        list.append(.fillRRect(band, cornerRadius: PlatformMetrics.wheelBandCornerRadius, PlatformMetrics.wheelBandFill))
        let font = _fontFor(size: PlatformMetrics.wheelFontSize)
        let line = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        let primary = Color.primary.resolve(in: environment)
        // The wheel's 320 pt sit in the middle of a wider frame.
        let left = bounds.minX + (bounds.width - PlatformMetrics.wheelSize.width) / 2
        let reach = PlatformMetrics.wheelRowOffsets.count
        for column in columns {
            let turned = turn(of: column.kind)
            let base = Int(turned.rounded(.down))
            for index in (base - reach)...(base + reach + 1) {
                guard let text = text(for: column.kind, offset: index), let row = Self.row(at: Double(index) - turned) else { continue }
                let width = _textWidth(text, font: font)
                let x = column.trailing ? left + column.anchor - width : left + column.anchor
                let centerY = bounds.midY + row.offset
                let pivot = left + column.pivot
                // Above and below the band: narrower, squashed and grey; inside it full size.
                for (clip, magnified) in [(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: band.minY - bounds.minY), false),
                                          (CGRect(x: bounds.minX, y: band.maxY, width: bounds.width, height: bounds.maxY - band.maxY), false),
                                          (band, true)] {
                    guard clip.minY < centerY + line / 2, clip.maxY > centerY - line / 2 else { continue }
                    list.append(.save)
                    list.append(.clipRect(clip))
                    if magnified {
                        _drawText(text, font: font, lineTop: CGPoint(x: x, y: centerY - line / 2), color: primary, into: &list)
                    } else {
                        let transform = CGAffineTransform(translationX: pivot, y: centerY)
                            .scaledBy(x: PlatformMetrics.wheelRowScaleX, y: max(row.scaleY, 0.01))
                            .translatedBy(x: -pivot, y: -centerY)
                        list.append(.concat(transform))
                        _drawText(text, font: font, lineTop: CGPoint(x: x, y: centerY - line / 2), color: primary.multiplyingAlpha(by: row.alpha), into: &list)
                    }
                    list.append(.restore)
                }
            }
        }
        list.append(.restore)
    }

    // MARK: Interaction

    private func column(at point: CGPoint) -> Kind? {
        let columns = columns
        let left = (frame.width - PlatformMetrics.wheelSize.width) / 2
        // Columns split midway between their pivots.
        for (index, column) in columns.enumerated() {
            guard index + 1 < columns.count else { return column.kind }
            if point.x - left < (column.pivot + columns[index + 1].pivot) / 2 { return column.kind }
        }
        return columns.last?.kind
    }

    package func pressBegan() {}

    package func pressBegan(at point: CGPoint) {
        guard environment.isEnabled, let kind = column(at: point) else { return }
        // A finger catches a turning column where it is.
        var motion = turns[kind] ?? Motion(position: 0)
        motion.hold(at: motion.position)
        turns[kind] = motion
        dragColumn = kind
        dragStart = point
        dragOrigin = motion.position
        dragged = false
        tracker.reset()
        tracker.add(point, at: runtime.wheelClock())
        runFrames()
    }

    package func pressMoved(to point: CGPoint) {
        guard let kind = dragColumn else { return }
        tracker.add(point, at: runtime.wheelClock())
        if abs(point.y - dragStart.y) > 3 { dragged = true }
        // Dragging up brings the later rows into the band; the period stops at its two rows
        // with the rubber band.
        var position = dragOrigin + Double(dragStart.y - point.y)
        if let bounds = bounds(of: kind), !bounds.contains(position) {
            let end = position > bounds.upperBound ? bounds.upperBound : bounds.lowerBound
            position = end + RubberBand.offset(forOvershoot: position - end, dimension: Double(frame.height))
        }
        var motion = turns[kind] ?? Motion(position: 0)
        motion.hold(at: position)
        turns[kind] = motion
        runtime.requestRepaint()
    }

    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard let kind = dragColumn else { return }
        dragColumn = nil
        if dragged {
            release(kind, velocity: -Double(tracker.velocity(at: runtime.wheelClock()).height))
            return
        }
        // A tap on a row above or below turns it into the band.
        let dy = point.y - frame.height / 2
        var nearest = 0
        let offsets = PlatformMetrics.wheelRowOffsets
        for distance in 1..<offsets.count where abs(abs(dy) - offsets[distance]) < abs(abs(dy) - offsets[nearest]) { nearest = distance }
        let rows = Double(dy < 0 ? -nearest : nearest)
        var motion = turns[kind] ?? Motion(position: 0)
        var target = (motion.position / pitch).rounded() * pitch + rows * pitch
        if let bounds = bounds(of: kind) { target = min(max(target, bounds.lowerBound), bounds.upperBound) }
        motion.animate(to: target, spring: Self.settle)
        turns[kind] = motion
        runFrames()
        settleIfStill(kind)
    }

    /// Turns a column by whole rows at once (keyboard and accessibility adjustments, tests).
    package func turn(_ kind: Kind, by rows: Int) {
        guard rows != 0, let next = date(kind, by: rows, from: view.date) else { return }
        view.binding.set(next)
        view = _WheelDateHost(date: view.binding.get(), binding: view.binding, components: view.components, panelSize: view.panelSize)
        runtime.setNeedsDisplay()
    }

    override package func unmount() {
        runtime.unsubscribeFrames(self)
        super.unmount()
    }

    package var semantics: SemanticsNode {
        let label = columns.compactMap { text(for: $0.kind, offset: 0) }.joined(separator: " ")
        var node = SemanticsNode(role: .group, label: label, frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        return node
    }
}
