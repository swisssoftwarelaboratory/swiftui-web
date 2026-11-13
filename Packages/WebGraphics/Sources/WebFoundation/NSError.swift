// Foundation's `NSError` and `Error.localizedDescription` on wasm (decision 0021): there is
// no Objective-C bridge, so `NSError` is a plain error class with a domain, a code and a user
// info dictionary, and every error describes itself as Foundation's would: a `LocalizedError`
// by its `errorDescription`, an `NSError` by its user info, anything else by the operation
// sentence with its type and code. `LocalizedError` is declared here, shadowing
// FoundationEssentials' (decision 0017): naming that one's protocol descriptor extracts
// CocoaError.swift and, through it, most of FoundationEssentials (3.3 MB of the Gallery).
#if os(WASI)
/// A specialized error that provides localized messages describing the error and why it occurred.
public protocol LocalizedError: Error {
    var errorDescription: String? { get }
    var failureReason: String? { get }
    var recoverySuggestion: String? { get }
    var helpAnchor: String? { get }
}

extension LocalizedError {
    public var errorDescription: String? { nil }
    public var failureReason: String? { nil }
    public var recoverySuggestion: String? { nil }
    public var helpAnchor: String? { nil }
}

#if _runtime(_ObjC)
// With an Objective-C runtime (decision 0023) `NSError` is an `NSObject`, as Foundation's is, so
// `@objc` members can take and hand back errors (a `(CustomerInfo?, NSError?) -> Void` completion).
// It describes itself through `NSObject`'s `description` (ObjectiveCBridging.swift).
open class NSError: NSObject, Error, @unchecked Sendable {
    public let domain: String
    public let code: Int
    public let userInfo: [String: Any]

    public init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo ?? [:]
        super.init()
    }
    /// An error with no domain, as `NSError()` makes on Apple platforms.
    public override convenience init() { self.init(domain: "", code: 0) }

    open var localizedDescription: String {
        if let text = userInfo[NSLocalizedDescriptionKey] as? String { return text }
        return "The operation couldn’t be completed. (\(domain) error \(code).)"
    }
    open var localizedFailureReason: String? { userInfo[NSLocalizedFailureReasonErrorKey] as? String }
    open var localizedRecoverySuggestion: String? { userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String }
    open override var description: String { localizedDescription }
}
#else
open class NSError: Error, CustomStringConvertible, @unchecked Sendable {
    public let domain: String
    public let code: Int
    public let userInfo: [String: Any]

    public init(domain: String, code: Int, userInfo: [String: Any]? = nil) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo ?? [:]
    }
    /// An error with no domain, as `NSError()` makes on Apple platforms (ButtonKit's previews
    /// throw one).
    public convenience init() { self.init(domain: "", code: 0) }

    open var localizedDescription: String {
        if let text = userInfo[NSLocalizedDescriptionKey] as? String { return text }
        return "The operation couldn’t be completed. (\(domain) error \(code).)"
    }
    open var localizedFailureReason: String? { userInfo[NSLocalizedFailureReasonErrorKey] as? String }
    open var localizedRecoverySuggestion: String? { userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String }
    public var description: String { localizedDescription }
}
#endif

extension NSError {
    /// The keys of an error's user info, which Swift spells as strings.
    public typealias UserInfoKey = String
}

public let NSLocalizedDescriptionKey = "NSLocalizedDescription"
public let NSLocalizedFailureReasonErrorKey = "NSLocalizedFailureReason"
public let NSLocalizedRecoverySuggestionErrorKey = "NSLocalizedRecoverySuggestion"
public let NSUnderlyingErrorKey = "NSUnderlyingError"
public let NSCocoaErrorDomain = "NSCocoaErrorDomain"
public let NSURLErrorDomain = "NSURLErrorDomain"
public let NSPOSIXErrorDomain = "NSPOSIXErrorDomain"
public let NSOSStatusErrorDomain = "NSOSStatusErrorDomain"
/// Cocoa's error codes apps raise themselves (the Countries app's `Loadable`, decision 0021).
public let NSUserCancelledError = 3072
public let NSFileNoSuchFileError = 4
public let NSFileReadNoSuchFileError = 260
public let NSURLErrorCancelled = -999
public let NSURLErrorNotConnectedToInternet = -1009
public let NSURLErrorTimedOut = -1001
public let NSURLErrorUnknown = -1
public let NSURLErrorBadURL = -1000
public let NSURLErrorUnsupportedURL = -1002
public let NSURLErrorCannotFindHost = -1003
public let NSURLErrorCannotConnectToHost = -1004
public let NSURLErrorNetworkConnectionLost = -1005
public let NSURLErrorDNSLookupFailed = -1006
public let NSURLErrorHTTPTooManyRedirects = -1007
public let NSURLErrorResourceUnavailable = -1008
public let NSURLErrorRedirectToNonExistentLocation = -1010
public let NSURLErrorBadServerResponse = -1011
public let NSURLErrorUserCancelledAuthentication = -1012
public let NSURLErrorUserAuthenticationRequired = -1013
public let NSURLErrorZeroByteResource = -1014
public let NSURLErrorCannotDecodeRawData = -1015
public let NSURLErrorCannotDecodeContentData = -1016
public let NSURLErrorCannotParseResponse = -1017
public let NSURLErrorInternationalRoamingOff = -1018
public let NSURLErrorCallIsActive = -1019
public let NSURLErrorDataNotAllowed = -1020
public let NSURLErrorSecureConnectionFailed = -1200
public let NSURLErrorCannotLoadFromNetwork = -2000
public let NSURLErrorFailingURLErrorKey = "NSErrorFailingURLKey"
public let NSURLErrorFailingURLStringErrorKey = "NSErrorFailingURLStringKey"
public let NSFilePathErrorKey = "NSFilePath"
public let NSHelpAnchorErrorKey = "NSHelpAnchor"
public let NSDebugDescriptionErrorKey = "NSDebugDescription"
public let NSLocalizedFailureErrorKey = "NSLocalizedFailure"

/// A localized string from the main bundle: the string catalogs are not loaded in a page, so
/// `value` (when given and not empty) else the key, as `Bundle.localizedString` answers.
public func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = .main, value: String = "", comment: String) -> String {
    bundle.localizedString(forKey: key, value: value.isEmpty ? nil : value, table: tableName)
}

extension Error {
    /// Foundation's code for a Swift error: an `NSError`'s, else the case's position in its enum (1-based when it has none).
    public var _code: Int {
        if let error = self as? NSError { return error.code }
        if let raw = (self as? any RawRepresentable)?.rawValue as? Int { return raw }
        return 1
    }
    public var _domain: String { (self as? NSError)?.domain ?? String(reflecting: type(of: self)) }

    /// What Foundation's `localizedDescription` says for this error.
    public var localizedDescription: String {
        if let error = self as? NSError { return error.localizedDescription }
        if let error = self as? any LocalizedError, let text = error.errorDescription { return text }
        return "The operation couldn’t be completed. (\(String(reflecting: type(of: self))) error \(_code).)"
    }
}
#endif
