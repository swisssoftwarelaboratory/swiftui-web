import WebFoundation   // Foundation everywhere, and the Selector stand-in where ObjectiveC is absent

// The window, the screen and the application: what the scene owns and the app touches first.

/// The backdrop for the app's user interface and the object that dispatches events to views.
@preconcurrency @MainActor
open class UIWindow: UIView {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    /// The root view controller, whose view fills the window.
    open var rootViewController: UIViewController? {
        didSet {
            guard rootViewController !== oldValue else { return }
            if let old = oldValue {
                old.viewIfLoaded?.removeFromSuperview()
                old.window = nil
            }
            if let controller = rootViewController {
                controller.window = self
                install(controller)
            }
        }
    }

    /// The window level (all windows share one plane in a browser page).
    open var windowLevel: Level = .normal
    open var screen: UIScreen { UIScreen.main }
    open var canResizeToFitContent = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        // A window is opaque black behind whatever it shows, like the screen it fills.
        isOpaque = true
    }

    /// The scene the window belongs to (the host's one scene; `UIWindow(windowScene:)` sets it).
    public var windowScene: UIWindowScene? = UIKitScene.shared.windowScene

    public convenience init(windowScene: UIWindowScene) {
        self.init(frame: windowScene.screen.bounds)
        self.windowScene = windowScene
    }

    public convenience init() {
        self.init(frame: UIScreen.main.bounds)
    }

    override open var next: UIResponder? { UIApplication.shared }
    override open var traitCollection: UITraitCollection {
        var traits = UIScreen.main.traitCollection
        traitOverrides.apply(to: &traits)
        if overrideUserInterfaceStyle != .unspecified { traits.userInterfaceStyle = overrideUserInterfaceStyle }
        return traits
    }
    override open var safeAreaInsets: UIEdgeInsets { UIScreen.main.safeAreaInsets }

    public private(set) var isKeyWindow = false

    /// Makes the window key and shows it: registers it with the scene.
    open func makeKeyAndVisible() {
        isHidden = false
        makeKey()
        UIKitScene.shared.add(self)
    }

    open func makeKey() {
        for window in UIKitScene.shared.windows where window !== self { window.isKeyWindow = false }
        isKeyWindow = true
        becomeKey()
    }

    open func becomeKey() {}
    open func resignKey() {}

    /// Adds a controller's view as the window's content, filling it with autoresizing.
    private func install(_ controller: UIViewController) {
        let view = controller.view!
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if UIKitScene.shared.windows.contains(where: { $0 === self }) { controller.beginAppearanceTransition(true, animated: false) }
        addSubview(view)
        if UIKitScene.shared.windows.contains(where: { $0 === self }) { controller.pendingAppearance = true }
    }

    /// Called by the scene when the window joins it: the root controller appears.
    func didJoinScene() {
        guard let controller = rootViewController, !controller.hasAppeared else { return }
        controller.beginAppearanceTransition(true, animated: false)
        controller.pendingAppearance = true
    }

    /// After the first layout of a joined window, controllers that were about to appear did.
    func completePendingAppearances() {
        var controller = rootViewController
        while let current = controller {
            current.completeAppearanceIfPending()
            controller = current.presentedViewController
        }
    }

    public struct Level: Hashable, Sendable, RawRepresentable, Comparable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let normal = Level(rawValue: 0)
        public static let statusBar = Level(rawValue: 1000)
        public static let alert = Level(rawValue: 2000)
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }
}

/// The screen the app draws on: its bounds and scale come from the host (`@preconcurrency`
/// as every UIKit class reaches Swift from Objective-C: a Swift 5 mode app reads
/// `UIScreen.main.bounds` from a nonisolated helper).
@preconcurrency @MainActor
public final class UIScreen {
    public static let main = UIScreen()

    /// The screen's size in points, set by the host before the app launches and on resize.
    public internal(set) var bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    public var nativeBounds: CGRect { CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale) }
    public internal(set) var scale: CGFloat = 2
    public var nativeScale: CGFloat { scale }
    public internal(set) var traitCollection = UITraitCollection()
    public internal(set) var safeAreaInsets = UIEdgeInsets.zero
    public var brightness: CGFloat = 1
    public var maximumFramesPerSecond: Int { 60 }
}

/// The centralized point of control and coordination for apps.
@preconcurrency @MainActor
public final class UIApplication: UIResponder {
    public static let shared = UIApplication()

    public var delegate: (any UIApplicationDelegate)?
    public var windows: [UIWindow] { UIKitScene.shared.windows }
    public var keyWindow: UIWindow? { UIKitScene.shared.windows.first { $0.isKeyWindow } }
    public var isIdleTimerDisabled = false
    public var applicationState: State = .active

