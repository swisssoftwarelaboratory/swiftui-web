// Audio for the web (decision 0021, pf-avfoundation-audio): `AVAudioPlayer` over the host's
// audio element, `AVAudioSession` and `AVAudioApplication` over its microphone permission,
// `AVAudioEngine` whose input node is the microphone delivering `AVAudioPCMBuffer`s to a tap.
// The module is host-agnostic: a host installs `_AVAudioHost` (the browser host with Web Audio
// and `getUserMedia`; without a host, players play nothing, the engine fails to start and no
// permission is granted). Written against Scrumdinger's AudioService and SpeechService.
import WebFoundation

// MARK: - The host

/// What a host provides: playback of a URL, the microphone permission and its sample stream.
public enum _AVAudioHost {
    /// A player for the URL, or nil when the host cannot play it.
    nonisolated(unsafe) public static var makePlayer: ((URL) -> (any _AVAudioPlayback)?)?
    /// Asks for the microphone; the answer arrives on the main actor.
    nonisolated(unsafe) public static var requestRecordPermission: ((@escaping @MainActor @Sendable (Bool) -> Void) -> Void)?
    /// Opens the microphone: samples arrive as mono float frames with their sample rate
    /// (chunks of `bufferSize` frames or whatever the host delivers), until stopped.
    nonisolated(unsafe) public static var openMicrophone: ((_ bufferSize: Int, _ deliver: @escaping @MainActor @Sendable ([Float], Double) -> Void, _ failed: @escaping @MainActor @Sendable (String) -> Void) -> (any _AVAudioCapture)?)?
    /// The permission already answered (a host remembers the browser's grant).
    nonisolated(unsafe) public static var recordPermission: AVAudioSession.RecordPermission = .undetermined
}

/// A playing sound in the host.
public protocol _AVAudioPlayback: AnyObject {
    func play()
    func pause()
    func stop()
    var currentTime: Double { get set }
    var duration: Double { get }
    var volume: Double { get set }
    var rate: Double { get set }
    var loops: Int { get set }
    var isPlaying: Bool { get }
    var onFinished: (@MainActor @Sendable () -> Void)? { get set }
}

/// An open microphone in the host.
public protocol _AVAudioCapture: AnyObject {
    var sampleRate: Double { get }
    func stop()
}

// MARK: - AVAudioPlayer

/// An object that plays audio data from a file or buffer.
public class AVAudioPlayer {
    public let url: URL?
    public let data: Data?
    private var playback: (any _AVAudioPlayback)?
    public weak var delegate: (any AVAudioPlayerDelegate)?
    private var pendingTime: Double = 0
    private var pendingVolume: Double = 1
    private var pendingRate: Double = 1
    public var pan: Float = 0
    public var enableRate = false
    public var numberOfLoops: Int = 0 {
        didSet { playback?.loops = numberOfLoops }
    }

    /// Initializes an audio player for playback of the sound at the URL.
    public init(contentsOf url: URL) throws {
        self.url = url
        data = nil
    }

    public init(contentsOf url: URL, fileTypeHint: String?) throws {
        self.url = url
        data = nil
    }

    /// Initializes an audio player for playback of the data (a `data:` URL for the host).
    public init(data: Data) throws {
        self.data = data
        url = URL(string: "data:audio/wav;base64," + data.base64EncodedString())
    }

    public init(data: Data, fileTypeHint: String?) throws {
        self.data = data
        url = URL(string: "data:audio/wav;base64," + data.base64EncodedString())
    }

    private func ensurePlayback() -> (any _AVAudioPlayback)? {
        if let playback { return playback }
        guard let url, let made = _AVAudioHost.makePlayer?(url) else { return nil }
        made.volume = pendingVolume
        made.rate = pendingRate
        made.loops = numberOfLoops
        made.currentTime = pendingTime
        nonisolated(unsafe) weak let player = self
        made.onFinished = {
            guard let player else { return }
            player.delegate?.audioPlayerDidFinishPlaying(player, successfully: true)
        }
        playback = made
        return made
    }

