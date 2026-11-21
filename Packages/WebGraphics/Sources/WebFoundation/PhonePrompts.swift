// The drawn iPhone's permission prompts as the app's frameworks reach them (new-website#666).
// UserNotifications, AVFoundation, Photos, LocalAuthentication, HealthKit and AlarmKit ask
// here, as on iOS the system asks for them: the host that draws an iPhone shows iOS's own
// alert (or Health's access sheet, or the Face ID badge) over the app, and keeps each answer
// for the app between visits, as the viewer's own iPhone would. Without a drawn iPhone
// (`isPresent` false) the frameworks keep their browser behaviour.
//
// This module sits under every framework (the Shadows ones import nothing else), so the hook
// lives here; SwiftUIWebCore draws the prompts and the browser host keeps the answers.

/// What the drawn iPhone shows when an app asks for something, and the answers it keeps.
public enum _PhonePrompts {
    /// A prompt as iOS shows it.
    public enum Ask: Sendable {
        /// iOS's alert: a bold title, a message and its buttons, left to right in a row of two,
        /// top to bottom otherwise. The answer is the pressed button's index.
        case alert(title: String, message: String, buttons: [String])
        /// Apple Health's access sheet: one switch per type the app writes (`share`) and reads
        /// (`read`), by display name, with the app's explanations. The answer is the names
        /// switched on, or nil for Don't Allow.
        case health(share: [String], read: [String], shareExplanation: String, readExplanation: String)
        /// The Face ID badge over the app; it always recognises the face.
        case faceID
    }

    /// The person's answer to a prompt.
    public enum Answer: Sendable {
        case button(Int)
        case health(allowed: Set<String>?)
        case done
    }

    /// Shows a prompt; the answer on the main actor once the person gave it. Set by the drawn
    /// iPhone while there is one.
    nonisolated(unsafe) public static var ask: (@MainActor (_ prompt: Ask, _ answered: @escaping @MainActor (Answer) -> Void) -> Void)?
    /// Whether the app runs in the drawn iPhone (readable from any thread).
    nonisolated(unsafe) public static var phone: (@Sendable () -> Bool)?
    /// The host's store for the answers (the browser's localStorage); kept in memory without one.
    nonisolated(unsafe) public static var load: (@Sendable (_ key: String) -> String?)?
    nonisolated(unsafe) public static var save: (@Sendable (_ key: String, _ value: String?) -> Void)?
    nonisolated(unsafe) private static var memory: [String: String] = [:]

    /// Whether prompts go to the drawn iPhone now.
    public static var isPresent: Bool { phone?() ?? false }

    /// The prefix of every answer kept, inside the app's own (`_AppSandbox`), so a fresh
    /// install forgets them all (new-website#709).
    public static var keyPrefix: String { _AppSandbox.prefix + "phone.permission." }

    /// The answer kept under `name` (nil: never asked).
    public static func answer(_ name: String) -> String? {
        if let load { return load(keyPrefix + name) }
        return memory[name]
    }

    /// Keeps an answer under `name` (nil forgets it).
    public static func setAnswer(_ name: String, _ value: String?) {
        guard !_AppSandbox.isErased else { return }
        if let save { save(keyPrefix + name, value); return }
        memory[name] = value
    }

    /// Forgets the answers kept in memory (a fresh install without a host store).
    public static func forgetAnswers() {
        memory = [:]
    }

    /// Shows `prompt` once the main actor runs; without a drawn iPhone, `fallback`.
    public static func show(_ prompt: Ask, fallback: Answer, answered: @escaping @MainActor @Sendable (Answer) -> Void) {
        let run: @MainActor @Sendable () -> Void = {
            guard let ask else { answered(fallback); return }
            ask(prompt) { answered($0) }
        }
        Task { @MainActor in run() }
    }

    // MARK: The words iOS uses

    /// The app's name as the home screen shows it.
    public static var appName: String {
        #if os(WASI)
        let info = Bundle.main.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        #endif
        return "App"
    }

    /// The app's explanation for `key` (`NSCameraUsageDescription` and friends), as its
    /// Info.plist gives it.
    public static func usage(_ key: String) -> String {
        #if os(WASI)
        if let text = Bundle.main.infoDictionary?[key] as? String { return text }
        #endif
        return ""
    }

    /// Whether the phone speaks German (the system prompts follow the phone's language).
    public static var german: Bool {
        #if os(WASI)
        return (Locale.current.languageCode ?? "en") == "de"
        #else
        return false
        #endif
    }

    /// Don't Allow and Allow, as iOS labels them.
    public static var dontAllow: String { german ? "Nicht erlauben" : "Don\u{2019}t Allow" }
    public static var allow: String { german ? "Erlauben" : "Allow" }

    /// The app's name in iOS's quotes.
    public static var quotedName: String { german ? "\u{201E}\(appName)\u{201C}" : "\u{201C}\(appName)\u{201D}" }
}
