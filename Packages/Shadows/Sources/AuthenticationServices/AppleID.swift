// Apple's `AuthenticationServices` module for wasm: Sign in with Apple (new-website#707).
//
// Inside the drawn iPhone an app's own `ASAuthorizationController` with an Apple ID request
// shows iOS's sheet over the dimmed app (the app's icon and name, the phone's Apple Account,
// Share or Hide My Email, Continue), then Face ID, and hands the app a credential from the
// phone's account, as iOS does. A second sign-in shows iOS's shorter sheet and gives no name or
// email. The sign-in is kept with the phone's other answers (`_PhonePrompts`), so removing the
// app forgets it. The sheet is drawn by the phone (SwiftUIWebCore's `DrawnPhonePrompts`);
// this module is the API apps call.
//
// In a plain page there is no Apple Account to sign in with: requests fail with
// `ASAuthorizationError.unknown`, as on a device signed out of iCloud, and the app takes its
// path for that.
//
// The identity token is shaped like Apple's (a JWT with Apple's claims for the app) but is not
// signed by Apple: a server that checks it against Apple's keys refuses it, as it should.
#if os(WASI)
import WebFoundation

// MARK: Errors

public let ASAuthorizationErrorDomain = "com.apple.AuthenticationServices.AuthorizationError"

/// An error from an authorization controller, with Apple's codes.
public struct ASAuthorizationError: Error, Hashable, Sendable, CustomNSError, LocalizedError {
    public enum Code: Int, Sendable {
        case unknown = 1000
        case canceled = 1001
        case invalidResponse = 1002
        case notHandled = 1003
        case failed = 1004
        case notInteractive = 1005
        case matchedExcludedCredential = 1006
        case credentialImport = 1007
        case credentialExport = 1008
        case preferSignInWithApple = 1009
        case deviceNotConfiguredForPasskeyCreation = 1010

        /// `catch ASAuthorizationError.canceled` and `case ASAuthorizationError.canceled:`.
        public static func ~= (code: Code, error: any Error) -> Bool {
            if let error = error as? ASAuthorizationError { return error.code == code }
            let value: Any = error
            if let error = value as? NSError { return error.domain == ASAuthorizationErrorDomain && error.code == code.rawValue }
            return false
        }
    }

    public let code: Code
    public init(_ code: Code) { self.code = code }

    public static var errorDomain: String { ASAuthorizationErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }
    public var errorDescription: String? {
        "The operation couldn\u{2019}t be completed. (com.apple.AuthenticationServices.AuthorizationError error \(code.rawValue).)"
    }

    public static let unknown = Code.unknown
    public static let canceled = Code.canceled
    public static let invalidResponse = Code.invalidResponse
    public static let notHandled = Code.notHandled
    public static let failed = Code.failed
    public static let notInteractive = Code.notInteractive
    public static let matchedExcludedCredential = Code.matchedExcludedCredential
    public static let credentialImport = Code.credentialImport
    public static let credentialExport = Code.credentialExport
    public static let preferSignInWithApple = Code.preferSignInWithApple
    public static let deviceNotConfiguredForPasskeyCreation = Code.deviceNotConfiguredForPasskeyCreation
}

// MARK: Providers, requests and credentials

/// Something that makes authorization requests (Apple ID, passwords).
public protocol ASAuthorizationProvider: NSObjectProtocol {}

/// What an authorization hands the app.
public protocol ASAuthorizationCredential: NSObjectProtocol {}

/// A finished authorization: who made it and what it gave.
open class ASAuthorization: NSObject, @unchecked Sendable {
    /// What the app asks to be shared besides the user identifier.
    public struct Scope: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let fullName = Scope(rawValue: "full_name")
        public static let email = Scope(rawValue: "email")
    }

    /// The OpenID operation a request makes.
    public struct OpenIDOperation: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let operationImplicit = OpenIDOperation(rawValue: "")
        public static let operationLogin = OpenIDOperation(rawValue: "login")
        public static let operationRefresh = OpenIDOperation(rawValue: "refresh")
        public static let operationLogout = OpenIDOperation(rawValue: "logout")
    }

    public let provider: any ASAuthorizationProvider
    public let credential: any ASAuthorizationCredential

    package init(provider: any ASAuthorizationProvider, credential: any ASAuthorizationCredential) {
        self.provider = provider
        self.credential = credential
        super.init()
    }
}

