// iOS 27's own calendar (new-website#674): the compact date pill's panel and `.graphical` on
// iOS. A "November 2026 >" header with the previous and next month chevrons, the weekday names
// from the locale's first day, the month's weeks (only its own days), the selected day on a
// filled circle and today in the tint. The header's title turns the grid into a month and a
// year wheel. Measured in the iOS 27 simulator on an iPhone 16 with a probe app
// (ios-in-browser/swipe-harness/picker-probe-674).
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

@MainActor
private var nextIOSCalendarIdentifier = 9_600_000

/// The calendar with its month and year wheel: which month it shows and whether the wheel is
/// open live here, so the wheel and the grid share them.
package struct _IOSCalendar: View {
    package let date: Date
    package let binding: _DateBinding
    /// In the compact picker's panel (320 × 332) rather than in the app's own layout.
    package let inPanel: Bool
    /// `.graphical` with the time too: a "Time" row with the time pill under the calendar.
    package let showsTime: Bool
    @State private var shown: Date?
    @State private var yearsOpen = false

    package init(date: Date, binding: _DateBinding, inPanel: Bool, showsTime: Bool = false) {
        self.date = date
        self.binding = binding
        self.inPanel = inPanel
        self.showsTime = showsTime
    }

    package var body: some View {
        let shownDate = shown ?? date
        let shownBinding = Binding<Date>(get: { shown ?? date }, set: { shown = $0 })
        let geometry = _IOSCalendarGeometry(inPanel: inPanel)
        let calendar = ZStack(alignment: .topLeading) {
            _IOSCalendarHost(date: date, binding: binding, shown: shownDate, inPanel: inPanel, yearsOpen: yearsOpen,
                             onShow: { shown = $0 }, onToggleYears: { yearsOpen.toggle() })
            if yearsOpen {
                _WheelDateHost(date: shownDate, binding: _DateBinding(shownBinding, minimum: nil, maximum: nil), components: .date,
                               monthAndYear: true, bandInset: geometry.wheelBandInset)
                    .padding(.top, geometry.wheelTop)
            }
        }
        if showsTime && !inPanel {
            // iOS 27 (graphical-both): the calendar 349.3 tall, then a 38 pt "Time" row 8 in
            // from both sides with the time pill at its end.
            let time = Binding<Date>(get: { binding.get() }, set: { binding.set($0) })
            VStack(alignment: .leading, spacing: 0) {
                calendar.padding(.bottom, -4)
                HStack {
                    Text("Time").fontWeight(.semibold)
                    Spacer()
                    DatePicker("", selection: time, displayedComponents: .hourAndMinute).labelsHidden()
                }
                .frame(height: 38)
                .padding(.horizontal, 8)
            }
        } else {
            calendar
        }
    }
}

/// Where everything sits, in the panel and in the app's own layout (iOS 27, iPhone 16).
package struct _IOSCalendarGeometry {
    package var inPanel: Bool

    /// The panel's calendar is 320 × 332; `.graphical` takes the width offered, 353.3 tall at
    /// 361 wide (iPhone 16) and 324.5 at 343 (iPhone SE golden, its last week reaching 5 past).
    package var width: CGFloat { 320 }
    package func height(width: CGFloat) -> CGFloat { inPanel ? 332 : 353.3 + (width - 361) * 1.6 }
    /// The header's centre line (title, chevrons) and the weekday names' centre, from the top.
    package var headerCenter: CGFloat { 34.7 }
    package var weekdayCenter: CGFloat { 77.4 }
    /// The weeks fill this band, split evenly between the month's weeks (five weeks get taller
    /// rows than six: 45.6 against 38 in the panel).
    package var gridTop: CGFloat { 86.4 }
    package func gridHeight(width: CGFloat) -> CGFloat { inPanel ? 228 : width * 0.7091 }
    /// The columns' band inset from the sides.
    package var columnInset: CGFloat { inPanel ? 10.3 : 0 }
    package var titleLeading: CGFloat { inPanel ? 20 : 12 }
    /// The chevrons' centres from the trailing edge.
    package var nextFromTrailing: CGFloat { inPanel ? 22.7 : 15.7 }
    package var previousFromTrailing: CGFloat { inPanel ? 68.3 : 59 }
    /// The panel draws its month chevrons in the label colour, `.graphical` in the tint.
    package var chevronsTinted: Bool { !inPanel }
    /// The month and year wheel's top and its band's inset.
    package var wheelTop: CGFloat { inPanel ? 39.4 : 54 }
    package var wheelBandInset: CGFloat { inPanel ? 16 : 8 }
}

