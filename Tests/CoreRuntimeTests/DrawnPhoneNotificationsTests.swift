// What an app's notifications and Live Activity do in the drawn iPhone (new-website#643, look and
// behaviour decided in #627): UserNotifications delivers as iOS does (the delegate asked only in
// the foreground, a banner it picks, the lock screen's list in the background), a tap on a banner
// or a notification opens the app through the delegate's `didReceive` and takes it off the list,
// the lock screen stacks several until tapped, `removeDeliveredNotifications` takes them away, and
// a Live Activity started through ActivityKit is drawn by the widget extension's own view, its
// intent button working, updated and ended by the app.
import ActivityKit
import AppIntents
import SwiftUI
import SwiftUIWebCore
import Testing
import UserNotifications
import WidgetKit

#if !os(WASI)
extension NotificationCentreSuites {
@Suite(.serialized) @MainActor struct DrawnPhoneNotificationsTests {
    private let size = CGSize(width: 393, height: 852)
    private var clock = 10.0

    init() {}

    private func phone() -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.drawsPhone = true
        runtime.mount(Color.gray.ignoresSafeArea())
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        // The browser host's wiring (NotificationsHost), as the canvas installs it.
        _UserNotificationsHost.phone = { _DrawnPhoneSystem.isPresent }
        _UserNotificationsHost.appIsInForeground = { _DrawnPhoneSystem.appIsInForeground }
        _UserNotificationsHost.present = { note, onOpen in
            _DrawnPhoneSystem.deliver(identifier: note.identifier, title: note.title, subtitle: note.subtitle, body: note.body,
                                      date: note.date, banner: note.banner, list: note.list, onOpen: onOpen)
        }
        _UserNotificationsHost.withdraw = { _DrawnPhoneSystem.withdraw($0) }
        _UserNotificationsHost.permission = { .authorized }
        return runtime
    }

    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        _ = r.render(scale: 2)
    }

    private func settle(_ r: Runtime, seconds: Double = 1.5) {
        for _ in 0..<Int(seconds * 60) { frame(r) }
    }

    private mutating func tap(_ r: Runtime, _ p: CGPoint) {
        r.pointerDown(at: p, type: .mouse, time: clock)
        clock += 0.08
        r.pointerUp(at: p, time: clock)
        clock += 0.01
        frame(r)
    }

    private func lock(_ r: Runtime) {
        r.phoneSideButtonPressed()
        settle(r)
        r.phoneSideButtonPressed()
        settle(r)
    }

    private func centre(of item: DrawnPhone.CoverItem, _ r: Runtime) -> CGPoint {
        let phone = r.drawnPhone!
        let rect = phone.columnRect(item)!
        return CGPoint(x: rect.midX, y: rect.midY + phone.coverTop)
    }

    /// Main-actor work a delivery starts: a few turns of the run loop.
    private func turns(_ r: Runtime) async {
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
        frame(r)
    }

    final class Handler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        var present: UNNotificationPresentationOptions = [.banner, .list]
        var asked: [String] = []
        var opened: [String] = []
        // The async forms, as Paulo's app writes them.
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            asked.append(notification.request.identifier)
            return present
        }
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            opened.append(response.notification.request.identifier)
        }
    }

    private func request(_ id: String, title: String = "Lunch") -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "450 g, ready to log."
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }

    @Test mutating func inTheForegroundTheDelegatePicksABannerAndATapOpensIt() async throws {
        let r = phone()
        let center = UNUserNotificationCenter.current()
        let handler = Handler()
        center.delegate = handler
        defer { center.delegate = nil; center.removeAllDeliveredNotifications() }
        try await center.add(request("lunch"))
        await turns(r)
        settle(r, seconds: 1)
        #expect(handler.asked == ["lunch"])
        #expect(r.drawnPhone!.bannerShown)
        #expect(r.drawnPhone!.notes.map(\.identifier) == ["lunch"])
        // A tap on the banner: the app hears it and it leaves the list.
        tap(r, CGPoint(x: 196, y: 80))
        await turns(r)
        #expect(handler.opened == ["lunch"])
        #expect(r.drawnPhone!.notes.isEmpty)
        #expect(!r.drawnPhone!.bannerShown)
    }

    @Test func inTheForegroundNothingShowsWhenTheDelegatePicksNothing() async throws {
        let r = phone()
        let center = UNUserNotificationCenter.current()
        let handler = Handler()
        handler.present = []
        center.delegate = handler
        defer { center.delegate = nil }
        try await center.add(request("rest-end"))
        await turns(r)
        #expect(handler.asked == ["rest-end"])
        #expect(!r.drawnPhone!.bannerShown)
        #expect(r.drawnPhone!.notes.isEmpty)
    }

    @Test mutating func lockedTheyStackAndATapOpensTheStackThenTheApp() async throws {
        let r = phone()
        let center = UNUserNotificationCenter.current()
        let handler = Handler()
        center.delegate = handler
        defer { center.delegate = nil; center.removeAllDeliveredNotifications() }
        lock(r)
        #expect(r.drawnPhone!.mode == .locked)
        for id in ["a", "b", "c"] {
            try await center.add(request(id))
            await turns(r)
        }
        // Not in the foreground: the delegate is never asked, all three are on the list.
        #expect(handler.asked.isEmpty)
        #expect(r.drawnPhone!.notes.map(\.identifier) == ["c", "b", "a"])
        #expect(r.drawnPhone!.columnLayout().entries.map(\.item) == [.stack])
        tap(r, centre(of: .stack, r))
        #expect(r.drawnPhone!.stackOpen)
        #expect(r.drawnPhone!.columnLayout().entries.map(\.item) == [.note(0), .note(1), .note(2)])
        tap(r, centre(of: .note(1), r))
        await turns(r)
        settle(r)
        #expect(handler.opened == ["b"])
        #expect(r.drawnPhone!.mode == .app)
        #expect(r.drawnPhone!.notes.map(\.identifier) == ["c", "a"])
        // The app takes the rest back.
        center.removeDeliveredNotifications(withIdentifiers: ["c"])
        await turns(r)
        #expect(r.drawnPhone!.notes.map(\.identifier) == ["a"])
    }

    @Test func aDarkScreenWakesForANotification() {
        let r = phone()
        r.phoneSideButtonPressed()
        settle(r)
        #expect(r.drawnPhone!.mode == .off)
        _DrawnPhoneSystem.deliver(identifier: "x", title: "Coach", subtitle: "", body: "How did your shoulders take it?", date: Date(),
                                  banner: true, list: true, onOpen: {})
        settle(r)
        #expect(r.drawnPhone!.mode == .locked)
        #expect(r.drawnPhone!.notes.count == 1)
    }

    @Test func calendarTriggersFindTheirNextDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var wanted = DateComponents()
        wanted.hour = 7
        wanted.minute = 0
        let start = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15 08:00 UTC
        let next = UNCalendarNotificationTrigger.next(after: start, matching: wanted, calendar: calendar)!
        let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
        #expect(parts.day == 16 && parts.hour == 7 && parts.minute == 0)
    }

    // MARK: Live Activity

    struct Workout: ActivityAttributes {
        struct ContentState: Codable, Hashable { var left: Int }
        var name: String
    }

    @MainActor final class Taps { static var skips = 0 }

    struct Skip: LiveActivityIntent {
        static let title: LocalizedStringResource = "Skip"
        init() {}
        @MainActor func perform() async throws -> some IntentResult {
            Taps.skips += 1
            return .result()
        }
    }

    struct WorkoutCard: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: Workout.self) { context in
                HStack {
                    Text("\(context.attributes.name): \(context.state.left) left")
                    Spacer()
                    Button(intent: Skip()) { Color.black.frame(width: 84, height: 44) }.buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .activityBackgroundTint(.white)
            } dynamicIsland: { _ in
                DynamicIsland { DynamicIslandExpandedRegion(.leading) { Text("") } } compactLeading: { Text("") } compactTrailing: { Text("") } minimal: { Text("") }
            }
        }
    }

    struct Extension: WidgetBundle {
        var body: some Widget { WorkoutCard() }
    }

    @Test mutating func aLiveActivityIsDrawnByItsOwnViewAndItsButtonWorks() async throws {
        let r = phone()
        #expect(!ActivityAuthorizationInfo().areActivitiesEnabled || _WidgetHost.hasExtension)
        Extension.main()
        #expect(ActivityAuthorizationInfo().areActivitiesEnabled)
        let activity = try Activity.request(attributes: Workout(name: "Upper Body A"), content: ActivityContent(state: .init(left: 3), staleDate: nil))
        await turns(r)
        #expect(Activity<Workout>.activities.count == 1)
        #expect(r.drawnPhone!.activities.count == 1)
        lock(r)
        let card = r.drawnPhone!.columnRect(.activity(0))!
        #expect(card.height >= 100)
        // Skip, on the card's right: the intent runs, the phone stays locked.
        let skips = Taps.skips
        tap(r, CGPoint(x: card.maxX - 42, y: card.midY + r.drawnPhone!.coverTop))
        await turns(r)
        #expect(Taps.skips == skips + 1)
        #expect(r.drawnPhone!.mode == .locked)
        await activity.update(ActivityContent(state: .init(left: 2), staleDate: nil))
        await turns(r)
        #expect(r.drawnPhone!.activities.count == 1)
        await activity.end(nil, dismissalPolicy: .immediate)
        await turns(r)
        #expect(Activity<Workout>.activities.isEmpty)
        #expect(r.drawnPhone!.activities.isEmpty)
    }
}
}
#endif
