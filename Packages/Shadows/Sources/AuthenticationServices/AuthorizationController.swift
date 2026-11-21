// `ASAuthorizationController` and the Sign in with Apple buttons (new-website#707): see
// AppleID.swift for what the drawn iPhone shows.
#if os(WASI)
import SwiftUI
import UIKit
import WebFoundation

/// The window the system's sheet is presented over.
public typealias ASPresentationAnchor = UIWindow

/// Hears how an authorization ended.
@MainActor @preconcurrency
public protocol ASAuthorizationControllerDelegate: NSObjectProtocol {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization)
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error)
}

extension ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {}
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {}
}

/// Gives the window the system's sheet is presented over.
@MainActor @preconcurrency
public protocol ASAuthorizationControllerPresentationContextProviding: NSObjectProtocol {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor
}

/// Performs authorization requests: on the drawn iPhone, Sign in with Apple's sheet, then Face
/// ID; in a plain page, no account to sign in with.
open class ASAuthorizationController: NSObject, @unchecked Sendable {
    public struct RequestOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let preferImmediatelyAvailableCredentials = RequestOptions(rawValue: 1 << 0)
    }

    public let authorizationRequests: [ASAuthorizationRequest]
    open weak var delegate: (any ASAuthorizationControllerDelegate)?
    open weak var presentationContextProvider: (any ASAuthorizationControllerPresentationContextProviding)?
    open var customAuthorizationMethods: [Any] = []

    /// Controllers whose sheet is up: Apple's keeps itself alive while it asks.
    nonisolated(unsafe) private static var asking: [ObjectIdentifier: ASAuthorizationController] = [:]
    private var finished = false

    public init(authorizationRequests: [ASAuthorizationRequest]) {
        self.authorizationRequests = authorizationRequests
        super.init()
    }

    open func performRequests() { perform(immediateOnly: false) }

    open func performRequests(options: RequestOptions) {
        perform(immediateOnly: options.contains(.preferImmediatelyAvailableCredentials))
    }

    /// The keyboard's suggestions of saved passwords and passkeys: the phone keeps none.
    open func performAutoFillAssistedRequests() {}

    /// Ends an authorization in progress; the delegate hears `.canceled` once the sheet is gone.
    open func cancel() {}

    private func perform(immediateOnly: Bool) {
        let apple = authorizationRequests.compactMap { $0 as? ASAuthorizationAppleIDRequest }.first
        guard let apple, _PhonePrompts.isPresent else {
            // No Apple Account in a plain page; no saved passwords on the phone.
            fail(_PhonePrompts.isPresent ? .canceled : .unknown)
            return
        }
        let returning = AppleIDSignIn.signedIn != nil
        if immediateOnly && !returning { fail(.canceled); return }
        let scopes = apple.requestedScopes ?? []
        Self.asking[ObjectIdentifier(self)] = self
        let ask = _PhonePrompts.AppleIDAsk(returning: returning, asksName: scopes.contains(.fullName), asksEmail: scopes.contains(.email))
        _PhonePrompts.show(.appleID(ask), fallback: .cancelled) { [self] answer in
            Self.asking[ObjectIdentifier(self)] = nil
            guard case let .appleID(name, hideEmail) = answer else { finish(.failure(ASAuthorizationError(.canceled))); return }
            let credential = AppleIDSignIn.credential(for: apple, returning: returning, name: name, hideEmail: hideEmail)
            finish(.success(ASAuthorization(provider: apple.provider, credential: credential)))
        }
    }

    private func fail(_ code: ASAuthorizationError.Code) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { finish(.failure(ASAuthorizationError(code))) }
        }
    }

    @MainActor private func finish(_ result: Result<ASAuthorization, any Error>) {
        guard !finished else { return }
        finished = true
        switch result {
        case let .success(authorization): delegate?.authorizationController(controller: self, didCompleteWithAuthorization: authorization)
        case let .failure(error): delegate?.authorizationController(controller: self, didCompleteWithError: error)
        }
    }
}

// MARK: The buttons, in words only (never Apple's logo)

/// The words on a Sign in with Apple button, in the phone's language.
private func appleButtonTitle(_ kind: Int) -> String {
    let german = _PhonePrompts.german
    switch kind {
    case 1: return german ? "Mit Apple fortfahren" : "Continue with Apple"
    case 2: return german ? "Mit Apple registrieren" : "Sign up with Apple"
    default: return german ? "Mit Apple anmelden" : "Sign in with Apple"
    }
}

/// SwiftUI's Sign in with Apple button: makes the request, lets the app fill it in, performs
/// it and tells the app how it ended.
@MainActor @preconcurrency
public struct SignInWithAppleButton: View {
    public struct Label: Sendable, Equatable {
        fileprivate let kind: Int
        public static let signIn = Label(kind: 0)
        public static let `continue` = Label(kind: 1)
        public static let signUp = Label(kind: 2)
    }

