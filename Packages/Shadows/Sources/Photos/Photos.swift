// Apple's `Photos` module for wasm (new-website#708): asking for the photo library. On the drawn
// iPhone `PHPhotoLibrary.requestAuthorization(for:)` shows iOS 27's own alert (a strip of the
// phone's photos, Select Photos, Allow Full Access, Don't Allow, or the shorter ask to add
// photos), asks once and keeps the answer between visits; Select Photos and
// `presentLimitedLibraryPicker` open the phone's photo sheet. The answers live in
// WebFoundation's `_PhotoAccess`. `PhotosPicker` never asks, as on iOS.
#if os(WASI)
import WebFoundation
import UIKit

/// Whether the app may use the photo library.
@frozen public enum PHAuthorizationStatus: Int, @unchecked Sendable {
    /// The person hasn't answered yet.
    case notDetermined = 0
    /// The app can't be given access (never on the drawn iPhone).
    case restricted = 1
    /// The person said no.
    case denied = 2
    /// Full access.
    case authorized = 3
    /// Only the photos the person picked.
    case limited = 4
}

/// What an app asks the photo library for.
@frozen public enum PHAccessLevel: Int, @unchecked Sendable {
    /// Adding photos only.
    case addOnly = 1
    /// Reading and writing.
    case readWrite = 2
}

/// The person's photo library.
open class PHPhotoLibrary: NSObject, @unchecked Sendable {
    private static let library = PHPhotoLibrary()

    /// The library every app shares.
    open class func shared() -> PHPhotoLibrary { library }

    /// The status for `accessLevel`, without asking.
    open class func authorizationStatus(for accessLevel: PHAccessLevel) -> PHAuthorizationStatus {
        status(accessLevel == .addOnly ? _PhotoAccess.addOnly : _PhotoAccess.readWrite)
    }

    /// The status for reading and writing, as before iOS 14: limited counts as authorized.
    @available(*, deprecated, message: "Use authorizationStatus(for:)")
    open class func authorizationStatus() -> PHAuthorizationStatus {
        let current = authorizationStatus(for: .readWrite)
        return current == .limited ? .authorized : current
    }

    /// Asks for `accessLevel` unless the person answered already; the handler gets the status.
    open class func requestAuthorization(for accessLevel: PHAccessLevel, handler: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        let done: @MainActor @Sendable (_PhotoAccess.Status) -> Void = { handler(status($0)) }
        if accessLevel == .addOnly { _PhotoAccess.requestAddOnly(answered: done) } else { _PhotoAccess.requestReadWrite(answered: done) }
    }

    /// Asks for `accessLevel` unless the person answered already.
    open class func requestAuthorization(for accessLevel: PHAccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requestAuthorization(for: accessLevel) { continuation.resume(returning: $0) }
        }
    }

    /// Asks for reading and writing, as before iOS 14: limited counts as authorized.
    @available(*, deprecated, message: "Use requestAuthorization(for:handler:)")
    open class func requestAuthorization(_ handler: @escaping @Sendable (PHAuthorizationStatus) -> Void) {
        requestAuthorization(for: .readWrite) { handler($0 == .limited ? .authorized : $0) }
    }

    /// Opens the photo sheet so the person can change which photos a limited app sees.
    @MainActor @preconcurrency
    open func presentLimitedLibraryPicker(from controller: UIViewController) {
        _PhotoAccess.choosePhotos { _ in }
    }

    /// Opens the photo sheet; the handler gets the ids of the photos newly picked.
    @MainActor @preconcurrency
    open func presentLimitedLibraryPicker(from controller: UIViewController, completionHandler: @escaping @Sendable ([String]) -> Void) {
        _PhotoAccess.choosePhotos { completionHandler($0) }
    }

    /// Opens the photo sheet; the ids of the photos newly picked.
    @MainActor @preconcurrency
    open func presentLimitedLibraryPicker(from controller: UIViewController) async -> [String] {
        await withCheckedContinuation { continuation in
            presentLimitedLibraryPicker(from: controller) { continuation.resume(returning: $0) }
        }
    }

    private static func status(_ access: _PhotoAccess.Status) -> PHAuthorizationStatus {
        PHAuthorizationStatus(rawValue: access.rawValue) ?? .notDetermined
    }
}
#endif
