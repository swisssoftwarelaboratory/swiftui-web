// `NSNumber` on wasm, where FoundationEssentials has none (Docs/coverage.md: 3 apps name it, in
// chart data and formatter calls). It was UIKitWeb's, for the keyboard notifications' user
// info; here every module that imports Foundation sees it. An integer keeps its exact value, a
// floating-point number its double, a boolean its truth; the accessors convert as Foundation's
// do (truncating toward zero), and numbers compare by value whatever they hold.
// Final, unlike Apple's, so a wasm build drops the methods an app never calls (the size gate).
#if os(WASI)

/// An object wrapper for primitive scalar numeric values.
public final class NSNumber: Hashable, Comparable, @unchecked Sendable, CustomStringConvertible,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    enum Storage: Sendable { case int(Int64), uint(UInt64), double(Double), bool(Bool) }
    let storage: Storage

    public init(value: Int) { storage = .int(Int64(value)) }
    public init(value: Int8) { storage = .int(Int64(value)) }
    public init(value: Int16) { storage = .int(Int64(value)) }
    public init(value: Int32) { storage = .int(Int64(value)) }
    public init(value: Int64) { storage = .int(value) }
    public init(value: UInt) { storage = .uint(UInt64(value)) }
    public init(value: UInt8) { storage = .uint(UInt64(value)) }
    public init(value: UInt16) { storage = .uint(UInt64(value)) }
    public init(value: UInt32) { storage = .uint(UInt64(value)) }
    public init(value: UInt64) { storage = .uint(value) }
    public init(value: Double) { storage = .double(value) }
    public init(value: Float) { storage = .double(Double(value)) }
    public init(value: Bool) { storage = .bool(value) }

    public convenience init(integerLiteral value: Int) { self.init(value: value) }
    public convenience init(floatLiteral value: Double) { self.init(value: value) }
    public convenience init(booleanLiteral value: Bool) { self.init(value: value) }

    public var doubleValue: Double {
        switch storage {
        case .int(let v): return Double(v)
        case .uint(let v): return Double(v)
        case .double(let v): return v
        case .bool(let v): return v ? 1 : 0
        }
    }
    public var int64Value: Int64 {
        switch storage {
        case .int(let v): return v
        case .uint(let v): return Int64(truncatingIfNeeded: v)
        case .double(let v): return !v.isFinite ? 0 : abs(v) < 9.2e18 ? Int64(v) : (v < 0 ? .min : .max)
        case .bool(let v): return v ? 1 : 0
        }
    }
    public var uint64Value: UInt64 {
        switch storage {
        case .uint(let v): return v
        default: return UInt64(truncatingIfNeeded: int64Value)
        }
    }
    public var floatValue: Float { Float(doubleValue) }
    /// The Objective-C type code of the stored value: "q" for a signed integer, "Q" for an
    /// unsigned one, "d" for a floating-point number and "c" for a boolean.
    public var objCType: UnsafePointer<CChar> {
        let code: StaticString
        switch storage {
        case .int: code = "q"
        case .uint: code = "Q"
        case .double: code = "d"
        case .bool: code = "c"
        }
        return UnsafeRawPointer(code.utf8Start).assumingMemoryBound(to: CChar.self)
    }
    public var intValue: Int { Int(truncatingIfNeeded: int64Value) }
    public var int8Value: Int8 { Int8(truncatingIfNeeded: int64Value) }
    public var int16Value: Int16 { Int16(truncatingIfNeeded: int64Value) }
    public var int32Value: Int32 { Int32(truncatingIfNeeded: int64Value) }
    public var uintValue: UInt { UInt(truncatingIfNeeded: uint64Value) }
    public var uint8Value: UInt8 { UInt8(truncatingIfNeeded: uint64Value) }
    public var uint16Value: UInt16 { UInt16(truncatingIfNeeded: uint64Value) }
    public var uint32Value: UInt32 { UInt32(truncatingIfNeeded: uint64Value) }
    public var boolValue: Bool {
        switch storage {
        case .bool(let v): return v
        default: return doubleValue != 0
        }
    }
    public var stringValue: String { description }
    /// The number as an address (Foundation's NSValue reading, used on return-address lists).
    public var pointerValue: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: uintValue) }

    public var description: String {
        switch storage {
        case .int(let v): return String(v)
        case .uint(let v): return String(v)
        case .double(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .bool(let v): return v ? "1" : "0"
        }
    }

    /// Orders this number against another by value.
    public func compare(_ otherNumber: NSNumber) -> ComparisonResult {
        if self < otherNumber { return .orderedAscending }
        if otherNumber < self { return .orderedDescending }
        return .orderedSame
    }

    public func isEqual(to number: NSNumber) -> Bool { self == number }

    public static func == (lhs: NSNumber, rhs: NSNumber) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.int(let a), .int(let b)): return a == b
        case (.uint(let a), .uint(let b)): return a == b
        default: return lhs.doubleValue == rhs.doubleValue
        }
    }

    public static func < (lhs: NSNumber, rhs: NSNumber) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.int(let a), .int(let b)): return a < b
        case (.uint(let a), .uint(let b)): return a < b
        default: return lhs.doubleValue < rhs.doubleValue
        }
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(doubleValue) }
}

