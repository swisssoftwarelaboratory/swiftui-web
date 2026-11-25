// Foundation's `Bundle` on wasm (decision 0021): FoundationEssentials has none. The app is one
// bundle whose resources are the files `scripts/assets.py` copied beside the module (asset
// catalogs by name; a package target's processed resources under the target's name), so a
// bundle made from any path answers for the app, and `Bundle.module` (SwiftPM's generated
// accessor extends `Foundation.Bundle` with it) resolves. Resource URLs are relative to the page.
#if os(WASI)
open class Bundle: @unchecked Sendable {
    /// The app's bundle.
    public static let main = Bundle(_path: "/")

    public let bundlePath: String
    public var bundleURL: URL { URL(fileURLWithPath: bundlePath) }
    public var resourcePath: String? { bundlePath }
    public var resourceURL: URL? { bundleURL }
    /// The App Store receipt: none on the web, where nothing was bought from the App Store.
    @available(*, deprecated, message: "Use AppTransaction.shared and Transaction.all from StoreKit.framework instead")
    public var appStoreReceiptURL: URL? { nil }
    public var bundleIdentifier: String? { Bundle._identifier }
    public var infoDictionary: [String: Any]? { Bundle._info }
    /// The app's languages, from its string catalogs and `.lproj` folders as the bundle's build
    /// recorded them (`scripts/assets.py`, the manifest; the browser host installs them).
    nonisolated(unsafe) public static var _hostLocalizations: (languages: [String], source: String?)?

    /// The localizations the bundle holds, as on iOS: every language of its string catalogs
    /// and `.lproj` folders (EnvironmentOverrides builds its locale picker from them, decision
    /// 0021); the development language alone when the build recorded none.
    public var localizations: [String] {
        let recorded = Self._hostLocalizations?.languages ?? []
        return recorded.isEmpty ? [developmentLocalization ?? "en"] : recorded
    }

    /// The catalogs' source language (`en` without catalogs).
    public var developmentLocalization: String? { Self._hostLocalizations?.source ?? "en" }

    /// The bundle's languages the user prefers, best first: the current locale's language
    /// where the bundle has it (a region-specific tag or its language), else the development one.
    public var preferredLocalizations: [String] {
        let current = Locale.current
        let identifier = current.identifier.replacingOccurrences(of: "_", with: "-")
        let language = current.languageCode ?? "en"
        let held = localizations
        if held.contains(identifier) { return [identifier] }
        if let match = held.first(where: { $0 == language || $0.hasPrefix(language + "-") }) { return [match] }
        return [developmentLocalization ?? held.first ?? "en"]
    }

    /// The identifier and Info dictionary the host installs (`CFBundleName` and friends).
    nonisolated(unsafe) public static var _identifier: String?
    nonisolated(unsafe) public static var _info: [String: Any]?
    /// Where a resource of the app lives relative to the page (the host's assets directory).
    nonisolated(unsafe) public static var _resourceBase = "assets/"

    public required init(_path path: String) { bundlePath = path }
    public convenience init?(path: String) { self.init(_path: path) }
    public convenience init?(url: URL) { self.init(_path: url.path) }
    public convenience init(for aClass: AnyClass) { self.init(_path: "/") }
    public convenience init?(identifier: String) { self.init(_path: "/") }

    public func object(forInfoDictionaryKey key: String) -> Any? { infoDictionary?[key] }

    /// The URL of a resource beside the app's assets: `assets/<name>.<ext>`.
    public func url(forResource name: String?, withExtension ext: String?) -> URL? {
        url(forResource: name, withExtension: ext, subdirectory: nil)
    }
    public func url(forResource name: String?, withExtension ext: String?, subdirectory: String?) -> URL? {
        guard let name else { return nil }
        var path = Bundle._resourceBase
        if let subdirectory, !subdirectory.isEmpty { path += subdirectory + "/" }
        path += name
        if let ext, !ext.isEmpty { path += "." + ext }
        let resource = String(path.dropFirst(Bundle._resourceBase.count))
        if Bundle._hostFiles != nil {
            // A file or folder the bundle doesn't have is nil, as on iOS.
            guard Bundle._isListedFile(resource) || Bundle._isListedFolder(resource) else { return nil }
            _MemoryFiles._warm(resource)
        }
        return URL(string: path)
    }
    public func path(forResource name: String?, ofType ext: String?) -> String? {
        url(forResource: name, withExtension: ext)?.relativeString
    }
    public func urls(forResourcesWithExtension ext: String?, subdirectory: String?) -> [URL]? {
        guard Bundle._hostFiles != nil else { return [] }
        let folder = subdirectory.flatMap { $0.isEmpty ? nil : $0 } ?? ""
        let names = Bundle._listedChildren(folder).filter { name in
            guard let ext, !ext.isEmpty else { return true }
            return name.hasSuffix("." + ext)
        }
        return names.compactMap { URL(string: Bundle._resourceBase + (folder.isEmpty ? "" : folder + "/") + $0) }
    }

