// iOS presentation fixtures (`ios/sheet/`, `ios/alert/`, `ios/dialog/`, `ios/tabs/`,
// `ios/datepicker/`, `ios/list/selection`, `ios/representable/sheet`): the sheet, alert and confirmation dialog captured
// as the whole iPhone window after a step presents them, the tab bar, the compact date picker's
// pills and a list's selection, rendered on the iPhone SE simulator (decision 0015) and
// reproduced by the runtime's iOS profile (Docs/elements/iOS.md). The presenting screens are
// white (`Color.white` behind the button): the glass materials blur what is behind them, and
// the goldens must show them over an app's white, not the harness window's clear.
import SwiftUI
import FixtureKit

@Observable
public final class IOSDatePanelModel {
    // 13 Nov 2026, 06:30 UTC.
    public var a = Date(timeIntervalSince1970: 1_794_547_800)
    public var b = Date(timeIntervalSince1970: 1_794_547_800)
    public var c = Date(timeIntervalSince1970: 1_794_547_800)
    public init() {}
}

@Observable
public final class IOSPresentationModel {
    public var sheet = false
    public var alert = false
    public var dialog = false
    public var tab = 0
    public var selection: Int?
    public var multiple: Set<Int> = []
    public init() {}
}

private struct SheetBody: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Text("Sheet title").font(.headline)
            Text("Some content under the title.")
            Button("Done") { dismiss() }
        }
        
    }
}

public enum IOSPresentationFixtures {
    static let phone = CGSize(width: 375, height: 667)
    static let utc = TimeZone(secondsFromGMT: 0)!
    /// Four hours before the shared fixture date: 11:09 AM, a two-digit hour, because iOS 26
    /// sizes a compact picker's time pill for the wider of its own time and the current time
    /// (`Docs/elements/UIKit/DatePicker.md`), so a one-digit hour would vary by the time of day.
    static let fixed = DatePickerFixtures.fixed.addingTimeInterval(-4 * 3600)