    public struct Style: Sendable, Equatable {
        fileprivate let kind: Int
        public static let black = Style(kind: 0)
        public static let white = Style(kind: 1)
        public static let whiteOutline = Style(kind: 2)
    }

    private let label: Label
    nonisolated(unsafe) private let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    nonisolated(unsafe) private let onCompletion: (Result<ASAuthorization, any Error>) -> Void
    @Environment(\.signInWithAppleButtonStyle) private var style

    @preconcurrency nonisolated public init(_ label: Label = .signIn,
                                            onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
                                            onCompletion: @escaping (Result<ASAuthorization, any Error>) -> Void) {
        self.label = label
        self.onRequest = onRequest
        self.onCompletion = onCompletion
    }

    public var body: some View {
        Button(action: perform) {
            GeometryReader { proxy in
                let fill: Color = style == .black ? .black : .white
                let ink: Color = style == .black ? .white : .black
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill)
                    if style == .whiteOutline {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black, lineWidth: 1)
                    }
                    Text(verbatim: appleButtonTitle(label.kind))
                        .font(.system(size: min(max(proxy.size.height * 0.4, 12), 26), weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 140, maxWidth: 375, minHeight: 30, maxHeight: 64)
        .accessibilityLabel(Text(verbatim: appleButtonTitle(label.kind)))
    }

    private func perform() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        onRequest(request)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let hearer = _AppleButtonDelegate(onCompletion)
        controller.delegate = hearer
        _AppleButtonDelegate.alive.append(hearer)
        controller.performRequests()
    }
}

/// Hands a button's controller's ending to the app's closure.
@MainActor private final class _AppleButtonDelegate: NSObject, ASAuthorizationControllerDelegate {
    static var alive: [_AppleButtonDelegate] = []
    private let completion: (Result<ASAuthorization, any Error>) -> Void
    init(_ completion: @escaping (Result<ASAuthorization, any Error>) -> Void) { self.completion = completion }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        done(.success(authorization))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        done(.failure(error))
    }
    private func done(_ result: Result<ASAuthorization, any Error>) {
        Self.alive.removeAll { $0 === self }
        completion(result)
    }
}

private struct _SignInWithAppleButtonStyleKey: EnvironmentKey {
    static let defaultValue = SignInWithAppleButton.Style.black
}

extension EnvironmentValues {
    fileprivate var signInWithAppleButtonStyle: SignInWithAppleButton.Style {
        get { self[_SignInWithAppleButtonStyleKey.self] }
        set { self[_SignInWithAppleButtonStyleKey.self] = newValue }
    }
}

extension View {
    /// The colours of the Sign in with Apple buttons inside.
    nonisolated public func signInWithAppleButtonStyle(_ style: SignInWithAppleButton.Style) -> some View {
        environment(\.signInWithAppleButtonStyle, style)
    }
}

/// UIKit's Sign in with Apple button, in words only.
@MainActor @preconcurrency
open class ASAuthorizationAppleIDButton: UIControl {
    public enum ButtonType: Int, Sendable {
        case signIn = 0
        case `continue` = 1
        case signUp = 2
        public static let `default` = ButtonType.signIn
    }

    public enum Style: Int, Sendable {
        case white = 0
        case whiteOutline = 1
        case black = 2
    }

    open var cornerRadius: CGFloat = 6 { didSet { layer.cornerRadius = cornerRadius } }
    private let titleLabel = UILabel()
    private let buttonType: ButtonType
    private let style: Style

    public init(authorizationButtonType type: ButtonType, authorizationButtonStyle style: Style) {
        buttonType = type
        self.style = style
        super.init(frame: CGRect(x: 0, y: 0, width: 140, height: 30))
        backgroundColor = style == .black ? .black : .white
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        if style == .whiteOutline {
            layer.borderWidth = 1
            layer.borderColor = UIColor.black.cgColor
        }
        titleLabel.text = appleButtonTitle(type.rawValue)
        titleLabel.textColor = style == .black ? .white : .black
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.5
        titleLabel.isUserInteractionEnabled = false
        addSubview(titleLabel)
        accessibilityLabel = titleLabel.text
    }

    public convenience init(type: ButtonType, style: Style) {
        self.init(authorizationButtonType: type, authorizationButtonStyle: style)
    }

    public required init?(coder: NSCoder) {
        buttonType = .signIn
        style = .black
        super.init(coder: coder)
    }

    open override var intrinsicContentSize: CGSize { CGSize(width: 140, height: 30) }

    open override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel.font = .systemFont(ofSize: min(max(bounds.height * 0.4, 12), 26), weight: .medium)
        titleLabel.frame = bounds.insetBy(dx: 8, dy: 0)
    }
}
#endif
