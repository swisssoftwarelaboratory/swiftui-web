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
        return URL(string: path)
    }
    public func path(forResource name: String?, ofType ext: String?) -> String? {
        url(forResource: name, withExtension: ext)?.relativeString
    }
    public func urls(forResourcesWithExtension ext: String?, subdirectory: String?) -> [URL]? { [] }

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
