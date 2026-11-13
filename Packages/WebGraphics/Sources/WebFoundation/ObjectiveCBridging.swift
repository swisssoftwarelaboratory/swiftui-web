// Collections and Foundation values crossing into Objective-C (decision 0023, v1.5 bridging).
//
// With the interop SDK an `@objc` member may only take and return types the compiler can
// represent in Objective-C: classes rooted at `NSObject`, and value types that conform to
// `_ObjectiveCBridgeable`. Apple's Foundation conforms `Array`, `Dictionary`, `Set`, `Date`,
// `URL`, `Data` and `UUID` to it, over `NSArray`, `NSDictionary` and the rest; there is no such
// Foundation here, so each type bridges to a small object of this module that holds the Swift
// value (`String` bridges in NSRegularExpression.swift). Objective-C code cannot read these
// objects as Foundation's classes; they carry values between Swift `@objc` members, whose
// caller bridges an argument in and whose body bridges it straight back out.
//
// The objects are named with an underscore: WebFoundationFormats gives some of them Foundation's
// names (`NSDictionary`, `NSSet`) as typealiases, `NSDate` is Core Data's spelling of `Date` here
// (WebCoreData, Values.swift), and the compiler reads some Foundation class names in the module
// named Foundation as Apple's Foundation being present (`NSString`, NSRegularExpression.swift).
#if os(WASI) && _runtime(_ObjC)

/// The object an array becomes in Objective-C: its elements, each as `Any`.
public final class _WebNSArray: NSObject, @unchecked Sendable {
    public let elements: [Any]
    public init(elements: [Any]) {
        self.elements = elements
        super.init()
    }
    public var count: Int { elements.count }
}

/// The object a dictionary becomes in Objective-C: its keys as `AnyHashable`, values as `Any`.
/// Foundation's `NSDictionary` (WebFoundationFormats names it so and gives it its members), open
/// for `NSMutableDictionary`. Equal when the entries are, as Foundation's are.
open class _WebNSDictionary: NSObject, @unchecked Sendable {
    public var entries: [AnyHashable: Any]
    public init(entries: [AnyHashable: Any]) {
        self.entries = entries
        super.init()
    }
    public override convenience init() { self.init(entries: [:]) }
    public var count: Int { entries.count }
    /// The value for the key, or nil (`object(forKey:)`).
    open subscript(key: Any) -> Any? { (key as? AnyHashable).flatMap { entries[$0] } }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? _WebNSDictionary else { return false }
        return _webEntriesEqual(entries, other.entries)
    }
    open override var hash: Int { entries.count }
}

/// The object a set becomes in Objective-C: its members as `AnyHashable`. Foundation's `NSSet`
/// (WebFoundationFormats names it so and gives it its members). Equal when the members are.
open class _WebNSSet: NSObject, ExpressibleByArrayLiteral, @unchecked Sendable {
    public var members: [AnyHashable]
    public init(members: [AnyHashable]) {
        self.members = members
        super.init()
    }
    public override convenience init() { self.init(members: []) }
    public required convenience init(arrayLiteral elements: Any...) { self.init(members: _WebSetMember.distinct(elements)) }
    public var count: Int { members.count }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? _WebNSSet else { return false }
        return Set(members) == Set(other.members)
    }
    open override var hash: Int { members.count }
}

/// The object a value type becomes in Objective-C (`Date`, `URL`, `Data`, `UUID`): the value
/// itself, as Foundation's `NSNumber` stands for every number type. Open so that Foundation's own
/// classes for those values (`NSURL`, `NSUUID`, `NSData`, WebFoundationFormats) are kinds of it,
/// and `nsURL as URL` bridges as it does on Apple platforms.
open class _WebNSValue: NSObject, @unchecked Sendable {
    private let _value: Any
    /// The value this object stands for.
    open var value: Any { _value }
    public init(_ value: Any) {
        _value = value
        super.init()
    }
    public override init() {
        _value = ()
        super.init()
    }
}

/// Whether two dictionaries hold equal entries, as `NSDictionary.isEqual(to:)` compares them.
public func _webEntriesEqual(_ lhs: [AnyHashable: Any], _ rhs: [AnyHashable: Any]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, value) in lhs {
        guard let other = rhs[key], _webValuesEqual(value, other) else { return false }
    }
    return true
}

