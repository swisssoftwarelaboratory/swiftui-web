// Thin module: apps write `import UIKit` and get the UIKitWeb implementation. Foundation and
// Observation are re-exported because real UIKit does the same (CGFloat/CGRect, @Observable)
// and unmodified app sources depend on it.
@_exported import UIKitWebCore
@_exported import Observation
#if canImport(CoreGraphics) && !os(WASI)
@_exported import Foundation
@_exported import CoreGraphics
#elseif os(WASI)
// wasm: Foundation would add 12 MB of ICU data and a second CGRect (decision 0006);
// WebFoundation is FoundationEssentials plus the stand-ins that keep its heavy members out
// of the bundle (decision 0017). WASILibc is libm and friends (`ceil`, `sqrt`), which UIKit
// re-exports through Foundation and Darwin.
@_exported import WebFoundation
@_exported import WASILibc
// Image sources (`CGImageSource`), which Apple's UIKit brings with it.
@_exported import WebImageIO
#else
// Linux: Foundation, and WebFoundation's stand-ins for what it lacks (`NSItemProvider`).
@_exported import Foundation
@_exported import WebFoundation
#endif

#if os(WASI)
import JavaScriptEventLoop
import WebGraphicsCanvas
#elseif canImport(AppKit)
import WebGraphicsNative
#endif

#if os(WASI)
/// On wasm there is no CoreGraphics: the recording context is what `CGContext` names, so
/// `UIGraphicsGetCurrentContext()` and `draw(_:)` code type-checks as on iOS. On Apple platforms
/// CoreGraphics keeps the name and the recording context is `UIGraphicsRecordingContext`.
public typealias CGContext = UIGraphicsRecordingContext
#endif

/// Gradients for `drawLinearGradient` / `drawRadialGradient`: the recording context's own class.
/// Declared here, beside the re-export of CoreGraphics, the name shadows CoreGraphics's
/// `CGGradient` (opaque, so it could not be drawn by the recorder) for apps importing UIKit.
public typealias CGGradient = UIGraphicsGradient

/// Marker used by the module-shadowing check (decision 0014).
public struct UIKitWebMarker: Sendable {
    public init() {}
    public static let implementation = "UIKitWeb"
}

extension UIApplicationDelegate {
    /// Launches the app (`@main` on the delegate): creates the delegate, sizes the screen from
    /// the host, calls the launch callbacks and shows the delegate's window (or the key window
    /// it made). In the browser the app runs in a canvas host; on macOS in an AppKit window
    /// painted with CoreGraphics; elsewhere (CLIs) it lays out once headlessly and returns.
    public static func main() {
        UIKitLaunch.run(name: "\(Self.self)") { UIKitLaunch.instantiate(Self.self) }
    }
}

/// What `@UIApplicationMain` expands to: creates the delegate class named by
/// `delegateClassName` and runs the app, as UIKit does. Needs the Objective-C runtime SDK
/// (decision 0023) to look the class up by name.
@discardableResult
public func UIApplicationMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
                              _ principalClassName: String?, _ delegateClassName: String?) -> Int32 {
    #if _runtime(_ObjC)
    guard let name = delegateClassName, let type = NSClassFromString(name) as? NSObject.Type else {
        fatalError("UIApplicationMain: no delegate class named \(delegateClassName ?? "nil")")
    }
    UIKitLaunch.run(name: name) {
        guard let delegate = type.init() as? any UIApplicationDelegate else {
            fatalError("UIApplicationMain: \(name) does not conform to UIApplicationDelegate")
        }
        return delegate
    }
    return 0
    #else
    fatalError("UIApplicationMain needs the Objective-C runtime (decision 0023); build with the swift-*-wasm-objc SDK")
    #endif
}

/// The launch sequence shared by the hosts.
@MainActor
enum UIKitLaunch {
    nonisolated(unsafe) static var retainedHost: AnyObject?

    /// The delegate instance: by the runtime's class instantiation with Objective-C (any
    /// initializer-free subclass of UIResponder), else the protocol's `init()`.
    static func instantiate<Delegate: UIApplicationDelegate>(_ type: Delegate.Type) -> any UIApplicationDelegate {
        #if _runtime(_ObjC)
        guard let objcType = type as? NSObject.Type, let delegate = objcType.init() as? any UIApplicationDelegate else {
            fatalError("\(type) must inherit from UIResponder (NSObject) to be instantiated at launch")
        }
        return delegate
        #else
        return Delegate()
        #endif
    }

    /// Sets up the host for the platform, makes the delegate and launches the app.
    nonisolated static func run(name: String, makeDelegate: @escaping @MainActor () -> any UIApplicationDelegate) {
        #if os(WASI)
        JavaScriptEventLoop.installGlobalExecutor()
        MainActor.assumeIsolated {
            let scene = UIKitScene.shared
            let host = CanvasSceneHost(scene: scene)
            scene.configureScreen(size: host.viewportSize, scale: host.pixelScale)
            scene.openURL = { url in host.openURL(url) }
            launch(delegate: makeDelegate())
            host.invalidate()
            retainedHost = host
        }
        #elseif canImport(AppKit)
        MainActor.assumeIsolated {
            let scene = UIKitScene.shared
            let size = NativeSceneHost.windowSize(default: CGSize(width: 390, height: 844))
            let host = NativeSceneHost(size: size, scene: scene)
            scene.configureScreen(size: size, scale: 2)
            scene.openURL = { url in if let parsed = URL(string: url) { host.openURL(parsed) } }
            host.prepare = { launch(delegate: makeDelegate()) }
            retainedHost = host
            host.run()
        }
        #else
        MainActor.assumeIsolated {
            UIKitScene.shared.configureScreen(size: CGSize(width: 390, height: 844), scale: 2)
            launch(delegate: makeDelegate())
            UIKitScene.shared.layout(in: CGSize(width: 390, height: 844))
            print("UIKitWeb: no window host on this platform; laid out \(name) headlessly.")
        }
        #endif
    }

    static func launch(delegate: any UIApplicationDelegate) {
        // The one launch sequence (`UIKitScene.launchApplication`): a registered or configured
        // scene delegate connects and activates (uk-scenes), else the app becomes active directly.
        UIKitScene.shared.launchApplication(delegate: delegate)
    }
}

/// The type a `#colorLiteral` with no other context makes, as in UIKit.
public typealias _ColorLiteralType = UIColor
