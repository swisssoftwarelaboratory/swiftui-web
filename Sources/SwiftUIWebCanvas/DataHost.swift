// The browser behind SwiftData's stores (decision 0021, pf-swiftdata): a container that is not
// in-memory-only keeps its rows in localStorage under `swiftuiweb.swiftdata.<name>` (inside the app's own prefix, `_AppSandbox`) — one JSON
// document per store, written at every save, read when a container of that name opens. The
// page's origin bounds it as it bounds every localStorage key.
//
// Storage can be refused at any step: reading `window.localStorage` throws a SecurityError when
// the page is denied storage (a sandboxed frame, blocked site data), `getItem` can throw the
// same, `setItem` throws when the origin's quota is spent. Each is caught in JavaScript and
// comes back as a Swift error — a persistent container then fails to open
// (`storageUnavailable`) or the save fails (`saveFailed`), as the app would see an unwritable
// store on a device; nothing traps and nothing stands in for the storage.
#if os(WASI)
import JavaScriptKit
import SwiftData
import WebFoundation   // `_AppSandbox`

@MainActor
enum DataHost {
    /// Inside the app's own prefix (`_AppSandbox`, new-website#709).
    static var prefix: String { _AppSandbox.prefix + "swiftdata." }

    /// What the browser said when it refused storage.
    struct StorageError: Error, CustomStringConvertible {
        let description: String
    }

    /// `op(key, value)`: "get", "set" or "remove" on localStorage, every exception returned as
    /// `{ error: "<message>" }` rather than thrown into the wasm caller.
    private static let op: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        try {
          var s = window.localStorage;
          if (!s) return { error: "no localStorage" };
          if (op === "get") { var v = s.getItem(key); return { value: v === null ? undefined : v }; }
          if (op === "set") { s.setItem(key, value); return {}; }
          s.removeItem(key); return {};
        } catch (e) { return { error: String(e) }; }
        """
        return try? make.throws.new("op", "key", "value", body)
    }()

    private static func run(_ what: String, _ key: String, _ value: String? = nil) throws -> String? {
        guard let op else { throw StorageError(description: "no Function constructor") }
        let result = op(what, key, value.map { JSValue.string($0) } ?? .undefined).object
        if let error = result?.error.string { throw StorageError(description: error) }
        return result?.value.string
    }

    static func install() {
        _ModelStore.Host.store = (
            load: { name in try run("get", prefix + name) },
            save: { name, json in
                guard !_AppSandbox.isErased else { return }
                if let json { _ = try run("set", prefix + name, json) } else { _ = try run("remove", prefix + name) }
            }
        )
    }
}
#endif
