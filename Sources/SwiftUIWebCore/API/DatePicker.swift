// DatePicker (Docs/elements/DatePicker.md): the macOS textual date field (two-digit component
// slots in a bezel, an optional mini stepper), the graphical calendar and clock; styles, the
// displayed components, ranges, and the time zone / calendar environment.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A control for selecting an absolute date.
public struct DatePicker<Label: View>: View {
    package let label: Label
    package let selection: Binding<Date>
    package let minimum: Date?
    package let maximum: Date?
    package let components: DatePickerComponents

    @Environment(\.datePickerStyle) private var style
    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\._formStyle) private var formStyle
    @Environment(\._inListRow) private var inListRow
    @Environment(\.platformProfile) private var platform

    /// Creates a date picker with a custom label.
    public init(selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date], @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        minimum = nil
        maximum = nil
        components = displayedComponents
    }

    /// Creates a date picker that limits the selection to a range.
    public init(selection: Binding<Date>, in bounds: ClosedRange<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
                @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        minimum = bounds.lowerBound
        maximum = bounds.upperBound
        components = displayedComponents
    }

    public init(selection: Binding<Date>, in bounds: PartialRangeFrom<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
                @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        minimum = bounds.lowerBound
        maximum = nil
        components = displayedComponents
    }

    public init(selection: Binding<Date>, in bounds: PartialRangeThrough<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date],
                @ViewBuilder label: () -> Label) {
        self.label = label()
        self.selection = selection
        minimum = nil
        maximum = bounds.upperBound
        components = displayedComponents
    }

    public var body: some View {
        // Read the selection here so observation tracks the model it comes from.
        let date = selection.wrappedValue
        let binding = _DateBinding(selection, minimum: minimum, maximum: maximum)
        let content: AnyView
        if style._kind == .graphical, platform.isIOS, components.contains(.date) {
            // iOS 27's own calendar (new-website#674), with a "Time" row when the time is shown too.
            content = AnyView(_IOSCalendar(date: date, binding: binding, inPanel: false, showsTime: components.contains(.hourAndMinute)))
        } else if style._kind == .graphical {
            content = AnyView(_GraphicalDatePicker(date: date, binding: binding, components: components))
        } else if style._kind == .wheel, platform.isIOS {
            content = AnyView(_WheelDateHost(date: date, binding: binding, components: components))
        } else {
            // macOS's compact field opens the graphical picker in a popover on a press.
            content = AnyView(_DateFieldHost(date: date, binding: binding, components: components, stepper: style._kind != .field,
                                             opensPopover: style._kind == .compact && !platform.isIOS))
        }
        // A grouped form row (or any iOS list row) spans its width: the label leading, the field
        // trailing; so does an iOS compact picker anywhere (its pills at the trailing edge).
        let pills = platform.isIOS && style._kind != .graphical && style._kind != .wheel
        return _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)), content: content,
                               mode: formStyle == .grouped || (platform.isIOS && inListRow) || pills ? .groupedFull : .centered)
    }
}

extension DatePicker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, displayedComponents: displayedComponents) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in bounds: ClosedRange<Date>,
                displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in bounds: ClosedRange<Date>,
                                   displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in bounds: PartialRangeFrom<Date>,
                displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in bounds: PartialRangeFrom<Date>,
                                   displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(title) }
    }

    public init(_ titleKey: LocalizedStringKey, selection: Binding<Date>, in bounds: PartialRangeThrough<Date>,
                displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, selection: Binding<Date>, in bounds: PartialRangeThrough<Date>,
                                   displayedComponents: DatePickerComponents = [.hourAndMinute, .date]) {
        self.init(selection: selection, in: bounds, displayedComponents: displayedComponents) { Text(title) }
    }
}

/// The components of a date that a date picker shows.
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    /// Displays hour and minute components based on the locale.
    public static let hourAndMinute = DatePickerComponents(rawValue: 1 << 0)
    /// Displays day, month, and year based on the locale.
    public static let date = DatePickerComponents(rawValue: 1 << 1)
}

/// The selection with its range, type-erased (a class so field reflection ignores it): reads,
/// and writes clamped into the range.
@MainActor
package final class _DateBinding {
    package let get: () -> Date
    private let write: (Date) -> Void
    package let minimum: Date?
    package let maximum: Date?

    package init(_ binding: Binding<Date>, minimum: Date?, maximum: Date?) {
        get = { binding.wrappedValue }
        write = { binding.wrappedValue = $0 }
        self.minimum = minimum
        self.maximum = maximum
    }

    package func set(_ date: Date) {
        var date = date
        if let minimum, date < minimum { date = minimum }
        if let maximum, date > maximum { date = maximum }
        write(date)
    }
}

// MARK: - Styles

public enum _DatePickerStyleKind: Sendable { case automatic, compact, field, stepperField, graphical, wheel }

/// A specification for the appearance and interaction of a date picker.
@MainActor @preconcurrency
public protocol DatePickerStyle {
    var _kind: _DatePickerStyleKind { get }
}

/// The default style for date pickers (the textual field with a stepper on macOS).
public struct DefaultDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .automatic }
}

/// A date picker style that displays the components in a compact, textual format.
public struct CompactDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .compact }
}

/// A date picker style that displays the components in an editable field.
public struct FieldDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .field }
}

/// A date picker style that displays the components in an editable field, with adjoining
/// stepper that can increment and decrement the selected component.
public struct StepperFieldDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .stepperField }
}

/// A date picker style that displays an interactive calendar or clock.
public struct GraphicalDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .graphical }
}

/// iOS: the spinning columns (`WheelDateNode`); the field with a stepper on macOS.
public struct WheelDatePickerStyle: DatePickerStyle {
    public init() {}
    public var _kind: _DatePickerStyleKind { .wheel }
}

