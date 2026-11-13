// `@UIApplicationDelegateAdaptor` (decision 0021, uk-app-delegate-adaptor): a SwiftUI app's
// UIKit app delegate. The delegate is one instance per process, made when the `App` value is
// instantiated and put through UIKit's launch sequence then (`UIKitScene.launchApplication`:
// `willFinishLaunching`, `didFinishLaunching`, the notification, `configurationForConnecting`
// whose `delegateClass` becomes the scene delegate, the scene's connection and activation).
// The page's visibility and focus reach the UIKit scene so `sceneDidBecomeActive` and
// `sceneWillResignActive` follow them as on iOS. A delegate that is an `ObservableObject` is
// also injected into the environment, as SwiftUI does (`@EnvironmentObject var delegate`).
import SwiftUIWebCore
import UIKitWebCore
import WebCombine
#if _runtime(_ObjC)
import ObjectiveC
#endif

/// A property wrapper type that you use to create a UIKit app delegate.
@propertyWrapper
public struct UIApplicationDelegateAdaptor<DelegateType: UIApplicationDelegate>: DynamicProperty {
    /// The underlying app delegate.
    public private(set) var wrappedValue: DelegateType

    /// Creates a UIKit app delegate of the type (once per process; later wrappers of the same
    /// type get the same instance).
    /// An `App` value is made on the main actor (Apple's wrapper is `@MainActor` too).
    @MainActor
    public init(_ delegateType: DelegateType.Type = DelegateType.self) {
        wrappedValue = _UIApplicationDelegateRegistry.delegate(of: delegateType)
    }

    public mutating func update() {}
}

extension UIApplicationDelegateAdaptor where DelegateType: ObservableObject {
    /// A projection of the observed object that provides bindings to its properties.
    public var projectedValue: ObservedObject<DelegateType>.Wrapper { ObservedObject(wrappedValue: wrappedValue).projectedValue }
}

/// The process's app delegates by type, and the launch they went through.
@MainActor
public enum _UIApplicationDelegateRegistry {
    private static var delegates: [ObjectIdentifier: any UIApplicationDelegate] = [:]
    /// Whether UIKit's launch sequence ran (once: the first adaptor's delegate is *the* app delegate).
    public private(set) static var launched = false

    static func delegate<D: UIApplicationDelegate>(of type: D.Type) -> D {
        if let existing = delegates[ObjectIdentifier(type)] as? D { return existing }
        #if _runtime(_ObjC)
        // With the Objective-C runtime (decision 0023) the class is instantiated as UIKit does,
        // without an `init()` requirement on the protocol.
        guard let objcType = type as? NSObject.Type, let delegate = objcType.init() as? D else {
            fatalError("\(type) must inherit from UIResponder (NSObject) to be an app delegate")
        }
        #else
        let delegate = D()
        #endif
        delegates[ObjectIdentifier(type)] = delegate
        if !launched {
            launched = true
            forwardHostLifecycle()
            UIKitScene.shared.launchApplication(delegate: delegate)
            if let observable = delegate as? any ObservableObject { _appEnvironmentObjects.append(observable) }
        }
        return delegate
    }

    /// The page's visibility and focus, from the SwiftUI runtime that hosts the app, to the
    /// UIKit scene (its delegates and notifications follow).
    private static func forwardHostLifecycle() {
        Runtime._hostLifecycleObservers.append { visible, focused in
            let scene = UIKitScene.shared
            if scene.hostIsVisible != visible { scene.hostIsVisible = visible }
            if scene.hostIsFocused != focused { scene.hostIsFocused = focused }
        }
    }

    /// Tests: forgets the delegates and the launch (the UIKit scene is reset separately).
    public static func _reset() {
        delegates.removeAll()
        launched = false
    }
}