extension Int {
    /// The number's value, truncated toward zero when it has a fractional part.
    public init(truncating number: NSNumber) { self = number.intValue }
}

/// Foundation's decimal number class. Here it is `NSNumber` itself, holding a double, which is
/// exact for prices and the amounts apps show (StoreKit's `SKProduct.price`). There is no bridge
/// to `Decimal`: parsing one links FoundationEssentials' locale machinery, megabytes an app pays
/// for even when it never calls it.
public typealias NSDecimalNumber = NSNumber

extension Int64 {
    public init(truncating number: NSNumber) { self = number.int64Value }
}

extension Double {
    public init(truncating number: NSNumber) { self = number.doubleValue }
}

extension Float {
    public init(truncating number: NSNumber) { self = number.floatValue }
}

extension Bool {
    public init(truncating number: NSNumber) { self = number.boolValue }
}

// MARK: - Numbers as objects (new-website#746)

// On iOS a JSON number, a property list number or any number in `Any` is an `NSNumber`, which an
// app reads either way: `value as? NSNumber`, or `value as? Double` straight from an NSNumber.
// The numeric types bridge to `NSNumber` here as they do there, so both casts work; a value comes
// out of an NSNumber only when it fits exactly, as Foundation's do (`2.5` is no `Int`, `300` no
// `UInt8`, only 0 and 1 are a `Bool`). Not with the Objective-C runtime SDK, whose `@objc` members
// would then take these numbers as Objective-C objects (ObjectiveCBridging.swift).
#if !_runtime(_ObjC)
public protocol _NSNumberBridged: _ObjectiveCBridgeable where _ObjectiveCType == NSNumber {
    init?(_exactly number: NSNumber)
    var _number: NSNumber { get }
}
extension _NSNumberBridged {
    public func _bridgeToObjectiveC() -> NSNumber { _number }
    public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Self?) { result = Self(_exactly: source) }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Self?) -> Bool {
        result = Self(_exactly: source)
        return result != nil
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Self { source.flatMap { Self(_exactly: $0) } ?? Self(_exactly: NSNumber(value: 0))! }
}
extension NSNumber {
    /// Whether it holds a floating-point value (else an integer or a boolean).
    var _isFloatingPoint: Bool { if case .double = storage { return true } else { return false } }
}
extension Double: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) {
        if n._isFloatingPoint { self = n.doubleValue; return }
        guard let exact = Double(exactly: n.int64Value) ?? Double(exactly: n.uint64Value) else { return nil }
        self = exact
    }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Float: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) {
        guard let d = Double(_exactly: n) else { return nil }
        // Foundation lets a double that is a float's nearest value through (0.1 as Float).
        guard d.isNaN || d.isInfinite || Double(Float(d)) == d || abs(d) <= Double(Float.greatestFiniteMagnitude) else { return nil }
        self = Float(d)
    }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Bool: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) {
        let d = n.doubleValue
        guard d == 0 || d == 1 else { return nil }
        self = d == 1
    }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension NSNumber {
    func _exactInteger<T: BinaryInteger>(_ type: T.Type) -> T? {
        if _isFloatingPoint { return T(exactly: doubleValue) }
        if case .uint(let v) = storage { return T(exactly: v) }
        return T(exactly: int64Value)
    }
}
extension Int: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(Int.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Int8: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(Int8.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Int16: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(Int16.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Int32: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(Int32.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension Int64: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(Int64.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension UInt: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(UInt.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension UInt8: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(UInt8.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension UInt16: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(UInt16.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension UInt32: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(UInt32.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
extension UInt64: @retroactive _ObjectiveCBridgeable, _NSNumberBridged {
    public init?(_exactly n: NSNumber) { guard let v = n._exactInteger(UInt64.self) else { return nil }; self = v }
    public var _number: NSNumber { NSNumber(value: self) }
}
#endif
#endif
