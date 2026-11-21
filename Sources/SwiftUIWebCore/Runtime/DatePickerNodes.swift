// DatePicker nodes (Docs/elements/DatePicker.md): the textual field (component slots in a bezel
// with a mini stepper), the month calendar and the analogue clock, plus the Gregorian date
// arithmetic they share (Foundation's calendar in the environment's time zone).
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// MARK: - Date arithmetic

package struct _DateParts: Equatable {
    package var year: Int, month: Int, day: Int, hour: Int, minute: Int
    /// 1 = Sunday.
    package var weekday: Int
}

extension EnvironmentValues {
    /// The Gregorian calendar in the environment's time zone (the only calendar drawn here).
    package var _gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

package enum _DateMath {
    package static let monthAbbreviations = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    package static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    package static let weekdayAbbreviations = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    package static func parts(of date: Date, calendar: Calendar) -> _DateParts {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        return _DateParts(year: c.year ?? 2001, month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0, minute: c.minute ?? 0, weekday: c.weekday ?? 1)
    }

    package static func date(from parts: _DateParts, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute)) ?? Date()
    }

    package static func adding(_ component: Calendar.Component, _ value: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    package static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return calendar.range(of: .day, in: .month, for: first)?.count ?? 30
    }

    /// The six weeks a month calendar shows, Sunday first: each day with whether it belongs to
    /// the month.
    package static func grid(year: Int, month: Int, calendar: Calendar) -> [[(day: Int, inMonth: Bool)]] {
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let leading = ((calendar.component(.weekday, from: first) - 1) + 7) % 7
        let count = daysInMonth(year: year, month: month, calendar: calendar)
        let previous = adding(.month, -1, to: first, calendar: calendar)
        let previousCount = daysInMonth(year: calendar.component(.year, from: previous), month: calendar.component(.month, from: previous), calendar: calendar)
        var cells: [(day: Int, inMonth: Bool)] = []
        for i in 0..<leading { cells.append((previousCount - leading + 1 + i, false)) }
        for day in 1...count { cells.append((day, true)) }
        var next = 1
        while cells.count < 42 { cells.append((next, false)); next += 1 }
        return (0..<6).map { Array(cells[$0 * 7..<$0 * 7 + 7]) }
    }
}

// MARK: - Text helpers

extension ViewNode {
    package func _fontFor(size: CGFloat, weight: Font.Weight = .regular) -> ResolvedFont {
        Font.system(size: size, weight: weight).resolve(profile: environment.platformProfile)
    }

    package func _textWidth(_ string: String, font: ResolvedFont) -> CGFloat {
        string.isEmpty ? 0 : runtime.layoutText(string, font: font, width: nil).size.width
    }

    /// Draws `string` with its line box's top-left at `origin` (the baseline from the font table).
    package func _drawText(_ string: String, font: ResolvedFont, lineTop origin: CGPoint, color: RGBA, into list: inout DisplayList) {
        let baseline = environment.platformProfile.systemFontMetrics(for: font).baseline
        list.append(.drawText(string, DisplayFont(font), origin: CGPoint(x: origin.x, y: origin.y + baseline), color))
    }
}

// MARK: - The field

@MainActor
private var nextDateIdentifier = 9_000_000

