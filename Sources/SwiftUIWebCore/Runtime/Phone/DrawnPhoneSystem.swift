#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// What reaches the drawn iPhone from the app's system frameworks (new-website#643): the
// notifications UserNotifications delivers (the lock screen's list, the pull-down, banners), the
// Live Activities ActivityKit starts (drawn live by the app's own view, through WidgetKit) and
// the lock screen widgets WidgetKit offers (#638). The frameworks never import this module; the
// browser host (UserNotifications) and WidgetKit (activities, widgets) call in here.

/// The drawn iPhone as the system frameworks reach it. Everything is a no-op without one.
@MainActor
public enum _DrawnPhoneSystem {
    /// Whether the app runs inside the drawn iPhone (readable from any thread).
    nonisolated public static var isPresent: Bool { present }
    nonisolated(unsafe) static var present = false

    /// The app's runtime, which a hosted tree measures and draws like.
    public static var hostRuntime: Runtime? { DrawnPhone.current?.runtime }

    /// Whether the app is in the foreground (it fills the screen, nothing over it): iOS asks
    /// the app's delegate what to show of a notification only then.
    public static var appIsInForeground: Bool {
        guard let phone = DrawnPhone.current else { return false }
        return phone.mode == .app && phone.cardShown && phone.coverAmount == 0
    }

    /// A delivered notification: on the lock screen's list and the pull-down when `list`, as a
    /// banner over the app or the home screen when `banner`. `onOpen` is the person opening it
    /// (the app then hears of it through its delegate's `didReceive`).
    public static func deliver(identifier: String, title: String, subtitle: String, body: String, date: Date,
                               banner: Bool, list: Bool, onOpen: @escaping @MainActor () -> Void) {
        guard let phone = DrawnPhone.current else { return }
        let note = DrawnPhone.Note(identifier: identifier, title: title, subtitle: subtitle, body: body, date: date, onOpen: onOpen)
        phone.receive(note, banner: banner, list: list)
    }

    /// Takes delivered notifications off the lock screen and the pull-down.
    public static func withdraw(_ identifiers: [String]) {
        DrawnPhone.current?.withdraw(identifiers)
    }

    /// Takes every delivered notification away.
    public static func withdrawAll() {
        DrawnPhone.current?.withdrawAll()
    }

    /// A Live Activity started: its view, drawn live at the top of the lock screen's column.
    public static func startActivity(id: String, view: AnyView, opensApp: @escaping @MainActor () -> Void = {}) {
        guard let phone = DrawnPhone.current else { return }
        phone.startActivity(id: id, view: view, opensApp: opensApp)
    }

    /// The activity's content changed: the same tree shows its new view.
    public static func updateActivity(id: String, view: AnyView) {
        DrawnPhone.current?.updateActivity(id: id, view: view)
    }

    /// The activity ended and leaves the lock screen.
    public static func endActivity(id: String) {
        DrawnPhone.current?.endActivity(id: id)
    }

    /// The lock screen widgets, in one row under the clock (none when the app has none).
    public static func setLockScreenWidgets(_ trees: [_HostedTree]) {
        DrawnPhone.current?.setLockScreenWidgets(trees)
    }
}
