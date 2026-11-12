// CoreHaptics on the web: the engine, patterns, events and players an app builds, all of which
// work as values and calls, over hardware that cannot play them. A browser has no haptic
// engine (`navigator.vibrate` is a single on/off motor, and Safari has none), so
// `capabilitiesForHardware().supportsHaptics` is false, as on an iPad or a Mac, and the path
// apps already take for those devices is the one that runs: they check it and skip haptics.
// An app that plays anyway gets no error and no feedback.
// Apple's frameworks re-export Foundation: a file importing only this module names TimeInterval.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc   // libm, which Apple's Foundation re-exports through Darwin
#endif

/// A value that indicates the playback should start immediately.
public let CHHapticTimeImmediate: TimeInterval = 0

/// The haptic and audio capabilities of the device.
public protocol CHHapticDeviceCapability {
    /// Whether the device supports haptic event playback.
    var supportsHaptics: Bool { get }
    /// Whether the device supports audio event playback.
    var supportsAudio: Bool { get }
}

struct _WebHapticCapability: CHHapticDeviceCapability {
    var supportsHaptics: Bool { false }
    var supportsAudio: Bool { false }
}

/// A haptic engine: plays haptic and audio patterns.
open class CHHapticEngine: @unchecked Sendable {
    /// The reasons the engine stopped.
    public enum StoppedReason: Int, Sendable {
        case audioSessionInterrupt = 1, applicationSuspended, idleTimeout, notifyWhenFinished, engineDestroyed, gameControllerDisconnect
        case systemError = -1
    }

    /// The engine's response after finishing.
    public enum FinishedAction: Int, Sendable { case stopEngine = 1, leaveEngineRunning }

    /// The device's haptic capabilities: none in a browser.
    open class func capabilitiesForHardware() -> any CHHapticDeviceCapability { _WebHapticCapability() }

    /// Called when the engine stops for an external reason.
    open var stoppedHandler: (StoppedReason) -> Void = { _ in }
    /// Called after the engine resets following a server failure.
    open var resetHandler: () -> Void = {}
    open var playsHapticsOnly = false
    open var playsAudioOnly = false
    open var isMutedForAudio = false
    open var isMutedForHaptics = false
    open var isAutoShutdownEnabled = false
    /// The engine's notion of now.
    open var currentTime: TimeInterval { Date().timeIntervalSinceReferenceDate }
    var running = false

    public init() throws {}
    public convenience init(audioSession: AnyObject?) throws { try self.init() }

    open func start() throws { running = true }
    open func start(completionHandler: ((Error?) -> Void)? = nil) { running = true; completionHandler?(nil) }
    open func stop(completionHandler: ((Error?) -> Void)? = nil) { running = false; completionHandler?(nil) }
    open func notifyWhenPlayersFinished(finishedHandler: @escaping (Error?) -> FinishedAction) { _ = finishedHandler(nil) }

    open func makePlayer(with pattern: CHHapticPattern) throws -> any CHHapticPatternPlayer { _SilentPlayer() }
    open func makeAdvancedPlayer(with pattern: CHHapticPattern) throws -> any CHHapticAdvancedPatternPlayer { _SilentPlayer() }

    /// Plays the pattern in an AHAP file: nothing to play here.
    open func playPattern(from url: URL) throws {}
    open func playPattern(from data: Data) throws {}
    open func registerAudioResource(_ resourceURL: URL, options: [AnyHashable: Any] = [:]) throws -> CHHapticAudioResourceID { 0 }
    open func unregisterAudioResource(_ resourceID: CHHapticAudioResourceID) throws {}
}

public typealias CHHapticAudioResourceID = UInt

/// A player of a haptic pattern.
public protocol CHHapticPatternPlayer: AnyObject {
    func start(atTime time: TimeInterval) throws
    func stop(atTime time: TimeInterval) throws
    func cancel() throws
    func send(_ parameters: [CHHapticDynamicParameter], atTime time: TimeInterval) throws
    func schedule(_ parameterCurve: CHHapticParameterCurve, atTime time: TimeInterval) throws
    var isMuted: Bool { get set }
}

