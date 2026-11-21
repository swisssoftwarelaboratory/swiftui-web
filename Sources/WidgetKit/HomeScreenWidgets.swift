// Home screen widgets as an app's widget extension declares them, running live in the drawn
// iPhone (new-website#638): `StaticConfiguration` and `AppIntentConfiguration` with their timeline
// providers. Each widget the extension offers in a home screen size shows once, in the size an
// iPhone's widget gallery leads with (medium when it offers it, else small, else large); its
// provider gives a timeline, the entry for now is drawn by the widget's own view, the next entry
// takes over at its date, and a new timeline comes as its reload policy says or when the app asks
// (`WidgetCenter.reloadTimelines`). Accessory families go to the lock screen's row.
import AppIntents
import SwiftUI

// MARK: - Families and environment

extension WidgetFamily {
    var phoneSize: _PhoneWidgetSize? {
        switch self {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: nil
        }
    }

    /// The family's size on the iPhone 16's screen.
    var displaySize: CGSize {
        switch self {
        case .systemSmall: CGSize(width: 158, height: 158)
        case .systemMedium: CGSize(width: 338, height: 158)
        case .systemLarge: CGSize(width: 338, height: 354)
        case .systemExtraLarge: CGSize(width: 338, height: 354)
        case .accessoryCircular: CGSize(width: 72, height: 72)
        case .accessoryRectangular: CGSize(width: 160, height: 72)
        case .accessoryInline: CGSize(width: 234, height: 26)
        case .accessoryCorner: CGSize(width: 72, height: 72)
        }
    }

    static let homeScreenFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    static let iPhoneFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline]
}

private struct WidgetFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily = .systemSmall
}

extension EnvironmentValues {
    /// The size of the widget the view draws.
    public var widgetFamily: WidgetFamily {
        get { self[WidgetFamilyKey.self] }
        set { self[WidgetFamilyKey.self] = newValue }
    }
}

extension ContainerBackgroundPlacement {
    /// The background of a widget: drawn behind the whole widget, under its content margins.
    public static let widget = ContainerBackgroundPlacement("widget")
}

// MARK: - Timeline providers

/// What a provider is told about the widget it makes a timeline for.
public struct TimelineProviderContext: Sendable {
    /// The widget's size.
    public let family: WidgetFamily
    /// Whether the widget gallery is asking (never here: the widget is on the home screen).
    public let isPreview: Bool
    /// The widget's size in points.
    public let displaySize: CGSize

    init(family: WidgetFamily) {
        self.family = family
        isPreview = false
        displaySize = family.displaySize
    }
}

/// Makes the entries a widget shows over time.
public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    typealias Context = TimelineProviderContext
    /// An entry with stand-in content, shown while the timeline loads.
    func placeholder(in context: Context) -> Entry
    /// One entry for now, for the widget gallery.
    func getSnapshot(in context: Context, completion: @escaping @Sendable (Entry) -> Void)
    /// The entries for now and later, and when to ask again.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<Entry>) -> Void)
}

/// Makes the entries a configurable widget shows over time, for its intent's settings.
public protocol AppIntentTimelineProvider {
    associatedtype Entry: TimelineEntry
    associatedtype Intent: WidgetConfigurationIntent
    typealias Context = TimelineProviderContext
    func placeholder(in context: Context) -> Entry
    // Asked on the main actor: the page has one thread, and the widget's view is made there.
    @MainActor func snapshot(for configuration: Intent, in context: Context) async -> Entry
    @MainActor func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry>
}

// MARK: - Configurations

/// What a home screen widget's configuration gives the host: how to get its timeline and draw an
/// entry.
@MainActor
protocol _TimelineWidget {
    var kind: String { get }
    var families: [WidgetFamily] { get }
    var marginsDisabled: Bool { get }
    /// The placeholder's view.
    func placeholderView(family: WidgetFamily) -> AnyView
    /// Asks the provider for a timeline: each entry's date and view, and the reload policy.
    func loadTimeline(family: WidgetFamily, _ done: @escaping @MainActor ([(date: Date, view: AnyView)], TimelineReloadPolicy) -> Void)
}

/// A widget whose content the person can't configure.
@MainActor @preconcurrency
public struct StaticConfiguration<Content: View>: WidgetConfiguration, _TimelineWidget {
    let kind: String
    var families: [WidgetFamily] = WidgetFamily.iPhoneFamilies
    var marginsDisabled = false
    private let placeholder: @MainActor (WidgetFamily) -> AnyView
    private let timeline: @MainActor (WidgetFamily, @escaping @MainActor ([(date: Date, view: AnyView)], TimelineReloadPolicy) -> Void) -> Void