    /// Prepares the player for playback by preloading its buffers.
    @discardableResult public func prepareToPlay() -> Bool { ensurePlayback() != nil }

    /// Plays audio asynchronously.
    @discardableResult public func play() -> Bool {
        guard let playback = ensurePlayback() else { return false }
        playback.play()
        return true
    }

    /// Plays audio asynchronously, starting at a specified point in the audio output device's
    /// timeline (the delay is not kept: it plays now).
    @discardableResult public func play(atTime time: TimeInterval) -> Bool { play() }

    public func pause() { playback?.pause() }

    /// Stops playback and undoes the setup needed for playback.
    public func stop() {
        playback?.stop()
        pendingTime = 0
    }

    /// The playback point, in seconds, within the timeline of the sound.
    public var currentTime: TimeInterval {
        get { playback?.currentTime ?? pendingTime }
        set { pendingTime = newValue; playback?.currentTime = newValue }
    }

    /// The total duration, in seconds, of the sound (0 until the host knows).
    public var duration: TimeInterval { playback?.duration ?? 0 }

    public var volume: Float {
        get { Float(playback?.volume ?? pendingVolume) }
        set { pendingVolume = Double(newValue); playback?.volume = Double(newValue) }
    }

    public func setVolume(_ volume: Float, fadeDuration: TimeInterval) { self.volume = volume }

    public var rate: Float {
        get { Float(playback?.rate ?? pendingRate) }
        set { pendingRate = Double(newValue); playback?.rate = Double(newValue) }
    }

    public var isPlaying: Bool { playback?.isPlaying ?? false }
    public var numberOfChannels: Int { 2 }
    public var deviceCurrentTime: TimeInterval { Date().timeIntervalSince1970 }
}

/// A protocol that defines the methods to respond to audio playback events and decoding errors.
public protocol AVAudioPlayerDelegate: AnyObject {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool)
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?)
}

extension AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {}
}

// MARK: - AVAudioSession

/// An object that communicates to the system how you intend to use audio in your app. The web
/// has one session: categories, modes and activation are recorded; the record permission is
/// the browser's microphone permission.
public final class AVAudioSession {
    nonisolated(unsafe) private static let shared = AVAudioSession()
    public static func sharedInstance() -> AVAudioSession { shared }

