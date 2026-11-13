// Names Apple's Foundation brings with the Objective-C runtime, for the stock wasm SDK, where
// there is none: `NSClassFromString` (RevenueCat looks up the ad-support classes by name and
// does without them when they are missing) and the `NSInteger` and `NSUInteger` aliases
// (Kingfisher's display link protocol); `autoreleasepool` is in Threading.swift. With the
// Objective-C runtime SDK the runtime's own declarations are in scope instead (WebFoundation
// re-exports `ObjectiveC`, decision 0023).
#if os(WASI) && !_runtime(_ObjC)

/// The class Swift knows by `aClassName`, as `NSStringFromClass` names it ("Module.Class"),
/// or nil. Without the runtime only Swift's own type metadata can be searched, so the name of
/// an Objective-C class, which has none here, finds nothing, as on a device without the
/// framework that declares it.
public func NSClassFromString(_ aClassName: String) -> AnyClass? {
    guard !aClassName.isEmpty else { return nil }
    return _typeByName(aClassName) as? AnyClass
}

/// Objective-C's integer types, as Swift imports them.
public typealias NSInteger = Int
public typealias NSUInteger = UInt

public let NSIntegerMax: Int = .max
public let NSIntegerMin: Int = .min
public let NSUIntegerMax: UInt = .max

#endif