/// The header, weekdays and weeks (`IOSCalendarNode`).
package struct _IOSCalendarHost: View {
    package let date: Date
    package let binding: _DateBinding
    package let shown: Date
    package let inPanel: Bool
    package let yearsOpen: Bool
    package let onShow: @MainActor (Date) -> Void
    package let onToggleYears: @MainActor () -> Void
    package typealias Body = Never
    package static func _makeNode(_ context: _NodeContext<_IOSCalendarHost>) -> TypedNode<_IOSCalendarHost> {
        IOSCalendarNode(context)
    }
}

@MainActor
package final class IOSCalendarNode: LeafNode<_IOSCalendarHost>, _Interactive {
    private let identifier: Int

    override package init(_ context: _NodeContext<_IOSCalendarHost>) {
        nextIOSCalendarIdentifier += 1
        identifier = nextIOSCalendarIdentifier
        super.init(context)
    }

    private var calendar: Calendar { environment._gregorian }
    private var geometry: _IOSCalendarGeometry { _IOSCalendarGeometry(inPanel: view.inPanel) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let g = geometry
        let width = g.inPanel ? g.width : (proposal.width ?? 361)
        return CGSize(width: width, height: g.height(width: width))
    }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    // MARK: The locale

    package struct Names {
        package var language: String
        package var region: String?

        package init(locale: Locale) {
            let parts = locale.identifier.split { $0 == "_" || $0 == "-" }.map(String.init)
            language = parts.first?.lowercased() ?? "en"
            region = parts.dropFirst().first?.uppercased()
        }

        /// 1 for Sunday, 2 for Monday. iOS takes the first day from the phone's own calendar,
        /// not from an app's `.environment(\.locale, …)` (en_US in the simulator still starts on
        /// Monday there): the drawn iPhone's region is Switzerland, so weeks start on Monday.
        package var firstWeekday: Int { 2 }

        /// The weekday names, Sunday first, as iOS 27 writes them over the columns.
        package var weekdays: [String] {
            switch language {
            case "de": return ["SO", "MO", "DI", "MI", "DO", "FR", "SA"]
            case "fr": return ["DIM", "LUN", "MAR", "MER", "JEU", "VEN", "SAM"]
            case "it": return ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"]
            default: return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
            }
        }

        package func title(year: Int, month: Int) -> String {
            switch language {
            case "fr": return "\(["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"][month - 1]) \(year)"
            default:
                let names = WheelDateNode.Style(locale: Locale(identifier: language)).monthNames
                return "\(names[month - 1]) \(year)"
            }
        }
    }

    private var names: Names { Names(locale: environment.locale) }

    // MARK: The month

    package var visibleMonth: (year: Int, month: Int) {
        let parts = _DateMath.parts(of: view.shown, calendar: calendar)
        return (parts.year, parts.month)
    }

    /// The month's weeks from the locale's first day: each cell its day, or nil before the 1st
    /// and after the last.
    package var weeks: [[Int?]] {
        let (year, month) = visibleMonth
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.shown
        let leading = (calendar.component(.weekday, from: first) - names.firstWeekday + 7) % 7
        let count = _DateMath.daysInMonth(year: year, month: month, calendar: calendar)
        var cells: [Int?] = Array(repeating: nil, count: leading) + (1...count).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var columnWidth: CGFloat { (frame.width - 2 * geometry.columnInset) / 7 }
    private var rowHeight: CGFloat { geometry.gridHeight(width: frame.width) / CGFloat(max(1, weeks.count)) }

    package func cell(row: Int, column: Int) -> CGRect {
        let g = geometry
        return CGRect(x: g.columnInset + CGFloat(column) * columnWidth, y: g.gridTop + CGFloat(row) * rowHeight, width: columnWidth, height: rowHeight)
    }

    // MARK: The header

    private var titleFont: ResolvedFont { _fontFor(size: 17, weight: .semibold) }

    /// The title's text box, its chevron right after it: the press area for the year wheel.
    package var titleRect: CGRect {
        let g = geometry
        let width = _textWidth(names.title(year: visibleMonth.year, month: visibleMonth.month), font: titleFont)
        return CGRect(x: g.titleLeading - 4, y: g.headerCenter - 18.85, width: width + 8 + 7 + 12, height: 37.7)
    }

    package var previousRect: CGRect {
        CGRect(x: frame.width - geometry.previousFromTrailing - 21.65, y: geometry.headerCenter - 18.85, width: 43.3, height: 37.7)
    }

    package var nextRect: CGRect {
        CGRect(x: frame.width - geometry.nextFromTrailing - 21.65, y: geometry.headerCenter - 18.85, width: 43.3, height: 37.7)
    }

    /// A chevron: `direction` 0 right, 1 down, 2 left.
    private func chevron(center: CGPoint, length: CGFloat, depth: CGFloat, direction: Int) -> Path {
        var path = Path()
        switch direction {
        case 1:
            path.move(to: CGPoint(x: center.x - length / 2, y: center.y - depth / 2))
            path.addLine(to: CGPoint(x: center.x, y: center.y + depth / 2))
            path.addLine(to: CGPoint(x: center.x + length / 2, y: center.y - depth / 2))
        case 2:
            path.move(to: CGPoint(x: center.x + depth / 2, y: center.y - length / 2))
            path.addLine(to: CGPoint(x: center.x - depth / 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x + depth / 2, y: center.y + length / 2))
        default:
            path.move(to: CGPoint(x: center.x - depth / 2, y: center.y - length / 2))
            path.addLine(to: CGPoint(x: center.x + depth / 2, y: center.y))
            path.addLine(to: CGPoint(x: center.x - depth / 2, y: center.y + length / 2))
        }
        return path
    }

    // MARK: Painting

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let g = geometry
        let dark = environment.colorScheme == .dark
        let primary = Color.primary.resolve(in: environment)
        let tint = Color.accentColor.resolve(in: environment)
        let (year, month) = visibleMonth

        // The header: "November 2026" and a chevron after it, in the tint while the wheel is open.
        let title = names.title(year: year, month: month)
        let titleFont = titleFont
        let titleLine = environment.platformProfile.systemFontMetrics(for: titleFont).lineHeight
        let titleWidth = _textWidth(title, font: titleFont)
        _drawText(title, font: titleFont, lineTop: CGPoint(x: bounds.minX + g.titleLeading, y: bounds.minY + g.headerCenter - titleLine / 2),
                  color: view.yearsOpen ? tint : primary, into: &list)
        let titleChevron = chevron(center: CGPoint(x: bounds.minX + g.titleLeading + titleWidth + 8 + 3.35, y: bounds.minY + g.headerCenter),
                                   length: 11.4, depth: 6.7, direction: view.yearsOpen ? 1 : 0)
        list.append(.strokePath(titleChevron, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round), tint))
        if view.yearsOpen { return }

        // The previous and next month: 10 × 17.4 chevrons.
        let chevronColor = g.chevronsTinted ? tint : primary
        for (rect, direction) in [(previousRect, 2), (nextRect, 0)] {
            let r = context.absoluteRect(rect)
            list.append(.strokePath(chevron(center: CGPoint(x: r.midX, y: r.midY), length: 17.4, depth: 10, direction: direction),
                                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round), chevronColor))
        }

        // The weekday names in 13 pt semibold grey.
        let grey = environment._ink(dark ? 0.36 : 0.41)
        let weekdayFont = _fontFor(size: 13, weight: .semibold)
        let weekdayLine = environment.platformProfile.systemFontMetrics(for: weekdayFont).lineHeight
        let weekdays = names.weekdays
        for column in 0..<7 {
            let name = weekdays[(names.firstWeekday - 1 + column) % 7]
            let cell = context.absoluteRect(self.cell(row: 0, column: column))
            let width = _textWidth(name, font: weekdayFont)
            _drawText(name, font: weekdayFont, lineTop: CGPoint(x: cell.midX - width / 2, y: bounds.minY + g.weekdayCenter - weekdayLine / 2), color: grey, into: &list)
        }

        // The days in 20 pt: the selection white (black in the dark) and semibold on a filled
        // circle, today in the tint on a pale tint circle; days out of the range dimmed.
        let selected = _DateMath.parts(of: view.binding.get(), calendar: calendar)
        let today = _DateMath.parts(of: Date(), calendar: calendar)
        let dayFont = _fontFor(size: 20), boldFont = _fontFor(size: 20, weight: .semibold)
        let dayLine = environment.platformProfile.systemFontMetrics(for: dayFont).lineHeight
        let diameter = min(columnWidth, rowHeight)
        for (row, week) in weeks.enumerated() {
            for (column, day) in week.enumerated() {
                guard let day else { continue }
                let cell = context.absoluteRect(self.cell(row: row, column: column))
                let circle = CGRect(x: cell.midX - diameter / 2, y: cell.midY - diameter / 2, width: diameter, height: diameter)
                let isSelected = selected.year == year && selected.month == month && selected.day == day
                let isToday = today.year == year && today.month == month && today.day == day
                var color = isInRange(year: year, month: month, day: day) ? primary : environment._ink(0.3)
                var font = dayFont
                if isSelected {
                    // Today selected: the circle in the tint.
                    let fill = isToday ? tint : primary
                    list.append(.fillRRect(circle, cornerRadius: diameter / 2, fill))
                    color = isToday || !dark ? RGBA(red: 1, green: 1, blue: 1, alpha: 1) : RGBA(red: 0, green: 0, blue: 0, alpha: 1)
                    font = boldFont
                } else if isToday {
                    list.append(.fillRRect(circle, cornerRadius: diameter / 2, tint.multiplyingAlpha(by: 0.12)))
                    color = tint
                }
                let text = "\(day)"
                let width = _textWidth(text, font: font)
                _drawText(text, font: font, lineTop: CGPoint(x: cell.midX - width / 2, y: cell.midY - dayLine / 2), color: color, into: &list)
            }
        }
    }

    /// Whether a day (any time of it) lies inside the picker's range.
    package func isInRange(year: Int, month: Int, day: Int) -> Bool {
        guard view.binding.minimum != nil || view.binding.maximum != nil else { return true }
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? view.date
        let end = _DateMath.adding(.day, 1, to: start, calendar: calendar).addingTimeInterval(-1)
        if let minimum = view.binding.minimum, end < minimum { return false }
        if let maximum = view.binding.maximum, start > maximum { return false }
        return true
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        if titleRect.contains(point) {
            view.onToggleYears()
            runtime.setNeedsDisplay()
            return
        }
        guard !view.yearsOpen else { return }
        let (year, month) = visibleMonth
        if previousRect.contains(point) || nextRect.contains(point) {
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.shown
            view.onShow(_DateMath.adding(.month, nextRect.contains(point) ? 1 : -1, to: first, calendar: calendar))
            runtime.setNeedsDisplay()
            return
        }
        for (row, week) in weeks.enumerated() {
            for (column, day) in week.enumerated() where cell(row: row, column: column).contains(point) {
                guard let day, isInRange(year: year, month: month, day: day) else { return }
                var parts = _DateMath.parts(of: view.binding.get(), calendar: calendar)
                parts.year = year; parts.month = month; parts.day = day
                view.binding.set(_DateMath.date(from: parts, calendar: calendar))
                runtime.setNeedsDisplay()
                return
            }
        }
    }

    package var semantics: SemanticsNode {
        let (year, month) = visibleMonth
        var node = SemanticsNode(role: .group, label: names.title(year: year, month: month), frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        return node
    }
}