    public struct Category: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "AVAudioSessionCategoryAmbient")
        public static let soloAmbient = Category(rawValue: "AVAudioSessionCategorySoloAmbient")
        public static let playback = Category(rawValue: "AVAudioSessionCategoryPlayback")
        public static let record = Category(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Category(rawValue: "AVAudioSessionCategoryPlayAndRecord")
        public static let multiRoute = Category(rawValue: "AVAudioSessionCategoryMultiRoute")
    }

    public struct Mode: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "AVAudioSessionModeDefault")
        public static let voiceChat = Mode(rawValue: "AVAudioSessionModeVoiceChat")
        public static let gameChat = Mode(rawValue: "AVAudioSessionModeGameChat")
        public static let videoRecording = Mode(rawValue: "AVAudioSessionModeVideoRecording")
        public static let measurement = Mode(rawValue: "AVAudioSessionModeMeasurement")
        public static let moviePlayback = Mode(rawValue: "AVAudioSessionModeMoviePlayback")
        public static let videoChat = Mode(rawValue: "AVAudioSessionModeVideoChat")
        public static let spokenAudio = Mode(rawValue: "AVAudioSessionModeSpokenAudio")
        public static let voicePrompt = Mode(rawValue: "AVAudioSessionModeVoicePrompt")
    }

    public struct CategoryOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1)
        public static let duckOthers = CategoryOptions(rawValue: 2)
        public static let allowBluetooth = CategoryOptions(rawValue: 4)
        public static let allowBluetoothHFP = CategoryOptions(rawValue: 4)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 8)
        public static let interruptSpokenAudioAndMixWithOthers = CategoryOptions(rawValue: 0x11)
        public static let allowBluetoothA2DP = CategoryOptions(rawValue: 0x20)
        public static let allowAirPlay = CategoryOptions(rawValue: 0x40)
        public static let overrideMutedMicrophoneInterruption = CategoryOptions(rawValue: 0x80)
    }

    public struct SetActiveOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1)
    }

    public enum RecordPermission: Int, Sendable {
        case undetermined = 1970168948
        case denied = 1684369017
        case granted = 1735552628
    }

    public enum RouteSharingPolicy: Int, Sendable { case `default`, longFormAudio, independent, longFormVideo }
    public enum PortOverride: Int, Sendable { case none = 0, speaker = 1936747378 }

    public private(set) var category: Category = .soloAmbient
    public private(set) var mode: Mode = .default
    public private(set) var categoryOptions: CategoryOptions = []
    public private(set) var routeSharingPolicy: RouteSharingPolicy = .default
    public private(set) var isActive = false
    public var sampleRate: Double { 48_000 }
    public var outputVolume: Float { 1 }
    public var isOtherAudioPlaying: Bool { false }
    public var inputNumberOfChannels: Int { 1 }
    public var outputNumberOfChannels: Int { 2 }
    public var availableCategories: [Category] { [.ambient, .soloAmbient, .playback, .record, .playAndRecord, .multiRoute] }

    public func setCategory(_ category: Category) throws { self.category = category }
    public func setCategory(_ category: Category, options: CategoryOptions) throws {
        self.category = category
        categoryOptions = options
    }
    public func setCategory(_ category: Category, mode: Mode, options: CategoryOptions = []) throws {
        self.category = category
        self.mode = mode
        categoryOptions = options
    }
    public func setCategory(_ category: Category, mode: Mode, policy: RouteSharingPolicy, options: CategoryOptions = []) throws {
        try setCategory(category, mode: mode, options: options)
        routeSharingPolicy = policy
    }
    public func setMode(_ mode: Mode) throws { self.mode = mode }
    public func setActive(_ active: Bool) throws { isActive = active }
    public func setActive(_ active: Bool, options: SetActiveOptions) throws { isActive = active }
    public func overrideOutputAudioPort(_ portOverride: PortOverride) throws {}
    public func setPreferredSampleRate(_ sampleRate: Double) throws {}
    public func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {}

    /// The microphone permission as the browser last answered it.
    public var recordPermission: RecordPermission { _AVAudioHost.recordPermission }

    /// Asks the browser for the microphone (a prompt the first time); the answer on the main actor.
    public func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission(completionHandler: response)
    }
}

/// Audio configuration shared by the app (iOS 17): the record permission.
public final class AVAudioApplication {
    nonisolated(unsafe) private static let sharedInstance = AVAudioApplication()
    public static var shared: AVAudioApplication { sharedInstance }

    public enum recordPermission: Int, Sendable {
        case undetermined = 0
        case denied = 1
        case granted = 2
    }

    public var recordPermission: recordPermission {
        switch _AVAudioHost.recordPermission {
        case .undetermined: .undetermined
        case .denied: .denied
        case .granted: .granted
        }
    }

    /// Asks for the microphone; the host remembers the grant.
    public static func requestRecordPermission(completionHandler: @escaping (Bool) -> Void) {
        if _AVAudioHost.recordPermission == .granted { completionHandler(true); return }
        guard let request = _AVAudioHost.requestRecordPermission else {
            _AVAudioHost.recordPermission = .denied
            completionHandler(false)
            return
        }
        nonisolated(unsafe) let completionHandler = completionHandler
        request { granted in
            _AVAudioHost.recordPermission = granted ? .granted : .denied
            completionHandler(granted)
        }
    }

    public static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}

// MARK: - Formats and buffers

/// A class that represents a buffer of audio data with a format. Mono float samples here.
public class AVAudioFormat: CustomStringConvertible {
    public let sampleRate: Double
    public let channelCount: UInt32
    public let commonFormat: AVAudioCommonFormat
    public let isInterleaved: Bool