extension CHHapticPatternPlayer {
    /// Sends dynamic parameters to the player (Apple's Swift name for `send`).
    public func sendParameters(_ parameters: [CHHapticDynamicParameter], atTime time: TimeInterval) throws { try send(parameters, atTime: time) }
    /// Schedules a parameter curve on the player (Apple's Swift name for `schedule`).
    public func scheduleParameterCurve(_ parameterCurve: CHHapticParameterCurve, atTime time: TimeInterval) throws { try schedule(parameterCurve, atTime: time) }
}

/// A player with pause, seek, looping and rate control.
public protocol CHHapticAdvancedPatternPlayer: CHHapticPatternPlayer {
    func pause(atTime time: TimeInterval) throws
    func resume(atTime time: TimeInterval) throws
    func seek(toOffset offsetTime: TimeInterval) throws
    var loopEnabled: Bool { get set }
    var loopEnd: TimeInterval { get set }
    var playbackRate: Float { get set }
    var completionHandler: ((Error?) -> Void)? { get set }
}

final class _SilentPlayer: CHHapticAdvancedPatternPlayer {
    var isMuted = false
    var loopEnabled = false
    var loopEnd: TimeInterval = 0
    var playbackRate: Float = 1
    var completionHandler: ((Error?) -> Void)?
    func start(atTime time: TimeInterval) throws { completionHandler?(nil) }
    func stop(atTime time: TimeInterval) throws {}
    func cancel() throws {}
    func send(_ parameters: [CHHapticDynamicParameter], atTime time: TimeInterval) throws {}
    func schedule(_ parameterCurve: CHHapticParameterCurve, atTime time: TimeInterval) throws {}
    func pause(atTime time: TimeInterval) throws {}
    func resume(atTime time: TimeInterval) throws {}
    func seek(toOffset offsetTime: TimeInterval) throws {}
}

/// A haptic or audio event.
open class CHHapticEvent: @unchecked Sendable {
    /// The kinds of event.
    public struct EventType: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let hapticTransient = EventType(rawValue: "HapticTransient")
        public static let hapticContinuous = EventType(rawValue: "HapticContinuous")
        public static let audioContinuous = EventType(rawValue: "AudioContinuous")
        public static let audioCustom = EventType(rawValue: "AudioCustom")
    }

    /// The identifiers of an event's parameters.
    public struct ParameterID: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let hapticIntensity = ParameterID(rawValue: "HapticIntensity")
        public static let hapticSharpness = ParameterID(rawValue: "HapticSharpness")
        public static let attackTime = ParameterID(rawValue: "AttackTime")
        public static let decayTime = ParameterID(rawValue: "DecayTime")
        public static let releaseTime = ParameterID(rawValue: "ReleaseTime")
        public static let sustained = ParameterID(rawValue: "Sustained")
        public static let audioVolume = ParameterID(rawValue: "AudioVolume")
        public static let audioPitch = ParameterID(rawValue: "AudioPitch")
        public static let audioPan = ParameterID(rawValue: "AudioPan")
        public static let audioBrightness = ParameterID(rawValue: "AudioBrightness")
    }

    open var type: EventType
    open var eventParameters: [CHHapticEventParameter]
    open var relativeTime: TimeInterval
    open var duration: TimeInterval

    public init(eventType type: EventType, parameters eventParams: [CHHapticEventParameter], relativeTime time: TimeInterval) {
        self.type = type
        eventParameters = eventParams
        relativeTime = time
        duration = 0
    }

    public init(eventType type: EventType, parameters eventParams: [CHHapticEventParameter], relativeTime time: TimeInterval, duration: TimeInterval) {
        self.type = type
        eventParameters = eventParams
        relativeTime = time
        self.duration = duration
    }

    public init(audioResourceID resID: CHHapticAudioResourceID, parameters eventParams: [CHHapticEventParameter], relativeTime time: TimeInterval) {
        type = .audioCustom
        eventParameters = eventParams
        relativeTime = time
        duration = 0
    }
}

/// A value that changes an event's character.
open class CHHapticEventParameter: @unchecked Sendable {
    open var parameterID: CHHapticEvent.ParameterID
    open var value: Float
    public init(parameterID: CHHapticEvent.ParameterID, value: Float) {
        self.parameterID = parameterID
        self.value = value
    }
}

