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
        /// Sign in with Apple's sheet over the dimmed app (new-website#707), then Face ID. The
        /// answer is `.appleID` with the name and email choice, or `.cancelled` for its close
        /// button.
        case appleID(AppleIDAsk)
    }

    /// What Sign in with Apple's sheet asks: a first sign-in asks to share the name and email
    /// the app requested; a returning one only asks to continue.
    public struct AppleIDAsk: Sendable, Equatable {
        public var returning: Bool
        public var asksName: Bool
        public var asksEmail: Bool
        public init(returning: Bool, asksName: Bool, asksEmail: Bool) {
            self.returning = returning
            self.asksName = asksName
            self.asksEmail = asksEmail
        }
    }

    /// The person's answer to a prompt.
    public enum Answer: Sendable {
        case button(Int)
        case health(allowed: Set<String>?)
        case done
        /// Sign in with Apple's Continue: the name as the sheet showed it (empty when cleared
        /// or not asked) and whether Hide My Email was chosen.
        case appleID(name: String, hideEmail: Bool)
        /// A sheet's close button.
        case cancelled
    }

    /// The drawn iPhone's Apple Account: a made-up person until the demo account is decided
    /// (new-website#194's fog). Its relay address for Hide My Email is one per app, as Apple's is.
    public enum AppleAccount {
        public static let givenName = "Mara"
        public static let familyName = "Keller"
        public static let email = "mara.keller@icloud.com"
        public static var fullName: String { givenName + " " + familyName }

        /// The app's bundle identifier, or its name without one.
        public static var appID: String {
            #if os(WASI)
            if let id = Bundle.main.infoDictionary?["CFBundleIdentifier"] as? String, !id.isEmpty { return id }
            #endif
            return _PhonePrompts.appName
        }

        /// A stable hex string of `count` digits from `seed` (FNV-1a, stretched).
        public static func digits(_ seed: String, count: Int) -> String {
            var out = ""
            var round: UInt64 = 0
            while out.count < count {
                var hash: UInt64 = 0xcbf29ce484222325
                for byte in (seed + "#" + String(round)).utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
                out += String(hash, radix: 16).leftPadded(16)
                round += 1
            }
            return String(out.prefix(count))
        }

        /// The app's Hide My Email address, as Apple's relay gives one per app.
        public static var relayEmail: String {
            let letters = Array("abcdefghjkmnpqrstvwxyz23456789")
            let hex = digits("relay:" + appID, count: 20)
            var word = ""
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                word.append(letters[Int(hex[index..<next], radix: 16)! % letters.count])
                index = next
            }
            return word + "@privaterelay.appleid.com"
        }

        /// The user identifier Apple gives this app for the account (team-scoped on iOS, here
        /// app-scoped): six digits, 32 hex digits, four digits.
        public static var userID: String {
            let hex = digits("user:" + appID, count: 42)
            let six = String(Int(hex.prefix(5), radix: 16)! % 1_000_000).leftPadded(6, with: "0")
            let four = String(Int(hex.suffix(4), radix: 16)! % 10_000).leftPadded(4, with: "0")
            return six + "." + String(hex.dropFirst(5).prefix(32)) + "." + four
        }
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

private extension String {
    func leftPadded(_ width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}