    public init(standardFormatWithSampleRate sampleRate: Double, channels: UInt32) {
        self.sampleRate = sampleRate
        channelCount = channels
        commonFormat = .pcmFormatFloat32
        isInterleaved = false
    }

    public init?(commonFormat: AVAudioCommonFormat, sampleRate: Double, channels: UInt32, interleaved: Bool) {
        self.sampleRate = sampleRate
        channelCount = channels
        self.commonFormat = commonFormat
        isInterleaved = interleaved
    }

    public var isStandard: Bool { commonFormat == .pcmFormatFloat32 && !isInterleaved }
    public var description: String { "<AVAudioFormat: \(channelCount) ch, \(Int(sampleRate)) Hz, Float32\(isInterleaved ? ", interleaved" : ", deinterleaved")>" }
}

public enum AVAudioCommonFormat: UInt, Sendable {
    case otherFormat = 0
    case pcmFormatFloat32 = 1
    case pcmFormatFloat64 = 2
    case pcmFormatInt16 = 3
    case pcmFormatInt32 = 4
}

public typealias AVAudioFrameCount = UInt32
public typealias AVAudioChannelCount = UInt32
public typealias AVAudioNodeBus = Int
public typealias AVAudioFramePosition = Int64

/// A buffer of audio data in PCM format, one float array per channel behind the pointers.
public class AVAudioPCMBuffer {
    public let format: AVAudioFormat
    public let frameCapacity: AVAudioFrameCount
    public var frameLength: AVAudioFrameCount
    private let channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let channelCount: Int

    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {
        self.format = format
        self.frameCapacity = frameCapacity
        frameLength = 0
        channelCount = Int(format.channelCount)
        channels = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: max(1, channelCount))
        for channel in 0..<channelCount {
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: Int(max(1, frameCapacity)))
            samples.initialize(repeating: 0, count: Int(max(1, frameCapacity)))
            channels[channel] = samples
        }
    }

    /// A buffer holding `samples` (mono) at `sampleRate`.
    package convenience init(samples: [Float], sampleRate: Double) {
        self.init(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1), frameCapacity: AVAudioFrameCount(samples.count))!
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress, !samples.isEmpty { channels[0].update(from: base, count: samples.count) }
        }
        frameLength = AVAudioFrameCount(samples.count)
    }

    deinit {
        for channel in 0..<channelCount { channels[channel].deallocate() }
        channels.deallocate()
    }

    /// The buffer's audio samples as floating point values, one pointer per channel.
    public var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? {
        format.commonFormat == .pcmFormatFloat32 ? UnsafePointer(channels) : nil
    }
    public var int16ChannelData: UnsafePointer<UnsafeMutablePointer<Int16>>? { nil }
    public var int32ChannelData: UnsafePointer<UnsafeMutablePointer<Int32>>? { nil }
    public var stride: Int { 1 }

    /// Channel `channel`'s first `frameLength` samples.
    public func _samples(channel: Int = 0) -> [Float] {
        guard channel < channelCount else { return [] }
        return Array(UnsafeBufferPointer(start: channels[channel], count: Int(frameLength)))
    }
}

/// A moment in an audio stream: the sample time at a sample rate.
public class AVAudioTime {
    public let sampleTime: AVAudioFramePosition
    public let sampleRate: Double
    public let hostTime: UInt64
    public init(sampleTime: AVAudioFramePosition, atRate sampleRate: Double) {
        self.sampleTime = sampleTime
        self.sampleRate = sampleRate
        hostTime = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    }
    public init(hostTime: UInt64) {
        self.hostTime = hostTime
        sampleTime = 0
        sampleRate = 0
    }
    public var isSampleTimeValid: Bool { sampleRate > 0 }
    public var isHostTimeValid: Bool { true }
}

// MARK: - AVAudioEngine

public typealias AVAudioNodeTapBlock = (AVAudioPCMBuffer, AVAudioTime) -> Void

