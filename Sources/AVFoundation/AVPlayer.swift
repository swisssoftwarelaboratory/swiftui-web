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
import UIKitWebCore   // CGSize (a clip's picture size)

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

/// An item a player plays: a URL. Its media loads into a video the browser host plays (new-website#746)
/// the first time something needs it: its status, a preroll, or a player layer showing it.
public final class AVPlayerItem: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public init(asset: AVAsset) { url = asset.url }
    public var asset: AVAsset { AVAsset(url: url) }
    /// The clip's duration: the build's record of a bundled clip at once, else the video's once read.
    public var duration: CMTime {
        if let seconds = _AVVideoHost.clipFacts?(url)?.duration { return CMTime(seconds: seconds) }
        return loadedDuration.map { CMTime(seconds: $0) } ?? .invalid
    }
    public var presentationSize: CGSize { _AVVideoHost.clipFacts?(url).map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    /// `.readyToPlay` once the video has a frame to show, `.failed` when it can't be played.
    public var status: AVPlayerItem.Status {
        MainActor.assumeIsolated { _ = _video() }
        return statusStorage
    }
    public enum Status: Int, Sendable { case unknown, readyToPlay, failed }

    private var statusStorage: Status = .unknown
    private var loadedDuration: Double?
    private var element: (any _AVVideoElement)?
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    /// Whether the video was made (something needed it).
    var _isLoaded: Bool { element != nil }
    /// The player that plays this item (told when the video ends).
    weak var _player: AVPlayer?

    /// The browser's video for this item, made on first need; nil without a host that plays video.
    @MainActor func _video() -> (any _AVVideoElement)? {
        if let element { return element }
        guard statusStorage != .failed, let make = _AVVideoHost.make else { return nil }
        element = make(url, { [weak self] duration in
            guard let self else { return }
            self.loadedDuration = duration
            self.statusStorage = .readyToPlay
            self.resume(true)
        }, { [weak self] in
            self?._player?._itemDidEnd()
        }, { [weak self] in
            self?.statusStorage = .failed
            self?.resume(false)
        }, { [weak self] in
            self?._player?._newFrame()
        })
        if element == nil { statusStorage = .failed }
        _player?.syncVideo()
        return element
    }

    /// Waits until the video can show a frame (true) or can't be played (false).
    @MainActor func _ready() async -> Bool {
        guard _video() != nil else { return false }
        switch statusStorage {
        case .readyToPlay: return true
        case .failed: return false
        case .unknown: return await withCheckedContinuation { waiting.append($0) }
        }
    }

    private func resume(_ ready: Bool) {
        let pending = waiting
        waiting = []
        for continuation in pending { continuation.resume(returning: ready) }
    }
}

/// A video the browser host plays for an item (`_AVVideoHost.make`), whose current frame a
/// player layer paints as a surface of the frame.
@MainActor public protocol _AVVideoElement: AnyObject {
    /// The surface its frames are painted from (`DisplayCommand.drawSurface`).
    var surface: Int { get }
    var currentTime: Double { get }
    func play(rate: Float)
    func pause()
    func seek(to seconds: Double)
    func setMuted(_ muted: Bool, volume: Float)
    func setLoops(_ loops: Bool)
}

/// The browser behind AVFoundation's video (new-website#746).
public enum _AVVideoHost {
    /// Makes the video for a URL: `ready(duration)` when it has a frame, `ended`, `failed`, and
    /// `frame` for each new picture it shows.
    @MainActor public static var make: ((_ url: URL, _ ready: @escaping (Double) -> Void, _ ended: @escaping () -> Void,
                                         _ failed: @escaping () -> Void, _ frame: @escaping () -> Void) -> (any _AVVideoElement)?)?
    /// A bundled clip's duration and picture size, as its build recorded them (iOS knows them at once).
    nonisolated(unsafe) public static var clipFacts: ((URL) -> (duration: Double, width: Double, height: Double)?)?
}

