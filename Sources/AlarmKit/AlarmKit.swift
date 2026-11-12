// AlarmKit on the web: alarms and timers that ring over the Lock Screen. A page cannot ring
// when it is closed, so alarms are never authorized: `authorizationState` is `.denied`,
// `requestAuthorization()` answers `.denied` and scheduling throws. An app's fallback (a
// notification, say) is the path that runs. Accepted for source compatibility.
@_exported import ActivityKit
import AppIntents
import SwiftUI

/// What an app attaches to its alarms.
public protocol AlarmMetadata: Codable, Hashable, Sendable {}

/// A button on an alarm's alert.
public struct AlarmButton: Codable, Hashable, Sendable {
    public var text: LocalizedStringResource
    public var textColor: Color
    public var systemImageName: String
    public init(text: LocalizedStringResource, textColor: Color, systemImageName: String) {
        self.text = text
        self.textColor = textColor
        self.systemImageName = systemImageName
    }
    // A colour does not encode: the alarm never leaves the page.
    enum CodingKeys: String, CodingKey { case text, systemImageName }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(LocalizedStringResource.self, forKey: .text)
        systemImageName = try c.decode(String.self, forKey: .systemImageName)
        textColor = .white
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(systemImageName, forKey: .systemImageName)
    }
}

/// How an alarm presents itself while alerting, counting down and paused.
public struct AlarmPresentation: Codable, Hashable, Sendable {
    public struct Alert: Codable, Hashable, Sendable {
        public enum SecondaryButtonBehavior: Codable, Hashable, Sendable { case countdown, custom }
        public var title: LocalizedStringResource
        public var stopButton: AlarmButton?
        public var secondaryButton: AlarmButton?
        public var secondaryButtonBehavior: SecondaryButtonBehavior?
        public init(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: SecondaryButtonBehavior? = nil) {
            self.title = title
            self.secondaryButton = secondaryButton
            self.secondaryButtonBehavior = secondaryButtonBehavior
        }
        public init(title: LocalizedStringResource, stopButton: AlarmButton, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: SecondaryButtonBehavior? = nil) {
            self.title = title
            self.stopButton = stopButton
            self.secondaryButton = secondaryButton
            self.secondaryButtonBehavior = secondaryButtonBehavior
        }
    }
    public struct Countdown: Codable, Hashable, Sendable {
        public var title: LocalizedStringResource
        public var pauseButton: AlarmButton?
        public init(title: LocalizedStringResource, pauseButton: AlarmButton? = nil) {
            self.title = title
            self.pauseButton = pauseButton
        }
    }
    public struct Paused: Codable, Hashable, Sendable {
        public var title: LocalizedStringResource
        public var resumeButton: AlarmButton
        public init(title: LocalizedStringResource, resumeButton: AlarmButton) {
            self.title = title
            self.resumeButton = resumeButton
        }
    }
    public var alert: Alert
    public var countdown: Countdown?
    public var paused: Paused?
    public init(alert: Alert, countdown: Countdown? = nil, paused: Paused? = nil) {
        self.alert = alert
        self.countdown = countdown
        self.paused = paused
    }
}

/// An alarm's state as its Live Activity shows it.
public struct AlarmPresentationState: Codable, Hashable, Sendable {
    public enum Mode: Codable, Hashable, Sendable { case alert, countdown, paused }
    public var alarmID: Alarm.ID
    public var mode: Mode
    public init(alarmID: Alarm.ID, mode: Mode) {
        self.alarmID = alarmID
        self.mode = mode
    }
}

/// The attributes of an alarm's Live Activity.
public struct AlarmAttributes<Metadata: AlarmMetadata>: ActivityAttributes, Sendable {
    public typealias ContentState = AlarmPresentationState
    public var presentation: AlarmPresentation
    public var metadata: Metadata?
    public var tintColor: Color
    public init(presentation: AlarmPresentation, metadata: Metadata? = nil, tintColor: Color) {
        self.presentation = presentation
        self.metadata = metadata
        self.tintColor = tintColor
    }
    enum CodingKeys: String, CodingKey { case presentation, metadata }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        presentation = try c.decode(AlarmPresentation.self, forKey: .presentation)
        metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
        tintColor = .accentColor
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(presentation, forKey: .presentation)
        try c.encodeIfPresent(metadata, forKey: .metadata)
    }
}

