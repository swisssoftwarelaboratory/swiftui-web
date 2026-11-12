// AVFoundation's player for SwiftUIWeb (sw-frameworks, decision 0018): the members apps use
// with `VideoPlayer`. The player holds the state the host's `<video>` element follows (the
// source, playing, muted, looping, the rate); there is no media pipeline of its own, so
// times and durations are what the host reports back — nothing yet.
#if os(WASI)
@_exported import WebFoundation   // as Apple's AVFoundation re-exports Foundation
#if os(WASI)
@_exported import WASILibc   // libm, which Apple's Foundation re-exports through Darwin
#endif
#else
import Foundation
#endif
import Observation

/// A time in seconds (CoreMedia's `CMTime` reduced to what the hosts can seek to).
public struct CMTime: Hashable, Sendable {
    public var seconds: Double
    public init(seconds: Double, preferredTimescale: Int32 = 600) { self.seconds = seconds }
    public static let zero = CMTime(seconds: 0)
    public static let invalid = CMTime(seconds: .nan)
    public var isValid: Bool { !seconds.isNaN }
}

public func CMTimeMake(value: Int64, timescale: Int32) -> CMTime { CMTime(seconds: Double(value) / Double(timescale)) }
public func CMTimeGetSeconds(_ time: CMTime) -> Double { time.seconds }

/// An item a player plays: a URL.
public final class AVPlayerItem: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public init(asset: AVAsset) { url = asset.url }
    public var asset: AVAsset { AVAsset(url: url) }
    public var duration: CMTime { .invalid }
    public var status: AVPlayerItem.Status { .unknown }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }
}

/// A media asset by URL.
public class AVAsset: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    /// The asset's duration (deprecated on iOS for `load(.duration)`): unknown until a host
    /// element has read the file, which nothing does yet.
    public var duration: CMTime { .invalid }
}

public final class AVURLAsset: AVAsset, @unchecked Sendable {
    public init(url: URL, options: [String: Any]? = nil) { super.init(url: url) }
}

/// Plays one item: `play()`, `pause()`, the rate, muting, looping through `actionAtItemEnd`.
@MainActor @Observable
public class AVPlayer {
    public private(set) var currentItem: AVPlayerItem?
    /// 0 paused, 1 playing (other rates are passed to the host's element).
    public var rate: Float = 0
    public var isMuted = false
    public var volume: Float = 1
    public var actionAtItemEnd: ActionAtItemEnd = .pause
    public var allowsExternalPlayback = true
    /// Whether the host shows transport controls (`VideoPlayer` shows them; apps hide them
    /// through the view's `_controls`).
    package var showsControls = true
    package var loopStorage = false
    private var seekTarget: Double?

    public enum ActionAtItemEnd: Int, Sendable { case advance, pause, none }
    public enum TimeControlStatus: Int, Sendable { case paused, waitingToPlayAtSpecifiedRate, playing }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }

    public init() {}
    public init(url: URL) { currentItem = AVPlayerItem(url: url) }
    public init(playerItem: AVPlayerItem?) { currentItem = playerItem }

    public var status: Status { currentItem == nil ? .unknown : .readyToPlay }
    public var timeControlStatus: TimeControlStatus { rate == 0 ? .paused : .playing }
    public var isPlaying: Bool { rate != 0 }

    public func play() { if rate == 0 { rate = 1 } }
    public func pause() { rate = 0 }
    public func replaceCurrentItem(with item: AVPlayerItem?) { currentItem = item }
    public func currentTime() -> CMTime { CMTime(seconds: seekTarget ?? 0) }
    public func seek(to time: CMTime) { seekTarget = time.seconds }
    public func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) { seekTarget = time.seconds; completionHandler(true) }
    public func seek(to date: Date) {}
    /// Seeks within the tolerances (exactly, here) and reports that the seek finished.
    @discardableResult
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) async -> Bool { seekTarget = time.seconds; return true }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        seekTarget = time.seconds
        completionHandler(true)
    }
    /// Loads media ahead of playing at `rate`: the host element buffers on its own, so this
    /// reports ready at once.
    @discardableResult
    public func preroll(atRate rate: Float) async -> Bool { currentItem != nil }
    public func preroll(atRate rate: Float, completionHandler: (@Sendable (Bool) -> Void)?) { completionHandler?(currentItem != nil) }
    public func cancelPendingPrerolls() {}
    public func addPeriodicTimeObserver(forInterval interval: CMTime, queue: Any? = nil, using block: @escaping @Sendable (CMTime) -> Void) -> Any { _TimeObserver() }
    public func removeTimeObserver(_ observer: Any) {}
}

/// A queue player plays its items in turn (the first one here).
@MainActor
public final class AVQueuePlayer: AVPlayer {
    public private(set) var items: [AVPlayerItem]
    public init(items: [AVPlayerItem]) {
        self.items = items
        super.init(playerItem: items.first)
    }
    public override init() { items = []; super.init() }
    public func advanceToNextItem() {
        if !items.isEmpty { items.removeFirst() }
        replaceCurrentItem(with: items.first)
    }
    public func insert(_ item: AVPlayerItem, after afterItem: AVPlayerItem?) {
        items.append(item)
        if currentItem == nil { replaceCurrentItem(with: item) }
    }
}

/// Loops a queue player's item (the host's element loops).
@MainActor
public final class AVPlayerLooper {
    public let player: AVQueuePlayer
    public init(player: AVQueuePlayer, templateItem: AVPlayerItem) {
        self.player = player
        player.actionAtItemEnd = .none
        player.loops = true
        if player.currentItem == nil { player.replaceCurrentItem(with: templateItem) }
    }
    public func disableLooping() { player.loops = false }
}

extension AVPlayer {
    /// Set by `AVPlayerLooper`; `VideoPlayer` passes it to the host.
    package var loops: Bool {
        get { loopStorage }
        set { loopStorage = newValue }
    }
}

/// The token a periodic time observer returns (no clock drives it yet).
final class _TimeObserver: Sendable {}
