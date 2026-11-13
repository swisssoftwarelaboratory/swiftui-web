// Foundation's copying protocols on wasm: SwiftSoup's `Attributes`, `Elements` and
// `OutputSettings` adopt `NSCopying`, and UIKit takes one as a context menu's identifier.
// `NSZone` is the Objective-C runtime's where that SDK is in use, a placeholder otherwise;
// zones are unused either way, as on Apple platforms since ARC.
#if os(WASI)
#if !_runtime(_ObjC)
/// A memory zone: unused, as on Apple platforms.
public struct NSZone: Sendable {}
#endif

/// An object that can make a copy of itself.
public protocol NSCopying {
    func copy(with zone: NSZone?) -> Any
}

/// An object that can make a mutable copy of itself.
public protocol NSMutableCopying {
    func mutableCopy(with zone: NSZone?) -> Any
}
#endif
