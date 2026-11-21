// The drawn iPhone's home screen with the app's own widgets (new-website#638, look in #626): a
// widget extension's `StaticConfiguration` runs live at the top of the home screen in the size the
// widget gallery leads with, the apps move down under it, its timeline's next entry takes over at
// its date, `WidgetCenter.reloadAllTimelines` brings the app's new data, a tap opens the app, and
// an app whose extension offers no home screen widget shows none.
import ActivityKit
import SwiftUI
import SwiftUIWebCore
import Testing
import WidgetKit

#if !os(WASI)
enum HomeWidgetData {
    nonisolated(unsafe) static var count = 3
    nonisolated(unsafe) static var later = false
}

struct HomeCountEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct HomeCountProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeCountEntry { HomeCountEntry(date: .now, text: "placeholder") }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (HomeCountEntry) -> Void) {
        completion(placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<HomeCountEntry>) -> Void) {
        let now = Date()
        var entries = [HomeCountEntry(date: now, text: "Count \(HomeWidgetData.count) \(context.family)")]
        if HomeWidgetData.later { entries.append(HomeCountEntry(date: now.addingTimeInterval(0.2), text: "Later")) }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct HomeCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Count", provider: HomeCountProvider()) { entry in
            Text(entry.text).containerBackground(.white, for: .widget)
        }
        .configurationDisplayName("Count")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HomeWidgetExtension: WidgetBundle {
    var body: some Widget { HomeCountWidget() }
}

struct HomeNoWidgetsExtension: WidgetBundle {
    struct Nothing: ActivityAttributes {
        struct ContentState: Codable, Hashable {}
    }
    struct Card: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: Nothing.self) { _ in Text("") } dynamicIsland: { _ in
                DynamicIsland { DynamicIslandExpandedRegion(.leading) { Text("") } } compactLeading: { Text("") } compactTrailing: { Text("") } minimal: { Text("") }
            }
        }
    }
    var body: some Widget { Card() }
}

extension NotificationCentreSuites {
@Suite(.serialized) @MainActor struct DrawnPhoneHomeTests {
    private let size = CGSize(width: 393, height: 852)
    private var clock = 10.0

    init() {}

    private func phone() -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = MonospaceTextEngine()   // the widget's tree measures with the app's engine
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.drawsPhone = true
        runtime.mount(Color.gray.ignoresSafeArea())
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    @discardableResult
    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) -> DisplayList {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        return r.render(scale: 2)
    }

    private func settle(_ r: Runtime, seconds: Double = 1.5) {
        for _ in 0..<Int(seconds * 60) { frame(r) }
    }

    private func turns(_ r: Runtime) async {
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
        frame(r)
    }

    private func texts(_ list: DisplayList) -> [String] {
        list.commands.compactMap { if case .drawText(let text, _, _, _) = $0 { return text } else { return nil } }
    }

    /// Up from the bottom edge: the app leaves for the home screen.
    private mutating func goHome(_ r: Runtime) {
        r.pointerDown(at: CGPoint(x: 196, y: 845), type: .mouse, time: clock)
        for step in 1...10 {
            clock += 0.016
            r.pointerMoved(to: CGPoint(x: 196, y: 845 - Double(step) * 40), time: clock)
        }
        clock += 0.016
        r.pointerUp(at: CGPoint(x: 196, y: 445), time: clock)
        settle(r)
    }

    private mutating func tap(_ r: Runtime, _ p: CGPoint) {
        r.pointerDown(at: p, type: .mouse, time: clock)
        clock += 0.08
        r.pointerUp(at: p, time: clock)
        clock += 0.01
        frame(r)
    }

    @Test mutating func theAppsWidgetRunsLiveAboveTheApps() async throws {
        HomeWidgetData.count = 3
        HomeWidgetData.later = false
        HomeWidgetExtension.main()
        let r = phone()
        goHome(r)
        await turns(r)
        let phone = r.drawnPhone!
        #expect(phone.mode == .home)
        // Medium, the gallery's first choice, across the width at the top; the apps below it.
        let placed = phone.placedWidgets
        #expect(placed.count == 1)
        #expect(placed.first?.rect == CGRect(x: 27, y: 72, width: 338, height: 158))
        #expect(abs(phone.iconRect.minY - (72 + 2 * 98)) < 0.5)
        #expect(texts(frame(r)).contains("Count 3 systemMedium"))
        // The app writes new data and asks for new timelines.
        HomeWidgetData.count = 4
        WidgetCenter.shared.reloadAllTimelines()
        await turns(r)
        #expect(texts(frame(r)).contains("Count 4 systemMedium"))
        let configured = try await WidgetCenter.shared.currentConfigurations()
        #expect(configured.map(\.kind) == ["Count"])
        // The timeline's next entry takes over at its date.
        HomeWidgetData.later = true
        WidgetCenter.shared.reloadTimelines(ofKind: "Count")
        await turns(r)
        try await Task.sleep(nanoseconds: 300_000_000)
        await turns(r)
        #expect(texts(frame(r)).contains("Later"))
        // A tap on the widget opens the app.
        let rect = placed[0].rect
        tap(r, CGPoint(x: rect.midX, y: rect.midY))
        settle(r)
        #expect(phone.mode == .app)
        #expect(phone.appIsFull)
    }

    @Test mutating func anAppWithoutHomeScreenWidgetsShowsNone() async throws {
        HomeNoWidgetsExtension.main()
        let r = phone()
        goHome(r)
        await turns(r)
        let phone = r.drawnPhone!
        #expect(phone.placedWidgets.isEmpty)
        #expect(phone.iconRect.minY == 72)
        #expect(phone.homeIconCount == 12)
    }
}
}
#endif
