// Foundation's locks, threads and cache on wasm, where FoundationEssentials has none of them and
// a page runs one thread: the packages apps pin reach for these first (Kingfisher's callback
// queue, swift-concurrency-extras' `LockIsolated`, SwiftSoup's mutex, the sweep's package build,
// Tools/Coverage). A lock never waits (nothing else can hold it), `Thread` is always the main
// thread, and `NSCache` keeps what it is given up to its limits. Also the clock constants and
// time types Apple's Foundation brings with it from Dispatch and CoreFoundation.
#if os(WASI)

// MARK: - Locks

/// The basic interface for lock objects.
public protocol NSLocking {
    func lock()
    func unlock()
}

extension NSLocking {
    /// Runs `body` while holding the lock.
    public func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// An object that coordinates the operation of multiple threads of execution within the same
/// application. With one thread, acquiring it always succeeds at once.
open class NSLock: NSObject, NSLocking, @unchecked Sendable {
    private var held = false
    open var name: String?
    public override init() { super.init() }
    open func lock() { held = true }
    open func unlock() { held = false }
    /// Acquires the lock unless it is already held.
    open func `try`() -> Bool {
        if held { return false }
        held = true
        return true
    }
    open func lock(before limit: Date) -> Bool { `try`() }
}

/// A lock that the same thread can acquire more than once.
open class NSRecursiveLock: NSObject, NSLocking, @unchecked Sendable {
    private var depth = 0
    open var name: String?
    public override init() { super.init() }
    open func lock() { depth += 1 }
    open func unlock() { depth = max(0, depth - 1) }
    open func `try`() -> Bool { depth += 1; return true }
    open func lock(before limit: Date) -> Bool { `try`() }
}

/// A condition variable. `wait()` returns at once: no other thread can signal it.
open class NSCondition: NSObject, NSLocking, @unchecked Sendable {
    open var name: String?
    public override init() { super.init() }
    open func lock() {}
    open func unlock() {}
    open func wait() {}
    open func wait(until limit: Date) -> Bool { false }
    open func signal() {}
    open func broadcast() {}
}

// MARK: - Thread

/// A thread of execution. A page has one: the main thread.
open class Thread: NSObject, @unchecked Sendable {
    private static let mainThread = Thread()
    private var block: (@Sendable () -> Void)?

    open class var current: Thread { mainThread }
    open class var main: Thread { mainThread }
    open class var isMainThread: Bool { true }
    open var isMainThread: Bool { self === Thread.mainThread }
    open class var callStackSymbols: [String] { [] }
    /// The return addresses of the calling frames; wasm doesn't expose its stack, so none.
    open class var callStackReturnAddresses: [NSNumber] { [] }
    open class func isMultiThreaded() -> Bool { false }

    open var name: String?
    open var threadDictionary: [AnyHashable: Any] = [:]
    open var stackSize = 0
    open var qualityOfService: QualityOfService = .default
    open private(set) var isExecuting = false
    open private(set) var isFinished = false
    open private(set) var isCancelled = false

    public override init() { super.init() }
    /// A thread that runs `block` when started.
    public convenience init(block: @escaping @Sendable () -> Void) {
        self.init()
        self.block = block
    }

    /// Starts the thread: its work runs on the main queue's next turn, the only thread there is.
    open func start() {
        guard !isExecuting, !isFinished else { return }
        isExecuting = true
        DispatchQueue.main.async { [self] in
            if !self.isCancelled { self.main() }
            self.isExecuting = false
            self.isFinished = true
        }
    }
    /// The thread's work: the block it was made with, or a subclass's override.
    open func main() { block?() }
    open func cancel() { isCancelled = true }

    /// Blocks the thread: the page's only thread waits out the interval.
    open class func sleep(forTimeInterval ti: TimeInterval) {
        let end = Date().addingTimeInterval(ti)
        while Date() < end {}
    }
    open class func sleep(until date: Date) { sleep(forTimeInterval: date.timeIntervalSinceNow) }
    open class func detachNewThread(_ block: @escaping @Sendable () -> Void) { Thread(block: block).start() }
}

/// The nature of work and its importance to the system.
public enum QualityOfService: Int, Sendable {
    case userInteractive = 0x21
    case userInitiated = 0x19
    case utility = 0x11
    case background = 0x09
    case `default` = -1
}

// MARK: - NSCache

/// A mutable collection of key-value pairs that it may evict: here, the oldest entries once
/// `countLimit` or `totalCostLimit` is passed. Keys compare as Foundation's do, by `isEqual`
/// (their hashable value), else by identity.
/// An object whose contents a cache may throw away while nobody is accessing them.
public protocol NSDiscardableContent: AnyObject {
    func beginContentAccess() -> Bool
    func endContentAccess()
    func discardContentIfPossible()
    func isContentDiscarded() -> Bool
}

open class NSCache<KeyType: AnyObject, ObjectType: AnyObject>: NSObject, @unchecked Sendable {
    private struct Entry { let key: KeyType; let object: ObjectType; let cost: Int }
    private var entries: [AnyHashable: Entry] = [:]
    private var order: [AnyHashable] = []
    private var totalCost = 0

    open var name = ""
    /// The most objects the cache holds (0: no limit).
    open var countLimit = 0 { didSet { trim() } }
    /// The most total cost the cache holds (0: no limit).
    open var totalCostLimit = 0 { didSet { trim() } }
    open var evictsObjectsWithDiscardedContent = true
    open weak var delegate: (any NSCacheDelegate)?

