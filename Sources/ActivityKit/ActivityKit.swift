// ActivityKit on the web: Live Activities. A plain page has no Lock Screen, so activities are not
// enabled there: `ActivityAuthorizationInfo().areActivitiesEnabled` is false, a request throws,
// and the list of running activities stays empty (the app's "Live Activities off" path runs).
// Inside the drawn iPhone (new-website#643) they run as on iOS: WidgetKit installs the host
// below once the app's widget extension is loaded, a request starts an activity the phone's
// lock screen draws with the extension's own view, and `update` and `end` reach it.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc
#endif

/// What runs the activities (WidgetKit, for the drawn iPhone). Type-erased: the attributes and
/// content are the app's own values.
public enum _ActivityKitHost {
    /// Whether activities can start now.
    nonisolated(unsafe) public static var enabled: (() -> Bool)?
    /// An activity started: its id, attributes and content (an `ActivityContent<State>`).
    nonisolated(unsafe) public static var started: (@MainActor (_ id: String, _ attributes: Any, _ content: Any) -> Void)?
    /// Its content changed.
    nonisolated(unsafe) public static var updated: (@MainActor (_ id: String, _ attributes: Any, _ content: Any) -> Void)?
    /// It ended; `immediately` takes it off the lock screen at once.
    nonisolated(unsafe) public static var ended: (@MainActor (_ id: String, _ immediately: Bool) -> Void)?

    static var isEnabled: Bool { enabled?() ?? false }

    static func onMain(_ body: @escaping @MainActor () -> Void) {
        nonisolated(unsafe) let body = body
        Task { @MainActor in body() }
    }
}

/// The running activities by attributes type, in the order they started.
nonisolated(unsafe) private var running: [ObjectIdentifier: [AnyObject]] = [:]

/// The static and dynamic data of a Live Activity.
public protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Decodable & Encodable & Hashable
}

/// Whether the person allows Live Activities (in the drawn iPhone; never on a plain page).
public struct ActivityAuthorizationInfo: Sendable {
    public init() {}
    public var areActivitiesEnabled: Bool { _ActivityKitHost.isEnabled }
    public var frequentPushesEnabled: Bool { false }
    public var activityEnablementUpdates: AsyncStream<Bool> { AsyncStream { $0.finish() } }
}

/// A Live Activity's state.
public enum ActivityState: Sendable, Codable, Hashable {
    case active, ended, dismissed, stale, pending
}

/// How an ended activity leaves the Lock Screen.
public struct ActivityUIDismissalPolicy: Hashable, Sendable {
    package enum Kind: Hashable, Sendable { case `default`, immediate, after(Date) }
    package let kind: Kind
    public static let `default` = ActivityUIDismissalPolicy(kind: .default)
    public static let immediate = ActivityUIDismissalPolicy(kind: .immediate)
    public static func after(_ date: Date) -> ActivityUIDismissalPolicy { ActivityUIDismissalPolicy(kind: .after(date)) }
}

/// How an activity is updated by push.
public struct PushType: Hashable, Sendable {
    public static let token = PushType()
    public static func channel(_ channelId: String) -> PushType { PushType() }
}

/// Where an activity shows.
public enum ActivityStyle: Hashable, Sendable { case standard, transient }

