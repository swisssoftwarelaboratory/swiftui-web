// Apple's `LocalAuthentication` module for wasm. A plain page has no Face ID, Touch ID or device
// passcode it can ask for, so a context reports that no biometry is available: `canEvaluatePolicy`
// answers false with `LAError.biometryNotAvailable` (or `.passcodeNotSet` for the owner policy) and
// `evaluatePolicy` replies false with the same error, on a later turn as Apple's does. Apps then
// take the path they already have for a device without biometry.
//
// Inside the drawn iPhone (new-website#666) the phone has Face ID, as an iPhone does: the first
// evaluation asks "Do you want to allow ... to use Face ID?" with the app's
// `NSFaceIDUsageDescription`, the answer is kept between visits, and then the Face ID badge
// shows and always recognises the face. After Don't Allow, biometrics are not available to the
// app; the owner policy would then ask for the passcode, which the phone does not draw, so it
// replies as if the person cancelled it.
#if os(WASI)
import WebFoundation

public let LAErrorDomain = "com.apple.LocalAuthentication"
public let LATouchIDAuthenticationMaximumAllowableReuseDuration: TimeInterval = 300

public enum LAPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
    case deviceOwnerAuthenticationWithWatch = 3
    case deviceOwnerAuthenticationWithBiometricsOrWatch = 4
    case deviceOwnerAuthenticationWithWristDetection = 5
}

public enum LABiometryType: Int, Sendable {
    case none = 0
    case touchID = 1
    case faceID = 2
    case opticID = 4
}

public enum LACredentialType: Int, Sendable {
    case applicationPassword = 0
}

public enum LAAccessControlOperation: Int, Sendable {
    case createItem, useItem, createKey, useKeySign, useKeyDecrypt, useKeyKeyExchange
}

/// An error from `LAContext`, with Apple's codes.
public struct LAError: Error, Hashable, Sendable, CustomNSError, LocalizedError {
    public enum Code: Int, Sendable {
        case authenticationFailed = -1
        case userCancel = -2
        case userFallback = -3
        case systemCancel = -4
        case passcodeNotSet = -5
        case biometryNotAvailable = -6
        case biometryNotEnrolled = -7
        case biometryLockout = -8
        case appCancel = -9
        case invalidContext = -10
        case watchNotAvailable = -11
        case biometryNotPaired = -12
        case biometryDisconnected = -13
        case invalidDimensions = -14
        case notInteractive = -1004

        public static let touchIDNotAvailable = Code.biometryNotAvailable
        public static let touchIDNotEnrolled = Code.biometryNotEnrolled
        public static let touchIDLockout = Code.biometryLockout

        /// `catch LAError.userCancel` and `case LAError.userCancel:` on an `Error`.
        public static func ~= (code: Code, error: any Error) -> Bool {
            if let error = error as? LAError { return error.code == code }
            let value: Any = error
            if let error = value as? NSError { return error.domain == LAErrorDomain && error.code == code.rawValue }
            return false
        }
    }

    public let code: Code

    public init(_ code: Code) { self.code = code }

    public static var errorDomain: String { LAErrorDomain }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [NSLocalizedDescriptionKey: LAError.describe(code)] }
    public var errorDescription: String? { LAError.describe(code) }

    public static let authenticationFailed = Code.authenticationFailed
    public static let userCancel = Code.userCancel
    public static let userFallback = Code.userFallback
    public static let systemCancel = Code.systemCancel
    public static let passcodeNotSet = Code.passcodeNotSet
    public static let biometryNotAvailable = Code.biometryNotAvailable
    public static let biometryNotEnrolled = Code.biometryNotEnrolled
    public static let biometryLockout = Code.biometryLockout
    public static let appCancel = Code.appCancel
    public static let invalidContext = Code.invalidContext
    public static let watchNotAvailable = Code.watchNotAvailable
    public static let biometryNotPaired = Code.biometryNotPaired
    public static let biometryDisconnected = Code.biometryDisconnected
    public static let invalidDimensions = Code.invalidDimensions
    public static let notInteractive = Code.notInteractive
    public static let touchIDNotAvailable = Code.biometryNotAvailable
    public static let touchIDNotEnrolled = Code.biometryNotEnrolled
    public static let touchIDLockout = Code.biometryLockout

    fileprivate static func describe(_ code: Code) -> String {
        switch code {
        case .biometryNotAvailable: "Biometry is not available on this device."
        case .passcodeNotSet: "A passcode is not set on this device."
        case .appCancel: "Authentication was canceled by the app."
        case .invalidContext: "The context was invalidated."
        default: "Authentication failed."
        }
    }
}

/// Where an app asks for the device owner's authentication. Nothing here can authenticate.
open class LAContext: NSObject, @unchecked Sendable {
    open var localizedFallbackTitle: String?
    open var localizedCancelTitle: String?
    open var localizedReason = ""
    open var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 0
    open var interactionNotAllowed = false
    open var biometryType: LABiometryType { _PhonePrompts.isPresent ? .faceID : .none }
    open var evaluatedPolicyDomainState: Data? { nil }
    private var invalidated = false