    public override init() { super.init() }

    private func identity(_ key: KeyType) -> AnyHashable {
        (key as? AnyHashable) ?? AnyHashable(ObjectIdentifier(key))
    }

    open func object(forKey key: KeyType) -> ObjectType? { entries[identity(key)]?.object }

    open func setObject(_ obj: ObjectType, forKey key: KeyType) { setObject(obj, forKey: key, cost: 0) }

    open func setObject(_ obj: ObjectType, forKey key: KeyType, cost g: Int) {
        let id = identity(key)
        if let old = entries[id] {
            totalCost -= old.cost
            order.removeAll { $0 == id }
        }
        entries[id] = Entry(key: key, object: obj, cost: g)
        order.append(id)
        totalCost += g
        trim()
    }

    open func removeObject(forKey key: KeyType) {
        let id = identity(key)
        guard let old = entries.removeValue(forKey: id) else { return }
        totalCost -= old.cost
        order.removeAll { $0 == id }
    }

    open func removeAllObjects() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }

    private func trim() {
        while !order.isEmpty, (countLimit > 0 && order.count > countLimit) || (totalCostLimit > 0 && totalCost > totalCostLimit) {
            let id = order.removeFirst()
            if let gone = entries.removeValue(forKey: id) {
                totalCost -= gone.cost
                // Apple's delegate takes the cache as NSCache<AnyObject, AnyObject>; a cache of
                // other types can't be passed as one in Swift, so only such a cache tells it.
                if let cache = self as? NSCache<AnyObject, AnyObject> {
                    delegate?.cache(cache, willEvictObject: gone.object)
                }
            }
        }
    }
}

/// What a cache tells its delegate (Apple's method is optional: here it has a default). It
/// refines `AnyObject`, not `NSObjectProtocol`: with the interop SDK that is the Objective-C
/// protocol, and a Swift protocol refining it crashes the 6.3 compiler while it emits the
/// protocol's metadata. Delegates are `NSObject` subclasses either way.
public protocol NSCacheDelegate: AnyObject {
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any)
}

extension NSCacheDelegate {
    public func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {}
}

// MARK: - Clock constants and CoreFoundation's time types

public let NSEC_PER_SEC: UInt64 = 1_000_000_000
public let NSEC_PER_MSEC: UInt64 = 1_000_000
public let NSEC_PER_USEC: UInt64 = 1_000
public let USEC_PER_SEC: UInt64 = 1_000_000
public let MSEC_PER_SEC: UInt64 = 1_000

/// A time interval in seconds (CoreFoundation's name, which Apple's Foundation brings with it).
public typealias CFTimeInterval = Double
/// Seconds since the reference date, 1 January 2001.
public typealias CFAbsoluteTime = Double
public func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime { Date().timeIntervalSinceReferenceDate }

// MARK: - String

extension StringProtocol {
    /// A new string made by appending `aString` to this one.
    public func appending<T: StringProtocol>(_ aString: T) -> String { String(self) + String(aString) }
}

// MARK: - CustomNSError

/// An error that names its own `NSError` domain, code and user info.
public protocol CustomNSError: Error {
    static var errorDomain: String { get }
    var errorCode: Int { get }
    var errorUserInfo: [String: Any] { get }
}

extension CustomNSError {
    public static var errorDomain: String { String(reflecting: self) }
    public var errorCode: Int { 1 }
    public var errorUserInfo: [String: Any] { [:] }
}

// MARK: - os_unfair_lock

// Darwin's unfair lock, which Apple's Foundation brings with it (swift-sharing's
// `PassthroughRelay` allocates one with only Foundation imported). One thread runs here, so
// locking marks the lock held and unlocking clears it; `trylock` fails while it is held.

/// A low-level lock that lets waiters spin and then block.
public struct os_unfair_lock_s: Sendable {
    public var _os_unfair_lock_opaque: UInt32
    public init() { _os_unfair_lock_opaque = 0 }
    public init(_os_unfair_lock_opaque: UInt32) { self._os_unfair_lock_opaque = _os_unfair_lock_opaque }
}
public typealias os_unfair_lock = os_unfair_lock_s
public typealias os_unfair_lock_t = UnsafeMutablePointer<os_unfair_lock_s>

public func os_unfair_lock_lock(_ lock: os_unfair_lock_t) { lock.pointee._os_unfair_lock_opaque = 1 }
public func os_unfair_lock_unlock(_ lock: os_unfair_lock_t) { lock.pointee._os_unfair_lock_opaque = 0 }
public func os_unfair_lock_trylock(_ lock: os_unfair_lock_t) -> Bool {
    guard lock.pointee._os_unfair_lock_opaque == 0 else { return false }
    lock.pointee._os_unfair_lock_opaque = 1
    return true
}
public func os_unfair_lock_assert_owner(_ lock: os_unfair_lock_t) {
    precondition(lock.pointee._os_unfair_lock_opaque != 0, "os_unfair_lock is not held")
}
public func os_unfair_lock_assert_not_owner(_ lock: os_unfair_lock_t) {
    precondition(lock.pointee._os_unfair_lock_opaque == 0, "os_unfair_lock is held")
}

// MARK: - Autorelease pools

#if !_runtime(_ObjC)
/// Runs `body` in an autorelease pool, which Swift's own memory management makes a plain call
/// here (Apple's ObjectiveC module declares it; the image caches drain one per decoded image).
public func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}
#endif
#endif
