// UserNotifications for the web (decision 0021, pf-usernotifications): the centre, its
// settings, authorisation, local requests and the delegate's two callbacks, over the browser's
// Notification API through a host hook (`_UserNotificationsHost`: `Notification.permission`,
// `requestPermission()`, `new Notification` for a delivered request, the click back as a
// response). Remote (push) notifications have no service in a page: `UIApplication`'s
// registration fails through its delegate (UIKitWeb). Written against the Countries app's
// `UserPermissionsInteractor` and `PushNotificationsHandler`.
// Apple's frameworks re-export Foundation: a file importing only this module names NSObject and Data.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc   // libm, which Apple's Foundation re-exports through Darwin
#endif

// MARK: - The host

public enum _UserNotificationsHost {
    /// The browser's current permission, when the host is in place.
    nonisolated(unsafe) public static var permission: (() -> UNAuthorizationStatus)?
    /// Asks the browser (a prompt the first time); the answer on the main actor.
    nonisolated(unsafe) public static var requestPermission: ((@escaping @MainActor (UNAuthorizationStatus) -> Void) -> Void)?
    /// Shows a notification; `onClick` is the user opening it.
    nonisolated(unsafe) public static var show: ((_ title: String, _ body: String, _ identifier: String, _ onClick: @escaping @MainActor () -> Void) -> Void)?
}

// MARK: - Authorization

public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}

public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
    /// Siri reads notifications aloud (asked for, as Apple's; a page has no announcer).
    public static let announcement = UNAuthorizationOptions(rawValue: 1 << 7)
    public static let timeSensitive = UNAuthorizationOptions(rawValue: 1 << 8)
}

public enum UNNotificationSetting: Int, Sendable {
    case notSupported = 0
    case disabled = 1
    case enabled = 2
}

/// The app's notification settings: the browser's permission, the alert setting with it.
public final class UNNotificationSettings: @unchecked Sendable {
    public let authorizationStatus: UNAuthorizationStatus
    public var alertSetting: UNNotificationSetting { authorizationStatus == .authorized ? .enabled : .disabled }
    public var soundSetting: UNNotificationSetting { authorizationStatus == .authorized ? .enabled : .disabled }
    public var badgeSetting: UNNotificationSetting { .notSupported }
    public var lockScreenSetting: UNNotificationSetting { .notSupported }
    public var notificationCenterSetting: UNNotificationSetting { .notSupported }
    public var carPlaySetting: UNNotificationSetting { .notSupported }
    public var criticalAlertSetting: UNNotificationSetting { .notSupported }
    public var alertStyle: UNAlertStyle { authorizationStatus == .authorized ? .banner : .none }
    public var providesAppNotificationSettings: Bool { false }
    public var showPreviewsSetting: UNShowPreviewsSetting { .always }
    public var timeSensitiveSetting: UNNotificationSetting { .notSupported }
    public var scheduledDeliverySetting: UNNotificationSetting { .notSupported }
    public var directMessagesSetting: UNNotificationSetting { .notSupported }
    init(authorizationStatus: UNAuthorizationStatus) { self.authorizationStatus = authorizationStatus }
}

public enum UNAlertStyle: Int, Sendable { case none = 0, banner = 1, alert = 2 }

/// When the system shows previews of an app's notifications.
public enum UNShowPreviewsSetting: Int, Sendable { case always = 0, whenAuthenticated = 1, never = 2 }

/// How much a notification should interrupt the person (Focus and the lock screen on iOS).
public enum UNNotificationInterruptionLevel: UInt, Sendable { case passive = 0, active = 1, timeSensitive = 2, critical = 3 }

// MARK: - Content, triggers, requests

/// The content of a notification.
open class UNNotificationContent: @unchecked Sendable {
    public internal(set) var title = ""
    public internal(set) var subtitle = ""
    public internal(set) var body = ""
    public internal(set) var badge: Int?
    public internal(set) var sound: UNNotificationSound?
    public internal(set) var userInfo: [AnyHashable: Any] = [:]
    public internal(set) var categoryIdentifier = ""
    public internal(set) var threadIdentifier = ""
    public internal(set) var interruptionLevel: UNNotificationInterruptionLevel = .active
    public internal(set) var relevanceScore: Double = 0
    public internal(set) var targetContentIdentifier: String?
    init() {}
    public func mutableCopy() -> UNMutableNotificationContent {
        let copy = UNMutableNotificationContent()
        copy.title = title; copy.subtitle = subtitle; copy.body = body; copy.badge = badge
        copy.sound = sound; copy.userInfo = userInfo; copy.categoryIdentifier = categoryIdentifier; copy.threadIdentifier = threadIdentifier
        copy.interruptionLevel = interruptionLevel; copy.relevanceScore = relevanceScore; copy.targetContentIdentifier = targetContentIdentifier
        return copy
    }
}

