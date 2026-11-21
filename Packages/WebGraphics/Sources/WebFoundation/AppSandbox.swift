// What the browser keeps for one app, under a prefix of its own (new-website#709). On iOS each
// app has its own container; in the browser every app on one site shares the page's storage
// (the client area serves every client's build from one address), so each app's keys start
// with its bundle identifier: `swiftuiweb.app[com.example.app].defaults.standard`. Two builds
// of the same app share their data, as an updated app keeps its container; two apps never do.
// An app built without an identifier keeps the plain `swiftuiweb.` prefix.
//
// Removing the app from the drawn iPhone's home screen forgets everything under its prefix:
// its defaults, files, keychain items, SwiftData and Core Data stores, open windows and the
// phone's permission answers. The browser host does the forgetting (`erase`); every host
// store writes through `isErased`, so nothing the app saves on its way out survives.

/// The app's own corner of the browser's storage.
public enum _AppSandbox {
    /// The prefix every key the app's data is kept under starts with.
    public static var prefix: String {
        #if os(WASI)
        let identifier = Bundle._identifier
        #else
        let identifier = nativeIdentifier
        #endif
        guard let identifier, !identifier.isEmpty else { return plainPrefix }
        return "swiftuiweb.app[\(identifier)]."
    }

    #if !os(WASI)
    /// The app's identity off the browser (tests stand in for one).
    nonisolated(unsafe) public static var nativeIdentifier: String?
    #endif

    /// The prefix of an app without a bundle identifier.
    public static let plainPrefix = "swiftuiweb."
    /// What every app's own prefix starts with (an app without an identifier leaves those keys alone).
    public static let appsPrefix = "swiftuiweb.app["

    /// Whether `key` holds this app's data.
    public static func owns(_ key: String) -> Bool {
        let prefix = prefix
        guard key.hasPrefix(prefix) else { return false }
        return prefix != plainPrefix || !key.hasPrefix(appsPrefix)
    }

    /// Set once the app's data is forgotten: the host's stores write nothing more until the
    /// page starts again.
    nonisolated(unsafe) public static var isErased = false
}
