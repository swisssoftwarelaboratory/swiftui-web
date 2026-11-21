// Phase 8 step 6, sw-datepicker: typing into the field, the compact popover, days outside the
// range, dragging the clock's hands, the iOS wheel, locales and both graphical components
// (Docs/elements/DatePicker.md).
import Foundation
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class DateModel { var date = DatePickerEditingTests.fixed }

@Suite @MainActor struct DatePickerEditingTests {
    nonisolated static let utc = TimeZone(identifier: "UTC")!
    /// 15 March 2025, 15:09 UTC.
    nonisolated static let fixed = Date(timeIntervalSinceReferenceDate: 763744140)
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let wheel23 = ResolvedFont(family: "system", size: 23, weight: .regular, italic: false, textStyle: nil, profile: "iOS")

    private func runtime<V: View>(_ view: V, iOS: Bool = false) -> Runtime {
        var environment = EnvironmentValues()
        if iOS { environment.platformProfile = .iOS }
        let runtime = Runtime(environment: environment)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let words = ["3", "15", "2025", "/", ":", ", ", " ", "PM", "AM", "09", "03", "15", "."] + (0...59).map({ "\($0)" }) + (0...9).map({ "0\($0)" })
        for word in words {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: 8, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        for word in ["March", "February", "April", "15", "14", "16", "2025", "11", "09", "AM", "PM"] {
            entries[RecordedTextEngine.key(font: Self.wheel23, width: nil, string: word)] = .init(width: 40, height: 28, firstBaseline: 22, lastBaseline: 22)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view.environment(\.timeZone, Self.utc).environment(\.locale, Locale(identifier: "en_US")))
        runtime.layout(in: CGSize(width: 400, height: 300))
        return runtime
    }

    private func parts(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    private func type(_ runtime: Runtime, _ text: String) {
        for character in text { _ = runtime.keyDown(KeyEvent(key: KeyEquivalent(character), characters: String(character))) }
    }

    @Test func typingFillsTheSelectedComponents() {
        let model = DateModel()
        let runtime = runtime(DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 })).labelsHidden()._probe("field"))
        let field = runtime.root.descendants(where: { $0 is DateFieldNode }).first as! DateFieldNode
        let frame = runtime.probeFrames["field"]!
        // Select the month, type a date: "4" fills the month and moves on (no month starts with 4x),
        // "2", "8" the day, then four digits the year.
        runtime.pointerDown(at: CGPoint(x: frame.minX + 8, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.minX + 8, y: frame.midY))
        #expect(field.selectedComponent == .month)
        type(runtime, "4")
        #expect(parts(model.date).month == 4 && field.selectedComponent == .day)
        type(runtime, "28")
        #expect(parts(model.date).day == 28 && field.selectedComponent == .year)
        type(runtime, "2031")
        #expect(parts(model.date).year == 2031 && field.selectedComponent == .hour)
        // "1" then "1" make 11; "p" turns the afternoon on; Delete takes the last digit back.
        type(runtime, "11")
        #expect(parts(model.date).hour == 23 && field.selectedComponent == .minute)
        type(runtime, "5")
        #expect(parts(model.date).minute == 5)
        _ = runtime.keyDown(KeyEvent(key: .delete))
        #expect(field.typed.isEmpty)
        _ = runtime.keyDown(KeyEvent(key: .leftArrow))
        type(runtime, "a")
        #expect(parts(model.date).hour == 11)
    }

    @Test func theCompactFieldOpensAPopoverCalendar() {
        let model = DateModel()
        let runtime = runtime(DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date)
            .datePickerStyle(.compact).labelsHidden()._probe("field"))
        let frame = runtime.probeFrames["field"]!
        runtime.pointerDown(at: CGPoint(x: frame.minX + 8, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.minX + 8, y: frame.midY))
        runtime.layout(in: CGSize(width: 400, height: 300))
        #expect(runtime.presentations.count == 1)
        guard case .popover = runtime.presentations[0].kind else { Issue.record("not a popover"); return }
        let calendar = runtime.presentations[0].content.descendants(where: { $0 is CalendarNode }).first as! CalendarNode
        // Picking a day in the popover changes the selection; the field follows.
        let cell = calendar.cell(row: 2, column: 3)
        let origin = calendar.frameInRoot.origin
        runtime.pointerDown(at: CGPoint(x: origin.x + cell.midX, y: origin.y + cell.midY))
        runtime.pointerUp(at: CGPoint(x: origin.x + cell.midX, y: origin.y + cell.midY))
        #expect(parts(model.date).day == 12)
    }

    @Test func daysOutsideTheRangeAreDimmedAndInert() {
        let model = DateModel()
        let range = Self.fixed.addingTimeInterval(-86400 * 5)...Self.fixed.addingTimeInterval(86400 * 10)
        let runtime = runtime(DatePicker("Range", selection: Binding(get: { model.date }, set: { model.date = $0 }), in: range, displayedComponents: .date)
            .datePickerStyle(.graphical).labelsHidden())
        let calendar = runtime.root.descendants(where: { $0 is CalendarNode }).first as! CalendarNode
        // March 2025: row 1 holds the 2nd to the 8th (outside), row 2 the 9th to the 15th.
        #expect(!calendar.isInRange(row: 1, day: (day: 5, inMonth: true)))
        #expect(calendar.isInRange(row: 2, day: (day: 10, inMonth: true)) && calendar.isInRange(row: 3, day: (day: 25, inMonth: true)))
        #expect(!calendar.isInRange(row: 3, day: (day: 26, inMonth: true)))
        let cell = calendar.cell(row: 1, column: 4)   // the 6th
        let origin = calendar.frameInRoot.origin
        runtime.pointerDown(at: CGPoint(x: origin.x + cell.midX, y: origin.y + cell.midY))
        runtime.pointerUp(at: CGPoint(x: origin.x + cell.midX, y: origin.y + cell.midY))
        #expect(parts(model.date).day == 15)
        // The dimmed days paint at the out-of-range alpha.
        let dimmed = runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("drawText(\"5\"") }
        #expect(dimmed.first?.hasSuffix("@\(66.0 / 255))") == true)
    }

    @Test func draggingTheClockHandsSetsTheTime() {
        let model = DateModel()
        let runtime = runtime(DatePicker("Clock", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .hourAndMinute)
            .datePickerStyle(.graphical).labelsHidden())
        let clock = runtime.root.descendants(where: { $0 is ClockNode }).first as! ClockNode
        let origin = clock.frameInRoot.origin
        let center = CGPoint(x: origin.x + PlatformMetrics.clockCenter.x, y: origin.y + PlatformMetrics.clockCenter.y)
        // Far from the centre: the minute hand; dragging to the right points it at 15.
        runtime.pointerDown(at: CGPoint(x: center.x + 55, y: center.y))
        #expect(clock.draggedHand == .minute)
        runtime.pointerMoved(to: CGPoint(x: center.x, y: center.y + 55))
        runtime.pointerUp(at: CGPoint(x: center.x, y: center.y + 55))
        #expect(parts(model.date).minute == 30 && parts(model.date).hour == 15)
        // Near the centre: the hour hand; straight up is 12, the afternoon kept.
        runtime.pointerDown(at: CGPoint(x: center.x, y: center.y - 20))
        #expect(clock.draggedHand == .hour)
        runtime.pointerUp(at: CGPoint(x: center.x, y: center.y - 20))
        #expect(parts(model.date).hour == 12)
    }

    @Test func theWheelTurnsByDragAndPress() {
        let model = DateModel()
        let runtime = runtime(VStack {
            DatePicker("Date", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()._probe("date")
            DatePicker("Time", selection: Binding(get: { model.date }, set: { model.date = $0 }), displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()._probe("time")
        }, iOS: true)
        #expect(runtime.probeFrames["date"]?.size == CGSize(width: 320, height: 216))
        let wheel = runtime.root.descendants(where: { $0 is WheelDateNode }).first as! WheelDateNode
        // Months go round, as on iOS.
        #expect(wheel.text(for: .month, offset: 0) == "March" && wheel.text(for: .month, offset: -1) == "February" && wheel.text(for: .month, offset: 10) == "January")
        // A column lands on its row, and the binding changes, once its spring has settled.
        var clock = 0.0
        runtime.wheelClock = { clock }
        func settle() {
            for _ in 0..<90 {
                _ = runtime.advanceAnimations(elapsed: 1.0 / 60)
                clock += 1.0 / 60
            }
            runtime.layout(in: CGSize(width: 400, height: 300))
        }
        let frame = runtime.probeFrames["date"]!
        // A press one row below the band in the day column turns the 16th into it.
        let day = CGPoint(x: frame.minX + 185, y: frame.midY + 31)
        runtime.pointerDown(at: day)
        runtime.pointerUp(at: day)
        #expect(parts(model.date).day == 15)
        settle()
        #expect(parts(model.date).day == 16)
        // A slow drag of two rows up in the year column adds two years.
        let year = CGPoint(x: frame.minX + 250, y: frame.midY)
        runtime.pointerDown(at: year)
        for k in 1...20 {
            clock += 0.05
            runtime.pointerMoved(to: CGPoint(x: year.x, y: year.y - CGFloat(k) * 3.1))
        }
        clock += 0.3
        runtime.pointerUp(at: CGPoint(x: year.x, y: year.y - 62))
        settle()
        #expect(parts(model.date).year == 2027)
        // The time wheel (en_US, 12-hour): the period column flips the half day (AM sits a row
        // above the selected PM).
        let time = runtime.probeFrames["time"]!
        let am = CGPoint(x: time.minX + 216, y: time.midY - 31)
        runtime.pointerDown(at: am)
        runtime.pointerUp(at: am)
        settle()
        #expect(parts(model.date).hour == 3)
    }

    @Test func theWheelFollowsTheLocale() {
        let gb = runtime(DatePicker("", selection: .constant(Self.fixed), displayedComponents: .hourAndMinute).datePickerStyle(.wheel).labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!), iOS: true)
        let gbWheel = gb.root.descendants(where: { $0 is WheelDateNode }).first as! WheelDateNode
        // 24-hour: two columns, the hours zero-padded and going round the whole day.
        #expect(gbWheel.columns.map(\.kind) == [.hour, .minute])
        #expect(gbWheel.text(for: .hour, offset: 0) == "15" && gbWheel.text(for: .hour, offset: 9) == "00")
        let de = runtime(DatePicker("", selection: .constant(Self.fixed), displayedComponents: .date).datePickerStyle(.wheel).labelsHidden()
            .environment(\.locale, Locale(identifier: "de_CH")).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!), iOS: true)
        let deWheel = de.root.descendants(where: { $0 is WheelDateNode }).first as! WheelDateNode
        #expect(deWheel.columns.map(\.kind) == [.day, .month, .year])
        #expect(deWheel.text(for: .day, offset: 0) == "15." && deWheel.text(for: .month, offset: 7) == "Oktober")
    }

    @Test func localesOrderTheFieldAndBothGraphicalComponentsShareARow() {
        let gb = runtime(DatePicker("GB", selection: .constant(Self.fixed)).labelsHidden().environment(\.locale, Locale(identifier: "en_GB")))
        let gbField = gb.root.descendants(where: { $0 is DateFieldNode }).first as! DateFieldNode
        #expect(gbField.text == "15/03/2025, 15:09")
        let de = runtime(DatePicker("DE", selection: .constant(Self.fixed)).labelsHidden().environment(\.locale, Locale(identifier: "de_DE")))
        #expect((de.root.descendants(where: { $0 is DateFieldNode }).first as! DateFieldNode).text == "15.3.2025, 15:09")
        let ja = runtime(DatePicker("JA", selection: .constant(Self.fixed)).labelsHidden().environment(\.locale, Locale(identifier: "ja_JP")))
        #expect((ja.root.descendants(where: { $0 is DateFieldNode }).first as! DateFieldNode).text == "2025/3/15 15:09")
        let both = runtime(DatePicker("Both", selection: .constant(Self.fixed)).datePickerStyle(.graphical).labelsHidden()._probe("both"))
        #expect(both.probeFrames["both"]?.width == 138.5 + 18 + 119)
    }
}
#endif
