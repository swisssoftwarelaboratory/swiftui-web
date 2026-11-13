// Scenes and the app lifecycle (uk-scenes): one `UIWindowScene` stands for the host's page or
// window; its windows are the scene's. The host's visibility and focus drive the application
// state and the scene's activation state, the delegates' lifecycle callbacks and the
// `UIApplication`/`UIScene` notifications. A scene delegate class registered with
// `UIApplication.sceneDelegateType` (what the scene manifest names in UIKit) is created and
// connected at launch; `UIWindow(windowScene:)` joins the scene. Feedback generators are no-ops:
// a page has no haptics.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An object that represents one instance of the app's UI.
@preconcurrency @MainActor
open class UIScene: UIResponder {
    public let session: UISceneSession
    public weak var delegate: (any UISceneDelegate)?
    public internal(set) var activationState: ActivationState = .foregroundActive
    open var title: String = ""
    open var subtitle: String = ""

    public init(session: UISceneSession) {
        self.session = session
        super.init()
    }

    public enum ActivationState: Int, Sendable {
        case unattached = -1, foregroundActive, foregroundInactive, background
    }

    public static let didActivateNotification = Notification.Name("UISceneDidActivateNotification")
    public static let willDeactivateNotification = Notification.Name("UISceneWillDeactivateNotification")
    public static let willEnterForegroundNotification = Notification.Name("UISceneWillEnterForegroundNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UISceneDidEnterBackgroundNotification")
    public static let didDisconnectNotification = Notification.Name("UISceneDidDisconnectNotification")
    public static let willConnectNotification = Notification.Name("UISceneWillConnectNotification")

    /// The options the system hands a scene when it connects.
    public final class ConnectionOptions {
        public let urlContexts: Set<UIOpenURLContext>
        public init(urlContexts: Set<UIOpenURLContext> = []) { self.urlContexts = urlContexts }
    }
}

/// A scene that manages one or more windows.
@preconcurrency @MainActor
open class UIWindowScene: UIScene {
    public var screen: UIScreen { UIScreen.main }
    /// The windows attached to the scene (every window of the host).
    public var windows: [UIWindow] { UIKitScene.shared.windows.filter { $0.windowScene === self } }
    public var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
    public var interfaceOrientation: UIInterfaceOrientation { screen.bounds.width > screen.bounds.height ? .landscapeLeft : .portrait }
    public var traitCollection: UITraitCollection { screen.traitCollection }
    public var sizeRestrictions: UISceneSizeRestrictions? { nil }
}

/// A scene's session: its role and identity.
public final class UISceneSession: Sendable {
    public let persistentIdentifier: String
    public let role: UISceneSession.Role
    public let configuration: UISceneConfiguration

    public init(persistentIdentifier: String = "main", role: Role = .windowApplication, configuration: UISceneConfiguration = UISceneConfiguration(name: "Default Configuration")) {
        self.persistentIdentifier = persistentIdentifier
        self.role = role
        self.configuration = configuration
    }

    public struct Role: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let windowApplication = Role(rawValue: "UIWindowSceneSessionRoleApplication")
        public static let windowExternalDisplay = Role(rawValue: "UIWindowSceneSessionRoleExternalDisplay")
    }
}

/// The scene configuration a session connects with: its name, role and delegate class
/// (`application(_:configurationForConnecting:options:)` sets `delegateClass` and the launch
/// connects the scene to an instance of it, decision 0021).
public final class UISceneConfiguration: @unchecked Sendable {
    public let name: String?
    public let role: UISceneSession.Role
    public var delegateClass: AnyClass?
    public var sceneClass: AnyClass?
    public var storyboard: Any?
    public init(name: String?, sessionRole: UISceneSession.Role = .windowApplication) {
        self.name = name
        self.role = sessionRole
    }
}

/// What the app delegate answers for a remote notification it was given to fetch for.
public enum UIBackgroundFetchResult: UInt, Sendable {
    case newData = 0
    case noData = 1
    case failed = 2
}

/// A URL the scene opened with.
public final class UIOpenURLContext: Hashable, @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func == (lhs: UIOpenURLContext, rhs: UIOpenURLContext) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

public struct UISceneSizeRestrictions: Sendable {
    public var minimumSize = CGSize.zero
    public var maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
}

/// The scene delegate's callbacks (every one optional).
@preconcurrency @MainActor
public protocol UISceneDelegate: AnyObject {
    init()
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
    func sceneDidDisconnect(_ scene: UIScene)
    func sceneDidBecomeActive(_ scene: UIScene)
    func sceneWillResignActive(_ scene: UIScene)
    func sceneWillEnterForeground(_ scene: UIScene)
    func sceneDidEnterBackground(_ scene: UIScene)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>)
}