    public init<Provider: TimelineProvider>(kind: String, provider: Provider,
                                            @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider.Entry: SendableMetatype {
        self.kind = kind
        placeholder = { family in AnyView(content(provider.placeholder(in: TimelineProviderContext(family: family)))) }
        timeline = { family, done in
            nonisolated(unsafe) let content = content
            nonisolated(unsafe) let done = done
            provider.getTimeline(in: TimelineProviderContext(family: family)) { timeline in
                // The page has one thread: the provider answers on the main actor.
                nonisolated(unsafe) let timeline = timeline
                MainActor.assumeIsolated {
                    done(timeline.entries.map { (date: $0.date, view: AnyView(content($0))) }, timeline.policy)
                }
            }
        }
    }

    func placeholderView(family: WidgetFamily) -> AnyView { placeholder(family) }
    func loadTimeline(family: WidgetFamily, _ done: @escaping @MainActor ([(date: Date, view: AnyView)], TimelineReloadPolicy) -> Void) {
        timeline(family, done)
    }
}

/// A widget whose content the person configures through an intent (shown with its defaults).
@MainActor @preconcurrency
public struct AppIntentConfiguration<Intent: WidgetConfigurationIntent, Content: View>: WidgetConfiguration, _TimelineWidget {
    let kind: String
    var families: [WidgetFamily] = WidgetFamily.iPhoneFamilies
    var marginsDisabled = false
    private let placeholder: @MainActor (WidgetFamily) -> AnyView
    private let timeline: @MainActor (WidgetFamily, @escaping @MainActor ([(date: Date, view: AnyView)], TimelineReloadPolicy) -> Void) -> Void

    public init<Provider: AppIntentTimelineProvider>(kind: String, intent: Intent.Type = Intent.self, provider: Provider,
                                                     @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider.Intent == Intent {
        self.kind = kind
        placeholder = { family in AnyView(content(provider.placeholder(in: TimelineProviderContext(family: family)))) }
        timeline = { family, done in
            nonisolated(unsafe) let provider = provider
            nonisolated(unsafe) let content = content
            Task { @MainActor in
                let timeline = await provider.timeline(for: Intent(), in: TimelineProviderContext(family: family))
                done(timeline.entries.map { (date: $0.date, view: AnyView(content($0))) }, timeline.policy)
            }
        }
    }

    func placeholderView(family: WidgetFamily) -> AnyView { placeholder(family) }
    func loadTimeline(family: WidgetFamily, _ done: @escaping @MainActor ([(date: Date, view: AnyView)], TimelineReloadPolicy) -> Void) {
        timeline(family, done)
    }
}

/// The settings a widget's configuration takes, read by the host.
@MainActor
protocol _WidgetSettings {
    func settingFamilies(_ families: [WidgetFamily]) -> Self
    func settingMarginsDisabled() -> Self
}

extension StaticConfiguration: _WidgetSettings {
    func settingFamilies(_ families: [WidgetFamily]) -> Self { var copy = self; copy.families = families; return copy }
    func settingMarginsDisabled() -> Self { var copy = self; copy.marginsDisabled = true; return copy }
}

extension AppIntentConfiguration: _WidgetSettings {
    func settingFamilies(_ families: [WidgetFamily]) -> Self { var copy = self; copy.families = families; return copy }
    func settingMarginsDisabled() -> Self { var copy = self; copy.marginsDisabled = true; return copy }
}

extension WidgetConfiguration {
    /// The sizes the widget offers.
    public func supportedFamilies(_ families: [WidgetFamily]) -> Self {
        (self as? any _WidgetSettings).flatMap { $0.settingFamilies(families) as? Self } ?? self
    }
    /// The widget draws to its edges, without the system's content margins.
    public func contentMarginsDisabled() -> Self {
        (self as? any _WidgetSettings).flatMap { $0.settingMarginsDisabled() as? Self } ?? self
    }
    /// The widget's name in the widget gallery (there is none here).
    public func configurationDisplayName(_ name: String) -> Self { self }
    public func configurationDisplayName(_ name: LocalizedStringKey) -> Self { self }
    public func configurationDisplayName(_ name: Text) -> Self { self }
    /// The widget's description in the widget gallery (there is none here).
    public func description(_ text: String) -> Self { self }
    public func description(_ text: LocalizedStringKey) -> Self { self }
    public func description(_ text: Text) -> Self { self }
    /// Whether the widget's background is removable (always kept here).
    public func containerBackgroundRemovable(_ removable: Bool = true) -> Self { self }
}

// MARK: - The running widgets

/// One widget on the phone: its timeline, the entry shown now, and the next change.
@MainActor
final class _RunningWidget {
    let configuration: any _TimelineWidget
    let family: WidgetFamily
    /// The entry's view shown now; each new one goes to the widget's tree.
    private(set) var content: AnyView {
        didSet { onContent?(content) }
    }
    var onContent: (@MainActor (AnyView) -> Void)?
    private var entries: [(date: Date, view: AnyView)] = []
    private var next: Task<Void, Never>?