    public override init() { super.init() }

    /// Whether `policy` can be evaluated: never in a plain page; on the drawn iPhone, unless the
    /// app was refused Face ID and asks for biometrics alone.
    open func canEvaluatePolicy(_ policy: LAPolicy, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        if let phoneFailure = phoneFailure(for: policy) {
            if let phoneFailure {
                error?.pointee = NSError(domain: LAErrorDomain, code: phoneFailure.errorCode, userInfo: phoneFailure.errorUserInfo)
                return false
            }
            return true
        }
        let failure = failure(for: policy)
        error?.pointee = NSError(domain: LAErrorDomain, code: failure.errorCode, userInfo: failure.errorUserInfo)
        return false
    }

    /// Replies `false` with the reason on the main queue's next turn; on the drawn iPhone, Face
    /// ID's ask the first time, then its badge, then `true`.
    open func evaluatePolicy(_ policy: LAPolicy, localizedReason: String,
                             reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        if let phoneFailure = phoneFailure(for: policy) {
            if let phoneFailure { DispatchQueue.main.async { reply(false, phoneFailure) }; return }
            Self.faceIDOnPhone(policy: policy, reply: reply)
            return
        }
        let failure = failure(for: policy)
        DispatchQueue.main.async { reply(false, failure) }
    }

    open func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        if phoneFailure(for: policy) != nil {
            return try await withCheckedThrowingContinuation { continuation in
                evaluatePolicy(policy, localizedReason: localizedReason) { ok, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: ok) }
                }
            }
        }
        throw failure(for: policy)
    }

    // MARK: The drawn iPhone's Face ID (new-website#666)

    /// On the drawn iPhone, what stops `policy` (`.some(nil)`: nothing does); nil in a plain page.
    private func phoneFailure(for policy: LAPolicy) -> LAError?? {
        guard _PhonePrompts.isPresent else { return nil }
        if invalidated { return .some(LAError(.invalidContext)) }
        switch policy {
        case .deviceOwnerAuthenticationWithWatch: return .some(LAError(.watchNotAvailable))
        case .deviceOwnerAuthenticationWithBiometrics, .deviceOwnerAuthenticationWithBiometricsOrWatch:
            return _PhonePrompts.answer("faceID") == "deny" ? .some(LAError(.biometryNotAvailable)) : .some(nil)
        default:
            return .some(nil)
        }
    }

    /// Asks once ("Do you want to allow ... to use Face ID?"), then the badge, which always
    /// recognises the face. Refused, the owner policy's passcode is not drawn: a cancel.
    private static func faceIDOnPhone(policy: LAPolicy, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        let badge: @MainActor @Sendable () -> Void = {
            _PhonePrompts.show(.faceID, fallback: .done) { _ in reply(true, nil) }
        }
        switch _PhonePrompts.answer("faceID") {
        case "allow":
            Task { @MainActor in badge() }
        case "deny":
            DispatchQueue.main.async { reply(false, LAError(.userCancel)) }
        default:
            let german = _PhonePrompts.german
            let title = german ? "M\u{00F6}chtest du \(_PhonePrompts.quotedName) erlauben, Face\u{00A0}ID zu verwenden?"
                : "Do you want to allow \(_PhonePrompts.quotedName) to use Face\u{00A0}ID?"
            _PhonePrompts.show(.alert(title: title, message: _PhonePrompts.usage("NSFaceIDUsageDescription"),
                                      buttons: [_PhonePrompts.dontAllow, "OK"]), fallback: .button(0)) { answer in
                if case .button(1) = answer {
                    _PhonePrompts.setAnswer("faceID", "allow")
                    badge()
                } else {
                    _PhonePrompts.setAnswer("faceID", "deny")
                    let biometricsOnly = policy == .deviceOwnerAuthenticationWithBiometrics || policy == .deviceOwnerAuthenticationWithBiometricsOrWatch
                    reply(false, LAError(biometricsOnly ? .biometryNotAvailable : .userCancel))
                }
            }
        }
    }

    open func evaluateAccessControl(_ accessControl: Any, operation: LAAccessControlOperation, localizedReason: String,
                                    reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        let failure = invalidated ? LAError(.invalidContext) : LAError(.biometryNotAvailable)
        DispatchQueue.main.async { reply(false, failure) }
    }

    open func setCredential(_ credential: Data?, type: LACredentialType) -> Bool { false }
    open func isCredentialSet(_ type: LACredentialType) -> Bool { false }

    /// Ends the context: later evaluations fail with `.invalidContext`.
    open func invalidate() { invalidated = true }

    private func failure(for policy: LAPolicy) -> LAError {
        if invalidated { return LAError(.invalidContext) }
        switch policy {
        case .deviceOwnerAuthentication: return LAError(.passcodeNotSet)
        case .deviceOwnerAuthenticationWithWatch: return LAError(.watchNotAvailable)
        default: return LAError(.biometryNotAvailable)
        }
    }
}

#endif