extension UISceneDelegate {
    public func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {}
    public func sceneDidDisconnect(_ scene: UIScene) {}
    public func sceneDidBecomeActive(_ scene: UIScene) {}
    public func sceneWillResignActive(_ scene: UIScene) {}
    public func sceneWillEnterForeground(_ scene: UIScene) {}
    public func sceneDidEnterBackground(_ scene: UIScene) {}
    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {}
}

/// A window scene's delegate keeps the scene's window (optional, as UIKit's: a delegate that
/// declares none keeps it on the scene, decision 0021).
@preconcurrency @MainActor
public protocol UIWindowSceneDelegate: UISceneDelegate {
    var window: UIWindow? { get set }
}

extension UIWindowSceneDelegate {
    public var window: UIWindow? {
        get { UIKitScene.shared.sceneDelegateWindow }
        set { UIKitScene.shared.sceneDelegateWindow = newValue }
    }
}

extension UIApplication {
    public static let didFinishLaunchingNotification = Notification.Name("UIApplicationDidFinishLaunchingNotification")
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
    public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")

    /// The scenes connected to the app: the host's one window scene.
    public var connectedScenes: Set<UIScene> { [UIKitScene.shared.windowScene] }
    public var openSessions: Set<UISceneSession> { [UIKitScene.shared.windowScene.session] }
    public var supportsMultipleScenes: Bool { false }

    /// The scene delegate class the app's scene manifest would name: set it before launch (in
    /// `main` or the app delegate's `willFinishLaunching`); the launch connects the scene to it.
    public var sceneDelegateType: (any UISceneDelegate.Type)? {
        get { UIKitScene.shared.sceneDelegateType }
        set { UIKitScene.shared.sceneDelegateType = newValue }
    }

    /// The configuration for a connecting scene (`application(_:configurationForConnecting:options:)`'s answer, kept for API compatibility).
    public func requestSceneSessionActivation(_ session: UISceneSession?, userActivity: Any?, options: Any?, errorHandler: ((Error) -> Void)? = nil) {}
    public func requestSceneSessionDestruction(_ session: UISceneSession, options: Any?, errorHandler: ((Error) -> Void)? = nil) {}
}

#if !_runtime(_ObjC)
// With the Objective-C runtime NSObject supplies the identity Equatable/Hashable (decision 0023).
extension UIScene: Hashable {
    nonisolated public static func == (lhs: UIScene, rhs: UIScene) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
#endif

extension UISceneSession: Hashable {
    public static func == (lhs: UISceneSession, rhs: UISceneSession) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension UIKitScene {
    /// The launch sequence with a delegate the caller made (a SwiftUI app's
    /// `@UIApplicationDelegateAdaptor`; `main()` makes its own): the launch callbacks and
    /// notification, the delegate's window shown, then the scene: the delegate's
    /// `configurationForConnecting` names the scene delegate class (`delegateClass`), else the
    /// registered `sceneDelegateType`; with one, the scene connects and activates through it,
    /// without one the app becomes active directly.
    public func launchApplication(delegate: any UIApplicationDelegate, launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) {
        let application = UIApplication.shared
        application.delegate = delegate
        _ = delegate.application(application, willFinishLaunchingWithOptions: launchOptions)
        _ = delegate.application(application, didFinishLaunchingWithOptions: launchOptions)
        NotificationCenter.default.post(name: UIApplication.didFinishLaunchingNotification, object: application)
        // The main menu (Containers/MenuBuilder.swift): the delegate's `buildMenu(with:)` runs once the app is up.
        UIMenuSystem.main.setNeedsRebuild()
        if let window = delegate.window, !windows.contains(where: { $0 === window }) {
            window.makeKeyAndVisible()
        }
        let contexts: Set<UIOpenURLContext> = lastOpenedURL.flatMap { URL(string: $0) }.map { [UIOpenURLContext(url: $0)] } ?? []
        let configuration = delegate.application(application, configurationForConnecting: windowScene.session, options: UIScene.ConnectionOptions(urlContexts: contexts))
        if let named = configuration.delegateClass as? any UISceneDelegate.Type { sceneDelegateType = named }
        if sceneDelegateType != nil {
            connectWindowScene()
        } else {
            delegate.applicationDidBecomeActive(application)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: application)
        }
    }