    /// The responder chain's end: a press nobody took is unhandled (Events/Keyboard.swift).
    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) { UIKitScene.shared.pressUnhandled = true }
    override public func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) { UIKitScene.shared.pressUnhandled = true }
    public var applicationIconBadgeNumber = 0

    /// Sends an action message: to `target`, or with a nil target up the responder chain from
    /// the first responder (the application itself at the end, then its delegate). Whether
    /// anything handled it. `sendAction(#selector(UIResponder.resignFirstResponder), to: nil, …)`,
    /// apps' way to dismiss the keyboard, reaches the first responder or, with none, the
    /// application, which has nothing to resign. Without the Objective-C runtime there are no
    /// selectors to send, so nothing handles it.
    @discardableResult
    public func sendAction(_ action: Selector, to target: Any?, from sender: Any?, for event: UIEvent?) -> Bool {
        #if _runtime(_ObjC)
        let receiver: NSObject?
        if let target = target as? NSObject {
            receiver = target.responds(to: action) ? target : nil
        } else {
            let start = UIKitScene.shared.firstResponder ?? self
            receiver = (start.target(forAction: action, withSender: sender) as? NSObject)
                ?? ((delegate as? NSObject).flatMap { $0.responds(to: action) ? $0 : nil })
        }
        guard let receiver else { return false }
        receiver._send(action, passing: sender)
        return true
        #else
        return false
        #endif
    }

    /// Background time: a page keeps running while it is open, so a task never expires and
    /// ending it only retires its identifier.
    public func beginBackgroundTask(withName taskName: String?, expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        nextBackgroundTask += 1
        return UIBackgroundTaskIdentifier(rawValue: nextBackgroundTask)
    }
    public func beginBackgroundTask(expirationHandler handler: (@MainActor @Sendable () -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        beginBackgroundTask(withName: nil, expirationHandler: handler)
    }
    public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
    /// Seconds of background time left: unbounded while the page is open.
    public var backgroundTimeRemaining: TimeInterval { .greatestFiniteMagnitude }
    private var nextBackgroundTask = 0

    /// Opens a URL with the host (a new tab in the browser). The settings URL
    /// (`openSettingsURLString`) has nothing to open in a page: the completion says so.
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {
        guard url.absoluteString != Self.openSettingsURLString, url.absoluteString != Self.openNotificationSettingsURLString else {
            completionHandler?(false)
            return
        }
        UIKitScene.shared.openURL?(url.absoluteString)
        completionHandler?(true)
    }

    @discardableResult
    public func open(_ url: URL, options: [OpenExternalURLOptionsKey: Any] = [:]) async -> Bool {
        await withCheckedContinuation { continuation in open(url, options: options) { continuation.resume(returning: $0) } }
    }

    public func canOpenURL(_ url: URL) -> Bool {
        url.absoluteString != Self.openSettingsURLString && url.absoluteString != Self.openNotificationSettingsURLString && UIKitScene.shared.openURL != nil
    }

    /// The URL that opens the app's settings on iOS; a page has no such place (`open` answers false).
    public static let openSettingsURLString = "app-settings:"
    public static let openNotificationSettingsURLString = "app-settings:notifications"

    /// Remote notifications: a page has no push service. Registering reports a failure to the
    /// delegate right away (the app's `didFailToRegisterForRemoteNotificationsWithError`),
    /// as iOS does without an entitlement or a network.
    public func registerForRemoteNotifications() {
        guard let delegate else { return }
        let application = self
        Task { @MainActor in delegate.application(application, didFailToRegisterForRemoteNotificationsWithError: RegistrationError.unavailable) }
    }
    public func unregisterForRemoteNotifications() {}
    public var isRegisteredForRemoteNotifications: Bool { false }

    public enum RegistrationError: Error, CustomStringConvertible {
        case unavailable
        public var description: String { "remote notifications are not available in a page" }
    }

    public struct OpenURLOptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let sourceApplication = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsSourceApplicationKey")
        public static let annotation = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsAnnotationKey")
        public static let openInPlace = OpenURLOptionsKey(rawValue: "UIApplicationOpenURLOptionsOpenInPlaceKey")
    }

    public enum State: Int, Sendable {
        case active = 0, inactive, background
    }

    public struct LaunchOptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let url = LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsURLKey")
    }

    public struct OpenExternalURLOptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }
}

/// The methods the app object calls on its delegate.
@preconcurrency @MainActor
public protocol UIApplicationDelegate: AnyObject {
    #if !_runtime(_ObjC)
    /// Without an Objective-C runtime the launch cannot instantiate the delegate class by
    /// name; with one (decision 0023) it does, as UIKit does.
    init()
    #endif
    var window: UIWindow? { get set }
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
    func applicationDidBecomeActive(_ application: UIApplication)
    func applicationWillResignActive(_ application: UIApplication)
    func applicationDidEnterBackground(_ application: UIApplication)
    func applicationWillEnterForeground(_ application: UIApplication)
    func applicationWillTerminate(_ application: UIApplication)
    /// The configuration for a scene about to connect: its `delegateClass` is the scene
    /// delegate the launch creates (the Countries app's `SceneDelegate`, decision 0021).
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
    /// Remote notifications: a page has no push service, so registering fails with
    /// `UIApplication.RegistrationError.unavailable`, reported through the delegate.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool
}

extension UIApplicationDelegate {
    public var window: UIWindow? {
        get { UIKitScene.shared.delegateWindow }
        set { UIKitScene.shared.delegateWindow = newValue }
    }
    public func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool { true }
    public func applicationDidBecomeActive(_ application: UIApplication) {}
    public func applicationWillResignActive(_ application: UIApplication) {}
    public func applicationDidEnterBackground(_ application: UIApplication) {}
    public func applicationWillEnterForeground(_ application: UIApplication) {}
    public func applicationWillTerminate(_ application: UIApplication) {}
    public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        connectingSceneSession.configuration
    }
    public func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}
    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult { .noData }
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool { false }
}

/// A background task's identifier (`UIApplication.beginBackgroundTask`).
public struct UIBackgroundTaskIdentifier: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let invalid = UIBackgroundTaskIdentifier(rawValue: 0)
}
