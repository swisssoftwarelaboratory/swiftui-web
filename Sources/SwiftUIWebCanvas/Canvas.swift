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
    public static func launch(windows: @autoclosure @escaping @MainActor () -> [_WindowDescriptor] = [], _ root: @escaping @MainActor () -> AnyView) {
        JavaScriptEventLoop.installGlobalExecutor()
        MediaHost.install()
        VideoHost.install()
        ShaderEffectHost.install()
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
            host.runtime.windowStateStore = (get: { storage.getItem?(_AppSandbox.prefix + "windows").string },
                                             set: { guard !_AppSandbox.isErased else { return }; _ = storage.setItem?(_AppSandbox.prefix + "windows", $0) })
        }
        // Documents open through a file input and save as downloads (sw-windows).
        host.runtime.documentOpenHandler = { [weak host] types, completion in host?.host.openFile(extensions: types.compactMap(\.preferredFilenameExtension), completion: completion) }
        host.runtime.documentSaveHandler = { [weak host] data, name, _, _ in host?.host.download(Array(data), name: name); return nil }
        retained = host
        // The app starts: its `App` value, its windows and its root view.
        let start: @MainActor () -> Void = { [weak host] in
            guard let host else { return }
            host.runtime.installWindows(windows())
            host.mount(root())
            // An app-level `@StateObject` or `@State` change re-reads the app's body (decision 0021).
            _appRemount = (host.runtime, { [weak host] in host?.mount(root()) })
            _appDidMount?(host.runtime)
            host.runtime.restoreWindows()
        }
        guard host.runtime.drawsPhone else { start(); return }
        // Removing the app on the drawn iPhone's home screen forgets its data and loads the page
        // again (new-website#709): the phone then starts on its home screen, the app freshly
        // installed and not running until it is opened, as on iOS.
        _DrawnPhoneSystem.reinstall = { reinstall() }
        if takeFreshInstall() {
            host.runtime.phoneStartsFreshlyInstalled(launch: start)
        } else {
            start()
        }
    }

    /// The flag a removal leaves for the next load, in the tab's own session storage.
    private static var freshInstallKey: String { _AppSandbox.prefix + "phone.freshInstall" }

    /// Whether this load follows a removal (the flag is gone once read).
    private static func takeFreshInstall() -> Bool {
        guard let session = JSObject.global.sessionStorage.object, session.getItem?(freshInstallKey).string != nil else { return false }
        _ = session.removeItem?(freshInstallKey)
        return true
    }

    /// Forgets everything the browser keeps for the app (`_AppSandbox`) and loads the page
    /// again, so nothing of the app's own memory survives either.
    private static func reinstall() {
        _AppSandbox.isErased = true
        for name in ["localStorage", "sessionStorage"] {
            guard let storage = JSObject.global[name].object else { continue }
            var keys: [String] = []
            let count = Int(storage.length.number ?? 0)
            for index in 0..<count {
                if let key = storage.key?(index).string, _AppSandbox.owns(key) { keys.append(key) }
            }
            for key in keys { _ = storage.removeItem?(key) }
        }
        _ = JSObject.global.sessionStorage.object?.setItem?(freshInstallKey, "1")
        _ = JSObject.global.location.object?.reload?()
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
        // `ImageRenderer.uiImage` (and so `pngData`, `jpegData`) rasterizes through UIKit's
        // scene, which got the page's rasterizer only once a UIKit view was mounted: an app that
        // renders a share picture on a screen without one got no image (new-website#668).
        if UIKitScene.shared.imageRasterizer == nil { UIKitScene.shared.imageRasterizer = runtime.imageRasterizer }
        ShareAction.systemHandler = { request in host.share(items: request.strings, subject: request.subject, message: request.message, files: request.files) }
        // The drawn share sheet's Copy (new-website#668): text, and images as PNG (what browsers
        // put on the clipboard; a JPEG is redrawn into one), handed over as a promise so Safari
        // takes it inside the press.
        if let navigator = JSObject.global.navigator.object, let clipboard = navigator.clipboard.object {
            if clipboard.writeText.function != nil {
                ShareAction._copyText = { text in _ = clipboard.writeText!(text) }
            }
            if clipboard.write.function != nil, JSObject.global.ClipboardItem.function != nil,
               let copyImage = JSObject.global.Function.function?.new("bytes", "type", Self.copyImageScript).jsValue.function {
                ShareAction._copyImage = { bytes, type in _ = copyImage(JSTypedArray<UInt8>(bytes).jsValue, type) }
            }
        }
    }

    /// Puts image bytes on the clipboard as PNG.
    private static let copyImageScript = """
        const blob = new Blob([bytes], { type });
        const png = type === 'image/png' ? Promise.resolve(blob) : createImageBitmap(blob).then((bitmap) => {
          const canvas = document.createElement('canvas');
          canvas.width = bitmap.width; canvas.height = bitmap.height;
          canvas.getContext('2d').drawImage(bitmap, 0, 0);
          return new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
        });
        return navigator.clipboard.write([new ClipboardItem({ 'image/png': png })]).catch((error) => console.warn('copy image', error));
        """

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