/// The editable content of a notification.
public final class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {
    public override init() { super.init() }
    public override var title: String { get { super.title } set { super.title = newValue } }
    public override var subtitle: String { get { super.subtitle } set { super.subtitle = newValue } }
    public override var body: String { get { super.body } set { super.body = newValue } }
    public override var badge: Int? { get { super.badge } set { super.badge = newValue } }
    public override var sound: UNNotificationSound? { get { super.sound } set { super.sound = newValue } }
    public override var userInfo: [AnyHashable: Any] { get { super.userInfo } set { super.userInfo = newValue } }
    public override var categoryIdentifier: String { get { super.categoryIdentifier } set { super.categoryIdentifier = newValue } }
    public override var threadIdentifier: String { get { super.threadIdentifier } set { super.threadIdentifier = newValue } }
    public override var interruptionLevel: UNNotificationInterruptionLevel {
        get { super.interruptionLevel }
        set { super.interruptionLevel = newValue }
    }
    public override var relevanceScore: Double { get { super.relevanceScore } set { super.relevanceScore = newValue } }
    public override var targetContentIdentifier: String? {
        get { super.targetContentIdentifier }
        set { super.targetContentIdentifier = newValue }
    }
}

public final class UNNotificationSound: @unchecked Sendable {
    public static let `default` = UNNotificationSound()
    public static let defaultCritical = UNNotificationSound()
    public static func named(_ name: String) -> UNNotificationSound { UNNotificationSound(named: UNNotificationSoundName(name)) }
    /// The sound's file in the app bundle (the page's notifications play the browser's sound).
    public let name: UNNotificationSoundName?
    init() { name = nil }
    /// A sound from a file in the app bundle.
    public init(named name: UNNotificationSoundName) { self.name = name }
    public static func criticalSoundNamed(_ name: UNNotificationSoundName) -> UNNotificationSound { UNNotificationSound(named: name) }
    public static func ringtoneSoundNamed(_ name: UNNotificationSoundName) -> UNNotificationSound { UNNotificationSound(named: name) }
}

/// The name of a sound file in the app bundle.
public struct UNNotificationSoundName: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// When a notification fires.
open class UNNotificationTrigger: @unchecked Sendable {
    public let repeats: Bool
    init(repeats: Bool) { self.repeats = repeats }
}

/// After an interval.
public final class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        super.init(repeats: repeats)
    }
}

/// A notification the app asks to show (`add(_:)`).
public final class UNNotificationRequest: @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

/// A delivered notification.
public final class UNNotification: @unchecked Sendable {
    public let request: UNNotificationRequest
    public let date: Date
    init(request: UNNotificationRequest, date: Date = Date()) {
        self.request = request
        self.date = date
    }
}

/// The user's response: opening a notification (the default action).
public final class UNNotificationResponse: @unchecked Sendable {
    public let notification: UNNotification
    public let actionIdentifier: String
    init(notification: UNNotification, actionIdentifier: String) {
        self.notification = notification
        self.actionIdentifier = actionIdentifier
    }
}

public let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
public let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

public struct UNNotificationPresentationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 4)
    @available(*, deprecated, renamed: "list")
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
}

public final class UNNotificationCategory: @unchecked Sendable {
    public let identifier: String
    public init(identifier: String, actions: [Any], intentIdentifiers: [String], options: UNNotificationCategoryOptions = []) { self.identifier = identifier }
}
public struct UNNotificationCategoryOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1)
}

// MARK: - The delegate

/// An interface for processing incoming notifications and responding to notification actions.
public protocol UNUserNotificationCenterDelegate: AnyObject {
    /// A notification arriving while the app is in the foreground: what to show for it.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    /// The user acted on a notification (opened it).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?)
}

extension UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([]) }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) { completionHandler() }
    public func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {}
}

// MARK: - The centre

/// The central object for managing notification-related activities for your app.
public final class UNUserNotificationCenter: @unchecked Sendable {
    private static let shared = UNUserNotificationCenter()
    public static func current() -> UNUserNotificationCenter { shared }

