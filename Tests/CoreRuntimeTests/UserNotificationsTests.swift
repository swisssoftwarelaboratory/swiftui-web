// UserNotifications (decision 0021, pf-usernotifications) against a fake host, in the order
// the Countries app's UserPermissionsInteractor and PushNotificationsHandler use it: the
// settings' status, requestAuthorization(options:), a local request delivered through the
// delegate's willPresent, the click back as didReceive with the request's userInfo. Without a
// host: never authorised, nothing shown.
import Testing
import UserNotifications
import WebFoundation

#if !os(WASI)
/// Every suite using the one notification centre or the drawn iPhone, one after another
/// (new-website#643): the centre, its delegate, the host's hooks and the phone the frameworks
/// reach are process-wide.
@Suite(.serialized) enum NotificationCentreSuites {}

extension NotificationCentreSuites {
@Suite(.serialized) struct UserNotificationsTests {
    final class Handler: NSObject, UNUserNotificationCenterDelegate {
        var presented: [String] = []
        var opened: [[AnyHashable: Any]] = []
        var presentWith: UNNotificationPresentationOptions = [.list, .banner, .sound]
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            presented.append(notification.request.identifier)
            completionHandler(presentWith)
        }
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
            opened.append(response.notification.request.content.userInfo)
            completionHandler()
        }
    }

    /// Delivery is a main-actor task after `add` returns: waits, bounded, until `condition`
    /// holds (a yield per turn, up to a second); the assertion after it decides.
    private func settled(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 { if await MainActor.run(body: condition) { return }; await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
    }

    private func withoutHost() {
        _UserNotificationsHost.permission = nil
        _UserNotificationsHost.requestPermission = nil
        _UserNotificationsHost.show = nil
        _UserNotificationsHost.phone = nil
        UNUserNotificationCenter._resetWithoutHost()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().delegate = nil
    }

    @Test func badgeCountAnswersBothForms() async throws {
        let center = UNUserNotificationCenter.current()
        nonisolated(unsafe) var told: [Bool] = []
        center.setBadgeCount(3) { error in told.append(error == nil) }
        center.setBadgeCount(0, withCompletionHandler: nil)
        try await center.setBadgeCount(1)
        #expect(told == [true])
    }

    @Test func withoutAHostNothingIsAuthorisedOrShown() async throws {
        withoutHost()
        let center = UNUserNotificationCenter.current()
        #expect(await center.notificationSettings().authorizationStatus == .notDetermined)
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        #expect(!granted)
        #expect(await center.notificationSettings().authorizationStatus == .denied)
        await #expect(throws: UNError.self) {
            try await center.add(UNNotificationRequest(identifier: "x", content: UNMutableNotificationContent(), trigger: nil))
        }
        withoutHost()
    }

    @MainActor
    @Test func theHostsPermissionDeliveryAndClickReachTheDelegate() async throws {
        withoutHost()
        nonisolated(unsafe) var permission = UNAuthorizationStatus.notDetermined
        nonisolated(unsafe) var prompts = 0
        nonisolated(unsafe) var shown: [(title: String, body: String, id: String, click: @MainActor () -> Void)] = []
        _UserNotificationsHost.permission = { permission }
        _UserNotificationsHost.requestPermission = { answer in prompts += 1; permission = .authorized; answer(.authorized) }
        _UserNotificationsHost.show = { title, body, id, click in shown.append((title, body, id, click)) }
        let center = UNUserNotificationCenter.current()
        let handler = Handler()
        center.delegate = handler
        // The interactor: status, then the request with [.alert, .sound], then the status again.
        #expect(await center.notificationSettings().authorizationStatus == .notDetermined)
        #expect(try await center.requestAuthorization(options: [.alert, .sound]) == true && prompts == 1)
        #expect(await center.notificationSettings().authorizationStatus == .authorized)
        #expect(try await center.requestAuthorization(options: [.alert]) == true && prompts == 1)   // already granted: no second prompt
        // A local request: the delegate's willPresent decides, the host shows it, a click comes back with the userInfo.
        let content = UNMutableNotificationContent()
        content.title = "Countries"; content.body = "Chad updated"
        content.userInfo = ["aps": ["country": "TD"]]
        try await center.add(UNNotificationRequest(identifier: "chad", content: content, trigger: nil))
        await settled { shown.count == 1 }
        #expect(handler.presented == ["chad"] && shown.count == 1 && shown[0].title == "Countries" && shown[0].body == "Chad updated" && shown[0].id == "chad")
        #expect(center.pendingRequests.isEmpty && center.deliveredNotifications.map(\.request.identifier) == ["chad"])
        shown[0].click()
        #expect(handler.opened.count == 1 && ((handler.opened[0]["aps"] as? [AnyHashable: Any])?["country"] as? String) == "TD")
        // A delegate that presents nothing: delivered, not shown.
        handler.presentWith = []
        try await center.add(UNNotificationRequest(identifier: "quiet", content: content, trigger: nil))
        await settled { handler.presented.count == 2 }
        #expect(handler.presented == ["chad", "quiet"] && shown.count == 1)
        // A timed request removed before it fires never shows.
        try await center.add(UNNotificationRequest(identifier: "later", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.05, repeats: false)))
        #expect(center.pendingRequests.map(\.identifier) == ["later"])
        center.removePendingNotificationRequests(withIdentifiers: ["later"])
        try await Task.sleep(nanoseconds: 120_000_000)   // past its 50 ms trigger: it had its chance to fire
        #expect(handler.presented == ["chad", "quiet"] && shown.count == 1 && center.pendingRequests.isEmpty)
        withoutHost()
    }
}
}
#endif