    init(configuration: any _TimelineWidget, family: WidgetFamily) {
        self.configuration = configuration
        self.family = family
        content = configuration.placeholderView(family: family)
    }

    /// Asks the provider for a new timeline.
    func reload() {
        configuration.loadTimeline(family: family) { [weak self] entries, policy in
            guard let self else { return }
            self.entries = entries.sorted { $0.date < $1.date }
            self.show(policy: policy)
        }
    }

    /// Shows the entry for now and waits for the next one, or for the reload the policy asks for.
    private func show(policy: TimelineReloadPolicy) {
        next?.cancel()
        let now = Date()
        if let current = entries.last(where: { $0.date <= now }) ?? entries.first {
            content = current.view
        }
        let upcoming = entries.first { $0.date > now }?.date
        let reloadAt: Date? = switch policy.kind {
        case .atEnd: entries.last.map { max($0.date, now.addingTimeInterval(5 * 60)) }
        case .after(let date): date
        case .never: nil
        }
        guard let wake = [upcoming, reloadAt].compactMap({ $0 }).min() else { return }
        next = Task { [weak self] in
            let seconds = max(0.05, wake.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if let upcoming, wake == upcoming, reloadAt.map({ upcoming < $0 }) ?? true {
                self.show(policy: policy)
            } else {
                self.reload()
            }
        }
    }
}

/// A widget's frame: its content inside the system's margins, its container background behind
/// the whole widget, its family in the environment.
struct _WidgetFrame: View {
    let content: AnyView
    let family: WidgetFamily
    let margins: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(margins ? 16 : 0)
            .backgroundPreferenceValue(_WidgetContainerBackgroundKey.self) { background in
                background ?? AnyView(Color.white)
            }
            .environment(\.widgetFamily, family)
    }
}

extension _WidgetHost {
    /// The widgets running on the phone, by kind.
    static var running: [(kind: String, widget: _RunningWidget)] = []

    /// Makes the phone's widgets from the extension: the home screen's, then the lock screen's.
    static func phoneWidgets() -> (home: [_PhoneWidget], lock: [_HostedTree]) {
        running = []
        guard let host = _DrawnPhoneSystem.hostRuntime else { return ([], []) }
        var home: [_PhoneWidget] = []
        var lock: [_HostedTree] = []
        for entry in entries {
            guard let configuration = entry.configuration as? any _TimelineWidget else { continue }
            let offered = configuration.families
            if let family = [WidgetFamily.systemMedium, .systemSmall, .systemLarge].first(where: offered.contains), let size = family.phoneSize {
                let tree = run(configuration, family: family, margins: !configuration.marginsDisabled, host: host)
                home.append(_PhoneWidget(tree: tree, size: size))
            }
            if let family = [WidgetFamily.accessoryRectangular, .accessoryCircular].first(where: offered.contains) {
                lock.append(run(configuration, family: family, margins: false, host: host))
            }
        }
        for (_, widget) in running { widget.reload() }
        return (home, lock)
    }

    /// A widget running in a tree of its own, its entries shown as its timeline goes.
    private static func run(_ configuration: any _TimelineWidget, family: WidgetFamily, margins: Bool, host: Runtime) -> _HostedTree {
        let widget = _RunningWidget(configuration: configuration, family: family)
        func frame(_ content: AnyView) -> AnyView { AnyView(_WidgetFrame(content: content, family: family, margins: margins)) }
        let tree = _HostedTree(frame(widget.content), host: host)
        tree.setFixedSize(family.displaySize)
        widget.onContent = { [weak tree] content in tree?.update(frame(content)) }
        running.append((configuration.kind, widget))
        return tree
    }

    /// The app asked for new timelines (`nil` for every kind).
    static func reload(kind: String?) {
        for (widgetKind, widget) in running where kind == nil || widgetKind == kind { widget.reload() }
    }

    /// The widgets on the phone, as `WidgetCenter` reports them.
    static var configured: [WidgetInfo] {
        running.map { WidgetInfo(kind: $0.kind, family: $0.widget.family) }
    }
}
