// CADisplayLink (Docs/elements/UIKit/Animation.md): a timer tied to the scene's frame clock.
// The link takes a handler, `CADisplayLink(target:handler:)` or `CADisplayLink { link in … }`,
// or, where there is an Objective-C runtime, iOS's `CADisplayLink(target:selector:)`.
// `add(to:forMode:)` starts it (the run loop and mode are accepted and ignored), `invalidate`
// ends it, `isPaused` holds it. `timestamp`, `targetTimestamp` and `duration` follow the frames
// the host delivers.

#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The frame rate range a display link prefers (`CAFrameRateRange` in Core Animation).
public typealias CAFrameRateRange = CADisplayLink.FrameRateRange

#if _runtime(_ObjC)
/// The link's superclass: `NSObject` where there is an Objective-C runtime, as on iOS, so an
/// `@objc` method can take the link (`@objc func tick(_ link: CADisplayLink)`).
public typealias _CADisplayLinkBase = NSObject
#else
open class _CADisplayLinkBase { public init() {} }
#endif

/// A timer object that lets your app synchronize its drawing to the refresh rate of the display.
@preconcurrency @MainActor
public final class CADisplayLink: _CADisplayLinkBase {
    public struct FrameRateRange: Equatable, Sendable {
        public var minimum: Float
        public var maximum: Float
        public var preferred: Float?
        public init(minimum: Float, maximum: Float, preferred: Float? = nil) { self.minimum = minimum; self.maximum = maximum; self.preferred = preferred }
        public static let `default` = FrameRateRange(minimum: 0, maximum: 0, preferred: nil)
    }

    private let handler: @MainActor (CADisplayLink) -> Void
    private weak var target: AnyObject?
    private let requiresTarget: Bool
    /// The time of the frame the handler was last called for, and of the next one.
    public private(set) var timestamp: Double = 0
    public private(set) var targetTimestamp: Double = 0
    /// Seconds between frames (the last interval the host delivered; a 60th before the first).
    public private(set) var duration: Double = 1.0 / 60
    public var isPaused = false { didSet { if !isPaused { UIKitScene.shared.setNeedsFrame() } } }
    public var preferredFramesPerSecond = 0
    public var preferredFrameRateRange: FrameRateRange = .default
    public private(set) var isValid = true
    private var isAdded = false

    /// A link calling `handler` with itself each frame while `target` lives.
    public init(target: AnyObject, handler: @escaping @MainActor (CADisplayLink) -> Void) {
        self.target = target
        self.requiresTarget = true
        self.handler = handler
        super.init()
    }

    public init(handler: @escaping @MainActor (CADisplayLink) -> Void) {
        self.requiresTarget = false
        self.handler = handler
        super.init()
    }

    #if _runtime(_ObjC)
    /// iOS's link: `selector` is sent to `target` with the link each frame. As on iOS the link
    /// keeps its target until it is invalidated.
    public convenience init(target: Any, selector: Selector) {
        let object = target as AnyObject
        self.init { link in (object as? NSObject)?._send(selector, passing: link) }
    }
    #endif

    /// Starts the link (the run loop and mode are accepted for source compatibility).
    public func add(to runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        guard isValid, !isAdded else { return }
        isAdded = true
        UIKitScene.shared.displayLinks.append(WeakDisplayLink(link: self))
        UIKitScene.shared.setNeedsFrame()
    }

    public func remove(from runLoop: RunLoop, forMode mode: RunLoop.Mode) {
        isAdded = false
        UIKitScene.shared.displayLinks.removeAll { $0.link === self || $0.link == nil }
    }

    public func invalidate() {
        isValid = false
        remove(from: .main, forMode: .default)
    }

    /// A frame passed: the handler runs with the new timestamps.
    func tick(elapsed: Double, now: Double) -> Bool {
        guard isValid, isAdded else { return false }
        if requiresTarget, target == nil { invalidate(); return false }
        guard !isPaused else { return true }
        duration = elapsed > 0 ? elapsed : duration
        timestamp = now
        targetTimestamp = now + duration
        handler(self)
        return isValid && isAdded
    }
}

struct WeakDisplayLink {
    weak var link: CADisplayLink?
}

#if os(WASI) || !canImport(QuartzCore)
// Apple's platforms have Core Animation's own.

/// The clock `CACurrentMediaTime()` counts on, started the first time it is read.
private let mediaTimeOrigin = ContinuousClock.now

/// The current absolute time, in seconds, on a monotonic clock. As on Apple's platforms, only
/// differences between two readings mean anything (here the clock starts at the first reading).
public func CACurrentMediaTime() -> Double {
    let elapsed = ContinuousClock.now - mediaTimeOrigin
    let (seconds, attoseconds) = elapsed.components
    return Double(seconds) + Double(attoseconds) / 1e18
}
#endif
