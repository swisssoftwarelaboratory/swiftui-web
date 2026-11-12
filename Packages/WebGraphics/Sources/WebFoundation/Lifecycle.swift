// Stand-ins for the Foundation types SwiftUI's lifecycle API names, which FoundationEssentials
// lacks on wasm: `Timer` (publishing through the frameworks' `Timer.publish`), `RunLoop` and its
// modes (accepted; the browser's loop is the only one), `NotificationCenter` with `Notification`
// and `Notification.Name`, and `NSUserActivity`. Linux also needs NSUserActivity; the other
// declarations remain Foundation's on native platforms.
#if os(WASI)

/// A timer: the frameworks' `Timer.publish(every:tolerance:on:in:)` schedules through tasks; a
/// scheduled timer runs its block on the main actor after its interval.
public final class Timer: @unchecked Sendable {
    public let timeInterval: TimeInterval
    public let repeats: Bool
    private var task: Task<Void, Never>?
    public private(set) var isValid = true

    package init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        self.repeats = repeats
    }

    /// The block of a timer made unscheduled (`init(timeInterval:repeats:block:)`), run once a
    /// run loop adds it.
    private var block: (@Sendable (Timer) -> Void)?

    /// A timer that runs `block` once added to a run loop (`RunLoop.main.add(_:forMode:)`).
    public convenience init(timeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) {
        self.init(timeInterval: interval, repeats: repeats)
        self.block = block
    }

    @discardableResult
    public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats)
        timer.schedule(block)
        return timer
    }

    /// Starts the timer's task: `block` on the main actor after each interval.
    package func schedule(_ block: @escaping @Sendable (Timer) -> Void) {
        guard task == nil, isValid else { return }
        let interval = timeInterval, repeats = repeats
        task = Task { @MainActor in
            repeat {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.001) * 1_000_000_000))
                guard !Task.isCancelled, self.isValid else { return }
                block(self)
            } while repeats && self.isValid
            self.isValid = false
        }
    }

    /// Schedules an unscheduled timer (once; the browser's loop is every run loop's).
    package func scheduleAdded() {
        guard let block else { return }
        self.block = nil
        schedule(block)
    }

    public func invalidate() {
        isValid = false
        task?.cancel()
        task = nil
    }
}

/// The run loop: the browser's event loop stands in for every mode.
public final class RunLoop: @unchecked Sendable {
    public struct Mode: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default")
        public static let common = Mode(rawValue: "common")
    }
    public static let main = RunLoop()
    public static var current: RunLoop { main }

    /// Adds a timer made with `Timer(timeInterval:repeats:block:)`: it starts firing (every mode
    /// is the browser's loop, so a `.common` timer fires during a drag as on iOS).
    public func add(_ timer: Timer, forMode mode: Mode) { timer.scheduleAdded() }
}

/// A notification: its name, an optional sender and user info.
public struct Notification: Hashable, @unchecked Sendable {
    public struct Name: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public let name: Name
    public let object: AnyObject?
    public let userInfo: [AnyHashable: Any]?

    public init(name: Name, object: AnyObject? = nil, userInfo: [AnyHashable: Any]? = nil) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }

    public static func == (lhs: Notification, rhs: Notification) -> Bool { lhs.name == rhs.name && lhs.object === rhs.object }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

public typealias NSNotification = Notification

/// A notification centre: observers keyed by name (and optionally sender), called on post.
public final class NotificationCenter: @unchecked Sendable {
    public static let `default` = NotificationCenter()

    private struct Observer {
        let name: Notification.Name?
        weak var object: AnyObject?
        let filtersObject: Bool
        let block: @Sendable (Notification) -> Void
        /// The object a selector observer sends to (nil for a block observer).
        var owner: ObjectIdentifier? = nil
    }
    private var observers: [Int: Observer] = [:]
    private var nextID = 0

    public init() {}

    /// Adds an observer (the queue is accepted; blocks run where `post` runs, which is the main
    /// thread, the only one here). Returns a token for `removeObserver`.
    @discardableResult
    public func addObserver(forName name: Notification.Name?, object: AnyObject? = nil, queue: OperationQueue? = nil, using block: @escaping @Sendable (Notification) -> Void) -> any NSObjectProtocolToken {
        nextID += 1
        let id = nextID
        observers[id] = Observer(name: name, object: object, filtersObject: object != nil, block: block)
        return NotificationToken(id: id)
    }

    public func removeObserver(_ token: Any) {
        if let token = token as? NotificationToken { observers[token.id] = nil; return }
        let owner = ObjectIdentifier(token as AnyObject)
        observers = observers.filter { $0.value.owner != owner }
    }

    /// Removes `observer`'s selector observations of `name` (every name when nil).
    public func removeObserver(_ observer: Any, name: Notification.Name?, object: Any?) {
        let owner = ObjectIdentifier(observer as AnyObject)
        observers = observers.filter { $0.value.owner != owner || (name != nil && $0.value.name != name) }
    }

    #if canImport(ObjectiveC)
    /// Sends `selector` to `observer` for each matching post while the observer lives (the
    /// notification is not passed: it is a struct here, so an `@objc` method cannot take it).
    /// A selector with no argument (`synchronize`, `refresh`) is sent with none, one with an
    /// argument (`didChange:`) with nil (`_send(_:passing:)`).
    public func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {
        let target = _WeakTarget(observer as AnyObject)
        nextID += 1
        observers[nextID] = Observer(name: name, object: object.map { $0 as AnyObject }, filtersObject: object != nil,
                                     block: { _ in (target.object as? NSObject)?._send(selector, passing: nil) },
                                     owner: ObjectIdentifier(observer as AnyObject))
    }
    #endif

    public func post(_ notification: Notification) {
        for observer in observers.values {
            if let name = observer.name, name != notification.name { continue }
            if observer.filtersObject, observer.object !== notification.object { continue }
            observer.block(notification)
        }
    }

    public func post(name: Notification.Name, object: AnyObject? = nil, userInfo: [AnyHashable: Any]? = nil) {
        post(Notification(name: name, object: object, userInfo: userInfo))
    }
}

/// A selector observer's target, held weakly.
final class _WeakTarget: @unchecked Sendable {
    weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
}

/// An observer token (`addObserver(forName:...)`'s return value).
public protocol NSObjectProtocolToken: AnyObject {}
public final class NotificationToken: NSObjectProtocolToken {
    package let id: Int
    package init(id: Int) { self.id = id }
}

#endif

#if !canImport(Darwin)

/// A user activity: the type, title, user info and web page URL the app would continue.
public final class NSUserActivity: @unchecked Sendable {
    public let activityType: String
    public var title: String?
    public var userInfo: [AnyHashable: Any]?
    public var webpageURL: URL?
    public var isEligibleForHandoff = true

    public init(activityType: String) { self.activityType = activityType }
    public func becomeCurrent() {}
    public func resignCurrent() {}
    public func invalidate() {}
}
#endif