    /// The default sheet (large detent): the dimmed window, the card's top corners and inset.
    public static let sheet = Fixture(
        "ios/sheet/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { SheetBody() }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// A `NavigationStack` inside a sheet, presented from one (sw-ios-sheet-nav, Scrumdinger's
    /// add screen): the sheet has a bar of its own, inline and untitled (`navigationTitle("")`),
    /// carrying its cancellation and confirmation items; the presenting stack's large title
    /// and items stay as they were under the dimming.
    public static let sheetNav = Fixture(
        "ios/sheet/nav", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        NavigationStack {
            List { Text("Daily Scrum") }
                .navigationTitle("Scrums")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Show sheet") { model.sheet = true }.probe("button") } }
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            NavigationStack {
                Form { TextField("Title", text: .constant("")).probe("field") }
                    .navigationTitle("")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Dismiss") { model.sheet = false }.probe("dismiss") }
                        ToolbarItem(placement: .confirmationAction) { Button("Add") { model.sheet = false }.probe("add") }
                    }
            }
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The same sheet with a title: the sheet's inline bar shows it, the presenting bar's own
    /// title does not change.
    public static let sheetNavTitled = Fixture(
        "ios/sheet/nav-titled", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        NavigationStack {
            List { Text("Daily Scrum") }
                .navigationTitle("Scrums")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Show sheet") { model.sheet = true }.probe("button") } }
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            NavigationStack {
                Form { TextField("Title", text: .constant("")).probe("field") }
                    .navigationTitle("New Scrum")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Dismiss") { model.sheet = false }.probe("dismiss") }
                        ToolbarItem(placement: .confirmationAction) { Button("Add") { model.sheet = false }.probe("add") }
                    }
            }
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// A medium detent and a hidden drag indicator's opposite: the visible grabber.
    public static let sheetMedium = Fixture(
        "ios/sheet/medium", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            SheetBody().presentationDetents([.medium]).presentationDragIndicator(.visible)
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    #if canImport(UIKit)
    /// A representable inside a sheet (ix-containers left it here): the UIKit label sits in
    /// the sheet's content like any leaf.
    public static let sheetRepresentable = Fixture(
        "ios/representable/sheet", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show sheet") { model.sheet = true }.probe("button")
        }
        .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            VStack(spacing: 12) {
                Text("Above")
                LabelBox(text: "UILabel in a sheet", hugging: 1000, resistance: 1000)
                Text("Below")
            }
            
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()
    #endif

    /// The alert: title, message, a destructive and a cancel button.
    public static let alert = Fixture(
        "ios/alert/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.alert = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Delete…") { model.alert = true }.probe("button")
        }
        .alert("Delete the item?", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) {
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// An alert with three buttons and a long title (sw-ios-presentation-rest): iOS stacks the
    /// buttons one per row and wraps the title.
    public static let alertStacked = Fixture(
        "ios/alert/stacked", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.alert = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Resolve…") { model.alert = true }.probe("button")
        }
        .alert("The document has unsaved changes that will be lost", isPresented: Binding(get: { model.alert }, set: { model.alert = $0 })) {
            Button("Save") {}
            Button("Discard", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to do before closing.")
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// `fullScreenCover`: the cover fills the window, no card inset or dimming.
    public static let fullScreenCover = Fixture(
        "ios/sheet/fullscreen", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.sheet = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Show cover") { model.sheet = true }.probe("button")
        }
        .fixtureFullScreenCover(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) {
            ZStack {
                Color.yellow.ignoresSafeArea()
                SheetBody()
            }
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// Multiple selection in edit mode: the selection circles, two rows checked by a step.
    public static let multipleSelection = Fixture(
        "ios/list/multiselect", size: CGSize(width: 375, height: 360),
        model: { IOSPresentationModel() },
        steps: [FixtureStep("select") { $0.multiple = [1, 3] }]
    ) { model in
        List(selection: Binding(get: { model.multiple }, set: { model.multiple = $0 })) {
            Text("First").tag(1).probe("first")
            Text("Second").tag(2).probe("second")
            Text("Third").tag(3).probe("third")
        }
        .fixtureEditModeActive()
        .probe("list")
    }.platform(.iOS)

    /// The confirmation dialog: a titled action sheet with three actions and a cancel button.
    public static let dialog = Fixture(
        "ios/dialog/basic", size: phone,
        model: { IOSPresentationModel() },
        steps: [FixtureStep("present") { $0.dialog = true }]
    ) { model in
        ZStack {
            Color.white.ignoresSafeArea()
            Button("Options…") { model.dialog = true }.probe("button")
        }
        .confirmationDialog("Item options", isPresented: Binding(get: { model.dialog }, set: { model.dialog = $0 }), titleVisibility: .visible) {
            Button("Copy") {}
            Button("Duplicate") {}
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose what to do with the item.")
        }
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    /// The tab bar: three tabs with symbols, the first selected. No step selects another: a
    /// programmatic selection change leaves iOS 26's pill raised as glass for seconds, so
    /// `ios/tabs/second` starts on the second tab instead.
    public static let tabs = Fixture("ios/tabs/basic", size: phone) {
        TabView(selection: .constant(0)) {
            Text("Home content").probe("home").tabItem { Label("Home", systemImage: "house") }.tag(0)
            Text("Search content").tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
            Text("Settings content").tabItem { Label("Settings", systemImage: "gear") }.tag(2)
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    public static let tabsSecond = Fixture("ios/tabs/second", size: phone) {
        TabView(selection: .constant(1)) {
            Text("Home content").tabItem { Label("Home", systemImage: "house") }.tag(0)
            Text("Search content").probe("search").tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
            Text("Settings content").tabItem { Label("Settings", systemImage: "gear") }.tag(2)
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// Five tabs with badges: a count on the second, a text on the fourth (the bar's slots
    /// narrow; badges sit on the symbols).
    public static let tabsBadges = Fixture("ios/tabs/badges", size: phone) {
        TabView(selection: .constant(0)) {
            Tab("Home", systemImage: "house", value: 0) { Text("Home content").probe("home") }
            Tab("Alerts", systemImage: "bell", value: 1) { Text("Alerts content") }.badge(3)
            Tab("Search", systemImage: "magnifyingglass", value: 2) { Text("Search content") }
            Tab("Mail", systemImage: "envelope", value: 3) { Text("Mail content") }.badge("New")
            Tab("More", systemImage: "ellipsis", value: 4) { Text("More content") }
        }
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// The page style on iPhone: three pages, the page indicator at the bottom.
    public static let tabsPage = Fixture("ios/tabs/page", size: phone) {
        TabView(selection: .constant(1)) {
            Color.red.frame(width: 120, height: 80).tag(0)
            Color.blue.frame(width: 120, height: 80).probe("page1").tag(1)
            Color.green.frame(width: 120, height: 80).tag(2)
        }
        .fixturePageTabStyle()
        .probe("tabs")
    }.platform(.iOS).capturesWindow()

    /// The compact date picker in a form: date, date and time, time; the tinted pills.
    public static let datePicker = Fixture("ios/datepicker/compact", size: CGSize(width: 375, height: 360)) {
        Form {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).probe("date")
            DatePicker("When", selection: .constant(fixed)).probe("dateTime")
            DatePicker("Time", selection: .constant(fixed), displayedComponents: .hourAndMinute).probe("time")
            DatePicker("Off", selection: .constant(fixed), displayedComponents: .date).disabled(true).probe("disabled")
        }
        .environment(\.timeZone, utc)
        .probe("form")
    }.platform(.iOS)

    /// iOS 27's own calendar (`.graphical`, new-website#674): the month's weeks from the
    /// locale's first day, the selected day on a filled circle; March 2025 holds no today.
    public static let dateGraphical = Fixture("ios/datepicker/graphical", size: CGSize(width: 375, height: 380)) {
        VStack {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).datePickerStyle(.graphical).labelsHidden().probe("calendar")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .environment(\.timeZone, utc)
        .probe("stack")
    }.platform(.iOS)

    /// The compact pills as the picker probe app shows them
    /// (swipe-harness/picker-probe-674): pressing the date pill opens iOS 27's calendar panel.
    /// No golden: the panel opens on a press, compared with the simulator's screenshots.
    public static let datePanels = Fixture("ios/datepicker/panels", size: CGSize(width: 375, height: 600), model: { IOSDatePanelModel() }, steps: []) { model in
        VStack(alignment: .leading, spacing: 24) {
            DatePicker("Time", selection: Binding(get: { model.a }, set: { model.a = $0 }), displayedComponents: .hourAndMinute).probe("time")
            DatePicker("Date", selection: Binding(get: { model.b }, set: { model.b = $0 }), displayedComponents: .date).probe("date")
            DatePicker("Both", selection: Binding(get: { model.c }, set: { model.c = $0 })).probe("both")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 59)
        .environment(\.locale, Locale(identifier: "en_GB"))
        .environment(\.timeZone, utc)
        .probe("stack")
    }.platform(.iOS)

    /// A list with a selection binding: the selected row's look after a step selects it.
    /// The wheel style (iOS only): the date's three columns and the time's, captured as the window.
    public static let dateWheel = Fixture("ios/datepicker/wheel", size: CGSize(width: 375, height: 520)) {
        VStack(spacing: 12) {
            DatePicker("Date", selection: .constant(fixed), displayedComponents: .date).fixtureWheelDateStyle().labelsHidden().probe("dateWheel")
            DatePicker("Time", selection: .constant(fixed), displayedComponents: .hourAndMinute).fixtureWheelDateStyle().labelsHidden().probe("timeWheel")
        }
        .environment(\.timeZone, utc)
        .probe("stack")
    }.platform(.iOS).capturesWindow()

    public static let listSelection = Fixture(
        "ios/list/selection", size: CGSize(width: 375, height: 360),
        model: { IOSPresentationModel() },
        steps: [FixtureStep("select") { $0.selection = 2 }]
    ) { model in
        List(selection: Binding(get: { model.selection }, set: { model.selection = $0 })) {
            Text("First").tag(1).probe("first")
            Text("Second").tag(2).probe("second")
            Text("Third").tag(3).probe("third")
        }
        .probe("list")
    }.platform(.iOS)

    public static var all: [Fixture] {
        var fixtures = [sheet, sheetNav, sheetNavTitled, sheetMedium, alert, alertStacked, fullScreenCover, dialog, tabs, tabsSecond, tabsBadges, tabsPage, datePicker, dateGraphical, datePanels, listSelection, multipleSelection]
        #if canImport(UIKit)
        fixtures.append(sheetRepresentable)
        #endif
        fixtures.append(dateWheel)
        return fixtures
    }
}
