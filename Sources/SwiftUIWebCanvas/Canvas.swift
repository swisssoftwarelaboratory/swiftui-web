import SwiftUIWebCore
#if os(WASI)
import JavaScriptEventLoop
import JavaScriptKit
import WebFoundation   // the drawn iPhone's permission answers (`_PhonePrompts`)
import UIKitWebCore
import SwiftUIWebWidgetLauncher
@_exported import WebGraphicsCanvas

/// A SwiftUI `Runtime` in the browser: the substrate's `CanvasSceneHost` (decision 0014) with the
/// runtime as its scene, the window background and chrome painted, links and share sheets wired
/// to the page, and the platform look chosen from the page's pointer (iOS on a touch device,
/// macOS elsewhere; `Docs/elements/iOS.md`) unless the page forces one.
@MainActor
public final class CanvasHost {
    public let runtime = Runtime()
    public let host: CanvasSceneHost

    /// Installs the JavaScript event loop, creates a host in `#app` (or `<body>`) and mounts.
    /// The platform hosts (audio, notifications, location, fetch, storage) are installed before `windows`
    /// is read: reading it makes the `App` value, whose delegate may already open its model
    /// container (Countries' AppEnvironment.bootstrap, decision 0021).
    public static func launch(windows: @autoclosure @MainActor () -> [_WindowDescriptor] = [], _ root: @escaping @MainActor () -> AnyView) {
        JavaScriptEventLoop.installGlobalExecutor()
        MediaHost.install()
        SpeechHost.install()
        NotificationsHost.install()
        // The app's widget extension, when it has one: its Live Activities and widgets reach the
        // drawn iPhone (new-website#643, #638).
        _ = swiftui_web_launch_widgets()
        GeolocationHost.install()
        NetworkHost.install()
        DataHost.install()
        SecurityHost.install()
        RegexHost.install()
        let host = CanvasHost()
        KeyboardHost.install()
        let windows = windows()
        // Open windows are remembered in localStorage and reopened on the next load (sw-windows).
        if let storage = JSObject.global.localStorage.object {
            // The drawn iPhone's permission answers stay between visits, as on the viewer's
            // own iPhone (new-website#666).
            _PhonePrompts.load = { key in MainActor.assumeIsolated { JSObject.global.localStorage.object?.getItem?(key).string } }
            _PhonePrompts.save = { key, value in
                MainActor.assumeIsolated {
                    guard let storage = JSObject.global.localStorage.object else { return }
                    if let value { _ = storage.setItem?(key, value) } else { _ = storage.removeItem?(key) }
                }
            }
            host.runtime.windowStateStore = (get: { storage.getItem?("swiftuiweb.windows").string },
                                             set: { _ = storage.setItem?("swiftuiweb.windows", $0) })
        }
        // Documents open through a file input and save as downloads (sw-windows).
        host.runtime.documentOpenHandler = { [weak host] types, completion in host?.host.openFile(extensions: types.compactMap(\.preferredFilenameExtension), completion: completion) }
        host.runtime.documentSaveHandler = { [weak host] data, name, _, _ in host?.host.download(Array(data), name: name); return nil }
        host.runtime.installWindows(windows)
        host.mount(root())
        // An app-level `@StateObject` or `@State` change re-reads the app's body (decision 0021).
        _appRemount = (host.runtime, { [weak host] in host?.mount(root()) })
        _appDidMount?(host.runtime)
        host.runtime.restoreWindows()
        retained = host
    }

    nonisolated(unsafe) private static var retained: CanvasHost?

    public init() {
        runtime.paintsWindowBackground = true
        runtime.paintsWindowChrome = true
        host = CanvasSceneHost(scene: runtime)
        switch host.requestedPlatform {
        case "ios": runtime.hostPlatformProfile = .iOS
        case "macos": runtime.hostPlatformProfile = .macOS
        default: runtime.hostPlatformProfile = host.hasCoarsePointer ? .iOS : .macOS
        }
        // The iPhone look on a computer draws the iPhone's keyboard, which a computer has none
        // of on screen (new-website#648); a phone's browser brings its own. `?keyboard=none`
        // leaves it out. Its frame posts UIKit's keyboard notifications.
        let search = JSObject.global.location.object?.search.string ?? ""
        runtime.drawsSoftwareKeyboard = runtime.hostPlatformProfile.isIOS && !host.hasCoarsePointer && !search.contains("keyboard=none")
        if runtime.drawsSoftwareKeyboard {
            KeyboardHost.drawsKeyboard = true
            runtime.onKeyboardFrameChange = { UIKitScene.shared.keyboardFrame = $0 }
        }
        // Links open in a new tab; share links use Web Share where the browser offers it.
        let host = self.host
        OpenURLAction.systemHandler = { url in host.openURL(url.absoluteString) }
        // `UIApplication.shared.open` from a SwiftUI app reaches the same tab (decision 0021).
        UIKitScene.shared.openURL = { url in host.openURL(url) }
        ShareAction.systemHandler = { request in host.share(items: request.strings, subject: request.subject, message: request.message, files: request.files) }
    }

    /// Mounts (or replaces) the root view and schedules a frame.
    public func mount(_ view: AnyView) {
        runtime.mount(view)
        host.invalidate()
    }
}

#else
/// The canvas host exists only on wasm; this keeps the module importable elsewhere.
public enum SwiftUIWebCanvas {}
#endif