/// An object that connects audio nodes: here the microphone's input node and an output node.
public class AVAudioNode {
    public weak var engine: AVAudioEngine?
    public var numberOfInputs: Int { 1 }
    public var numberOfOutputs: Int { 1 }
    package var taps: [AVAudioNodeBus: (bufferSize: AVAudioFrameCount, block: AVAudioNodeTapBlock)] = [:]
    package var format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)

    package init() {}

    public func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { format }
    public func outputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat { format }

    /// Installs an audio tap on the bus to record, monitor, and observe the output of the node.
    public func installTap(onBus bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat?, block tapBlock: @escaping AVAudioNodeTapBlock) {
        taps[bus] = (bufferSize, tapBlock)
    }

    public func removeTap(onBus bus: AVAudioNodeBus) { taps[bus] = nil }
    public func reset() {}
}

/// The microphone (`AVAudioEngine.inputNode`): while the engine runs, the host's samples reach
/// the taps as float buffers at the host's sample rate.
public final class AVAudioInputNode: AVAudioNode {
    public var isVoiceProcessingEnabled: Bool { false }
    public func setVoiceProcessingEnabled(_ enabled: Bool) throws {}
    public var voiceProcessingAGCEnabled = false
    public var voiceProcessingBypassed = false

    package func deliver(_ samples: [Float], sampleRate: Double, position: AVAudioFramePosition) {
        if sampleRate != format.sampleRate { format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) }
        for (_, tap) in taps {
            let buffer = AVAudioPCMBuffer(samples: samples, sampleRate: sampleRate)
            tap.block(buffer, AVAudioTime(sampleTime: position, atRate: sampleRate))
        }
    }
}

public final class AVAudioOutputNode: AVAudioNode {}
public final class AVAudioMixerNode: AVAudioNode {
    public var outputVolume: Float = 1
    public override init() { super.init() }
}

/// An object that manages a graph of audio nodes: the microphone in, the speakers out.
public final class AVAudioEngine {
    public let inputNode = AVAudioInputNode()
    public let outputNode = AVAudioOutputNode()
    public let mainMixerNode = AVAudioMixerNode()
    public private(set) var isRunning = false
    private var capture: (any _AVAudioCapture)?
    private var position: AVAudioFramePosition = 0
    public var isAutoShutdownEnabled = false
    public var isInManualRenderingMode: Bool { false }

    public init() {
        inputNode.engine = self
        outputNode.engine = self
        mainMixerNode.engine = self
    }

    public func attach(_ node: AVAudioNode) { node.engine = self }
    public func detach(_ node: AVAudioNode) { node.engine = nil }
    public func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {}
    public func connect(_ node1: AVAudioNode, to node2: AVAudioNode, fromBus bus1: AVAudioNodeBus, toBus bus2: AVAudioNodeBus, format: AVAudioFormat?) {}
    public func disconnectNodeInput(_ node: AVAudioNode) {}
    public func disconnectNodeOutput(_ node: AVAudioNode) {}
    public func prepare() {}

    public struct StartError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Starts the engine: opens the microphone when a tap wants it (the host asks the browser for it).
    public func start() throws {
        guard !isRunning else { return }
        guard let open = _AVAudioHost.openMicrophone else { throw StartError(description: "AVAudioEngine: no audio host") }
        let bufferSize = Int(inputNode.taps.values.map(\.bufferSize).max() ?? 1024)
        nonisolated(unsafe) let node = inputNode
        nonisolated(unsafe) let engine = self
        let failure = _Box<String?>(nil)
        capture = open(bufferSize, { samples, rate in
            node.deliver(samples, sampleRate: rate, position: engine.position)
            engine.position += AVAudioFramePosition(samples.count)
        }, { message in
            failure.value = message
            engine.stop()
        })
        if let message = failure.value { throw StartError(description: message) }
        guard capture != nil else { throw StartError(description: "AVAudioEngine: the microphone could not be opened") }
        isRunning = true
    }

    public func pause() {
        capture?.stop()
        capture = nil
        isRunning = false
    }

    public func stop() {
        pause()
        position = 0
    }

    public func reset() { stop() }
}

final class _Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
