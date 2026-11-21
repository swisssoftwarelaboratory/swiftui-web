// EventKit on the web: a page cannot reach the person's calendars, so the event store answers
// every access request as a person who declined it would (not granted, no error) and reports the
// access as denied. The entity types are values an app fills and hands to the store, so the code
// that writes an event compiles and runs; saving without access throws, as it does on a device.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation

/// The kinds of entity an event store holds.
public enum EKEntityType: UInt, Sendable {
    case event = 0
    case reminder = 1
}

/// Whether the app may reach the store's entities of a type.
public enum EKAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case fullAccess = 3
    case writeOnly = 4
    @available(*, deprecated, renamed: "fullAccess")
    public static var authorized: EKAuthorizationStatus { .fullAccess }
}

/// Which occurrences of a recurring event a change applies to.
public enum EKSpan: Int, Sendable {
    case thisEvent = 0
    case futureEvents = 1
}

/// The completion an access request calls: whether access was granted, and an error.
public typealias EKEventStoreRequestAccessCompletionHandler = @Sendable (Bool, (any Error)?) -> Void

/// The errors an event store throws.
public struct EKError: Error, Sendable, Equatable {
    public enum Code: Int, Sendable {
        case eventStoreNotAuthorized = 29
        case noCalendar = 1
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static var eventStoreNotAuthorized: Code { .eventStoreNotAuthorized }
    public static var noCalendar: Code { .noCalendar }
}

/// A calendar: a named collection of events.
public final class EKCalendar: @unchecked Sendable {
    public var title: String
    public let calendarIdentifier: String
    public var allowsContentModifications: Bool { modifiable }
    private let modifiable: Bool
    init(title: String, modifiable: Bool = false) { self.title = title; self.modifiable = modifiable; calendarIdentifier = UUID().uuidString }
}

/// The base of events and reminders: what they have in common.
open class EKCalendarItem: @unchecked Sendable {
    public var calendar: EKCalendar!
    public var title: String! = ""
    public var location: String?
    public var notes: String?
    public var url: URL?
    public var calendarItemIdentifier: String { identifier }
    public var hasNotes: Bool { notes?.isEmpty == false }
    let identifier = UUID().uuidString
    init() {}
}

/// An event in a calendar.
public final class EKEvent: EKCalendarItem, @unchecked Sendable {
    public var startDate: Date!
    public var endDate: Date!
    public var isAllDay = false
    public var eventIdentifier: String! { identifier }
    public var timeZone: TimeZone?

    /// A new event for `eventStore`, in no calendar until one is set.
    public init(eventStore: EKEventStore) { super.init() }
}

/// The store of the person's calendars, which a page cannot reach. Inside the drawn iPhone
/// (new-website#710) it asks as iOS does, once, and an allowed app finds the empty calendar of
/// an iPhone with nothing in it yet: one calendar, the events it saves this visit.
open class EKEventStore: @unchecked Sendable {
    public init() {}

    /// The access the app has: denied, the answer the requests give; the drawn iPhone's kept
    /// answer inside it.
    open class func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus {
        guard _PhoneCalendar.inPhone else { return .denied }
        switch _PhonePrompts.answer(entityType == .event ? _PhoneCalendar.events : _PhoneCalendar.reminders) {
        case "full": return .fullAccess
        case "writeOnly": return .writeOnly
        case "deny": return .denied
        default: return .notDetermined
        }
    }