/// The textual field: the shown components sit in fixed slots (two tabular digits for month,
/// day, hour and minute, four for the year, 17 pt for the period) separated by "/", ", ", ":"
/// and a space; numbers are right-aligned in their slots. With a stepper the bezel is inset 1,
/// 72 pt wide for a date (the content starts 1 further in), then a 9 pt gap and the 13 × 20
/// stepper; without one (the field style) the bezel is the control with 3 pt insets and 21 tall.
@MainActor
package final class DateFieldNode: LeafNode<_DateFieldHost>, _Interactive, _KeyHandling, _Adjustable {
    private let identifier: Int
    /// The component a press selected (the stepper and arrow keys adjust it; none adjusts the first).
    package private(set) var selectedComponent: Calendar.Component?
    /// The digits typed into the selected component since it was selected.
    package private(set) var typed = ""
    private var typedComponent: Calendar.Component?

    override package init(_ context: _NodeContext<_DateFieldHost>) {
        nextDateIdentifier += 1
        identifier = nextDateIdentifier
        super.init(context)
    }

    package enum Segment {
        case value(Calendar.Component, String, width: CGFloat)
        case separator(String, width: CGFloat)
        package var width: CGFloat {
            switch self {
            case .value(_, _, let width), .separator(_, let width): return width
            }
        }
    }

    private var calendar: Calendar { environment._gregorian }
    private var font: ResolvedFont { _fontFor(size: PlatformMetrics.buttonLabelSize) }

    /// How a locale orders and pads the date (datepicker/locales on macOS 26.6: en_GB
    /// "15/03/2025, 15:09", de_DE "15.  3.2025, 15:09", fr_FR "15/03/2025", ja_JP "2025/  3/15 15:09";
    /// en_US "3/15/2025, 3:09 PM"). Other locales take their language's or region's rule, else en_US.
    package struct Format {
        package var order: [Calendar.Component]
        package var separator: String
        package var padsDate: Bool
        package var twentyFourHour: Bool
        package var joiner: String

        package static func format(for locale: Locale) -> Format {
            // The identifier's own parts (Foundation's accessors are deprecated on macOS).
            let parts = locale.identifier.split { $0 == "_" || $0 == "-" }.map(String.init)
            let language = parts.first?.lowercased() ?? "en"
            let region = parts.dropFirst().first?.uppercased()
            if language == "en", region == nil || region == "US" || region == "CA" || region == "PH" {
                return Format(order: [.month, .day, .year], separator: "/", padsDate: false, twentyFourHour: false, joiner: ", ")
            }
            switch language {
            case "de", "da", "nb", "fi", "cs", "pl", "ru", "tr":
                return Format(order: [.day, .month, .year], separator: ".", padsDate: false, twentyFourHour: true, joiner: ", ")
            case "ja", "zh", "ko", "hu", "lt":
                return Format(order: [.year, .month, .day], separator: "/", padsDate: false, twentyFourHour: true, joiner: " ")
            case "nl":
                return Format(order: [.day, .month, .year], separator: "-", padsDate: true, twentyFourHour: true, joiner: ", ")
            default:
                return Format(order: [.day, .month, .year], separator: "/", padsDate: true, twentyFourHour: true, joiner: ", ")
            }
        }
    }

    package var format: Format { Format.format(for: environment.locale) }

    /// The segments for the shown components.
    package var segments: [Segment] {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let digit = PlatformMetrics.dateDigitWidth, separator = PlatformMetrics.dateSeparatorWidth
        let format = format
        var result: [Segment] = []
        if view.components.contains(.date) {
            func pad(_ value: Int) -> String { format.padsDate && value < 10 ? "0\(value)" : "\(value)" }
            for (index, component) in format.order.enumerated() {
                if index > 0 { result.append(.separator(format.separator, width: separator)) }
                switch component {
                case .year: result.append(.value(.year, "\(parts.year)", width: 4 * digit))
                case .month: result.append(.value(.month, pad(parts.month), width: 2 * digit))
                default: result.append(.value(.day, pad(parts.day), width: 2 * digit))
                }
            }
        }
        if view.components.contains(.hourAndMinute) {
            if !result.isEmpty { result.append(.separator(format.joiner, width: format.joiner == " " ? separator : PlatformMetrics.dateCommaWidth)) }
            let minute = parts.minute < 10 ? "0\(parts.minute)" : "\(parts.minute)"
            if format.twentyFourHour {
                let hour = parts.hour < 10 ? "0\(parts.hour)" : "\(parts.hour)"
                result += [.value(.hour, hour, width: 2 * digit), .separator(":", width: separator), .value(.minute, minute, width: 2 * digit)]
            } else {
                let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
                result += [.value(.hour, "\(hour12)", width: 2 * digit), .separator(":", width: separator),
                           .value(.minute, minute, width: 2 * digit), .separator(" ", width: separator),
                           .value(.era, parts.hour < 12 ? "AM" : "PM", width: PlatformMetrics.datePeriodWidth)]
            }
        }
        return result
    }

    private var contentWidth: CGFloat { segments.reduce(0) { $0 + $1.width } }

    /// The bezel (its fill; the border is drawn outside) and where the content starts.
    package var bezel: CGRect {
        if view.stepper {
            return CGRect(x: PlatformMetrics.dateStepperBezelInset + PlatformMetrics.textFieldBorderWidth, y: 0,
                          width: contentWidth - 2 * PlatformMetrics.textFieldBorderWidth, height: frame.height)
        }
        return CGRect(x: PlatformMetrics.textFieldBorderWidth, y: 0, width: contentWidth + 2 * PlatformMetrics.dateFieldInset - 2 * PlatformMetrics.textFieldBorderWidth,
                      height: frame.height)
    }

    package var contentStart: CGFloat {
        view.stepper ? PlatformMetrics.dateStepperBezelInset + 2 * PlatformMetrics.textFieldBorderWidth : PlatformMetrics.dateFieldInset
    }

    package var stepperRect: CGRect? {
        guard view.stepper else { return nil }
        return CGRect(x: frame.width - PlatformMetrics.dateStepperSize.width, y: (frame.height - PlatformMetrics.dateStepperSize.height) / 2 + PlatformMetrics.dateStepperOffset,
                      width: PlatformMetrics.dateStepperSize.width, height: PlatformMetrics.dateStepperSize.height)
    }

    // MARK: iOS pills (ios/datepicker/compact)

    /// iOS: the values sit in tinted pills at the row's trailing edge ("Mar 15, 2025", "11:09 AM").
    private var pills: Bool { PlatformMetrics.datePills }
    private var pillFont: ResolvedFont { _fontFor(size: PlatformMetrics.dateTextSize) }
    private var pillHeight: CGFloat { view.components.contains(.hourAndMinute) ? PlatformMetrics.dateTimePillHeight : PlatformMetrics.datePillHeight }

    /// The pills' texts in the locale's way, as iOS 27 writes them: en_GB "13 Oct 2026" and
    /// "05:30", en_US "Oct 13, 2026" and "5:30 AM", German "13.10.2026", French "13 oct. 2026".
    package var pillTexts: [String] {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let style = WheelDateNode.Style(locale: environment.locale)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        var result: [String] = []
        if view.components.contains(.date) {
            let month = _DateMath.monthAbbreviations[min(max(parts.month, 1), 12) - 1]
            switch style.language {
            case "de", "da", "nb", "fi", "cs", "pl", "ru", "tr": result.append("\(parts.day).\(two(parts.month)).\(parts.year)")
            case "fr":
                let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
                result.append("\(parts.day) \(months[parts.month - 1]) \(parts.year)")
            default:
                result.append(style.monthFirst ? "\(month) \(parts.day), \(parts.year)" : "\(parts.day) \(month) \(parts.year)")
            }
        }
        if view.components.contains(.hourAndMinute) {
            if style.twentyFourHour {
                result.append("\(two(parts.hour)):\(two(parts.minute))")
            } else {
                let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
                // A narrow no-break space before the period, as iOS writes it.
                result.append("\(hour12):\(two(parts.minute))\u{202F}\(parts.hour < 12 ? "AM" : "PM")")
            }
        }
        return result
    }

    /// The pills, trailing-aligned in the node, and their texts.
    package var pillRects: [(text: String, rect: CGRect)] {
        var x = frame.width
        var result: [(String, CGRect)] = []
        for text in pillTexts.reversed() {
            let width = _textWidth(text, font: pillFont) + 2 * PlatformMetrics.datePillPadding
            x -= width
            result.insert((text, CGRect(x: x, y: 0, width: width, height: pillHeight)), at: 0)
            x -= PlatformMetrics.datePillGap
        }
        return result
    }

    private var pillsWidth: CGFloat {
        let texts = pillTexts
        return texts.reduce(0) { $0 + _textWidth($1, font: pillFont) + 2 * PlatformMetrics.datePillPadding } + CGFloat(max(0, texts.count - 1)) * PlatformMetrics.datePillGap
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if pills { return CGSize(width: pillsWidth, height: pillHeight) }
        if view.stepper {
            let width = PlatformMetrics.dateStepperBezelInset + contentWidth + PlatformMetrics.dateStepperGap + PlatformMetrics.dateStepperSize.width
            return CGSize(width: width, height: PlatformMetrics.dateCompactHeight)
        }
        return CGSize(width: contentWidth + 2 * PlatformMetrics.dateFieldInset, height: PlatformMetrics.dateFieldHeight)
    }

    override package var layoutSpacing: ViewSpacing { .textLikeControl }

    /// The text line sits 2 pt down in the 20 pt stepper styles (macOS 27; 26.2 centred it in
    /// 22) and a point down in the 21 pt field.
    private func lineTop(_ lineHeight: CGFloat) -> CGFloat {
        view.stepper ? PlatformMetrics.dateCompactTextTop : PlatformMetrics.dateFieldTextTop
    }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let metrics = environment.platformProfile.systemFontMetrics(for: pills ? pillFont : font)
        let baseline = (pills ? (size.height - metrics.lineHeight) / 2 : view.stepper ? PlatformMetrics.dateCompactTextTop : PlatformMetrics.dateFieldTextTop) + metrics.baseline
        return ViewDimensions(size: size, explicit: [VerticalAlignment.firstTextBaseline.key: baseline, VerticalAlignment.lastTextBaseline.key: baseline])
    }

    /// The slot rectangles of the value segments, in the node's coordinates.
    package var slots: [(component: Calendar.Component, rect: CGRect)] {
        var x = contentStart
        var result: [(Calendar.Component, CGRect)] = []
        let lineHeight = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        let y = lineTop(lineHeight)
        for segment in segments {
            if case .value(let component, _, let width) = segment {
                result.append((component, CGRect(x: x, y: y, width: width, height: lineHeight)))
            }
            x += segment.width
        }
        return result
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        let dark = environment.colorScheme == .dark
        let black = { (alpha: Double) in self.environment._ink(alpha) }
        if pills {
            // iOS: a tinted pill per value with the text centred; disabled, the texts alone.
            let font = pillFont
            let lineHeight = environment.platformProfile.systemFontMetrics(for: font).lineHeight
            let color = (environment.foregroundColor ?? .primary).resolve(in: environment)
            let open = popover.flatMap { popover in runtime.presentations.contains { $0 === popover } ? openPill : nil }
            for (index, (text, rect)) in pillRects.enumerated() {
                let pill = context.absoluteRect(rect)
                // iOS 27: capsules; the pill whose picker is open shows its text in the tint.
                if enabled { list.append(.fillRRect(pill, cornerRadius: min(PlatformMetrics.datePillCornerRadius, pill.height / 2), black(PlatformMetrics.datePillAlpha))) }
                let origin = CGPoint(x: pill.minX + PlatformMetrics.datePillPadding, y: pill.minY + (pill.height - lineHeight) / 2)
                _drawText(text, font: font, lineTop: origin, color: open == index ? Color.accentColor.resolve(in: environment) : color, into: &list)
            }
            return
        }
        let bezel = context.absoluteRect(self.bezel)
        let outer = bezel.insetBy(dx: -PlatformMetrics.textFieldBorderWidth, dy: -PlatformMetrics.textFieldBorderWidth)
        // The light capsule: a 12/255 edge outside the white bezel; the dark one a (35) edge
        // around a (22) fill at 85 % (dark/chrome, macOS 27).
        list.append(.fillRRect(outer, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.textFieldBorderWidth,
                               dark ? PlatformMetrics.dateFieldBorderDark : black(PlatformMetrics.dateFieldBorderAlpha)))
        list.append(.fillRRect(bezel, cornerRadius: PlatformMetrics.textFieldCornerRadius, dark ? PlatformMetrics.dateFieldFillDark : environment._controlBackground))
        let focused = runtime.focusedIdentifier == identifier
        if focused {
            let ring = outer.insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
            list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.focusRingWidth, style: .circular),
                                    style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                    Color.accentColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: environment)))
        }
        // Components: numbers right-aligned in their slots, the period a point before its slot.
        var color = (environment.foregroundColor ?? .primary).resolve(in: environment)
        if !enabled { color = color.multiplyingAlpha(by: PlatformMetrics.disabledLabelOpacity) }
        let font = font
        let lineHeight = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        var x = bounds.minX + contentStart
        let lineTop = bounds.minY + self.lineTop(lineHeight)
        for segment in segments {
            switch segment {
            case .separator(let text, let width):
                _drawText(text, font: font, lineTop: CGPoint(x: x, y: lineTop), color: color, into: &list)
                x += width
            case .value(let component, let text, let width):
                let textWidth = _textWidth(text, font: font)
                let origin: CGFloat = component == .era ? x - PlatformMetrics.datePeriodLead : x + width - textWidth
                var textColor = color
                if focused, selectedComponent == component {
                    list.append(.fillRRect(CGRect(x: x, y: lineTop, width: width, height: lineHeight), cornerRadius: PlatformMetrics.dateSelectionCornerRadius,
                                           Color.accentColor.resolve(in: environment)))
                    textColor = RGBA(red: 1, green: 1, blue: 1, alpha: 1)
                }
                _drawText(text, font: font, lineTop: CGPoint(x: origin, y: lineTop), color: textColor, into: &list)
                x += width
            }
        }
        // The mini stepper: a rounded box with a divider and two chevrons.
        if let stepper = stepperRect.map(context.absoluteRect) {
            list.append(.fillRRect(stepper, cornerRadius: PlatformMetrics.dateStepperCornerRadius,
                                   black(enabled ? PlatformMetrics.stepperFill : PlatformMetrics.stepperDisabledFill)))
            let divider = CGRect(x: stepper.minX + PlatformMetrics.dateStepperDividerInset, y: stepper.minY + PlatformMetrics.dateStepperDividerTop,
                                 width: stepper.width - 2 * PlatformMetrics.dateStepperDividerInset, height: 1)
            list.append(.fillRect(divider, black(PlatformMetrics.stepperDividerAlpha)))
            let x0 = stepper.minX + PlatformMetrics.dateStepperChevronInset, x1 = stepper.maxX - PlatformMetrics.dateStepperChevronInset
            var chevrons = Path()
            chevrons.move(to: CGPoint(x: x0, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase))
            chevrons.addLine(to: CGPoint(x: stepper.midX, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase - PlatformMetrics.dateStepperChevronRise))
            chevrons.addLine(to: CGPoint(x: x1, y: stepper.minY + PlatformMetrics.dateStepperUpChevronBase))
            chevrons.move(to: CGPoint(x: x0, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase))
            chevrons.addLine(to: CGPoint(x: stepper.midX, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase + PlatformMetrics.dateStepperChevronRise))
            chevrons.addLine(to: CGPoint(x: x1, y: stepper.minY + PlatformMetrics.dateStepperDownChevronBase))
            list.append(.strokePath(chevrons, style: StrokeStyle(lineWidth: PlatformMetrics.stepperChevronStroke, lineCap: .round, lineJoin: .round),
                                    black(enabled ? PlatformMetrics.stepperChevronAlpha : PlatformMetrics.stepperDisabledChevronAlpha)))
        }
    }

    // MARK: Interaction

    /// Steps the selected component (the first when none is selected).
    package func step(_ direction: Int) {
        let component = selectedComponent ?? slots.first?.component ?? .day
        let date = view.date
        let next: Date
        switch component {
        case .era:
            next = _DateMath.adding(.hour, direction > 0 ? 12 : -12, to: date, calendar: calendar)
        default:
            next = _DateMath.adding(component, direction, to: date, calendar: calendar)
        }
        view.binding.set(next)
        // Re-read so a binding nobody observes still shows the new date.
        view = _DateFieldHost(date: view.binding.get(), binding: view.binding, components: view.components, stepper: view.stepper, opensPopover: view.opensPopover)
        runtime.setNeedsDisplay()
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {}

    /// The compact style's popover with the graphical picker, while open.
    package private(set) var popover: PresentationNode?

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, environment.isEnabled else { return }
        // Presses arrive outside layout: read this picker's own platform's metrics.
        let previous = PlatformMetrics.select(environment.platformProfile)
        defer { PlatformMetrics.current = previous }
        if pills {
            openPicker(at: point)
            return
        }
        if let stepper = stepperRect, stepper.contains(point) {
            step(point.y < stepper.midY ? 1 : -1)
            return
        }
        if view.opensPopover {
            // The compact style: the graphical picker in a popover under the field.
            if let popover, runtime.presentations.contains(where: { $0 === popover }) { return }
            let content = AnyView(_GraphicalDatePicker(date: view.date, binding: view.binding, components: view.components).padding(PlatformMetrics.defaultSpacing))
            popover = runtime.present(kind: .popover(arrowEdge: .bottom, anchor: .rect(.bounds)), view: content, environment: environment, anchor: self) { [weak self] in
                self?.popover = nil
            }
            return
        }
        if let slot = slots.first(where: { $0.rect.insetBy(dx: -2, dy: -4).contains(point) }) {
            select(slot.component)
        } else if let last = slots.last, point.x > last.rect.maxX {
            select(last.component)
        } else {
            select(slots.first?.component)
        }
        runtime.focus(semanticsIdentifier: identifier)
        runtime.setNeedsDisplay()
    }

    /// The pill whose picker is open (0 the first).
    private var openPill = 0

    /// iOS: a pressed pill opens its picker over the app in the iPhone's frosted panel: the time
    /// wheel for a time, the calendar for a date (`PresentationNode.isSystemPicker`).
    private func openPicker(at point: CGPoint) {
        if let popover, runtime.presentations.contains(where: { $0 === popover }) { return }
        let rects = pillRects
        let index = rects.firstIndex { point.x < $0.rect.maxX + PlatformMetrics.datePillGap / 2 } ?? max(0, rects.count - 1)
        let isTime = view.components.contains(.hourAndMinute) && (index == rects.count - 1)
        openPill = index
        let content: AnyView = isTime
            ? AnyView(_WheelDateHost(date: view.date, binding: view.binding, components: .hourAndMinute, panelSize: PlatformMetrics.timePopoverSize))
            : AnyView(_IOSCalendar(date: view.date, binding: view.binding, inPanel: true))
        var source = rects.indices.contains(index) ? rects[index].rect : CGRect(origin: .zero, size: frame.size)
        source.origin.y = 0
        source.size.height = frame.height
        popover = runtime.present(kind: .popover(arrowEdge: .bottom, anchor: .rect(.rect(source))), view: content, environment: environment, anchor: self) { [weak self] in
            guard let self else { return }
            popover = nil
            // Re-read so a binding nobody observes still shows the picked time.
            view = _DateFieldHost(date: view.binding.get(), binding: view.binding, components: view.components, stepper: view.stepper, opensPopover: view.opensPopover)
            runtime.setNeedsDisplay()
        }
        popover?.isSystemPicker = true
        runtime.setNeedsDisplay()
    }

    private func select(_ component: Calendar.Component?) {
        if component != selectedComponent { typed = "" }
        selectedComponent = component
    }

    /// Up/Down step the selected component, Left/Right move the selection; digits type into the
    /// selected component (two for the month, day, hour and minute, four for the year; the
    /// selection moves on when the component is full), Delete takes a digit back, A and P set
    /// the period.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard environment.isEnabled, press.modifiers.shortcutModifiers.isEmpty else { return false }
        let components = slots.map(\.component)
        switch press.key {
        case .upArrow: step(1); return true
        case .downArrow: step(-1); return true
        case .leftArrow, .rightArrow:
            let current = components.firstIndex { $0 == selectedComponent } ?? 0
            let next = press.key == .rightArrow ? min(current + 1, components.count - 1) : max(current - 1, 0)
            select(components.isEmpty ? nil : components[next])
            runtime.setNeedsDisplay()
            return true
        case .delete, .deleteForward:
            guard !typed.isEmpty else { return false }
            typed.removeLast()
            applyTyped()
            return true
        default:
            break
        }
        guard press.characters.count == 1, let character = press.characters.first else { return false }
        if let digit = character.wholeNumberValue {
            if selectedComponent == nil || typedComponent != selectedComponent { typed = "" }
            if selectedComponent == nil { select(components.first) }
            guard let component = selectedComponent, component != .era else { return false }
            typedComponent = component
            typed.append("\(digit)")
            applyTyped()
            // Full, or unable to take another digit: move on to the next component.
            let capacity = component == .year ? 4 : 2
            let value = Int(typed) ?? 0
            let maximum = component == .month ? 12 : component == .day ? 31 : component == .hour ? (format.twentyFourHour ? 23 : 12) : component == .minute ? 59 : 9999
            if typed.count >= capacity || (component != .year && value * 10 > maximum) {
                if let index = components.firstIndex(of: component), index + 1 < components.count { select(components[index + 1]) } else { typed = "" }
            }
            return true
        }
        if character == "a" || character == "A" || character == "p" || character == "P", view.components.contains(.hourAndMinute), !format.twentyFourHour {
            var parts = _DateMath.parts(of: view.date, calendar: calendar)
            let wantsPM = character == "p" || character == "P"
            if (parts.hour >= 12) != wantsPM { parts.hour = wantsPM ? parts.hour + 12 : parts.hour - 12 }
            commit(parts)
            return true
        }
        return false
    }

    /// Sets the selected component from the typed digits (clamped into its range).
    private func applyTyped() {
        guard let component = selectedComponent, let value = Int(typed) else { return }
        var parts = _DateMath.parts(of: view.date, calendar: calendar)
        switch component {
        case .month: parts.month = min(max(value, 1), 12)
        case .day: parts.day = min(max(value, 1), _DateMath.daysInMonth(year: parts.year, month: parts.month, calendar: calendar))
        case .hour:
            if format.twentyFourHour {
                parts.hour = min(max(value, 0), 23)
            } else {
                let base = parts.hour >= 12 ? 12 : 0
                parts.hour = base + (min(max(value, 1), 12) % 12)
            }
        case .minute: parts.minute = min(max(value, 0), 59)
        case .year: if typed.count == 4 { parts.year = value }
        default: return
        }
        commit(parts)
    }

    private func commit(_ parts: _DateParts) {
        view.binding.set(_DateMath.date(from: parts, calendar: calendar))
        view = _DateFieldHost(date: view.binding.get(), binding: view.binding, components: view.components, stepper: view.stepper, opensPopover: view.opensPopover)
        runtime.setNeedsDisplay()
    }

    package func adjust(increment: Bool) { step(increment ? 1 : -1) }
    package func setValue(_ value: Double) {}

    /// The shown text, for assistive technology.
    package var text: String {
        segments.map { segment -> String in
            switch segment {
            case .value(_, let text, _), .separator(let text, _): return text
            }
        }.joined()
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: .group, label: text, frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        node.isAdjustable = view.stepper
        node.value = text
        return node
    }
}

