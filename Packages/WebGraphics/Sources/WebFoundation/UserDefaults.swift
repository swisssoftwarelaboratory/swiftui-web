// Foundation's `UserDefaults` on wasm (decision 0021): FoundationEssentials has none. A
// dictionary of the property-list scalars apps store (strings, numbers, booleans, data, arrays
// and dictionaries of them), kept in memory and handed to the host as JSON after every change
// (`_hostStore`: the browser host keeps it in localStorage under the suite's name); registered
// defaults answer for missing keys as Foundation's do.
#if os(WASI)
public final class UserDefaults: @unchecked Sendable {
    /// The app's defaults.
    public static let standard = UserDefaults(suite: nil)
    public static let didChangeNotification = Notification.Name("NSUserDefaultsDidChangeNotification")

    /// Where a suite's values live between loads: the host installs one before the app runs.
    nonisolated(unsafe) public static var _hostStore: (load: (String) -> String?, save: (String, String) -> Void)?

    public let _suiteName: String
    private var values: [String: _Value] = [:]
    private var registered: [String: _Value] = [:]
    private var loaded = false

    private init(suite: String?) { _suiteName = suite ?? "standard" }
    public convenience init?(suiteName: String?) {
        if suiteName == nil { return nil }
        self.init(suite: suiteName)
    }

    // MARK: Reading

    public func object(forKey key: String) -> Any? { _stored(forKey: key)?.any }
    /// Key-value coding's read, which on Apple's platforms answers as `object(forKey:)`.
    public func value(forKey key: String) -> Any? { object(forKey: key) }
    public func string(forKey key: String) -> String? {
        switch _stored(forKey: key) {
        case .string(let s)?: return s
        case .int(let i)?: return String(i)
        case .double(let d)?: return String(d)
        case .bool(let b)?: return b ? "1" : "0"
        default: return nil
        }
    }
    public func integer(forKey key: String) -> Int {
        switch _stored(forKey: key) {
        case .int(let i)?: return i
        case .double(let d)?: return Int(d)
        case .bool(let b)?: return b ? 1 : 0
        case .string(let s)?: return Int(s) ?? Int(Double(s) ?? 0)
        default: return 0
        }
    }
    public func double(forKey key: String) -> Double {
        switch _stored(forKey: key) {
        case .int(let i)?: return Double(i)
        case .double(let d)?: return d
        case .bool(let b)?: return b ? 1 : 0
        case .string(let s)?: return Double(s) ?? 0
        default: return 0
        }
    }
    public func float(forKey key: String) -> Float { Float(double(forKey: key)) }
    public func bool(forKey key: String) -> Bool {
        switch _stored(forKey: key) {
        case .bool(let b)?: return b
        case .int(let i)?: return i != 0
        case .double(let d)?: return d != 0
        case .string(let s)?: return ["1", "true", "YES", "yes"].contains(s)
        default: return false
        }
    }
    public func data(forKey key: String) -> Data? { if case .data(let d)? = _stored(forKey: key) { return d } else { return nil } }
    public func url(forKey key: String) -> URL? { string(forKey: key).flatMap { URL(string: $0) } }
    public func array(forKey key: String) -> [Any]? { if case .array(let a)? = _stored(forKey: key) { return a.map(\.any) } else { return nil } }
    public func stringArray(forKey key: String) -> [String]? {
        guard case .array(let a)? = _stored(forKey: key) else { return nil }
        var strings: [String] = []
        for element in a { if case .string(let s) = element { strings.append(s) } else { return nil } }
        return strings
    }
    public func dictionary(forKey key: String) -> [String: Any]? { if case .dictionary(let d)? = _stored(forKey: key) { return d.mapValues(\.any) } else { return nil } }
    public func dictionaryRepresentation() -> [String: Any] {
        load()
        return registered.merging(values) { $1 }.merging(arguments) { $1 }.mapValues(\.any)
    }

    // MARK: Writing

    public func set(_ value: Any?, forKey key: String) {
        load()
        if let value, let stored = _Value(value) { values[key] = stored } else { values[key] = nil }
        save()
    }
    public func set(_ value: Int, forKey key: String) { set(value as Any, forKey: key) }
    public func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
    public func set(_ value: Float, forKey key: String) { set(Double(value) as Any, forKey: key) }
    public func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
    public func set(_ url: URL?, forKey key: String) { set(url?.absoluteString as Any?, forKey: key) }
    public func removeObject(forKey key: String) { set(nil, forKey: key) }
    /// Key-value coding's write, which on Apple's platforms stores as `set(_:forKey:)`.
    public func setValue(_ value: Any?, forKey key: String) { set(value, forKey: key) }
    public func register(defaults: [String: Any]) {
        for (key, value) in defaults { if let stored = _Value(value) { registered[key] = stored } }
    }
    @discardableResult public func synchronize() -> Bool { true }
    public func removePersistentDomain(forName name: String) { values.removeAll(); save() }

    // MARK: Storage

    private func _stored(forKey key: String) -> _Value? {
        load()
        return arguments[key] ?? values[key] ?? registered[key]
    }

    /// The argument domain: `-key value` pairs among the launch arguments answer first in the
    /// standard defaults, above anything stored, and are never saved, as on Apple's platforms
    /// (`simctl launch <app> -screen settings`). The browser host takes the arguments from the
    /// page (`?args=`). Values stay strings, which the typed readers convert.
    private lazy var arguments: [String: _Value] = {
        guard _suiteName == "standard" else { return [:] }
        var domain: [String: _Value] = [:]
        let launch = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i + 1 < launch.count {
            let flag = launch[i]
            if flag.count > 1, flag.hasPrefix("-"), !flag.hasPrefix("--") {
                domain[String(flag.dropFirst())] = .string(launch[i + 1])
                i += 2
            } else {
                i += 1
            }
        }
        return domain
    }()

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let text = UserDefaults._hostStore?.load(_suiteName),
              let stored = try? _TransferJSONDecoder().decode([String: _Value].self, from: Data(text.utf8)) else { return }
        values = stored
    }

    private func save() {
        guard let store = UserDefaults._hostStore, let data = try? _TransferJSONEncoder().encode(values) else { return }
        store.save(_suiteName, String(decoding: data, as: UTF8.self))
    }

    /// A property-list value: what Foundation's defaults accept.
    public indirect enum _Value: Codable, Equatable {
        case string(String), int(Int), double(Double), bool(Bool), data(Data), date(Date)
        case array([_Value]), dictionary([String: _Value])

        init?(_ any: Any) {
            switch any {
            case let v as String: self = .string(v)
            case let v as Bool: self = .bool(v)
            case let v as Int: self = .int(v)
            case let v as Double: self = .double(v)
            case let v as Float: self = .double(Double(v))
            case let v as Data: self = .data(v)
            case let v as Date: self = .date(v)
            case let v as URL: self = .string(v.absoluteString)
            case let v as [Any]:
                var elements: [_Value] = []
                for element in v { guard let e = _Value(element) else { return nil }; elements.append(e) }
                self = .array(elements)
            case let v as [String: Any]:
                var entries: [String: _Value] = [:]
                for (key, element) in v { guard let e = _Value(element) else { return nil }; entries[key] = e }
                self = .dictionary(entries)
            default: return nil
            }
        }

        var any: Any {
            switch self {
            case .string(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            case .bool(let v): return v
            case .data(let v): return v
            case .date(let v): return v
            case .array(let v): return v.map(\.any)
            case .dictionary(let v): return v.mapValues(\.any)
            }
        }
    }
}
#endif
