// AlarmKit on the web: alarms and timers that ring over the Lock Screen. A page cannot ring
// when it is closed, so alarms are never authorized: `authorizationState` is `.denied`,
// `requestAuthorization()` answers `.denied` and scheduling throws. An app's fallback (a
// notification, say) is the path that runs. Accepted for source compatibility.
//
// Inside the drawn iPhone (new-website#710) alarms ask as iOS does: `requestAuthorization()`
// (or the first `schedule`) shows iOS's alert once and keeps the answer, and an allowed alarm
// is scheduled and listed, counting down or paused as asked, but it waits: nothing rings on
// the drawn lock screen until what an alarm does there is decided.
@_exported import ActivityKit
import WebFoundation
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

    public var authorizationState: AuthorizationState {
        guard Self.inPhone else { return .denied }
        switch _PhonePrompts.allowed(Self.name) {
        case true?: return .authorized
        case false?: return .denied
        case nil: return .notDetermined
        }
    }

    public func requestAuthorization() async throws -> AuthorizationState {
        guard Self.inPhone else { return .denied }
        if authorizationState != .notDetermined { return authorizationState }
        // The simulator refuses AlarmKit without an alert: the English is from published
        // screenshots, the German follows iOS's "Darf ..." alerts (new-website#710).
        let title = _PhonePrompts.german ? "Darf \(_PhonePrompts.quotedName) Wecker und Timer planen?"
            : "Allow \(_PhonePrompts.quotedName) to schedule alarms and timers?"
        let allowed: Bool = await withCheckedContinuation { done in
            _PhonePrompts.askAllow(Self.name, title: title, usageKey: "NSAlarmKitUsageDescription") { done.resume(returning: $0) }
        }
        let state: AuthorizationState = allowed ? .authorized : .denied
        for continuation in authorizationWatchers.values { continuation.yield(state) }
        return state
    }

    public var alarms: [Alarm] { get throws { scheduled } }

    public var alarmUpdates: AsyncStream<[Alarm]> {
        AsyncStream { continuation in
            let id = UUID()
            alarmWatchers[id] = continuation
            continuation.yield(scheduled)
            continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.alarmWatchers[id] = nil } }
            if !Self.inPhone { continuation.finish() }
        }
    }

    public var authorizationUpdates: AsyncStream<AuthorizationState> {
        AsyncStream { continuation in
            let id = UUID()
            authorizationWatchers[id] = continuation
            continuation.yield(authorizationState)
            continuation.onTermination = { [weak self] _ in Task { @MainActor in self?.authorizationWatchers[id] = nil } }
            if !Self.inPhone { continuation.finish() }
        }
    }

    /// Schedules an alarm: refused on the web; inside the drawn iPhone it asks first when it
    /// was never asked, as iOS does, and an allowed alarm waits in the list.
    public func schedule<Metadata: AlarmMetadata>(id: Alarm.ID, configuration: AlarmConfiguration<Metadata>) async throws -> Alarm {
        guard Self.inPhone else { throw AlarmError.unauthorized }
        let state = authorizationState == .notDetermined ? try await requestAuthorization() : authorizationState
        guard state == .authorized else { throw AlarmError.unauthorized }
        let alarm = Alarm(id: id, schedule: configuration.schedule, countdownDuration: configuration.countdownDuration,
                          state: configuration.schedule == nil && configuration.countdownDuration != nil ? .countdown : .scheduled)
        scheduled.removeAll { $0.id == id }
        scheduled.append(alarm)
        changed()
        return alarm
    }
    public func countdown(id: Alarm.ID) throws { try set(id, .countdown) }
    public func cancel(id: Alarm.ID) throws { remove(id) }
    public func stop(id: Alarm.ID) throws { remove(id) }
    public func pause(id: Alarm.ID) throws { try set(id, .paused) }
    public func resume(id: Alarm.ID) throws { try set(id, .countdown) }

    // MARK: Inside the drawn iPhone

    static let name = "alarms"
    static var inPhone: Bool {
        #if os(WASI)
        return _PhonePrompts.isPresent
        #else
        return false
        #endif
    }

    private var scheduled: [Alarm] = []
    private var alarmWatchers: [UUID: AsyncStream<[Alarm]>.Continuation] = [:]
    private var authorizationWatchers: [UUID: AsyncStream<AuthorizationState>.Continuation] = [:]

    private func set(_ id: Alarm.ID, _ state: Alarm.State) throws {
        guard let index = scheduled.firstIndex(where: { $0.id == id }) else { return }
        scheduled[index].state = state
        changed()
    }

    private func remove(_ id: Alarm.ID) {
        guard scheduled.contains(where: { $0.id == id }) else { return }
        scheduled.removeAll { $0.id == id }
        changed()
    }

    private func changed() {
        for continuation in alarmWatchers.values { continuation.yield(scheduled) }
    }
}

// Apple's `LocalizedStringResource` is Equatable but not Hashable on macOS, where the fork's
// tests build this module too: the presentations hash a resource by its key (equality stays
// the synthesized one).
extension AlarmButton {
    public func hash(into hasher: inout Hasher) { hasher.combine(text.key); hasher.combine(systemImageName) }
}
extension AlarmPresentation.Alert {
    public func hash(into hasher: inout Hasher) { hasher.combine(title.key); hasher.combine(stopButton); hasher.combine(secondaryButton); hasher.combine(secondaryButtonBehavior) }
}
extension AlarmPresentation.Countdown {
    public func hash(into hasher: inout Hasher) { hasher.combine(title.key); hasher.combine(pauseButton) }
}
extension AlarmPresentation.Paused {
    public func hash(into hasher: inout Hasher) { hasher.combine(title.key); hasher.combine(resumeButton) }
}
