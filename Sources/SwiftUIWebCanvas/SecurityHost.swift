// The browser behind the Security framework's keychain items (decision 0021, the Ember app's
// session cookie): each item in localStorage under `swiftuiweb.keychain.<identity>` (inside the app's own prefix, `_AppSandbox`), bounded
// by the page's origin as every key there is. Storage the browser refuses (a sandboxed frame,
// blocked site data, a spent quota) reads as no item and a write that does not stick — the
// functions answer `errSecSuccess` for the write they made in memory, as a keychain whose
// backing store is read-only would not; nothing traps.
#if os(WASI)
import JavaScriptKit
import WebFoundation

@MainActor
enum SecurityHost {
    /// Inside the app's own prefix (`_AppSandbox`, new-website#709).
    static var prefix: String { _AppSandbox.prefix + "keychain." }

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

    private static func run(_ what: String, _ key: String, _ value: String? = nil) -> String? {
        guard let op else { return nil }
        return op(what, key, value.map { JSValue.string($0) } ?? .undefined).object?.value.string
    }

    static func install() {
        _SecurityHost.store = (
            load: { key in run("get", prefix + key) },
            save: { key, value in
                guard !_AppSandbox.isErased else { return }
                _ = value.map { run("set", prefix + key, $0) } ?? run("remove", prefix + key) }
        )
    }
}
#endif
