// ActivityKit on the web: Live Activities. A page has no Lock Screen or Dynamic Island, so
// activities are not enabled: `ActivityAuthorizationInfo().areActivitiesEnabled` is false, a
// request throws, and the list of running activities stays empty. An app's "Live Activities
// off" path is the one that runs. Accepted for source compatibility.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc
#endif

/// The static and dynamic data of a Live Activity.
public protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Decodable & Encodable & Hashable
}

/// Whether the person allows Live Activities (never on the web).
public struct ActivityAuthorizationInfo: Sendable {
    public init() {}
    public var areActivitiesEnabled: Bool { false }
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

/// A Live Activity (none start on the web).
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

    /// Requests an activity: refused on the web (`.unsupported`).
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }
    public static func request(attributes: Attributes, contentState: ContentState, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil, style: ActivityStyle) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    /// The running activities: none on the web.
    public static var activities: [Activity<Attributes>] { [] }
    public static var activityUpdates: AsyncStream<Activity<Attributes>> { AsyncStream { $0.finish() } }
    public var activityStateUpdates: AsyncStream<ActivityState> { AsyncStream { $0.finish() } }
    public var contentUpdates: AsyncStream<ActivityContent<ContentState>> { AsyncStream { $0.finish() } }
    public var pushTokenUpdates: AsyncStream<Data> { AsyncStream { $0.finish() } }

    public func update(_ content: ActivityContent<ContentState>) async { self.content = content }
    public func update(_ content: ActivityContent<ContentState>, alertConfiguration: AlertConfiguration?) async { self.content = content }
    public func update(using contentState: ContentState) async { content = ActivityContent(state: contentState, staleDate: nil) }
    public func end(_ content: ActivityContent<ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        if let content { self.content = content }
        activityState = .ended
    }
    public func end(using contentState: ContentState? = nil, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        activityState = .ended
    }
}
