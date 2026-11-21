// Signs in with Apple as apps do: the SwiftUI button asking for the name and email, and a
// controller of the app's own for a returning sign-in, then shows what came back.
import AuthenticationServices
import Foundation
import SwiftUI

@main
struct AppleSignInApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var account = Account()
    @State private var controllerDelegate: ControllerDelegate?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = "n-0S6_WzA2Mj"
                    } onCompletion: { result in
                        account.take(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    Button("Sign in with a controller") { signInWithController() }
                    Button("Check the account") { check() }
                }
                Section("Result") {
                    LabeledContent("Outcome", value: account.outcome)
                    LabeledContent("User", value: account.user)
                    LabeledContent("Name", value: account.name)
                    LabeledContent("Email", value: account.email)
                    LabeledContent("Scopes", value: account.scopes)
                    LabeledContent("State", value: account.state)
                }
            }
            .navigationTitle("Sign in")
        }
    }

    private func signInWithController() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = ControllerDelegate { account.take($0) }
        controller.delegate = delegate
        controllerDelegate = delegate
        controller.performRequests()
    }

    private func check() {
        let user = account.userID ?? ""
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: user) { state, _ in
            let words = switch state {
            case .authorized: "authorized"
            case .revoked: "revoked"
            case .notFound: "not found"
            case .transferred: "transferred"
            @unknown default: "?"
            }
            Task { @MainActor in account.state = words }
        }
    }
}

final class ControllerDelegate: NSObject, ASAuthorizationControllerDelegate {
    let done: (Result<ASAuthorization, Error>) -> Void
    init(_ done: @escaping (Result<ASAuthorization, Error>) -> Void) { self.done = done }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        done(.success(authorization))
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        done(.failure(error))
    }
}

@Observable final class Account {
    var outcome = "-"
    var user = "-"
    var userID: String?
    var name = "-"
    var email = "-"
    var scopes = "-"
    var state = "-"

    func take(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { outcome = "other credential"; return }
            outcome = "signed in"
            userID = credential.user
            user = String(credential.user.prefix(14)) + "…"
            name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            if credential.fullName == nil { name = "none" }
            email = credential.email ?? "none"
            scopes = credential.authorizedScopes.map(\.rawValue).joined(separator: ", ")
            if scopes.isEmpty { scopes = "none" }
        case let .failure(error):
            if case ASAuthorizationError.canceled = error { outcome = "cancelled" } else { outcome = "error \((error as NSError).code)" }
        }
    }
}