/// Whether two values Foundation's collections hold are equal: as hashables, else as objects.
public func _webValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    if let left = lhs as? AnyHashable, let right = rhs as? AnyHashable { return left == right }
    if let left = lhs as? NSObject, let right = rhs as? NSObject { return left.isEqual(right) }
    return false
}

/// A key back to the dictionary's or set's own key type: the boxed value, else the hashable itself.
@inline(__always)
func _webUnbox<Key>(_ key: AnyHashable, as type: Key.Type) -> Key? {
    if let unboxed = key.base as? Key { return unboxed }
    return key as? Key
}

extension Array: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSArray
    public func _bridgeToObjectiveC() -> _WebNSArray { _WebNSArray(elements: map { $0 as Any }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSArray, result: inout [Element]?) {
        result = source.elements.map { $0 as! Element }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSArray, result: inout [Element]?) -> Bool {
        var converted: [Element] = []
        converted.reserveCapacity(source.elements.count)
        for element in source.elements {
            guard let typed = element as? Element else { result = nil; return false }
            converted.append(typed)
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSArray?) -> [Element] {
        source?.elements.map { $0 as! Element } ?? []
    }
}

extension Dictionary: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSDictionary
    public func _bridgeToObjectiveC() -> _WebNSDictionary {
        var entries: [AnyHashable: Any] = [:]
        entries.reserveCapacity(count)
        for (key, value) in self { entries[AnyHashable(key)] = value }
        return _WebNSDictionary(entries: entries)
    }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSDictionary, result: inout [Key: Value]?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an Objective-C dictionary's entries are not \(Key.self): \(Value.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSDictionary, result: inout [Key: Value]?) -> Bool {
        var converted: [Key: Value] = [:]
        converted.reserveCapacity(source.entries.count)
        for (key, value) in source.entries {
            guard let typedKey = _webUnbox(key, as: Key.self), let typedValue = value as? Value else { result = nil; return false }
            converted[typedKey] = typedValue
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSDictionary?) -> [Key: Value] {
        guard let source else { return [:] }
        var result: [Key: Value]?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result ?? [:]
    }
}

extension Set: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSSet
    public func _bridgeToObjectiveC() -> _WebNSSet { _WebNSSet(members: map { AnyHashable($0) }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an Objective-C set's members are not \(Element.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) -> Bool {
        var converted = Set<Element>(minimumCapacity: source.members.count)
        for member in source.members {
            guard let typed = _webUnbox(member, as: Element.self) else { result = nil; return false }
            converted.insert(typed)
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSSet?) -> Set<Element> {
        guard let source else { return [] }
        var result: Set<Element>?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result ?? []
    }
}

/// `description` on every object, as Foundation gives `NSObject`: the runtime's header declares
/// it with Foundation's `NSString`, which this SDK does not define, so the compiler leaves it out
/// and an app's `override var description` overrode nothing (RevenueCat's model classes). The
/// header's selector is still taken, so this one has a selector of its own; subclasses override
/// it by name, as they do Foundation's, and Swift's `String(describing:)` reads it. Where a module
/// named Foundation is loaded the compiler would import the header's too; the SDK's API notes
/// (scripts/objc-sdk) name that one `__description`, so this stays the only `description`.
extension NSObject: @retroactive CustomStringConvertible, @retroactive CustomDebugStringConvertible {
    @objc(_webDescription) open var description: String {
        "<\(type(of: self)): 0x\(String(UInt(bitPattern: ObjectIdentifier(self).hashValue), radix: 16))>"
    }
    @objc(_webDebugDescription) open var debugDescription: String { description }
}

/// A value type that bridges as itself in a `_WebNSValue`.
public protocol _WebValueBridged: _ObjectiveCBridgeable where _ObjectiveCType == _WebNSValue {}

extension _WebValueBridged {
    public func _bridgeToObjectiveC() -> _WebNSValue { _WebNSValue(self) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSValue, result: inout Self?) { result = (source.value as! Self) }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSValue, result: inout Self?) -> Bool {
        result = source.value as? Self
        return result != nil
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSValue?) -> Self { source!.value as! Self }
}

extension Date: @retroactive _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }
// URL, UUID and Data bridge to their own classes, `NSURL`, `NSUUID` and `NSData`
// (WebFoundationFormats), so `url as NSURL` converts as it does on Apple platforms.

#endif
