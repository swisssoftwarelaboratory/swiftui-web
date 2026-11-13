// The names of Apple's ObjectiveC module that code without the runtime still uses: the root
// class, its protocol and the selector type (decision 0026; WebFoundation re-exports them). The
// Objective-C runtime SDK has the real module instead (decision 0023), and native builds have
// Apple's, so everything here is wasm without the runtime only.
#if os(WASI) && !_runtime(_ObjC)

/// A command name (`onCommand`); `#selector` needs an Objective-C runtime, so commands are
/// named by their selector string ("copy:", "selectAll:").
public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }
    public var description: String { name }
}

// MARK: - NSObject (decision 0021: the Countries app subclasses it for its notification
// delegate; `super.init()`, identity equality, a hash and a description).

/// The protocol the root class conforms to.
public protocol NSObjectProtocol: AnyObject {
    func isEqual(_ object: Any?) -> Bool
    var hash: Int { get }
    var description: String { get }
}

/// The root class of most Objective-C class hierarchies, without the runtime: identity
/// equality and hashing, overridable, as apps subclass it for delegates.
open class NSObject: NSObjectProtocol, Hashable, CustomStringConvertible {
    public init() {}
    open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSObject else { return false }
        return other === self
    }
    open var hash: Int { ObjectIdentifier(self).hashValue }
    open var description: String { "<\(type(of: self))>" }
    open var debugDescription: String { description }
    public static func == (lhs: NSObject, rhs: NSObject) -> Bool { lhs.isEqual(rhs) }
    public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
    open class var description: String { "\(self)" }
    public func isKind(of aClass: AnyClass) -> Bool { type(of: self) == aClass }
    public func isMember(of aClass: AnyClass) -> Bool { type(of: self) == aClass }

    // Sending a message by selector. Without the runtime no method is registered under a
    // selector, so an object responds to none and a send returns nothing: code that checks
    // first (`responds(to:)`, then `perform`), as Kingfisher does for `sharedApplication`,
    // takes its branch for a missing method. A class overrides these to answer for itself.
    open func responds(to aSelector: Selector!) -> Bool { false }
    open class func responds(to aSelector: Selector!) -> Bool { false }
    open class func instancesRespond(to aSelector: Selector!) -> Bool { false }
    open func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    open func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    open func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
}

#endif
