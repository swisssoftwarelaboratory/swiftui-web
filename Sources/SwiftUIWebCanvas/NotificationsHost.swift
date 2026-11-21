// The browser behind UserNotifications (decision 0021, pf-usernotifications): the page's
// Notification API — the user's permission as the browser holds it, `requestPermission()` as
// the one prompt, `new Notification(title, {body, tag})` for a delivered local request, and its
// `click` as the response the delegate receives. Nothing is pushed from a server: there is no
// push service here, and `UIApplication.registerForRemoteNotifications` fails through the
// app's delegate (UIKitWeb).
//
// Inside the drawn iPhone (new-website#643) the phone is the notification centre instead: its
// own permission (kept for the page, as iOS keeps it for the app), delivery to the lock
// screen's list, the pull-down and banners, and the person opening one there. Until the drawn
// permission prompt is built (#666), asking for permission answers Allow, as a tester would.
#if os(WASI)
import JavaScriptKit
import SwiftUIWebCore
import UserNotifications

@MainActor
enum NotificationsHost {
    static func install() {
        installPhone()
        guard let constructor = JSObject.global.Notification.function else { return }   // not every browser (iOS Safari outside a web app)
        _UserNotificationsHost.permission = {
            if _DrawnPhoneSystem.isPresent { return phonePermission }
            return status(of: constructor.permission.string)
        }
        _UserNotificationsHost.requestPermission = { completion in
            if _DrawnPhoneSystem.isPresent { askOnPhone(completion); return }
            guard let promise = constructor.requestPermission?().object else { completion(.denied); return }
            let resolved = JSClosure { (arguments: [JSValue]) -> JSValue in
                let answer = status(of: arguments.first?.string)
                MainActor.assumeIsolated { completion(answer) }
                return .undefined
            }
            let rejected = JSClosure { (_: [JSValue]) -> JSValue in MainActor.assumeIsolated { completion(.denied) }; return .undefined }
            _ = promise.then!(resolved, rejected)
            retained.append(resolved)
            retained.append(rejected)
        }
        _UserNotificationsHost.show = { title, body, identifier, onClick in
            let options = JSObject.global.Object.function!.new()
            options.body = .string(body)
            options.tag = .string(identifier)
            let notification = constructor.new(title, options)
            let clicked = JSClosure { (_: [JSValue]) -> JSValue in MainActor.assumeIsolated { onClick() }; return .undefined }
            notification.onclick = .object(clicked)
            retained.append(clicked)
            shown.append(notification)
        }
    }

    // MARK: The drawn iPhone

    private static func installPhone() {
        _UserNotificationsHost.phone = { _DrawnPhoneSystem.isPresent }
        _UserNotificationsHost.appIsInForeground = { _DrawnPhoneSystem.appIsInForeground }
        _UserNotificationsHost.present = { note, onOpen in
            _DrawnPhoneSystem.deliver(identifier: note.identifier, title: note.title, subtitle: note.subtitle, body: note.body,
                                      date: note.date, banner: note.banner, list: note.list, onOpen: onOpen)
        }
        _UserNotificationsHost.withdraw = { identifiers in _DrawnPhoneSystem.withdraw(identifiers) }
        if _UserNotificationsHost.permission == nil {
            // A browser without the Notification API still has the phone's.
            _UserNotificationsHost.permission = { _DrawnPhoneSystem.isPresent ? phonePermission : .denied }
            _UserNotificationsHost.requestPermission = { completion in
                if _DrawnPhoneSystem.isPresent { askOnPhone(completion) } else { completion(.denied) }
            }
        }
    }

    nonisolated private static let permissionKey = "swiftuiweb.phone.notifications"

    /// The app's notification permission on the drawn iPhone, kept in the page's storage.
    nonisolated static var phonePermission: UNAuthorizationStatus {
        get {
            guard let stored = JSObject.global.localStorage.object?.getItem?(permissionKey).string, let raw = Int(stored) else { return .notDetermined }
            return UNAuthorizationStatus(rawValue: raw) ?? .notDetermined
        }
        set { _ = JSObject.global.localStorage.object?.setItem?(permissionKey, String(newValue.rawValue)) }
    }

    /// The phone's answer: the one asked before, else Allow (the drawn prompt is #666).
    private static func askOnPhone(_ completion: @escaping @MainActor (UNAuthorizationStatus) -> Void) {
        if phonePermission != .notDetermined { completion(phonePermission); return }
        phonePermission = .authorized
        completion(.authorized)
    }

    nonisolated static func status(of permission: String?) -> UNAuthorizationStatus {
        switch permission {
        case "granted": .authorized
        case "denied": .denied
        default: .notDetermined
        }
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []
    nonisolated(unsafe) static var shown: [JSObject] = []
}
#endif