public typealias ASAuthorizationScope = ASAuthorization.Scope
public typealias ASAuthorizationOpenIDOperation = ASAuthorization.OpenIDOperation

/// A request an authorization controller performs.
open class ASAuthorizationRequest: NSObject, @unchecked Sendable {
    public let provider: any ASAuthorizationProvider
    package init(provider: any ASAuthorizationProvider) {
        self.provider = provider
        super.init()
    }
}

/// An OpenID request: the scopes asked for, and the app's state and nonce.
open class ASAuthorizationOpenIDRequest: ASAuthorizationRequest, @unchecked Sendable {
    open var requestedScopes: [ASAuthorization.Scope]?
    open var state: String?
    open var nonce: String?
    open var requestedOperation: ASAuthorization.OpenIDOperation = .operationImplicit
}

/// A Sign in with Apple request.
open class ASAuthorizationAppleIDRequest: ASAuthorizationOpenIDRequest, @unchecked Sendable {
    /// The user identifier of an account the app already knows.
    open var user: String?
}

/// Whether the person signing in is likely a real person.
public enum ASUserDetectionStatus: Int, Sendable {
    case unsupported = 0
    case unknown = 1
    case likelyReal = 2
}

/// The age range the Apple Account reports (iOS 26).
public enum ASUserAgeRange: Int, Sendable {
    case unknown = 0
    case child = 1
    case notChild = 2
}

/// What Sign in with Apple hands the app.
open class ASAuthorizationAppleIDCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    /// The account's identifier for this app; the same at every sign-in.
    public let user: String
    public let state: String?
    public let authorizedScopes: [ASAuthorization.Scope]
    public let authorizationCode: Data?
    public let identityToken: Data?
    /// The email the person chose to share, the first time only.
    public let email: String?
    /// The name the person shared, the first time only.
    public let fullName: PersonNameComponents?
    public let realUserStatus: ASUserDetectionStatus
    public let userAgeRange: ASUserAgeRange

    package init(user: String, state: String?, authorizedScopes: [ASAuthorization.Scope], authorizationCode: Data?, identityToken: Data?,
                 email: String?, fullName: PersonNameComponents?, realUserStatus: ASUserDetectionStatus) {
        self.user = user
        self.state = state
        self.authorizedScopes = authorizedScopes
        self.authorizationCode = authorizationCode
        self.identityToken = identityToken
        self.email = email
        self.fullName = fullName
        self.realUserStatus = realUserStatus
        userAgeRange = .notChild
        super.init()
    }
}

/// Makes Sign in with Apple requests and tells whether an account is still signed in.
open class ASAuthorizationAppleIDProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public enum CredentialState: Int, Sendable {
        case revoked = 0
        case authorized = 1
        case notFound = 2
        case transferred = 3
    }

    /// Posted when the person stops using Apple ID with the app.
    public static let credentialRevokedNotification = NSNotification.Name("ASAuthorizationAppleIDCredentialRevokedNotification")

    public override init() { super.init() }

    open func createRequest() -> ASAuthorizationAppleIDRequest {
        ASAuthorizationAppleIDRequest(provider: self)
    }

    /// Authorized while the phone's account is signed in to the app under `userID`; not found
    /// otherwise (never signed in, or the app was removed). In a plain page, not found.
    open func getCredentialState(forUserID userID: String,
                                 completion: @escaping @Sendable (CredentialState, (any Error)?) -> Void) {
        let state = Self.state(forUserID: userID)
        DispatchQueue.main.async { completion(state, nil) }
    }

    open func credentialState(forUserID userID: String) async throws -> CredentialState {
        Self.state(forUserID: userID)
    }

    private static func state(forUserID userID: String) -> CredentialState {
        guard _PhonePrompts.isPresent, AppleIDSignIn.signedIn != nil else { return .notFound }
        return userID == _PhonePrompts.AppleAccount.userID ? .authorized : .notFound
    }
}