/// A parameter that changes events while a pattern plays.
open class CHHapticDynamicParameter: @unchecked Sendable {
    /// The identifiers of the dynamic parameters.
    public struct ID: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let hapticIntensityControl = ID(rawValue: "HapticIntensityControl")
        public static let hapticSharpnessControl = ID(rawValue: "HapticSharpnessControl")
        public static let hapticAttackTimeControl = ID(rawValue: "HapticAttackTimeControl")
        public static let hapticDecayTimeControl = ID(rawValue: "HapticDecayTimeControl")
        public static let hapticReleaseTimeControl = ID(rawValue: "HapticReleaseTimeControl")
        public static let audioVolumeControl = ID(rawValue: "AudioVolumeControl")
        public static let audioPanControl = ID(rawValue: "AudioPanControl")
        public static let audioBrightnessControl = ID(rawValue: "AudioBrightnessControl")
        public static let audioPitchControl = ID(rawValue: "AudioPitchControl")
        public static let audioAttackTimeControl = ID(rawValue: "AudioAttackTimeControl")
        public static let audioDecayTimeControl = ID(rawValue: "AudioDecayTimeControl")
        public static let audioReleaseTimeControl = ID(rawValue: "AudioReleaseTimeControl")
    }

    open var parameterID: ID
    open var value: Float
    open var relativeTime: TimeInterval
    public init(parameterID: ID, value: Float, relativeTime time: TimeInterval) {
        self.parameterID = parameterID
        self.value = value
        relativeTime = time
    }
}

/// A curve that changes a dynamic parameter over time.
open class CHHapticParameterCurve: @unchecked Sendable {
    /// A point on the curve.
    open class ControlPoint: @unchecked Sendable {
        open var relativeTime: TimeInterval
        open var value: Float
        public init(relativeTime time: TimeInterval, value: Float) {
            relativeTime = time
            self.value = value
        }
    }

    open var parameterID: CHHapticDynamicParameter.ID
    open var relativeTime: TimeInterval
    open var controlPoints: [ControlPoint]
    public init(parameterID: CHHapticDynamicParameter.ID, controlPoints: [ControlPoint], relativeTime: TimeInterval) {
        self.parameterID = parameterID
        self.controlPoints = controlPoints
        self.relativeTime = relativeTime
    }
}

/// A set of events and parameters that make up a haptic pattern.
open class CHHapticPattern: @unchecked Sendable {
    /// The keys of a pattern dictionary (an AHAP file's structure).
    public struct Key: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { rawValue = value }
        public static let version: Key = "Version"
        public static let pattern: Key = "Pattern"
        public static let event: Key = "Event"
        public static let eventType: Key = "EventType"
        public static let time: Key = "Time"
        public static let eventDuration: Key = "EventDuration"
        public static let eventParameters: Key = "EventParameters"
        public static let parameterID: Key = "ParameterID"
        public static let parameterValue: Key = "ParameterValue"
    }

    open private(set) var events: [CHHapticEvent]
    open private(set) var parameters: [CHHapticDynamicParameter]
    open private(set) var parameterCurves: [CHHapticParameterCurve]
    /// The pattern's length: the end of its last event.
    open var duration: TimeInterval { events.map { $0.relativeTime + $0.duration }.max() ?? 0 }

    public init(events: [CHHapticEvent], parameters: [CHHapticDynamicParameter]) throws {
        self.events = events
        self.parameters = parameters
        parameterCurves = []
    }

    public init(events: [CHHapticEvent], parameterCurves: [CHHapticParameterCurve]) throws {
        self.events = events
        parameters = []
        self.parameterCurves = parameterCurves
    }

    /// A pattern from a dictionary in AHAP's structure. The events are not read.
    public init(dictionary patternDict: [Key: Any]) throws {
        events = []
        parameters = []
        parameterCurves = []
    }

    /// A pattern from an AHAP file. The events are not read.
    public convenience init(contentsOf ahapURL: URL) throws { try self.init(dictionary: [:]) }
}