    /// Asks for access to read and write events: not granted (asked in the drawn iPhone).
    open func requestFullAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) {
        _PhoneCalendar.ask(.event, full: true, answered: completion)
    }
    /// Asks for access to add events: not granted (asked in the drawn iPhone).
    open func requestWriteOnlyAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) {
        _PhoneCalendar.ask(.event, full: false, answered: completion)
    }
    /// Asks for access to reminders: not granted (asked in the drawn iPhone).
    open func requestFullAccessToReminders(completion: @escaping EKEventStoreRequestAccessCompletionHandler) {
        _PhoneCalendar.ask(.reminder, full: true, answered: completion)
    }
    /// Asks for access to the entities of a type: since iOS 17 it asks nothing and grants nothing.
    open func requestAccess(to entityType: EKEntityType, completion: @escaping EKEventStoreRequestAccessCompletionHandler) { completion(false, nil) }

    open func requestFullAccessToEvents() async throws -> Bool {
        await withCheckedContinuation { done in requestFullAccessToEvents { granted, _ in done.resume(returning: granted) } }
    }
    open func requestWriteOnlyAccessToEvents() async throws -> Bool {
        await withCheckedContinuation { done in requestWriteOnlyAccessToEvents { granted, _ in done.resume(returning: granted) } }
    }
    open func requestFullAccessToReminders() async throws -> Bool {
        await withCheckedContinuation { done in requestFullAccessToReminders { granted, _ in done.resume(returning: granted) } }
    }
    open func requestAccess(to entityType: EKEntityType) async throws -> Bool { false }

    /// The calendar new events go to: none without access.
    open var defaultCalendarForNewEvents: EKCalendar? { canWrite ? _PhoneCalendar.calendar : nil }
    /// The calendars holding entities of a type: none without access.
    open func calendars(for entityType: EKEntityType) -> [EKCalendar] {
        entityType == .event && Self.authorizationStatus(for: .event) == .fullAccess ? [_PhoneCalendar.calendar] : []
    }

    /// Saves an event: without access it throws, as the store does on a device.
    open func save(_ event: EKEvent, span: EKSpan) throws { try save(event, span: span, commit: true) }
    open func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        guard canWrite else { throw EKError(.eventStoreNotAuthorized) }
        if event.calendar == nil { event.calendar = _PhoneCalendar.calendar }
        _PhoneCalendar.saved.removeAll { $0 === event }
        _PhoneCalendar.saved.append(event)
    }
    /// Removes an event: without access it throws.
    open func remove(_ event: EKEvent, span: EKSpan) throws { try remove(event, span: span, commit: true) }
    open func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        guard Self.authorizationStatus(for: .event) == .fullAccess else { throw EKError(.eventStoreNotAuthorized) }
        _PhoneCalendar.saved.removeAll { $0 === event }
    }
    /// Writes pending changes: there are none.
    open func commit() throws {}

    /// The event with this identifier: none without access.
    open func event(withIdentifier identifier: String) -> EKEvent? {
        guard Self.authorizationStatus(for: .event) == .fullAccess else { return nil }
        return _PhoneCalendar.saved.first { $0.eventIdentifier == identifier }
    }

    private var canWrite: Bool {
        let status = Self.authorizationStatus(for: .event)
        return status == .fullAccess || status == .writeOnly
    }
}

/// Calendars and reminders inside the drawn iPhone (new-website#710).
enum _PhoneCalendar {
    static let events = "calendar"
    static let reminders = "reminders"
    /// The iPhone's one calendar, and what the app saved to it this visit.
    static let calendar = EKCalendar(title: _PhonePrompts.german ? "Kalender" : "Calendar", modifiable: true)
    nonisolated(unsafe) static var saved: [EKEvent] = []

    static var inPhone: Bool {
        #if os(WASI)
        return _PhonePrompts.isPresent
        #else
        return false
        #endif
    }

    /// iOS's alert for full or write-only access; a write-only app asking for full access is
    /// asked again. Outside the drawn iPhone: not granted.
    static func ask(_ type: EKEntityType, full: Bool, answered: @escaping EKEventStoreRequestAccessCompletionHandler) {
        guard inPhone else { answered(false, nil); return }
        let name = type == .event ? events : reminders
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess || status == .denied || (status == .writeOnly && !full) {
            Task { @MainActor in answered(status != .denied, nil) }
            return
        }
        let german = _PhonePrompts.german
        let app = _PhonePrompts.quotedName
        let title: String
        var message: String
        var buttons = [_PhonePrompts.dontAllow, _PhonePrompts.allow]
        var allowIndex = 1
        switch (type, full) {
        case (.event, true):
            // Full access stacks its buttons, Allow Full Access on top, with iOS's own line
            // under the app's usage text.
            title = german ? "Darf \(app) auf deinen Kalender zugreifen?" : "Allow \(app) to access your calendar?"
            message = _PhonePrompts.usage("NSCalendarsFullAccessUsageDescription")
            let extra = german ? "Kalenderereignisse k\u{00F6}nnen zus\u{00E4}tzliche Daten wie Orte, E-Mail-Adressen oder Notizen enthalten."
                : "Calendar events may include additional data, such as locations, email addresses, or notes."
            message = [message, extra].filter { !$0.isEmpty }.joined(separator: "\n\n")
            buttons = [german ? "Vollen Zugriff erlauben" : "Allow Full Access", _PhonePrompts.dontAllow]
            allowIndex = 0
        case (.event, false):
            title = german ? "Darf \(app) Ereignisse zu deinem Kalender hinzuf\u{00FC}gen?" : "Allow \(app) to add events to your calendar?"
            message = _PhonePrompts.usage("NSCalendarsWriteOnlyAccessUsageDescription")
        default:
            title = german ? "Darf \(app) auf deine Erinnerungen zugreifen?" : "Allow \(app) to access your reminders?"
            message = _PhonePrompts.usage("NSRemindersFullAccessUsageDescription")
        }
        let allowAt = allowIndex
        _PhonePrompts.askAlert(name, title: title, message: message, buttons: buttons, fallback: 1 - allowAt) { index in
            if index == allowAt {
                _PhonePrompts.setAnswer(name, full ? "full" : "writeOnly")
            } else if status == .notDetermined {
                _PhonePrompts.setAnswer(name, "deny")
            }
            let now = EKEventStore.authorizationStatus(for: type)
            answered(full ? now == .fullAccess : (now == .fullAccess || now == .writeOnly), nil)
        }
    }
}