    /// The bundle's files as its build listed them (`scripts/web-media.py`): each path under the
    /// resources as the app names it (`Celebrations/a000.heic`), with the path it is stored under
    /// (itself, or `Celebrations/a000.webp` when the build converted it). Nil when the build
    /// listed none: then every name is taken to exist, and a missing one fails when it is read.
    nonisolated(unsafe) public static var _hostFiles: [String: String]? {
        didSet { listedFolders = nil }
    }
    /// The folders of the listed files, each with the names directly inside it ("" the top).
    nonisolated(unsafe) private static var listedFolders: [String: [String]]?

    static func _isListedFile(_ resource: String) -> Bool { _hostFiles?[resource] != nil }
    static func _isListedFolder(_ resource: String) -> Bool { folders()[resource.hasSuffix("/") ? String(resource.dropLast()) : resource] != nil }
    /// The names directly inside a listed folder (files and folders), sorted.
    static func _listedChildren(_ folder: String) -> [String] { folders()[folder] ?? [] }
    /// Where a listed file is stored under the resources (its own path unless the build renamed it).
    static func _storedPath(_ resource: String) -> String { _hostFiles?[resource] ?? resource }

    private static func folders() -> [String: [String]] {
        if let listedFolders { return listedFolders }
        var made: [String: Set<String>] = [:]
        for path in (_hostFiles ?? [:]).keys {
            var parts = path.split(separator: "/").map(String.init)
            while !parts.isEmpty {
                let name = parts.removeLast()
                made[parts.joined(separator: "/"), default: []].insert(name)
            }
        }
        let sorted = made.mapValues { $0.sorted() }
        listedFolders = sorted
        return sorted
    }

    /// A localized string from the bundle's string tables (`scripts/assets.py` writes each
    /// language's `<lang>.lproj/<Table>.strings.json` from the string catalogs and `.strings`
    /// files): a `<lang>.lproj` bundle (`Bundle(path:)` of `path(forResource: "de", ofType:
    /// "lproj")`, how an app shows a language of its own choosing) reads its language's
    /// tables, any other bundle the language it prefers. Without an entry, `value`, else the key.
    public func localizedString(forKey key: String, value: String?, table: String?) -> String {
        let name = table.flatMap { $0.isEmpty ? nil : $0 } ?? "Localizable"
        if let found = Bundle._stringTable(name, in: stringFolder)?[key] { return found }
        if let value, !value.isEmpty { return value }
        return key
    }

    /// Where this bundle's tables are: its own folder for a `.lproj` bundle, else the
    /// preferred language's under the resources.
    private var stringFolder: String {
        if bundlePath.hasSuffix(".lproj") {
            let name = bundlePath.split(separator: "/").last.map(String.init) ?? bundlePath
            return Bundle._resourceBase + name
        }
        return Bundle._resourceBase + (preferredLocalizations.first ?? "en") + ".lproj"
    }

    /// The tables read so far, by path; a table the bundle lacks is remembered as nil.
    nonisolated(unsafe) private static var stringTables: [String: [String: String]?] = [:]

    private static func _stringTable(_ name: String, in folder: String) -> [String: String]? {
        let path = folder + "/" + name + ".strings.json"
        if let known = stringTables[path] { return known }
        // Only a language the build recorded has tables (no request, and no 404, for the rest).
        let language = String(folder.dropFirst(_resourceBase.count).dropLast(".lproj".count))
        guard _hostLocalizations?.languages.contains(language) ?? false else {
            stringTables[path] = .some(nil)
            return nil
        }
        var table: [String: String]?
        if let url = URL(string: path), let data = try? Data(contentsOf: url) {
            table = try? JSONDecoder().decode([String: String].self, from: data)
        }
        stringTables[path] = table
        return table
    }
}
#endif
