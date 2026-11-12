// WidgetKit on the web: the calls an app's own target makes to its widgets. A page has no
// home screen, so there are no widgets to reload: `WidgetCenter` accepts every reload and
// reports no configured widgets, as on a device where the user has added none. The timeline
// types are values, so code shared between an app and its widget extension compiles and runs.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation
#if os(WASI)
@_exported import WASILibc   // libm, which Apple's Foundation re-exports through Darwin
#endif

/// The sizes a widget can take.
public enum WidgetFamily: Int, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case systemSmall = 0
    case systemMedium = 1
    case systemLarge = 2
    case systemExtraLarge = 3
    case accessoryCorner = 4
    case accessoryCircular = 5
    case accessoryRectangular = 6
    case accessoryInline = 7

    public var description: String {
        switch self {
        case .systemSmall: "systemSmall"
        case .systemMedium: "systemMedium"
        case .systemLarge: "systemLarge"
        case .systemExtraLarge: "systemExtraLarge"
        case .accessoryCorner: "accessoryCorner"
        case .accessoryCircular: "accessoryCircular"
        case .accessoryRectangular: "accessoryRectangular"
        case .accessoryInline: "accessoryInline"
        }
    }
}

/// A widget the user has configured.
public struct WidgetInfo: Sendable, CustomStringConvertible {
    /// The widget's kind, as its configuration names it.
    public let kind: String
    /// The size the user chose.
    public let family: WidgetFamily

    public var description: String { "WidgetInfo(kind: \(kind), family: \(family))" }
}

/// The app's way to tell its widgets that their data changed.
public final class WidgetCenter: @unchecked Sendable {
    /// The shared center.
    public static let shared = WidgetCenter()

    private init() {}

    /// Reloads the timelines of every widget the app has (none on the web).
    public func reloadAllTimelines() {}

    /// Reloads the timelines of the widgets of one kind (none on the web).
    public func reloadTimelines(ofKind kind: String) {}

    /// The widgets the user has configured: none on the web.
    public func getCurrentConfigurations(_ completion: @escaping (Result<[WidgetInfo], any Error>) -> Void) {
        completion(.success([]))
    }

    /// The widgets the user has configured: none on the web.
    public func currentConfigurations() async throws -> [WidgetInfo] { [] }

    /// Tells the system the app's widgets may have changed which kinds they offer.
    public func invalidateConfigurationRecommendations() {}
}

/// A type that specifies the date to display a widget, and, optionally, its relevance.
public protocol TimelineEntry {
    /// The date for WidgetKit to render the widget.
    var date: Date { get }
    /// How relevant this entry is to show, compared with others.
    var relevance: TimelineEntryRelevance? { get }
}

extension TimelineEntry {
    public var relevance: TimelineEntryRelevance? { nil }
}

/// How relevant a timeline entry is, compared with the others.
public struct TimelineEntryRelevance: Codable, Hashable, Sendable {
    public let score: Float
    public let duration: TimeInterval

    public init(score: Float, duration: TimeInterval = 0) {
        self.score = score
        self.duration = duration
    }
}

/// When WidgetKit asks for a new timeline once the entries run out.
public struct TimelineReloadPolicy: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case atEnd
        case never
        case after(Date)
    }

    let kind: Kind

    /// A new timeline after the last entry's date.
    public static let atEnd = TimelineReloadPolicy(kind: .atEnd)
    /// No new timeline until the app asks for one.
    public static let never = TimelineReloadPolicy(kind: .never)
    /// A new timeline after `date`.
    public static func after(_ date: Date) -> TimelineReloadPolicy { TimelineReloadPolicy(kind: .after(date)) }
}

/// The entries of a widget's timeline and when to ask for the next one.
public struct Timeline<EntryType: TimelineEntry> {
    public let entries: [EntryType]
    public let policy: TimelineReloadPolicy

    public init(entries: [EntryType], policy: TimelineReloadPolicy) {
        self.entries = entries
        self.policy = policy
    }
}

extension Timeline: Sendable where EntryType: Sendable {}