/// A content state with when it goes stale and how relevant it is.
public struct ActivityContent<State: Decodable & Encodable & Hashable>: Hashable {
    public let state: State
    public let staleDate: Date?
    public let relevanceScore: Double
    public init(state: State, staleDate: Date?, relevanceScore: Double = 0) {
        self.state = state
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

extension ActivityContent: Sendable where State: Sendable {}

/// An alert that lights the screen when an activity updates.
public struct AlertConfiguration: Equatable, Sendable {
    public var title: LocalizedStringResource
    public var body: LocalizedStringResource
    public var sound: AlertSound
    public init(title: LocalizedStringResource, body: LocalizedStringResource, sound: AlertSound) {
        self.title = title
        self.body = body
        self.sound = sound
    }
    public struct AlertSound: Equatable, Sendable {
        package let name: String?
        public static var `default`: AlertSound { AlertSound(name: nil) }
        public static func named(_ name: String) -> AlertSound { AlertSound(name: name) }
    }
}

/// The errors of requesting an activity.
public enum ActivityAuthorizationError: Error, Sendable {
    case attributesTooLarge, denied, globalMaximumExceeded, malformedActivityIdentifier, missingProcessIdentifier,
         persistenceFailure, reconnectNotPermitted, targetMaximumExceeded, unentitled, unsupported, unsupportedTarget, visibility
}

/// A Live Activity: started in the drawn iPhone, refused on a plain page.
public final class Activity<Attributes: ActivityAttributes>: Identifiable, @unchecked Sendable {
    public typealias ContentState = Attributes.ContentState
    public typealias ID = String

    public let id: String
    public let attributes: Attributes
    public private(set) var content: ActivityContent<ContentState>
    public private(set) var activityState: ActivityState = .active
    public var contentState: ContentState { content.state }
    public var pushToken: Data? { nil }

    init(attributes: Attributes, content: ActivityContent<ContentState>) {
        id = UUID().uuidString
        self.attributes = attributes
        self.content = content
    }

    private static var kind: ObjectIdentifier { ObjectIdentifier(Attributes.self) }

    /// Requests an activity: it runs in the drawn iPhone; elsewhere `.unsupported`.
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil) throws -> Activity<Attributes> {
        guard _ActivityKitHost.isEnabled else { throw ActivityAuthorizationError.unsupported }
        let activity = Activity(attributes: attributes, content: content)
        running[kind, default: []].append(activity)
        let id = activity.id
        nonisolated(unsafe) let attributes = attributes, content = content
        _ActivityKitHost.onMain { _ActivityKitHost.started?(id, attributes, content) }
        return activity
    }
    public static func request(attributes: Attributes, contentState: ContentState, pushType: PushType? = nil) throws -> Activity<Attributes> {
        try request(attributes: attributes, content: ActivityContent(state: contentState, staleDate: nil), pushType: pushType)
    }
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil, style: ActivityStyle) throws -> Activity<Attributes> {
        try request(attributes: attributes, content: content, pushType: pushType)
    }

    /// The running activities of this kind.
    public static var activities: [Activity<Attributes>] { (running[kind] ?? []).compactMap { $0 as? Activity<Attributes> } }
    public static var activityUpdates: AsyncStream<Activity<Attributes>> { AsyncStream { $0.finish() } }
    public var activityStateUpdates: AsyncStream<ActivityState> { AsyncStream { $0.finish() } }
    public var contentUpdates: AsyncStream<ActivityContent<ContentState>> { AsyncStream { $0.finish() } }
    public var pushTokenUpdates: AsyncStream<Data> { AsyncStream { $0.finish() } }

    public func update(_ content: ActivityContent<ContentState>) async { apply(content) }
    public func update(_ content: ActivityContent<ContentState>, alertConfiguration: AlertConfiguration?) async { apply(content) }
    public func update(using contentState: ContentState) async { apply(ActivityContent(state: contentState, staleDate: nil)) }
    public func end(_ content: ActivityContent<ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        if let content { apply(content) }
        finish(dismissalPolicy)
    }
    public func end(using contentState: ContentState? = nil, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        if let contentState { apply(ActivityContent(state: contentState, staleDate: nil)) }
        finish(dismissalPolicy)
    }

    private func apply(_ content: ActivityContent<ContentState>) {
        guard activityState == .active else { return }
        self.content = content
        let id = id
        nonisolated(unsafe) let attributes = attributes, content = content
        _ActivityKitHost.onMain { _ActivityKitHost.updated?(id, attributes, content) }
    }

    /// Ended: out of the running list. The lock screen keeps an ended activity until it is
    /// dismissed (`.default`), takes it off at once (`.immediate`) or at the given date.
    private func finish(_ policy: ActivityUIDismissalPolicy) {
        guard activityState == .active else { return }
        activityState = .ended
        running[Self.kind]?.removeAll { $0 === self }
        let id = id
        switch policy.kind {
        case .immediate:
            _ActivityKitHost.onMain { _ActivityKitHost.ended?(id, true) }
        case .default:
            _ActivityKitHost.onMain { _ActivityKitHost.ended?(id, false) }
        case .after(let date):
            let wait = max(0, date.timeIntervalSinceNow)
            Task { @MainActor in
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                _ActivityKitHost.ended?(id, true)
            }
        }
    }
}
