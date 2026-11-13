// `NSUbiquitousKeyValueStore` where Foundation has none (wasm, and Linux's Foundation): the
// iCloud key-value store apps keep small settings in beside `@AppStorage` (Docs/coverage.md:
// 3 apps). There is no iCloud here, so the store is local: a defaults suite of its own, which
// the browser host keeps in localStorage as it does `UserDefaults.standard`. Nothing ever
// changes it externally, so `didChangeExternallyNotification` is never posted.
// Final, unlike Apple's, so a wasm build drops the methods an app never calls (the size gate).
#if !canImport(Darwin)
#if !os(WASI)
import Foundation
#endif

/// An iCloud-based container of key-value pairs you use to share data among instances of your
/// app running on a person's connected devices.
#if _runtime(_ObjC)
// An object of the runtime where there is one (decision 0023), so `#selector(synchronize)` names
// it: CloudStorage observes `willEnterForegroundNotification` with that selector.
public final class NSUbiquitousKeyValueStore: NSObject, @unchecked Sendable {
    fileprivate let defaults = UserDefaults(suiteName: "NSUbiquitousKeyValueStore") ?? .standard

    public override init() { super.init() }

    /// Writes in-memory keys and values to disk: they already are, so this answers true.
    @objc @discardableResult
    public func synchronize() -> Bool { true }
}
#else
public final class NSUbiquitousKeyValueStore: @unchecked Sendable {
    fileprivate let defaults = UserDefaults(suiteName: "NSUbiquitousKeyValueStore") ?? .standard

    public init() {}

    /// Writes in-memory keys and values to disk: they already are, so this answers true.
    @discardableResult
    public func synchronize() -> Bool { true }
}
#endif

extension NSUbiquitousKeyValueStore {
    /// The shared iCloud key-value store object.
    public static let `default` = NSUbiquitousKeyValueStore()

    /// Posted when the value of one or more keys in the local key-value store changed due to
    /// incoming data pushed from iCloud.
    public static let didChangeExternallyNotification = Notification.Name("NSUbiquitousKeyValueStoreDidChangeExternallyNotification")

    public func object(forKey aKey: String) -> Any? { defaults.object(forKey: aKey) }
    public func set(_ anObject: Any?, forKey aKey: String) { defaults.set(anObject, forKey: aKey) }
    public func removeObject(forKey aKey: String) { defaults.removeObject(forKey: aKey) }

    public func string(forKey aKey: String) -> String? { defaults.string(forKey: aKey) }
    public func array(forKey aKey: String) -> [Any]? { defaults.array(forKey: aKey) }
    public func dictionary(forKey aKey: String) -> [String: Any]? { defaults.dictionary(forKey: aKey) }
    public func data(forKey aKey: String) -> Data? { defaults.data(forKey: aKey) }
    public func longLong(forKey aKey: String) -> Int64 { Int64(defaults.integer(forKey: aKey)) }
    public func double(forKey aKey: String) -> Double { defaults.double(forKey: aKey) }
    public func bool(forKey aKey: String) -> Bool { defaults.bool(forKey: aKey) }

    public func set(_ aString: String?, forKey aKey: String) { defaults.set(aString, forKey: aKey) }
    public func set(_ aData: Data?, forKey aKey: String) { defaults.set(aData, forKey: aKey) }
    public func set(_ anArray: [Any]?, forKey aKey: String) { defaults.set(anArray, forKey: aKey) }
    public func set(_ aDictionary: [String: Any]?, forKey aKey: String) { defaults.set(aDictionary, forKey: aKey) }
    public func set(_ value: Int64, forKey aKey: String) { defaults.set(Int(value), forKey: aKey) }
    public func set(_ value: Double, forKey aKey: String) { defaults.set(value, forKey: aKey) }
    public func set(_ value: Bool, forKey aKey: String) { defaults.set(value, forKey: aKey) }

    /// Every key and value in the store.
    public var dictionaryRepresentation: [String: Any] {
        var all: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where defaults.object(forKey: key) != nil { all[key] = value }
        return all
    }
}

/// The user-info key whose value says why the store changed externally.
public let NSUbiquitousKeyValueStoreChangeReasonKey = "NSUbiquitousKeyValueStoreChangeReasonKey"
/// The user-info key whose value lists the keys that changed.
public let NSUbiquitousKeyValueStoreChangedKeysKey = "NSUbiquitousKeyValueStoreChangedKeysKey"
/// The value changed on another device.
public let NSUbiquitousKeyValueStoreServerChange = 0
/// The store was first synchronized with iCloud.
public let NSUbiquitousKeyValueStoreInitialSyncChange = 1
/// The app's iCloud quota was exceeded.
public let NSUbiquitousKeyValueStoreQuotaViolationChange = 2
/// The iCloud account changed.
public let NSUbiquitousKeyValueStoreAccountChange = 3
#endif
