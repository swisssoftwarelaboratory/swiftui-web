// Key-value coding on NSObject where there is an Objective-C runtime (decision 0023): Foundation
// declares `value(forKey:)` and `setValue(_:forKey:)` on every object in a category, so code
// calls them on `AnyObject` as well as on its own classes (swift-issue-reporting's XCTest
// shims read an issue's `type` and set an option's `issueMatcher` that way). The runtime's own
// header has no such category, so without these the call does not compile.
//
// A key reads the stored property of that name (the object's own, then its superclasses'), as
// Foundation's accessor search finds a property's instance variable. A key the object has no
// property for goes to `value(forUndefinedKey:)`, which stops as Foundation's exception does;
// a class overrides it, and the setter's `setValue(_:forUndefinedKey:)`, to answer for itself.
// Setting goes through the property's Objective-C setter (`setName:`) when the value is an
// object or bridges to one, as the setter then takes one; for any other value this module
// cannot call the setter without its signature (a wrong one traps on wasm), so a class set by
// key with one overrides `setValue(_:forKey:)`.
#if os(WASI) && _runtime(_ObjC)
import ObjectiveC

extension NSObject {
    /// The value of the stored property named `key`.
    @objc open func value(forKey key: String) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children where child.label == key || child.label == "_" + key {
                return _unwrappedOptional(child.value)
            }
            mirror = current.superclassMirror
        }
        return value(forUndefinedKey: key)
    }

    /// Sets the property named `key` through its setter, for an object value (or nil).
    @objc open func setValue(_ value: Any?, forKey key: String) {
        guard let first = key.first else { return setValue(value, forUndefinedKey: key) }
        let setter = NSSelectorFromString("set" + first.uppercased() + key.dropFirst() + ":")
        guard responds(to: setter), value.map(_isObjectArgument) ?? true else {
            return setValue(value, forUndefinedKey: key)
        }
        _ = perform(setter, with: value)
    }

    /// Called for a key with no property: stops, as Foundation raises `NSUndefinedKeyException`.
    @objc open func value(forUndefinedKey key: String) -> Any? {
        fatalError("[<\(type(of: self))> valueForUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
    }

    /// Called for a key that cannot be set: stops, as Foundation raises `NSUndefinedKeyException`.
    @objc open func setValue(_ value: Any?, forUndefinedKey key: String) {
        fatalError("[<\(type(of: self))> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key \(key).")
    }
}

/// Whether `value` reaches an Objective-C setter as an object: a class instance, or a value that
/// bridges to one (`String`, arrays, dates and the rest, ObjectiveCBridging.swift).
private func _isObjectArgument(_ value: Any) -> Bool {
    type(of: value) is AnyClass || value is any _ObjectiveCBridgeable
}

/// `value`, or nil when it is an empty optional (a property of optional type that is nil).
private func _unwrappedOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return value }
    return mirror.children.first.map(\.value)
}
#endif