/// A saved password request. The drawn iPhone keeps no passwords.
open class ASAuthorizationPasswordRequest: ASAuthorizationRequest, @unchecked Sendable {}

/// Makes saved password requests.
open class ASAuthorizationPasswordProvider: NSObject, ASAuthorizationProvider, @unchecked Sendable {
    public override init() { super.init() }
    open func createRequest() -> ASAuthorizationPasswordRequest { ASAuthorizationPasswordRequest(provider: self) }
}

/// A saved password.
open class ASPasswordCredential: NSObject, ASAuthorizationCredential, @unchecked Sendable {
    public let user: String
    public let password: String
    public init(user: String, password: String) {
        self.user = user
        self.password = password
        super.init()
    }
}

// MARK: The phone's sign-in

/// The phone's Sign in with Apple for this app: what it keeps, and the credential it makes.
enum AppleIDSignIn {
    /// "share", "hide" or "none" (the email choice of the first sign-in) once signed in.
    static var signedIn: String? { _PhonePrompts.answer("appleID") }

    static func credential(for request: ASAuthorizationAppleIDRequest, returning: Bool, name: String, hideEmail: Bool) -> ASAuthorizationAppleIDCredential {
        typealias Account = _PhonePrompts.AppleAccount
        let scopes = request.requestedScopes ?? []
        if !returning {
            _PhonePrompts.setAnswer("appleID", scopes.contains(.email) ? (hideEmail ? "hide" : "share") : "none")
        }
        let choice = signedIn ?? "none"
        let email: String? = choice == "none" ? nil : (choice == "hide" ? Account.relayEmail : Account.email)
        var fullName: PersonNameComponents?
        if !returning, scopes.contains(.fullName) {
            var components = PersonNameComponents()
            let words = name.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if let first = words.first { components.givenName = first }
            if words.count > 1 { components.familyName = words.dropFirst().joined(separator: " ") }
            fullName = components
        }
        let now = Int(Date().timeIntervalSince1970)
        let code = "c" + Account.digits("code:\(now):\(UInt64.random(in: 0...UInt64.max))", count: 32) + ".0.\(Account.digits("r", count: 4))."
            + Account.digits("code2:\(now)", count: 22)
        return ASAuthorizationAppleIDCredential(
            user: Account.userID, state: request.state, authorizedScopes: returning ? [] : scopes,
            authorizationCode: Data(code.utf8),
            identityToken: Data(token(nonce: request.nonce, email: email, private: choice == "hide", now: now).utf8),
            email: returning ? nil : email, fullName: fullName, realUserStatus: returning ? .unsupported : .likelyReal)
    }

    /// A JWT with the claims Apple's identity token carries for the app; its signature is not
    /// Apple's.
    private static func token(nonce: String?, email: String?, private isPrivate: Bool, now: Int) -> String {
        typealias Account = _PhonePrompts.AppleAccount
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let header = "{\"kid\":\"SWUIWEB1\",\"alg\":\"RS256\"}"
        var claims = [
            "\"iss\":\"https://appleid.apple.com\"", "\"aud\":" + quoted(Account.appID),
            "\"exp\":\(now + 86_400)", "\"iat\":\(now)", "\"sub\":" + quoted(Account.userID),
            "\"c_hash\":" + quoted(Account.digits("c_hash:\(now)", count: 22)),
        ]
        if let email {
            claims += ["\"email\":" + quoted(email), "\"email_verified\":true", "\"is_private_email\":\(isPrivate)"]
        }
        claims += ["\"auth_time\":\(now)", "\"nonce_supported\":true"]
        if let nonce { claims.append("\"nonce\":" + quoted(nonce)) }
        let payload = "{" + claims.joined(separator: ",") + "}"
        let signature = Data(Account.digits("sig:\(now)", count: 256).utf8)
        return base64URL(Data(header.utf8)) + "." + base64URL(Data(payload.utf8)) + "." + base64URL(signature)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
