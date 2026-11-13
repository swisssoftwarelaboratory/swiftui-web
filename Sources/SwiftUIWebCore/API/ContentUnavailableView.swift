// ContentUnavailableView (Docs/elements/ContentUnavailableView.md): the label's icon above
// its title (title3 bold, secondary), a description (title3, secondary) and actions, top-aligned
// in the space the view fills (macOS 27 and iOS; a NavigationStack centres it at its own
// height); the icon goes when the column does not fit the height on offer.

/// An interface, consisting of a label and additional content, that you display when the
/// content of your app is unavailable to users.
public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    package let label: Label
    package let description: Description
    package let actions: Actions

    /// Creates an interface with a label, a description and actions.
    public init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
                @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: some View {
        // The column is its own height, centred by whatever holds it (a 175 pt frame puts the
        // tray 22.75 down; stacks centre a run of them). When it does not fit the height on
        // offer, the title-only column fills it from the top (`unavailable/corners` `plain`: a
        // 190 pt frame drops the tray; a 169 pt one too, 169.5 keeps it).
        ViewThatFits(in: .vertical) {
            _UnavailableColumn(label: label, description: description, actions: actions, showsIcon: true)
            // `minHeight: 0`: a column taller than the height on offer still takes only that
            // height, from the top (without it a flexible frame is never shorter than its child).
            _UnavailableColumn(label: label, description: description, actions: actions, showsIcon: false)
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The unavailable view's column: the label (with or without its icon), the description 6
/// below it and 12 above what follows, the actions 6 below, 20 above everything and 26 beneath
/// (20 when there are actions).
struct _UnavailableColumn<Label: View, Description: View, Actions: View>: View {
    let label: Label
    let description: Description
    let actions: Actions
    let showsIcon: Bool

    var body: some View {
        let hasActions = Actions.self != EmptyView.self
        VStack(spacing: 0) {
            label.labelStyle(_UnavailableLabelStyle(showsIcon: showsIcon))
            if Description.self != EmptyView.self {
                description.font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.top, PlatformMetrics.unavailableDescriptionGap).padding(.bottom, PlatformMetrics.unavailableDescriptionBottom)
            }
            if hasActions {
                HStack { actions }.padding(.top, PlatformMetrics.unavailableActionsGap)
            }
        }
        .padding(.top, PlatformMetrics.unavailableTopPadding)
        .padding(.bottom, hasActions ? PlatformMetrics.unavailableActionsBottomPadding : PlatformMetrics.unavailableBottomPadding)
        .fixedSize(horizontal: false, vertical: true)   // keeps its lines in a short cell (iOS `search` wraps to two)
    }
}

/// The unavailable view's label: the icon (a symbol at 36 pt, the tertiary colour) above the
/// title (title3 bold, secondary), 24 apart, both centred; without the icon when the column
/// does not fit (`ViewThatFits` above).
struct _UnavailableLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: PlatformMetrics.unavailableIconGap) {
            if showsIcon {
                configuration.icon.font(.system(size: PlatformMetrics.unavailableIconSize)).foregroundStyle(.tertiary)
            }
            configuration.title.font(.title3).fontWeight(.bold).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}

extension ContentUnavailableView where Label == SwiftUIWebCore.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// Creates an interface with a title, an image and a description.
    public init(_ title: LocalizedStringKey, image: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, image: image)
        self.description = description
        actions = EmptyView()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, image: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, image: image)
        self.description = description
        actions = EmptyView()
    }

    /// Creates an interface with a title, a system image and a description.
    public init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, systemImage: systemImage)
        self.description = description
        actions = EmptyView()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, systemImage: String, description: Text? = nil) {
        label = SwiftUIWebCore.Label(title, systemImage: systemImage)
        self.description = description
        actions = EmptyView()
    }
}

extension ContentUnavailableView where Label == SwiftUIWebCore.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    /// The interface for an empty search: "No Results" with a spelling hint.
    public static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }

    /// The interface for a search with no results for `text`.
    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView("No Results for \u{201C}\(text)\u{201D}", systemImage: "magnifyingglass", description: Text("Check the spelling or try a new search."))
    }
}