/// A media asset by URL.
public class AVAsset: @unchecked Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    /// The asset's duration (deprecated on iOS for `load(.duration)`): a bundled clip's from its
    /// build's record, at once as on iOS; unknown for other URLs.
    @available(*, deprecated, message: "Use load(.duration) instead")
    public var duration: CMTime { _AVVideoHost.clipFacts?(url).map { CMTime(seconds: $0.duration) } ?? .invalid }
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
    public init(url: URL) { currentItem = AVPlayerItem(url: url); currentItem?._player = self }
    public init(playerItem: AVPlayerItem?) { currentItem = playerItem; currentItem?._player = self }

    public var status: Status { currentItem == nil ? .unknown : .readyToPlay }
    public var timeControlStatus: TimeControlStatus { rate == 0 ? .paused : .playing }
    public var isPlaying: Bool { rate != 0 }

    /// The rate, muting and looping go to the item's video once it has one; a playing video asks
    /// for frames so its pictures are painted.
    public func play() { if rate == 0 { rate = 1 }; syncVideo() }
    public func pause() { rate = 0; syncVideo() }
    public func replaceCurrentItem(with item: AVPlayerItem?) {
        currentItem?._video()?.pause()
        currentItem = item
        item?._player = self
        syncVideo()
    }
    public func currentTime() -> CMTime {
        if let video = videoIfLoaded { return CMTime(seconds: video.currentTime) }
        return CMTime(seconds: seekTarget ?? 0)
    }
    public func seek(to time: CMTime) { seekTarget = time.seconds; videoIfLoaded?.seek(to: time.seconds) }
    public func seek(to time: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) { seek(to: time); completionHandler(true) }
    public func seek(to date: Date) {}
    /// Seeks within the tolerances (exactly, here) and reports that the seek finished.
    @discardableResult
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) async -> Bool { seek(to: time); return true }
    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping @Sendable (Bool) -> Void) {
        seek(to: time)
        completionHandler(true)
    }
    /// Loads the item's media ahead of playing: true once its video can show a frame.
    @discardableResult
    public func preroll(atRate rate: Float) async -> Bool {
        guard let item = currentItem else { return false }
        guard _AVVideoHost.make != nil else { return true }
        let ready = await item._ready()
        syncVideo()
        return ready
    }
    public func preroll(atRate rate: Float, completionHandler: (@Sendable (Bool) -> Void)?) {
        Task { @MainActor in completionHandler?(await preroll(atRate: rate)) }
    }

    /// The current item's video when something already loaded it (a layer, a status check).
    private var videoIfLoaded: (any _AVVideoElement)? {
        guard let item = currentItem, item._isLoaded || layerShowsVideo else { return nil }
        return item._video()
    }
    /// Whether a player layer shows this player.
    package var layerShowsVideo: Bool { layers.contains { $0.layer != nil } }

    /// Brings the video in line with the player: rate, muting, looping, the pending seek.
    package func syncVideo() {
        guard let video = videoIfLoaded else { return }
        video.setMuted(isMuted, volume: volume)
        video.setLoops(loops)
        if let seekTarget { video.seek(to: seekTarget); self.seekTarget = nil }
        if rate != 0 { video.play(rate: rate) } else { video.pause() }
        _newFrame()
    }

    /// The layers showing this player (`AVPlayerLayer.player`), repainted with each new picture.
    package var layers: [WeakLayerBox] = []
    package struct WeakLayerBox { package weak var layer: AnyObject?; package init(_ layer: AnyObject) { self.layer = layer } }
    /// Set by the layers' module: repaints a layer showing this player.
    nonisolated(unsafe) package static var repaint: ((AnyObject) -> Void)?

    func _newFrame() {
        layers.removeAll { $0.layer == nil }
        for box in layers { if let layer = box.layer { Self.repaint?(layer) } }
    }

    /// The item's video reached its end: paused there, as `actionAtItemEnd` `.pause` does.
    func _itemDidEnd() {
        guard !loops, actionAtItemEnd != .none else { return }
        rate = 0
        _newFrame()
    }
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