// MARK: - The calendar

/// The month calendar: a 137.5 × 148 box (in a 138.5 pt view) holding the month's name and
/// year in 13 pt bold, previous/today/next controls, the weekday row in 10 pt bold grey and six
/// weeks of 18.5 × 18 cells with 11 pt day numbers right-aligned, the selected day on a grey
/// rounded highlight and the neighbouring months' days in grey.
@MainActor
package final class CalendarNode: LeafNode<_CalendarHost>, _Interactive {
    private let identifier: Int
    /// The month shown when the user paged away from the selection's month.
    package private(set) var shown: (year: Int, month: Int)?

    override package init(_ context: _NodeContext<_CalendarHost>) {
        nextDateIdentifier += 1
        identifier = nextDateIdentifier
        super.init(context)
    }

    private var calendar: Calendar { environment._gregorian }

    package var visibleMonth: (year: Int, month: Int) {
        if let shown { return shown }
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        return (parts.year, parts.month)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.calendarSize }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    package var box: CGRect {
        CGRect(x: PlatformMetrics.calendarBoxInset.width, y: PlatformMetrics.calendarBoxInset.height,
               width: PlatformMetrics.calendarBoxSize.width, height: PlatformMetrics.calendarBoxSize.height)
    }

    package func cell(row: Int, column: Int) -> CGRect {
        let box = box
        return CGRect(x: box.minX + PlatformMetrics.calendarCellMargin + CGFloat(column) * PlatformMetrics.calendarCellSize.width,
                      y: box.minY + PlatformMetrics.calendarFirstRowCenter - PlatformMetrics.calendarCellSize.height / 2 + CGFloat(row) * PlatformMetrics.calendarCellSize.height,
                      width: PlatformMetrics.calendarCellSize.width, height: PlatformMetrics.calendarCellSize.height)
    }

    /// The previous-month, today and next-month controls, trailing in the header row.
    package var controls: (previous: CGRect, today: CGRect, next: CGRect) {
        let box = box
        let centerY = box.minY + PlatformMetrics.calendarHeaderCenter
        let arrow = PlatformMetrics.calendarArrowSize, dot = PlatformMetrics.calendarDotDiameter, gap = PlatformMetrics.calendarControlGap
        let next = CGRect(x: box.maxX - PlatformMetrics.calendarControlTrailing - arrow.width, y: centerY - arrow.height / 2, width: arrow.width, height: arrow.height)
        let today = CGRect(x: next.minX - gap - dot, y: centerY - dot / 2, width: dot, height: dot)
        let previous = CGRect(x: today.minX - gap - arrow.width, y: centerY - arrow.height / 2, width: arrow.width, height: arrow.height)
        return (previous, today, next)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        // The ink: black in the light appearance, white in the dark, where the box is also
        // filled white at 13/255 under a stronger edge (dark/chrome, macOS 27).
        let dark = environment.colorScheme == .dark
        let black = { (alpha: Double) in self.environment._ink(alpha) }
        let box = context.absoluteRect(self.box)
        if dark {
            list.append(.fillRRect(box, cornerRadius: PlatformMetrics.calendarBoxCornerRadius, black(PlatformMetrics.calendarBoxFillDark)))
        }
        list.append(.strokePath(Path(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: PlatformMetrics.calendarBoxCornerRadius, style: .circular),
                                style: StrokeStyle(lineWidth: 1), black(dark ? PlatformMetrics.calendarBoxBorderAlphaDark : PlatformMetrics.calendarBoxBorderAlpha)))
        let primary = Color.primary.resolve(in: environment)
        let grey = black(dark ? PlatformMetrics.calendarMutedAlphaDark : PlatformMetrics.calendarMutedAlpha)
        // Header: "Mar 2025" in 13 pt bold, the controls in the secondary colour.
        let (year, month) = visibleMonth
        let header = _fontFor(size: PlatformMetrics.buttonLabelSize, weight: .bold)
        let headerLine = environment.platformProfile.systemFontMetrics(for: header).lineHeight
        _drawText("\(_DateMath.monthAbbreviations[month - 1]) \(year)", font: header,
                  lineTop: CGPoint(x: box.minX + PlatformMetrics.calendarHeaderLeading, y: box.minY + PlatformMetrics.calendarHeaderCenter - headerLine / 2),
                  color: primary, into: &list)
        let controls = controls
        let secondary = Color.secondary.resolve(in: environment)
        for (rect, forward) in [(controls.previous, false), (controls.next, true)] {
            let r = context.absoluteRect(rect)
            var triangle = Path()
            if forward {
                triangle.move(to: CGPoint(x: r.minX, y: r.minY)); triangle.addLine(to: CGPoint(x: r.maxX, y: r.midY)); triangle.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            } else {
                triangle.move(to: CGPoint(x: r.maxX, y: r.minY)); triangle.addLine(to: CGPoint(x: r.minX, y: r.midY)); triangle.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            }
            triangle.closeSubpath()
            list.append(.fillPath(triangle, secondary))
        }
        let today = context.absoluteRect(controls.today)
        list.append(.fillRRect(today, cornerRadius: today.width / 2, secondary))
        // Weekdays, centred in their columns.
        let weekdayFont = _fontFor(size: PlatformMetrics.calendarWeekdaySize, weight: .bold)
        let weekdayLine = environment.platformProfile.systemFontMetrics(for: weekdayFont).lineHeight
        for (column, name) in _DateMath.weekdayAbbreviations.enumerated() {
            let cell = context.absoluteRect(self.cell(row: 0, column: column))
            let width = _textWidth(name, font: weekdayFont)
            _drawText(name, font: weekdayFont, lineTop: CGPoint(x: cell.midX - width / 2, y: box.minY + PlatformMetrics.calendarWeekdayCenter - weekdayLine / 2),
                      color: grey, into: &list)
        }
        // Days, right-aligned 3 pt before the cell's trailing edge; the selection highlighted.
        let dayFont = _fontFor(size: PlatformMetrics.calendarDaySize)
        let dayLine = environment.platformProfile.systemFontMetrics(for: dayFont).lineHeight
        let selected = _DateMath.parts(of: view.date, calendar: calendar)
        let dimmed = black(PlatformMetrics.calendarOutOfRangeAlpha)
        for (row, week) in _DateMath.grid(year: year, month: month, calendar: calendar).enumerated() {
            for (column, day) in week.enumerated() {
                let cell = context.absoluteRect(self.cell(row: row, column: column))
                if day.inMonth, selected.year == year, selected.month == month, selected.day == day.day {
                    let highlight = cell.insetBy(dx: 0, dy: PlatformMetrics.calendarHighlightInset)
                    list.append(.fillRRect(highlight, cornerRadius: PlatformMetrics.calendarHighlightCornerRadius, dark ? PlatformMetrics.calendarHighlightDark : black(PlatformMetrics.calendarHighlightAlpha)))
                }
                let text = "\(day.day)"
                let width = _textWidth(text, font: dayFont)
                // Days outside the picker's range are dimmed (datepicker/looks `rangeCalendar`).
                let color = !day.inMonth ? grey : isInRange(row: row, day: day) ? primary : dimmed
                _drawText(text, font: dayFont, lineTop: CGPoint(x: cell.maxX - PlatformMetrics.calendarDayTrailing - width, y: cell.midY - dayLine / 2),
                          color: color, into: &list)
            }
        }
    }

    /// The parts a grid cell names: the shown month's day, or the neighbouring month's.
    private func parts(row: Int, day: (day: Int, inMonth: Bool)) -> _DateParts {
        let (year, month) = visibleMonth
        var parts = _DateMath.parts(of: view.date, calendar: calendar)
        if day.inMonth {
            parts.year = year; parts.month = month
        } else {
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.date
            let moved = _DateMath.adding(.month, row == 0 ? -1 : 1, to: first, calendar: calendar)
            parts.year = calendar.component(.year, from: moved); parts.month = calendar.component(.month, from: moved)
        }
        parts.day = day.day
        return parts
    }

    /// Whether a day (any time of it) lies inside the picker's range.
    package func isInRange(row: Int, day: (day: Int, inMonth: Bool)) -> Bool {
        guard view.binding.minimum != nil || view.binding.maximum != nil else { return true }
        var parts = parts(row: row, day: day)
        parts.hour = 0; parts.minute = 0
        let start = _DateMath.date(from: parts, calendar: calendar)
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
        let controls = controls
        let (year, month) = visibleMonth
        if controls.previous.insetBy(dx: -4, dy: -4).contains(point) || controls.next.insetBy(dx: -4, dy: -4).contains(point) {
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? view.date
            let moved = _DateMath.adding(.month, controls.next.insetBy(dx: -4, dy: -4).contains(point) ? 1 : -1, to: first, calendar: calendar)
            shown = (calendar.component(.year, from: moved), calendar.component(.month, from: moved))
            runtime.setNeedsDisplay()
            return
        }
        if controls.today.insetBy(dx: -4, dy: -4).contains(point) {
            shown = nil
            select(_DateMath.parts(of: Date(), calendar: calendar))
            return
        }
        let grid = _DateMath.grid(year: year, month: month, calendar: calendar)
        for row in 0..<6 {
            for column in 0..<7 where cell(row: row, column: column).contains(point) {
                let day = grid[row][column]
                // A dimmed day (outside the range) takes no press.
                guard isInRange(row: row, day: day) else { return }
                shown = nil
                select(parts(row: row, day: day))
                return
            }
        }
    }

    /// Sets the selection's year, month and day (keeping the time).
    private func select(_ target: _DateParts) {
        var parts = _DateMath.parts(of: view.date, calendar: calendar)
        parts.year = target.year; parts.month = target.month; parts.day = target.day
        view.binding.set(_DateMath.date(from: parts, calendar: calendar))
        view = _CalendarHost(date: view.binding.get(), binding: view.binding)
        runtime.setNeedsDisplay()
    }

    package var semantics: SemanticsNode {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        var node = SemanticsNode(role: .group, label: "\(_DateMath.monthAbbreviations[parts.month - 1]) \(parts.day), \(parts.year)", frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        return node
    }
}

// MARK: - The clock

/// The analogue clock: a 120 pt dial in a 119 pt square, a 6 pt bezel ring with a light-blue
/// to grey vertical gradient over a faint inner shadow, 13 pt numerals at radius 48.5, the
/// period under the centre in 13 pt medium grey, and black hands. Display only.
@MainActor
package final class ClockNode: LeafNode<_ClockHost>, _Interactive {
    private let identifier: Int
    private var calendar: Calendar { environment._gregorian }
    /// The hand a press took hold of (dragging it sets the time).
    package private(set) var draggedHand: Calendar.Component?

    override package init(_ context: _NodeContext<_ClockHost>) {
        nextDateIdentifier += 1
        identifier = nextDateIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { PlatformMetrics.clockSize }
    override package var layoutSpacing: ViewSpacing { .plainControl }

    package var dragAxes: Axis.Set { [.horizontal, .vertical] }

    /// A press takes the minute hand beyond the hour hand's reach, else the hour hand.
    package func pressBegan(at point: CGPoint) {
        guard environment.isEnabled else { return }
        let dx = point.x - PlatformMetrics.clockCenter.x, dy = point.y - PlatformMetrics.clockCenter.y
        let distance = (dx * dx + dy * dy).squareRoot()
        draggedHand = distance > PlatformMetrics.clockHourHandLength + 4 ? .minute : .hour
        drag(to: point)
    }

    package func pressBegan() {}
    package func pressMoved(to point: CGPoint) { drag(to: point) }
    package func pressEnded(inside: Bool) { draggedHand = nil }

    /// Turns the held hand to the point's angle: the minute hand to the nearest minute, the hour
    /// hand to the nearest hour (its period kept).
    private func drag(to point: CGPoint) {
        guard let hand = draggedHand else { return }
        let dx = point.x - PlatformMetrics.clockCenter.x, dy = PlatformMetrics.clockCenter.y - point.y
        guard dx != 0 || dy != 0 else { return }
        // Clockwise from the top, 0 to 1.
        var turn = (Double.pi / 2 - _atan2(dy, dx)) / (2 * .pi)
        if turn < 0 { turn += 1 }
        var parts = _DateMath.parts(of: view.date, calendar: calendar)
        switch hand {
        case .minute: parts.minute = Int((turn * 60).rounded()) % 60
        default:
            let hour = Int((turn * 12).rounded()) % 12
            parts.hour = (parts.hour >= 12 ? 12 : 0) + hour
        }
        view.binding.set(_DateMath.date(from: parts, calendar: calendar))
        view = _ClockHost(date: view.binding.get(), binding: view.binding)
        runtime.setNeedsDisplay()
    }

    package var semantics: SemanticsNode {
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let hour12 = parts.hour % 12 == 0 ? 12 : parts.hour % 12
        var node = SemanticsNode(role: .group, label: "\(hour12):\(parts.minute < 10 ? "0" : "")\(parts.minute) \(parts.hour < 12 ? "AM" : "PM")", frame: frameInRoot, identifier: identifier)
        node.isFocusable = true
        return node
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let center = CGPoint(x: bounds.minX + PlatformMetrics.clockCenter.x, y: bounds.minY + PlatformMetrics.clockCenter.y)
        let radius = PlatformMetrics.clockRadius
        let black = { (alpha: Double) in self.environment._ink(alpha) }
        func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)) }
        // The face, the bezel ring (a vertical gradient) and the inner shadow fading downwards.
        list.append(.fillPath(circle(radius), PlatformMetrics.clockFaceColor))
        let ring = PlatformMetrics.clockRingWidth
        let ringGradient = DisplayGradient(kind: .linear(start: CGPoint(x: center.x, y: center.y - radius), end: CGPoint(x: center.x, y: center.y + radius)),
                                           stops: [.init(location: 0, color: PlatformMetrics.clockRingTop), .init(location: 1, color: PlatformMetrics.clockRingBottom)])
        list.append(.strokeGradient(circle(radius - ring / 2), style: StrokeStyle(lineWidth: ring), ringGradient))
        let shadowGradient = DisplayGradient(kind: .linear(start: CGPoint(x: center.x, y: center.y - radius), end: CGPoint(x: center.x, y: center.y + radius)),
                                             stops: [.init(location: 0, color: black(PlatformMetrics.clockInnerShadowAlpha)), .init(location: 1, color: black(0))])
        list.append(.strokeGradient(circle(radius - ring - PlatformMetrics.clockInnerShadowWidth / 2), style: StrokeStyle(lineWidth: PlatformMetrics.clockInnerShadowWidth), shadowGradient))
        // Numerals around the dial and the period under the centre.
        let font = _fontFor(size: PlatformMetrics.buttonLabelSize)
        let line = environment.platformProfile.systemFontMetrics(for: font).lineHeight
        let primary = Color.primary.resolve(in: environment)
        for hour in 1...12 {
            let angle = Double.pi / 2 - Double(hour) * .pi / 6
            let text = "\(hour)"
            let width = _textWidth(text, font: font)
            let position = CGPoint(x: center.x + PlatformMetrics.clockNumeralRadius * CGFloat(_cos(angle)), y: center.y - PlatformMetrics.clockNumeralRadius * CGFloat(_sin(angle)))
            _drawText(text, font: font, lineTop: CGPoint(x: position.x - width / 2, y: position.y - line / 2), color: primary, into: &list)
        }
        let parts = _DateMath.parts(of: view.date, calendar: calendar)
        let periodFont = _fontFor(size: PlatformMetrics.buttonLabelSize, weight: .medium)
        let period = parts.hour < 12 ? "AM" : "PM"
        let periodWidth = _textWidth(period, font: periodFont)
        _drawText(period, font: periodFont, lineTop: CGPoint(x: center.x - periodWidth / 2, y: center.y + PlatformMetrics.clockPeriodOffset - line / 2),
                  color: black(PlatformMetrics.clockPeriodAlpha), into: &list)
        // Hands and the centre cap.
        let hourAngle = Double.pi / 2 - (Double(parts.hour % 12) + Double(parts.minute) / 60) * .pi / 6
        let minuteAngle = Double.pi / 2 - Double(parts.minute) * .pi / 30
        for (angle, length, width) in [(hourAngle, PlatformMetrics.clockHourHandLength, PlatformMetrics.clockHourHandWidth),
                                       (minuteAngle, PlatformMetrics.clockMinuteHandLength, PlatformMetrics.clockMinuteHandWidth)] {
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: CGPoint(x: center.x + length * CGFloat(_cos(angle)), y: center.y - length * CGFloat(_sin(angle))))
            list.append(.strokePath(hand, style: StrokeStyle(lineWidth: width, lineCap: .round), primary))
        }
        list.append(.fillPath(circle(PlatformMetrics.clockCapRadius), primary))
    }
}