    /// Connects the scene to the registered delegate class (the launch sequence), with the
    /// URL the page opened with when there is one.
    public func connectWindowScene() {
        let scene = windowScene
        guard sceneDelegate == nil, let type = sceneDelegateType else { return }
        let delegate = type.init()
        sceneDelegate = delegate
        scene.delegate = delegate
        let contexts: Set<UIOpenURLContext> = lastOpenedURL.flatMap { URL(string: $0) }.map { [UIOpenURLContext(url: $0)] } ?? []
        NotificationCenter.default.post(name: UIScene.willConnectNotification, object: scene)
        delegate.scene(scene, willConnectTo: scene.session, options: UIScene.ConnectionOptions(urlContexts: contexts))
        if let windowed = delegate as? any UIWindowSceneDelegate, let window = windowed.window, !windows.contains(where: { $0 === window }) {
            window.makeKeyAndVisible()
        }
        if hostIsVisible && hostIsFocused { activateScene() }
    }

    /// Disconnects the scene from its delegate (tests; a host closing).
    public func disconnectWindowScene() {
        guard let delegate = sceneDelegate else { return }
        delegate.sceneDidDisconnect(windowScene)
        NotificationCenter.default.post(name: UIScene.didDisconnectNotification, object: windowScene)
        sceneDelegate = nil
        windowScene.delegate = nil
    }

    /// Reports the host's state: the application state, the scene's activation state, the
    /// delegates and the notifications follow (`hostIsVisible`, `hostIsFocused`).
    func applyLifecycle(from previous: (visible: Bool, focused: Bool)) {
        let application = UIApplication.shared
        let wasActive = previous.visible && previous.focused, isActive = hostIsVisible && hostIsFocused
        if previous.visible && !hostIsVisible {
            if wasActive { deactivateScene() }
            application.applicationState = .background
            windowScene.activationState = .background
            sceneDelegate?.sceneDidEnterBackground(windowScene)
            NotificationCenter.default.post(name: UIScene.didEnterBackgroundNotification, object: windowScene)
            application.delegate?.applicationDidEnterBackground(application)
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: application)
            return
        }
        if !previous.visible && hostIsVisible {
            application.delegate?.applicationWillEnterForeground(application)
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: application)
            sceneDelegate?.sceneWillEnterForeground(windowScene)
            NotificationCenter.default.post(name: UIScene.willEnterForegroundNotification, object: windowScene)
            application.applicationState = .inactive
            windowScene.activationState = .foregroundInactive
        }
        if !wasActive && isActive { activateScene() }
        if wasActive && !isActive && hostIsVisible { deactivateScene() }
    }

    private func activateScene() {
        let application = UIApplication.shared
        application.applicationState = .active
        windowScene.activationState = .foregroundActive
        sceneDelegate?.sceneDidBecomeActive(windowScene)
        NotificationCenter.default.post(name: UIScene.didActivateNotification, object: windowScene)
        application.delegate?.applicationDidBecomeActive(application)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: application)
    }

    private func deactivateScene() {
        let application = UIApplication.shared
        sceneDelegate?.sceneWillResignActive(windowScene)
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: windowScene)
        application.delegate?.applicationWillResignActive(application)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: application)
        application.applicationState = .inactive
        windowScene.activationState = .foregroundInactive
    }
}

// MARK: - Feedback generators (no haptics in a page: every call is a no-op)
// `@preconcurrency`, as Apple's UIKit reaches a Swift 6 toolchain: a Swift 5 mode app makes
// and fires one from a nonisolated helper (EnvironmentOverrides' `Haptic`, decision 0021).

@preconcurrency @MainActor
open class UIFeedbackGenerator {
    public init() {}
    public init(view: UIView) {}
    open func prepare() {}
}

@preconcurrency @MainActor
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackStyle: Int, Sendable { case light, medium, heavy, soft, rigid }
    public let style: FeedbackStyle
    public init(style: FeedbackStyle = .medium) { self.style = style; super.init() }
    public init(style: FeedbackStyle, view: UIView) { self.style = style; super.init(view: view) }
    open func impactOccurred() {}
    open func impactOccurred(intensity: CGFloat) {}
    open func impactOccurred(at location: CGPoint) {}
}

@preconcurrency @MainActor
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
    open func selectionChanged() {}
    open func selectionChanged(at location: CGPoint) {}
}

@preconcurrency @MainActor
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
    public enum FeedbackType: Int, Sendable { case success, warning, error }
    open func notificationOccurred(_ type: FeedbackType) {}
    open func notificationOccurred(_ type: FeedbackType, at location: CGPoint) {}
}