/// An alarm.
public struct Alarm: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = UUID
    public enum State: Codable, Hashable, Sendable { case scheduled, countdown, paused, alerting }
    public enum Schedule: Codable, Hashable, Sendable {
        case fixed(Date)
        case relative(Relative)
        public struct Relative: Codable, Hashable, Sendable {
            public struct Time: Codable, Hashable, Sendable {
                public var hour: Int
                public var minute: Int
                public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
            }
            public enum Recurrence: Codable, Hashable, Sendable { case never, weekly([Locale.Weekday]) }
            public var time: Time
            public var repeats: Recurrence
            public init(time: Time, repeats: Recurrence = .never) { self.time = time; self.repeats = repeats }
        }
    }
    public struct CountdownDuration: Codable, Hashable, Sendable {
        public var preAlert: TimeInterval?
        public var postAlert: TimeInterval?
        public init(preAlert: TimeInterval?, postAlert: TimeInterval?) { self.preAlert = preAlert; self.postAlert = postAlert }
    }
    public var id: UUID
    public var schedule: Schedule?
    public var countdownDuration: CountdownDuration?
    public var state: State
}

/// Schedules and manages alarms (none are authorized on the web).
public final class AlarmManager: @unchecked Sendable {
    public enum AlarmError: Error, Sendable { case maximumLimitReached, unauthorized }
    public enum AuthorizationState: Codable, Hashable, Sendable { case notDetermined, denied, authorized }

    /// What an alarm is: its schedule or countdown, its presentation and its intents.
    public struct AlarmConfiguration<Metadata: AlarmMetadata> {
        public var countdownDuration: Alarm.CountdownDuration?
        public var schedule: Alarm.Schedule?
        public var attributes: AlarmAttributes<Metadata>
        public init(countdownDuration: Alarm.CountdownDuration? = nil, schedule: Alarm.Schedule? = nil, attributes: AlarmAttributes<Metadata>,
                    stopIntent: (any LiveActivityIntent)? = nil, secondaryIntent: (any LiveActivityIntent)? = nil,
                    sound: AlertConfiguration.AlertSound = .default) {
            self.countdownDuration = countdownDuration
            self.schedule = schedule
            self.attributes = attributes
        }
        public static func timer(duration: TimeInterval, attributes: AlarmAttributes<Metadata>, stopIntent: (any LiveActivityIntent)? = nil,
                                 secondaryIntent: (any LiveActivityIntent)? = nil, sound: AlertConfiguration.AlertSound = .default) -> AlarmConfiguration<Metadata> {
            AlarmConfiguration(countdownDuration: Alarm.CountdownDuration(preAlert: duration, postAlert: nil), attributes: attributes,
                               stopIntent: stopIntent, secondaryIntent: secondaryIntent, sound: sound)
        }
        public static func alarm(schedule: Alarm.Schedule? = nil, attributes: AlarmAttributes<Metadata>, stopIntent: (any LiveActivityIntent)? = nil,
                                 secondaryIntent: (any LiveActivityIntent)? = nil, sound: AlertConfiguration.AlertSound = .default) -> AlarmConfiguration<Metadata> {
            AlarmConfiguration(schedule: schedule, attributes: attributes, stopIntent: stopIntent, secondaryIntent: secondaryIntent, sound: sound)
        }
    }

    public static let shared = AlarmManager()
    init() {}

    public var authorizationState: AuthorizationState { .denied }
    public func requestAuthorization() async throws -> AuthorizationState { .denied }
    public var alarms: [Alarm] { get throws { [] } }
    public var alarmUpdates: AsyncStream<[Alarm]> { AsyncStream { $0.finish() } }
    public var authorizationUpdates: AsyncStream<AuthorizationState> { AsyncStream { $0.finish() } }

    /// Schedules an alarm: refused on the web.
    public func schedule<Metadata: AlarmMetadata>(id: Alarm.ID, configuration: AlarmConfiguration<Metadata>) async throws -> Alarm {
        throw AlarmError.unauthorized
    }
    public func countdown(id: Alarm.ID) throws {}
    public func cancel(id: Alarm.ID) throws {}
    public func stop(id: Alarm.ID) throws {}
    public func pause(id: Alarm.ID) throws {}
    public func resume(id: Alarm.ID) throws {}
}
