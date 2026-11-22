// The photo library's own ask on the drawn iPhone (new-website#708), as iOS 27 asks it
// (traced in the iOS 27.0 simulator, English and German): the Photos framework's
// `PHPhotoLibrary` calls these, and the drawn iPhone shows the alerts through `_PhonePrompts`.
//
// iOS keeps two answers per app. Full access (read and write) answers Select Photos (limited
// to the photos picked then), Allow Full Access, or Don't Allow; once the app may add photos,
// its last button reads Keep Add Only, which also says no to full access. Adding only answers
// Allow or Don't Allow, and is asked even after full access was refused or limited; full
// access allows adding without asking. The photos Select Photos picked are kept with the
// answers, so a fresh install forgets them too (new-website#709).

/// What the drawn iPhone answers when an app asks for its photo library.
public enum _PhotoAccess {
    /// `PHAuthorizationStatus`'s raw values.
    public enum Status: Int, Sendable {
        case notDetermined = 0, restricted = 1, denied = 2, authorized = 3, limited = 4
    }

    static let fullKey = "photos"
    static let addKey = "photos.add"
    static let selectedKey = "photos.selected"

    /// Full access as kept: nil never asked, else "full", "limited" or "deny".
    static var full: String? { _PhonePrompts.answer(fullKey) }

    /// The status for reading and writing.
    public static var readWrite: Status {
        switch full {
        case "full": .authorized
        case "limited": .limited
        case "deny": .denied
        default: .notDetermined
        }
    }

    /// The status for adding only: full access allows it too.
    public static var addOnly: Status {
        if full == "full" { return .authorized }
        switch _PhonePrompts.allowed(addKey) {
        case true?: return .authorized
        case false?: return .denied
        case nil: return .notDetermined
        }
    }

    /// The photos the app may see while limited (ids in the drawn phone's library).
    public static var selected: [String] {
        guard let kept = _PhonePrompts.answer(selectedKey), !kept.isEmpty else { return [] }
        return kept.split(separator: "\n").map(String.init)
    }

    static func keepSelected(_ ids: [String]) {
        _PhonePrompts.setAnswer(selectedKey, ids.joined(separator: "\n"))
    }

    /// Asks for full access unless it was answered, keeps the answer, and hands on the status.
    /// Select Photos opens the photo sheet before answering, as on iOS.
    public static func requestReadWrite(answered: @escaping @MainActor @Sendable (Status) -> Void) {
        if readWrite != .notDetermined { let known = readWrite; Task { @MainActor in answered(known) }; return }
        let afterAdd = _PhonePrompts.allowed(addKey) == true
        let buttons = [selectPhotos, allowFullAccess, afterAdd ? keepAddOnly : _PhonePrompts.dontAllow]
        let prompt = _PhonePrompts.Ask.photoLibrary(title: afterAdd ? fullAccessTitle : accessTitle,
                                                    message: _PhonePrompts.usage("NSPhotoLibraryUsageDescription"), buttons: buttons)
        // Without a drawn iPhone nothing asks: a plain page's photos are the picker's, open to all.
        _PhonePrompts.askOnce(fullKey, prompt, fallback: 1) { index in
            guard readWrite == .notDetermined else { answered(readWrite); return }
            switch index {
            case 0:
                _PhonePrompts.setAnswer(fullKey, "limited")
                keepSelected([])
                choosePhotos { _ in answered(readWrite) }
            case 1:
                _PhonePrompts.setAnswer(fullKey, "full")
                answered(readWrite)
            default:
                _PhonePrompts.setAnswer(fullKey, "deny")
                answered(readWrite)
            }
        }
    }

    /// Asks to add photos unless that was answered (or full access allows it).
    public static func requestAddOnly(answered: @escaping @MainActor @Sendable (Status) -> Void) {
        if addOnly != .notDetermined { let known = addOnly; Task { @MainActor in answered(known) }; return }
        let message = _PhonePrompts.usage("NSPhotoLibraryAddUsageDescription")
        _PhonePrompts.askOnce(addKey, .alert(title: addTitle, message: message, buttons: [_PhonePrompts.dontAllow, _PhonePrompts.allow]), fallback: 1) { index in
            if addOnly == .notDetermined { _PhonePrompts.setAnswer(addKey, index == 1 ? "allow" : "deny") }
            answered(addOnly)
        }
    }

    /// Opens the photo sheet with the photos picked so far marked, and keeps what is marked
    /// when it closes (`presentLimitedLibraryPicker`). Only while limited; otherwise nothing
    /// opens and the answer is empty, as on iOS.
    public static func choosePhotos(answered: @escaping @MainActor @Sendable ([String]) -> Void) {
        guard readWrite == .limited else { Task { @MainActor in answered([]) }; return }
        let before = selected
        _PhonePrompts.show(.selectPhotos(selected: before), fallback: .photos(before)) { answer in
            var ids = before
            if case let .photos(marked) = answer { ids = marked }
            keepSelected(ids)
            answered(ids.filter { !before.contains($0) })
        }
    }

    // MARK: The words iOS 27 uses

    private static var german: Bool { _PhonePrompts.german }
    private static var name: String { _PhonePrompts.quotedName }

    static var accessTitle: String {
        german ? "Darf \(name) auf deine Fotomediathek zugreifen?" : "Allow \(name) to access your photo library?"
    }

    /// After adding was allowed. iOS 27's German has no space after "Darf" here.
    static var fullAccessTitle: String {
        german ? "Darf\(name) auf deine gesamte Fotomediathek zugreifen?" : "Allow \(name) full access to your photo library?"
    }

    static var addTitle: String {
        german ? "Darf \(name) Fotos und Videos zu deiner Fotomediathek hinzuf\u{00FC}gen?"
            : "Allow \(name) to add photos and videos to your photo library?"
    }

    static var selectPhotos: String { german ? "Fotos ausw\u{00E4}hlen" : "Select Photos" }
    static var allowFullAccess: String { german ? "Vollen Zugriff erlauben" : "Allow Full Access" }
    static var keepAddOnly: String { german ? "Weiterhin nur Zugriff zum Hinzuf\u{00FC}gen" : "Keep Add Only" }

    /// The line under the photo strip's count.
    public static var metadataLine: String {
        german ? "Fotos k\u{00F6}nnen Daten zu Standort, Farbtiefe, Untertitel und Audio enthalten."
            : "Photos may contain data associated with location, depth information, captions, and audio."
    }

    /// The count under the strip. iOS 27 leaves it in English in German too.
    public static func countLine(_ count: Int) -> String {
        count == 1 ? "1 Photo" : "\(count) Photos"
    }
}
