// Link (Docs/elements/Link.md): a control that opens a URL through the `openURL` environment
// action; hosts open it in the browser or the default application.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// A control for navigating to a URL.
public struct Link<Label: View>: View {
    package let destination: URL
    package let label: Label
    @Environment(\.openURL) private var openURL

    /// Creates a control, consisting of a URL and a label, used to navigate to the given URL.
    public init(destination: URL, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    public var body: some View {
        let destination = destination
        let openURL = openURL
        // The label snaps to the pixel grid like a control's (link/basic `customLabel`); the
        // plain style dims a disabled link to 50 % (`buttonPlainDisabledAlpha`).
        // Hovered, the pointer is the pointing hand (`pointerStyle(.link)`: the browser's and
        // AppKit's hand cursor); the text keeps its look (sw-sharelink, 2026-10-11).
        return Button(action: { openURL(destination) }) {
            label.foregroundColor(Color(storage: .system(.link)))._pixelAligned()
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}

extension Link where Label == Text {
    /// Creates a control, consisting of a URL and a title key, used to navigate to a URL.
    public init(_ titleKey: LocalizedStringKey, destination: URL) {
        self.init(destination: destination) { Text(titleKey) }
    }

    /// Creates a control, consisting of a URL and a title string, used to navigate to a URL.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, destination: URL) {
        self.init(destination: destination) { Text(title) }
    }
}

// MARK: - openURL

/// An action that opens a URL.
public struct OpenURLAction: Sendable {
    /// The result of a custom open URL action.
    public struct Result: Sendable {
        package enum Kind: Sendable { case handled, discarded, systemAction(URL?) }
        package let kind: Kind
        /// The action handled the URL.
        public static let handled = Result(kind: .handled)
        /// The action discarded the URL.
        public static let discarded = Result(kind: .discarded)
        /// The URL should be opened by the system (the host).
        public static let systemAction = Result(kind: .systemAction(nil))
        /// Another URL should be opened by the system.
        public static func systemAction(_ url: URL) -> Result { Result(kind: .systemAction(url)) }
    }

    package let handler: (@MainActor @Sendable (URL) -> Result)?

    /// Creates an action that opens a URL with a custom handler.
    public init(handler: @escaping @MainActor @Sendable (URL) -> Result) {
        self.handler = handler
    }

    package init() { handler = nil }

    /// The host's opener (the browser opens a tab, the native host asks the system); nil until a
    /// host installs one.
    @MainActor public static var systemHandler: (@MainActor (URL) -> Void)?

    /// Opens the URL: the custom handler decides, else the host opens it.
    @MainActor public func callAsFunction(_ url: URL) {
        callAsFunction(url) { _ in }
    }

    /// Opens the URL and reports whether it could be (`false` when discarded or no host opens URLs).
    @MainActor public func callAsFunction(_ url: URL, completion: @escaping (Bool) -> Void) {
        var target: URL? = url
        if let handler {
            switch handler(url).kind {
            case .handled: completion(true); return
            case .discarded: completion(false); return
            case .systemAction(let other): target = other ?? url
            }
        }
        // The app's page in iOS Settings (`openSettingsURLString`, `openNotificationSettingsURLString`):
        // there is no Settings to open, in a page or the drawn iPhone (new-website#666), so nothing
        // happens, as UIApplication's `open` does with it; the browser never gets the address.
        if target?.scheme == "app-settings" { completion(false); return }
        guard let target, let system = Self.systemHandler else { completion(false); return }
        system(target)
        completion(true)
    }
}

package struct OpenURLKey: EnvironmentKey {
    package static let defaultValue = OpenURLAction()
}

extension EnvironmentValues {
    /// An action that opens a URL (`Link` uses it; set it to intercept links).
    public var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }
}