    public weak var delegate: (any UNUserNotificationCenterDelegate)?
    public var supportsContentExtensions: Bool { false }
    /// Requests the host remembers answering, delivered or pending (`add` with a trigger waits).
    public private(set) var pendingRequests: [UNNotificationRequest] = []
    public private(set) var deliveredNotifications: [UNNotification] = []
    private var categories: Set<String> = []
    /// The permission without a host: never asked, never granted.
    nonisolated(unsafe) private static var permissionWithoutHost: UNAuthorizationStatus = .notDetermined

    init() {}

    private var status: UNAuthorizationStatus { _UserNotificationsHost.permission?() ?? Self.permissionWithoutHost }

    /// The app's settings now (the browser's permission).
    public func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
        completionHandler(UNNotificationSettings(authorizationStatus: status))
    }

    public func notificationSettings() async -> UNNotificationSettings { UNNotificationSettings(authorizationStatus: status) }

    /// Asks the user (the browser's prompt the first time); `false` without a host.
    public func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, Error?) -> Void) {
        if status == .authorized { completionHandler(true, nil); return }
        guard let request = _UserNotificationsHost.requestPermission else {
            Self.permissionWithoutHost = .denied
            completionHandler(false, nil)
            return
        }
        nonisolated(unsafe) let completionHandler = completionHandler
        request { answer in completionHandler(answer == .authorized, nil) }
    }

    public func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            requestAuthorization(options: options) { granted, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
            }
        }
    }

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) { self.categories = Set(categories.map(\.identifier)) }
    public func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) { completionHandler([]) }

    /// Schedules a local notification: shown through the host (after the trigger's interval
    /// when it has one), the delegate asked first while the app is in the foreground, as on
    /// iOS; a click is the default action delivered to the delegate.
    public func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {
        guard status == .authorized else {
            completionHandler?(UNError.notAuthorized)
            return
        }
        pendingRequests.append(request)
        // Delivery is asynchronous, on the main actor, as iOS delivers after `add` returns.
        let interval = (request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval ?? 0
        Task { @MainActor [weak self] in
            if interval > 0 { try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            self?.deliver(request)
        }
        completionHandler?(nil)
    }

    public func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
        }
    }

    @MainActor
    private func deliver(_ request: UNNotificationRequest) {
        guard pendingRequests.contains(where: { $0 === request }) else { return }   // removed before it fired
        pendingRequests.removeAll { $0 === request }
        let notification = UNNotification(request: request)
        deliveredNotifications.append(notification)
        let show = { [weak self] in
            guard let self else { return }
            _UserNotificationsHost.show?(request.content.title, request.content.body, request.identifier) { [weak self] in
                guard let self else { return }
                let response = UNNotificationResponse(notification: notification, actionIdentifier: UNNotificationDefaultActionIdentifier)
                self.delegate?.userNotificationCenter(self, didReceive: response) {}
            }
        }
        if let delegate {
            // The foreground rule: the delegate chooses what to present; nothing means nothing shown.
            delegate.userNotificationCenter(self, willPresent: notification) { options in
                if !options.isEmpty { show() }
            }
        } else {
            show()
        }
    }

    public func getPendingNotificationRequests(completionHandler: @escaping ([UNNotificationRequest]) -> Void) { completionHandler(pendingRequests) }
    public func pendingNotificationRequests() async -> [UNNotificationRequest] { pendingRequests }
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { pendingRequests.removeAll { identifiers.contains($0.identifier) } }
    public func removeAllPendingNotificationRequests() { pendingRequests.removeAll() }
    public func getDeliveredNotifications(completionHandler: @escaping ([UNNotification]) -> Void) { completionHandler(deliveredNotifications) }
    public func deliveredNotifications() async -> [UNNotification] { deliveredNotifications }
    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) { deliveredNotifications.removeAll { identifiers.contains($0.request.identifier) } }
    public func removeAllDeliveredNotifications() { deliveredNotifications.removeAll() }
    public func setBadgeCount(_ newBadgeCount: Int) async throws {}
    /// The badge has nowhere to show in a browser tab; the handler is told it went through.
    public func setBadgeCount(_ newBadgeCount: Int, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }

    /// Tests: the host-less permission back to never asked.
    public static func _resetWithoutHost() { permissionWithoutHost = .notDetermined }
}

extension UNNotificationCategory: Hashable {
    public static func == (lhs: UNNotificationCategory, rhs: UNNotificationCategory) -> Bool { lhs.identifier == rhs.identifier }
    public func hash(into hasher: inout Hasher) { hasher.combine(identifier) }
}

public enum UNError: Error, CustomStringConvertible {
    case notAuthorized
    public var description: String { "notifications are not authorized" }
}