extension DatePickerStyle where Self == DefaultDatePickerStyle {
    public static var automatic: DefaultDatePickerStyle { DefaultDatePickerStyle() }
}
extension DatePickerStyle where Self == CompactDatePickerStyle {
    public static var compact: CompactDatePickerStyle { CompactDatePickerStyle() }
}
extension DatePickerStyle where Self == FieldDatePickerStyle {
    public static var field: FieldDatePickerStyle { FieldDatePickerStyle() }
}
extension DatePickerStyle where Self == StepperFieldDatePickerStyle {
    public static var stepperField: StepperFieldDatePickerStyle { StepperFieldDatePickerStyle() }
}
extension DatePickerStyle where Self == GraphicalDatePickerStyle {
    public static var graphical: GraphicalDatePickerStyle { GraphicalDatePickerStyle() }
}
extension DatePickerStyle where Self == WheelDatePickerStyle {
    public static var wheel: WheelDatePickerStyle { WheelDatePickerStyle() }
}

package struct DatePickerStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any DatePickerStyle = MainActor.assumeIsolated { DefaultDatePickerStyle() }
}

package struct TimeZoneKey: EnvironmentKey {
    package static let defaultValue = TimeZone.current
}

package struct CalendarKey: EnvironmentKey {
    package static let defaultValue = Calendar.current
}

package struct LocaleKey: EnvironmentKey {
    package static let defaultValue = Locale.current
}

extension EnvironmentValues {
    package var datePickerStyle: any DatePickerStyle {
        get { self[DatePickerStyleKey.self] }
        set { self[DatePickerStyleKey.self] = newValue }
    }

    /// The current time zone that views should use when handling dates.
    public var timeZone: TimeZone {
        get { self[TimeZoneKey.self] }
        set { self[TimeZoneKey.self] = newValue }
    }

    /// The current calendar that views should use when handling dates.
    public var calendar: Calendar {
        get { self[CalendarKey.self] }
        set { self[CalendarKey.self] = newValue }
    }

    /// The current locale that views should use (dates and numbers format in English either way).
    public var locale: Locale {
        get { self[LocaleKey.self] }
        set { self[LocaleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for date pickers within this view.
    nonisolated public func datePickerStyle<S: DatePickerStyle>(_ style: S) -> some View {
        environment(\.datePickerStyle, style)
    }
}

// MARK: - Primitives

/// The textual field: the components in a bezel, with a mini stepper unless `stepper` is false
/// (`DateFieldNode`).
public struct _DateFieldHost: View {
    package let date: Date
    package let binding: _DateBinding
    package let components: DatePickerComponents
    package let stepper: Bool
    /// The compact style: a press opens the graphical picker in a popover instead of selecting a component.
    package let opensPopover: Bool

    package init(date: Date, binding: _DateBinding, components: DatePickerComponents, stepper: Bool, opensPopover: Bool = false) {
        self.date = date
        self.binding = binding
        self.components = components
        self.stepper = stepper
        self.opensPopover = opensPopover
    }

    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_DateFieldHost>) -> TypedNode<_DateFieldHost> {
        DateFieldNode(context)
    }
}

/// The graphical style: the month calendar for the date, the clock for the time (both side by
/// side when both components are shown).
package struct _GraphicalDatePicker {
    package let date: Date
    package let binding: _DateBinding
    package let components: DatePickerComponents
}

extension _GraphicalDatePicker: View {
    package var body: some View {
        HStack(spacing: PlatformMetrics.graphicalDateTimeSpacing) {
            if components.contains(.date) { _CalendarHost(date: date, binding: binding) }
            if components.contains(.hourAndMinute) { _ClockHost(date: date, binding: binding) }
        }
    }
}

/// The month calendar (`CalendarNode`).
public struct _CalendarHost: View {
    package let date: Date
    package let binding: _DateBinding
    package init(date: Date, binding: _DateBinding) {
        self.date = date
        self.binding = binding
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_CalendarHost>) -> TypedNode<_CalendarHost> {
        CalendarNode(context)
    }
}

/// iOS's wheel picker (`WheelDateNode`): the month, day and year columns, or the hour, minute
/// and period columns.
public struct _WheelDateHost: View {
    package let date: Date
    package let binding: _DateBinding
    package let components: DatePickerComponents
    /// In the compact picker's panel: the panel's size (the wheel centred in it, its band inset
    /// from the panel's sides); nil for a wheel in the app's own layout.
    package let panelSize: CGSize?
    /// iOS's calendar header opens a month and a year column instead (new-website#674): the
    /// wheel as wide as the calendar, its band `bandInset` in from the sides.
    package let monthAndYear: Bool
    package let bandInset: CGFloat?
    package init(date: Date, binding: _DateBinding, components: DatePickerComponents, panelSize: CGSize? = nil,
                 monthAndYear: Bool = false, bandInset: CGFloat? = nil) {
        self.date = date
        self.binding = binding
        self.components = components
        self.panelSize = panelSize
        self.monthAndYear = monthAndYear
        self.bandInset = bandInset
    }

    /// The same wheel showing another date.
    package func showing(_ date: Date) -> _WheelDateHost {
        _WheelDateHost(date: date, binding: binding, components: components, panelSize: panelSize, monthAndYear: monthAndYear, bandInset: bandInset)
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_WheelDateHost>) -> TypedNode<_WheelDateHost> {
        WheelDateNode(context)
    }
}

/// The analogue clock (`ClockNode`).
public struct _ClockHost: View {
    package let date: Date
    package let binding: _DateBinding
    package init(date: Date, binding: _DateBinding) {
        self.date = date
        self.binding = binding
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ClockHost>) -> TypedNode<_ClockHost> {
        ClockNode(context)
    }
}
