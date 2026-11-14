// Navigation stack runtime: the stack keeps its root and one node per pushed entry, all laid out
// under their own bars, paints the top one, and takes its size from it (Docs/elements/Navigation.md).
// On iOS a push or pop slides between the two screens and a pushed screen's bar carries a back
// button (Docs/elements/iOS.md).

@MainActor
package final class NavigationStackNode: LayoutNode<_NavigationStackHost>, _FrameSubscriber, _StartsOnScreen {
    package private(set) var root: TypedNode<AnyView>!
    package private(set) var context: _NavigationContext!

    /// One pushed view.
    package final class Entry {
        package enum Kind { case value(AnyHashable), view, presented(Binding<Bool>, owner: ObjectIdentifier) }
        package let kind: Kind
        package var view: AnyView?
        package var node: ViewNode?
        /// Whether the screen sits under a large-title bar; assumed until its content is read.
        var largeBar = true
        /// Whether its content has scrolled the large title away (the bar is the inline one).
        var collapsed = false
        init(kind: Kind, view: AnyView?) { self.kind = kind; self.view = view }
    }

    package private(set) var entries: [Entry] = []
    private var lastValues: [AnyHashable] = []
    /// Destination builders registered by `navigationDestination(for:)` in the subtree, by type.
    package var destinations: [ObjectIdentifier: _NavigationDestinationBuilder] = [:]
    /// The back button in the bar over a pushed screen (iOS): hit-tested as a child, painted with the bar.
    private var backButton: NavigationBackButtonNode!
    /// A push or pop sliding between two screens (iOS), and its progress: a paint-only
    /// animation driven by the frame subscribers, so the page is not laid out again each frame.
    private var slide: Slide?
    private var slideTween: Tween?
    /// iOS (ios/search): the `searchable` field at the bottom of the top screen, and the scope
    /// bar under the hidden bar while the search is presented; laid out with the screens.
    private var searchBar: TypedNode<AnyView>?
    private var scopeBar: TypedNode<AnyView>?
    /// iOS (ios/sheet/nav): the `toolbar` items in the screens' subtrees, shown as pills in the
    /// top screen's bar; a hosted subtree like the search chrome, hit tested as a child.
    private var toolbarSources: [ToolbarSource] = []
    private var itemsBar: TypedNode<AnyView>?
    /// The top screen's bottom toolbar (`.bottomBar` items), and whether it shows this pass.
    private var bottomItemsBar: TypedNode<AnyView>?
    private var bottomBarShown = false

    package func registerToolbar(_ node: ViewNode, items: [_ToolbarItemData]) {
        if let index = toolbarSources.firstIndex(where: { $0.node === node }) {
            toolbarSources[index].items = items
        } else {
            toolbarSources.append(ToolbarSource(node: node, items: items))
        }
        runtime.requestLayout(invalidatingSizes: true)
    }

    package func unregisterToolbar(_ node: ViewNode) {
        toolbarSources.removeAll { $0.node === node || $0.node == nil }
        runtime.requestLayout(invalidatingSizes: true)
    }

    /// The items whose `toolbar` sits in one of `nodes`' subtrees (a screen's).
    private func toolbarItems(over nodes: [ViewNode]) -> [_ToolbarItemData] {
        toolbarSources.filter { source in
            guard let node = source.node, node.isMounted else { return false }
            var current: ViewNode? = node
            while let candidate = current {
                if nodes.contains(where: { $0 === candidate }) { return true }
                if candidate === self { return false }
                current = candidate.parent
            }
            return false
        }.flatMap(\.items)
    }

    /// Inside a sheet (ios/sheet/nav) the bar sits `sheetNavigationBarTopInset` lower.
    private var barTopInset: CGFloat {
        guard environment.platformProfile.isIOS else { return 0 }
        var current = parent
        while let node = current {
            if let presentation = node as? PresentationNode {
                return presentation.kind == .sheet && !presentation.options.fullScreen ? PlatformMetrics.sheetNavigationBarTopInset : 0
            }
            if node is NavigationStackNode { return 0 }
            current = node.parent
        }
        return 0
    }

    package init(_ context: _NodeContext<_NavigationStackHost>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        self.context = _NavigationContext(stack: self)
        backButton = NavigationBackButtonNode(_NodeContext(view: _NavigationBackButton(), parent: self, environment: context.environment))
        root = AnyView._makeNode(_NodeContext(view: context.view.root, parent: self, environment: contentEnvironment(large: rootLarge)))
        lastValues = context.view.values
        _ = reconcile(with: context.view.values)
        settleBarModes(force: false)
    }

    /// The environment of the root (`pushed` false) or of a pushed destination.
    private func contentEnvironment(large: Bool, pushed: Bool = false) -> EnvironmentValues {
        var environment = environment
        environment._navigationContext = context
        environment.dismiss = DismissAction { [weak self] in self?.pop() }
        if pushed { environment.isPresented = true }
        environment._underNavigationBar = environment.platformProfile.isIOS && large
        environment._navigationBarOverhang = environment.platformProfile.isIOS
            ? (large ? PlatformMetrics.navigationBarLargeHeight : PlatformMetrics.navigationBarInlineHeight) + barTopInset : 0
        return environment
    }

    /// Whether the root sits under a large-title bar (iOS lists drop their top inset there).
    /// Assumed until the content is mounted and its display mode read; corrected in a second pass.
    private var rootLarge = true
    private var rootCollapsed = false

    private func settleBarModes(force: Bool) {
        guard environment.platformProfile.isIOS else { return }
        var previousLarge = false
        for (index, screen) in screens.enumerated() {
            let bar = bar(over: screen.nodes, index: index, previousLarge: previousLarge, hiddenBySearch: false)
            previousLarge = bar?.large ?? false
            let actual = bar?.large ?? false
            if let entry = screen.entry {
                if entry.largeBar != actual {
                    entry.largeBar = actual
                    refresh(entry, force: force)
                }
            } else if rootLarge != actual {
                rootLarge = actual
                root.update(view: view.root, environment: contentEnvironment(large: actual), force: force)
            }
        }
    }

    // MARK: Screens and their iOS bars

    /// The root and each pushed entry that has a node, bottom to top.
    private struct Screen {
        let nodes: [ViewNode]
        let entry: Entry?
    }

    private var screens: [Screen] {
        [Screen(nodes: root.layoutChildren, entry: nil)] + entries.compactMap { entry in entry.node.map { Screen(nodes: $0.layoutChildren, entry: entry) } }
    }

    /// The layout nodes of the root and of each pushed view, bottom to top.
    private var groups: [[ViewNode]] { screens.map(\.nodes) }

    /// The bar over a screen: its title and display mode come from the modifiers in the
    /// screen's subtree (ios/nav/basic: a 117 pt bar with the large title; ios/nav/inline: 64),
    /// and a pushed screen gets a back button unless it hides it (ios/nav/push*).
    private struct Bar {
        /// The title drawn (nil for an untitled bar: `navigationTitle("")` with items, ios/sheet/nav).
        var title: String?
        /// A large-title bar (the screen's content lays out under it without its own top inset).
        var large: Bool
        /// Whether the large title is scrolled away, leaving the inline bar (ios/nav/scroll).
        var collapsed: Bool
        var back: Bool
        var height: CGFloat
        var items: [_ToolbarItemData]
        var showsLargeTitle: Bool { large && !collapsed }
    }

    /// The bar over screen `index` whose nodes are `nodes`, or nil when nothing shows one: an
    /// untitled root, or a pushed screen with neither a title nor a back button (ios/nav/push-noback
    /// fills the whole stack). `.automatic` inherits the previous screen's large title.
    /// A back at the root (a compact split view's detail, shown by a sidebar selection): its
    /// bar carries a back button, and popping the root runs this.
    package var rootBack: (@MainActor () -> Void)? {
        didSet { if (oldValue == nil) != (rootBack == nil) { runtime.requestLayout() } }
    }

    /// The back at the root: this stack's own or, for a stack that is the content of an
    /// enclosing stack's root with nothing pushed (an app's `NavigationStack` in a split view's
    /// detail), the enclosing stack's.
    private var effectiveRootBack: (@MainActor () -> Void)? {
        if let rootBack { return rootBack }
        var node = parent
        while let current = node, !(current is PresentationNode) {
            if let stack = current as? NavigationStackNode { return stack.entries.isEmpty ? stack.rootBack : nil }
            node = current.parent
        }
        return nil
    }

    /// Whether a navigation stack sits in `node`'s subtree outside any presentation: that stack
    /// draws the screen's bar (a split view's detail wrapping its own `NavigationStack`).
    private static func holdsStack(_ node: ViewNode) -> Bool {
        node.structuralChildren.contains { child in
            !(child is PresentationNode) && (child is NavigationStackNode || holdsStack(child))
        }
    }

    private func bar(over nodes: [ViewNode], index: Int, previousLarge: Bool, collapsed: Bool = false, hiddenBySearch: Bool = true) -> Bar? {
        guard environment.platformProfile.isIOS, let top = nodes.first else { return nil }
        if nodes.contains(where: Self.holdsStack) { return nil }
        // A presented search hides the bar (ios/search/active) unless the search keeps it; the
        // content still lays out as under its bar (`settleBarModes`: the list keeps no top inset).
        if hiddenBySearch, let search = search(over: nodes), search.isPresented, !search.searchSource.keepsBar { return nil }
        let title = (top.descendants(where: { $0 is any _NavigationTitleProviding }).first as? any _NavigationTitleProviding)?._navigationTitle
        let mode = (top.descendants(where: { $0 is any _NavigationTitleDisplayModeProviding }).first as? any _NavigationTitleDisplayModeProviding)?._titleDisplayMode ?? .automatic
        let hidesBack = (top.descendants(where: { $0 is any _NavigationBackButtonHiddenProviding }).first as? any _NavigationBackButtonHiddenProviding)?._hidesBackButton ?? false
        // `toolbar(.hidden, for: .navigationBar)` / `toolbarVisibility` in the screen: no bar,
        // so no title, items or back button (the screen draws its own chrome, as on iOS).
        let barVisibility = (top.descendants(where: { ($0 as? any _NavigationBarVisibilityProviding)?._navigationBarVisibility != nil }).first
            as? any _NavigationBarVisibilityProviding)?._navigationBarVisibility
        if barVisibility == .hidden { return nil }
        let back = (index > 0 || effectiveRootBack != nil) && !hidesBack
        let items = toolbarItems(over: nodes).filter(\.placement.isInIOSNavigationBar)
        guard title != nil || back || !items.isEmpty else { return nil }
        var large: Bool
        switch mode {
        case .inline: large = false
        case .large: large = true
        default: large = index == 0 || previousLarge
        }
        // An empty title (ios/sheet/nav) is an inline bar with nothing to draw; a principal item
        // takes the title's place in the inline bar (UIKit's titleView: the title is not drawn).
        if title == nil || title == "" { large = false }
        let principal = items.contains { $0.placement.iOSGroup == .principal }
        if principal { large = false }
        let showsLarge = large && !collapsed
        return Bar(title: title == "" || principal ? nil : title, large: large, collapsed: large && collapsed, back: back,
                   height: (showsLarge ? PlatformMetrics.navigationBarLargeHeight : PlatformMetrics.navigationBarInlineHeight) + barTopInset, items: items)
    }

    /// What the bars are computed from besides the screens' subtrees.
    private struct BarsKey: Equatable {
        var tree: UInt64
        var requests: UInt64
        var collapsed: [Bool]
        var rootBack: Bool
        var topInset: CGFloat
        /// The heights come from the metrics selected where the bars are asked for, which are
        /// not always this stack's (ios/nav/push: the root screen measured after a pop).
        var heights: [CGFloat]
    }
    private var barsMemo: (key: BarsKey, bars: [Bar?])?

    /// The bars over `screens`, bottom to top. Remembered until a node is created, updated or
    /// removed anywhere, a collapse or the root's back changes, or a full layout is requested:
    /// each computation walks every screen's subtree several times, and a pass asked for them
    /// about five times, a paint once more (new-website#216: 15% of a real app's layout).
    private var bars: [Bar?] {
        let key = BarsKey(tree: runtime.treeVersion, requests: runtime.fullLayoutRequests,
                          collapsed: [rootCollapsed] + entries.map(\.collapsed), rootBack: effectiveRootBack != nil, topInset: barTopInset,
                          heights: [PlatformMetrics.navigationBarLargeHeight, PlatformMetrics.navigationBarInlineHeight])
        if let memo = barsMemo, memo.key == key { return memo.bars }
        let result = computeBars()
        barsMemo = (key, result)
        return result
    }

    private func computeBars() -> [Bar?] {
        var result: [Bar?] = []
        var previousLarge = false
        for (index, screen) in screens.enumerated() {
            let bar = bar(over: screen.nodes, index: index, previousLarge: previousLarge, collapsed: screen.entry?.collapsed ?? rootCollapsed)
            previousLarge = bar?.large ?? false
            result.append(bar)
        }
        return result
    }

    // MARK: The search field (iOS)

    /// The `searchable` in a screen's subtree: iOS 26 puts its field at the bottom of the screen.
    /// A `searchable` on the stack itself (outside it, above this node) is the root screen's.
    private func search(over nodes: [ViewNode]) -> (any _SearchProviding)? {
        guard environment.platformProfile.isIOS, let top = nodes.first else { return nil }
        if let provider = Self.nearestSearch(in: top) { return provider }
        guard root.layoutChildren.first === top else { return nil }
        var current = parent
        while let candidate = current {
            if candidate is NavigationStackNode || candidate is PresentationNode { return nil }
            if let provider = candidate as? any _SearchProviding { return provider }
            current = candidate.parent
        }
        return nil
    }

    /// The first `searchable` in `node`'s subtree outside any nested stack: a stack inside a
    /// screen (a split view's detail that is a `NavigationStack` of its own) shows its own field.
    private static func nearestSearch(in node: ViewNode) -> (any _SearchProviding)? {
        if let provider = node as? any _SearchProviding { return provider }
        if node is NavigationStackNode { return nil }
        for child in node.structuralChildren {
            if let provider = nearestSearch(in: child) { return provider }
        }
        return nil
    }

    /// What the search takes from a screen (ios/search): a 76 pt band at the bottom for the
    /// field at rest, 60 while presented; presented, the hidden bar leaves a 10 pt inset at the
    /// top and an active scope bar a 44 pt band under it.
    private struct SearchChrome {
        var source: SearchSource
        var presented: Bool
        var scopes: SearchScopeSource?
        var top: CGFloat
        var bottom: CGFloat
    }

    private func searchChrome(over nodes: [ViewNode]) -> SearchChrome? {
        guard let provider = search(over: nodes) else { return nil }
        let source = provider.searchSource
        let presented = provider.isPresented
        let scopes = presented ? runtime.activeSearchScopes : nil
        var top: CGFloat = presented && !source.keepsBar ? PlatformMetrics.searchPresentedTopInset : 0
        if scopes != nil { top += PlatformMetrics.searchScopeBandHeight }
        return SearchChrome(source: source, presented: presented, scopes: scopes, top: top,
                            bottom: presented ? PlatformMetrics.searchPresentedBandHeight : PlatformMetrics.searchBandHeight)
    }

    /// Mounts, updates or drops the field and the scope bar for this layout pass, and places them.
    private func layoutSearchChrome(_ chrome: SearchChrome?, barHeight: CGFloat) {
        guard let chrome else {
            searchBar?.unmount()
            searchBar = nil
            scopeBar?.unmount()
            scopeBar = nil
            return
        }
        let barView = AnyView(_IOSSearchBarView(source: chrome.source, presented: chrome.presented))
        if let searchBar {
            searchBar.update(view: barView, environment: environment, force: false)
        } else {
            searchBar = AnyView._makeNode(_NodeContext(view: barView, parent: self, environment: environment))
        }
        let band = CGRect(x: 0, y: frame.height - chrome.bottom, width: frame.width, height: chrome.bottom)
        for node in searchBar?.layoutChildren ?? [] {
            node.place(at: band.origin, anchor: .topLeading, proposal: ProposedViewSize(band.size), by: self)
        }
        if let scopes = chrome.scopes {
            let scopeView = AnyView(_IOSSearchScopeBarView(scopes: scopes))
            if let scopeBar {
                scopeBar.update(view: scopeView, environment: environment, force: false)
            } else {
                scopeBar = AnyView._makeNode(_NodeContext(view: scopeView, parent: self, environment: environment))
            }
            let bandRect = CGRect(x: 0, y: barHeight + chrome.top - PlatformMetrics.searchScopeBandHeight, width: frame.width,
                                  height: PlatformMetrics.searchScopeBandHeight)
            for node in scopeBar?.layoutChildren ?? [] {
                node.place(at: bandRect.origin, anchor: .topLeading, proposal: ProposedViewSize(bandRect.size), by: self)
            }
        } else {
            scopeBar?.unmount()
            scopeBar = nil
        }
    }

    private var searchChromeNodes: [ViewNode] { (scopeBar?.layoutChildren ?? []) + (searchBar?.layoutChildren ?? []) }

    /// Mounts, updates or drops the top screen's bar items (iOS) and places them across the bar.
    private func layoutItemsBar(_ bar: Bar?) {
        guard let bar, !bar.items.isEmpty else {
            itemsBar?.unmount()
            itemsBar = nil
            return
        }
        let view = AnyView(_IOSBarItemsView(items: bar.items))
        var environment = environment
        environment._automaticLabelContext = .toolbar
        if let itemsBar {
            itemsBar.update(view: view, environment: environment, force: false)
        } else {
            itemsBar = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        }
        let band = CGRect(x: 0, y: barTopInset, width: frame.width, height: PlatformMetrics.navigationBarInlineHeight)
        for node in itemsBar?.layoutChildren ?? [] {
            node.place(at: band.origin, anchor: .topLeading, proposal: ProposedViewSize(band.size), by: self)
        }
    }

    private var itemsBarNodes: [ViewNode] { itemsBar?.layoutChildren ?? [] }

    /// Mounts, updates or drops the top screen's bottom toolbar (iOS) and returns the band it
    /// takes at the bottom of the screen: none while its items show nothing (an item whose
    /// content is an `if` that is false), as UIKit hides an empty toolbar.
    private func mountBottomBar(over nodes: [ViewNode]) -> CGFloat {
        let items = environment.platformProfile.isIOS ? toolbarItems(over: nodes).filter { $0.placement.iOSGroup == .bottom } : []
        guard !items.isEmpty else {
            bottomItemsBar?.unmount()
            bottomItemsBar = nil
            bottomBarShown = false
            return 0
        }
        let view = AnyView(_IOSBottomBarItemsView(items: items))
        var environment = environment
        environment._automaticLabelContext = .toolbar
        if let bottomItemsBar {
            bottomItemsBar.update(view: view, environment: environment, force: false)
        } else {
            bottomItemsBar = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        }
        let row = ProposedViewSize(width: bottomBarRowWidth, height: PlatformMetrics.navigationBarItemHeight)
        bottomBarShown = bottomBarNodes.contains { node in
            let size = node.sizeThatFits(row)
            return size.width > 0 && size.height > 0
        }
        return bottomBarShown ? PlatformMetrics.searchBandHeight : 0
    }

    private var bottomBarRowWidth: CGFloat { max(0, frame.width - 2 * PlatformMetrics.navigationBarItemInset) }

    /// Places the bottom toolbar's row in its band, above the search field's band if any (the
    /// row's pills centred where the field at rest is).
    private func placeBottomBar(band: CGFloat, below: CGFloat) {
        guard bottomBarShown, band > 0 else { return }
        let y = frame.height - below - band + PlatformMetrics.searchFieldTop + (PlatformMetrics.searchFieldHeight - PlatformMetrics.navigationBarItemHeight) / 2
        for node in bottomBarNodes {
            node.place(at: CGPoint(x: PlatformMetrics.navigationBarItemInset, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bottomBarRowWidth, height: PlatformMetrics.navigationBarItemHeight), by: self)
        }
    }

    private var bottomBarNodes: [ViewNode] { bottomItemsBar?.layoutChildren ?? [] }
    private var shownBottomBarNodes: [ViewNode] { bottomBarShown ? bottomBarNodes : [] }

    /// The bars' hosted items over the screens: the top bar's, the bottom bar's, the search's.
    private var chromeNodes: [ViewNode] {
        var nodes = itemsBarNodes
        nodes += shownBottomBarNodes
        nodes += searchChromeNodes
        return nodes
    }

    // MARK: The large title collapsing as the screen scrolls (iOS)

    /// The top screen's scroll view, whose offset drives its bar (found at layout).
    private weak var topScrollView: ViewNode?
    /// Set when a collapse state flipped during a layout pass: the screen is placed again.
    private var collapseChanged = false

    /// A scroll view inside the stack moved. Scrolled past the large title (ios/nav/scroll:
    /// `row8`, the bar is 64 and the content frame grows, its offset reduced by the difference so
    /// what is on screen stays put); back at the top it expands again. A little scrolling leaves
    /// the bar large with the content sliding under it (`row1`).
    package func scrollDidChange(_ node: ViewNode & _Scrollable) {
        guard environment.platformProfile.isIOS, node === topScrollView, let screen = screens.last, let bar = bars.last ?? nil, bar.large else { return }
        let collapsed = screen.entry?.collapsed ?? rootCollapsed
        let offset = node.contentOffset.y
        let collapse = PlatformMetrics.navigationLargeTitleCollapse
        if !collapsed, offset >= collapse {
            setCollapsed(true, on: screen)
            // The frame of a scroll view below the bar grows by the collapse, so its offset
            // shrinks to keep the content put; one extending under the bar (`ignoresSafeArea`)
            // keeps its frame and its offset (ios/nav/ignores: row 8 stays at the window's top).
            let extendsUnderBar = node.frameInRoot.minY - frameInRoot.minY < bar.height - 0.5
            if !extendsUnderBar { _ = node.scroll(by: CGSize(width: 0, height: -collapse)) }
        } else if collapsed, offset <= 0 {
            setCollapsed(false, on: screen)
        } else {
            return
        }
        if runtime.isLayingOut { collapseChanged = true } else { runtime.requestFullLayout() }
    }

    private func setCollapsed(_ collapsed: Bool, on screen: Screen) {
        if let entry = screen.entry { entry.collapsed = collapsed } else { rootCollapsed = collapsed }
    }

    /// How far the top screen's content has scrolled the large title up, 0 to its height.
    private var largeTitleScroll: CGFloat {
        guard let scroll = topScrollView as? (ViewNode & _Scrollable) else { return 0 }
        return min(max(0, scroll.contentOffset.y), PlatformMetrics.navigationLargeTitleCollapse)
    }

    override package func update(view: _NavigationStackHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        changingScreens {
            root.update(view: view.root, environment: contentEnvironment(large: rootLarge), force: force)
            var retired: [Entry] = []
            if view.values != lastValues {
                lastValues = view.values
                retired = reconcile(with: view.values)
            }
            for entry in entries { refresh(entry, force: force) }
            return retired
        }
        settleBarModes(force: force)
    }

    /// Makes the value entries match the path (reusing nodes for the unchanged prefix); views
    /// pushed by destination links or `isPresented` bindings stay, after the values. Returns the
    /// entries the path dropped, still mounted (`changingScreens` retires them).
    private func reconcile(with values: [AnyHashable]) -> [Entry] {
        let valueEntries = entries.filter { if case .value = $0.kind { return true } else { return false } }
        let others = entries.filter { if case .value = $0.kind { return false } else { return true } }
        var kept: [Entry] = []
        for (index, value) in values.enumerated() {
            if index < valueEntries.count, case .value(let existing) = valueEntries[index].kind, existing == value {
                kept.append(valueEntries[index])
            } else {
                kept.append(Entry(kind: .value(value), view: nil))
            }
        }
        let retired = valueEntries.filter { entry in !kept.contains(where: { $0 === entry }) }
        // The views pushed above the path (destination links, presented destinations) stay on
        // top of whatever the path becomes: nav/path-change clears the path under a presented
        // screen and SwiftUI keeps that screen (its binding stays on).
        entries = kept + others
        return retired
    }

    /// Builds or updates an entry's node from its view (values resolve through the registry).
    private func refresh(_ entry: Entry, force: Bool) {
        if case .value(let value) = entry.kind {
            entry.view = destinations[ObjectIdentifier(type(of: value.base))]?.make(value)
        }
        guard let view = entry.view else {
            entry.node?.unmount()
            entry.node = nil
            return
        }
        if let node = entry.node as? TypedNode<AnyView> {
            node.update(view: view, environment: contentEnvironment(large: entry.largeBar, pushed: true), force: force)
        } else {
            entry.node?.unmount()
            entry.node = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: contentEnvironment(large: entry.largeBar, pushed: true)))
        }
    }

    // MARK: Pushing and popping

    /// Runs a change to the entries, then slides between the screens it swapped on iOS: the old
    /// top under a pushed one, or the popped one over the new top. The entries `body` retires
    /// stay mounted as the leaving screen until the slide ends (unmounted at once elsewhere).
    /// Told when the stack's depth changes (a compact split view shows its detail on a push and
    /// returns to its column on the pop to the root).
    package var onDepthChanged: ((_ before: Int, _ after: Int) -> Void)?

    private func changingScreens(_ body: () -> [Entry]) {
        let before = groups.last ?? []
        let count = groups.count
        let retired = body()
        let after = groups.last ?? []
        if groups.count > count {
            beginSlide(push: true, lower: before, upper: after, leaving: retired)
        } else if groups.count < count {
            beginSlide(push: false, lower: after, upper: before, leaving: retired)
        } else {
            for entry in retired { entry.node?.unmount() }
        }
        if groups.count != count { onDepthChanged?(count, groups.count) }
    }

    /// Pushes a value: appends it to the path (the binding's owner re-renders the stack).
    package func push(value: AnyHashable) {
        view.path.set(view.values + [value])
        syncWithBinding()
    }

    /// Re-reads the path after this node changed it, so a binding nobody observes still
    /// navigates (an observed one re-renders the stack as well, finding nothing to do).
    private func syncWithBinding() {
        let values = view.path.get()
        view = _NavigationStackHost(root: view.root, path: view.path, values: values)
        if values != lastValues {
            lastValues = values
            changingScreens {
                let retired = reconcile(with: values)
                for entry in entries { refresh(entry, force: false) }
                return retired
            }
        }
        runtime.requestLayout()
    }

    /// Pushes a destination view (not part of the path binding).
    package func push(view: AnyView) {
        let entry = Entry(kind: .view, view: view)
        changingScreens {
            entries.append(entry)
            refresh(entry, force: false)
            return []
        }
        runtime.requestLayout()
    }

    /// `navigationDestination(isPresented:)` turned on: pushes its view once; while it is up,
    /// a new view (an `item` destination's next item) replaces the pushed one in place.
    package func present(_ view: AnyView, isPresented: Binding<Bool>, owner: ObjectIdentifier) {
        if let existing = entries.first(where: { if case .presented(_, let o) = $0.kind { return o == owner } else { return false } }) {
            existing.view = view
            refresh(existing, force: false)
            runtime.requestLayout()
            return
        }
        let entry = Entry(kind: .presented(isPresented, owner: owner), view: view)
        changingScreens {
            entries.append(entry)
            refresh(entry, force: false)
            return []
        }
        runtime.requestLayout()
    }

    /// `navigationDestination(isPresented:)` turned off: removes its view.
    package func dismiss(owner: ObjectIdentifier) {
        guard let index = entries.firstIndex(where: { if case .presented(_, let o) = $0.kind { return o == owner } else { return false } }) else { return }
        changingScreens {
            let removed = Array(entries[index...])
            entries.removeSubrange(index...)
            return removed
        }
        runtime.requestLayout()
    }

    /// Pops the top entry. Returns false when the stack shows its root.
    @discardableResult
    package func pop() -> Bool {
        guard let top = entries.last else {
            guard let rootBack = effectiveRootBack else { return false }
            rootBack()
            return true
        }
        switch top.kind {
        case .value:
            view.path.set(Array(view.values.dropLast()))
            syncWithBinding()
        case .view:
            changingScreens { entries.removeLast(); return [top] }
            runtime.requestLayout()
        case .presented(let binding, _):
            changingScreens { entries.removeLast(); return [top] }
            binding.wrappedValue = false
            runtime.requestLayout()
        }
        return true
    }

    // MARK: The slide of a push or pop (iOS)

    /// The two screens a push or pop swaps: the pushed one slides in from the trailing edge
    /// over the old top, which travels a little the other way under a dimming; a pop reverses it.
    private struct Slide {
        let push: Bool
        /// The screen beneath: the old top of a push, the new top of a pop.
        let lower: [ViewNode]
        /// The screen on top: the pushed one, or the popped one on its way out.
        let upper: [ViewNode]
        /// The bar over the popped screen, read while its nodes were still the top.
        let upperBar: Bar?
        /// Entries a pop retired, unmounted when the slide ends.
        let leaving: [Entry]
    }

    private func beginSlide(push: Bool, lower: [ViewNode], upper: [ViewNode], leaving: [Entry]) {
        finishSlide()
        guard environment.platformProfile.isIOS, hasBeenPlaced, !lower.isEmpty, !upper.isEmpty else {
            for entry in leaving { entry.node?.unmount() }
            return
        }
        let upperBar = push ? nil : bar(over: upper, index: groups.count, previousLarge: bars.last??.large ?? false)
        slide = Slide(push: push, lower: lower, upper: upper, upperBar: upperBar, leaving: leaving)
        // UIKit's push and pop: a critical spring at ω 18.26 /s, not an ease of fixed length
        // (the simulator's push eases on to about 0.3 s, new-website#262). It starts when its
        // first frame is shown (`startOnScreen`): laying out the new screen is not part of it.
        slideTween = Tween(from: [0], to: [1], animation: Animation(spring: .navigation), start: runtime.animationClock)
        runtime.paintAnimations += 1
        runtime.subscribeFrames(self)
    }

    private func finishSlide() {
        guard let slide else { return }
        self.slide = nil
        slideTween = nil
        runtime.paintAnimations -= 1
        runtime.unsubscribeFrames(self)
        for entry in slide.leaving { entry.node?.unmount() }
        runtime.requestRepaint()
    }

    /// Each frame of a slide repaints (without laying the page out again); the last one
    /// settles the screens.
    package func frameDidAdvance() {
        if let slideTween, slideTween.isFinished(at: runtime.animationClock) { finishSlide() }
        runtime.requestRepaint()
    }

    /// A slide begun in this frame starts when the frame is shown (`Runtime.beginAnimationsOnScreen`).
    package func startOnScreen(now: Double, lateness: Double) {
        if slideTween?.start == now { slideTween?.start += lateness }
    }

    /// The slide in flight with its progress, or nil once its tween ended (finishing it then).
    private var activeSlide: (Slide, Double)? {
        guard let slide, let slideTween else { return nil }
        guard !slideTween.isFinished(at: runtime.animationClock) else {
            finishSlide()
            return nil
        }
        return (slide, slideTween.value(at: runtime.animationClock).first ?? 1)
    }

    // MARK: Layout

    private func size(of group: [ViewNode], _ proposal: ProposedViewSize) -> CGSize {
        group.reduce(CGSize.zero) { size, node in
            let fit = node.sizeThatFits(proposal)
            return CGSize(width: max(size.width, fit.width), height: max(size.height, fit.height))
        }
    }

    /// The bar over a screen is the screen's safe area: content is laid out under it, and a
    /// view that ignores the safe area extends up under the bar (ios/representable/safearea-color,
    /// safearea-ignored). A scroll view or list is laid out under the bar as well rather than
    /// extending and insetting (the goldens place its frame there).
    override package func providedSafeAreaInsets(for child: ViewNode) -> EdgeInsets {
        let bars = self.bars
        for (index, screen) in screens.enumerated() where screen.nodes.contains(where: { $0 === child }) {
            guard index < bars.count, let bar = bars[index] else { return EdgeInsets() }
            return EdgeInsets(top: bar.height, leading: 0, bottom: 0, trailing: 0)
        }
        return EdgeInsets()
    }

    /// macOS: the top screen's size. iOS: the proposal, whatever the content (ios/nav/sizing: a
    /// stack holding one word is 320 × 267.5 in a 300 pt column next to a text), the content
    /// sizing only an unspecified dimension.
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let content: CGSize
        if let bar = bars.last ?? nil {
            let inner = ProposedViewSize(width: proposal.width, height: proposal.height.map { max(0, $0 - bar.height) })
            let fit = size(of: groups.last ?? [], inner)
            content = CGSize(width: fit.width, height: fit.height + bar.height)
        } else {
            content = size(of: groups.last ?? [], proposal)
        }
        guard environment.platformProfile.isIOS else { return content }
        return CGSize(width: proposal.width ?? content.width, height: proposal.height ?? content.height)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        // A search presented since the last update hides the bar: the screens read the bar
        // modes again before they are placed (the list under it drops its top inset).
        settleBarModes(force: false)
        topScrollView = groups.last?.first?.descendants(where: { $0 is any _Scrollable }).first
        var bars = self.bars
        for pass in 0..<2 {
            // Only the root and the top screen are laid out (screens between them are not:
            // their probes never report in nav/path-change). The frame is the top screen's
            // size, but both centre in a box as large as the larger of the two, anchored at the
            // frame's top-left: a 16 pt presented screen over a 44 pt root sits 14 down and the
            // root at the frame's top; a 72 pt pushed screen holds the root 14 down.
            var placed = groups.count > 1 ? [(groups[0], bars[0]), (groups[groups.count - 1], bars[bars.count - 1])] : Array(zip(groups, bars))
            // The top screen gives the search its bands (ios/search); a lower screen is laid
            // out as if it had none.
            let chrome = searchChrome(over: groups.last ?? [])
            let chromes: [SearchChrome?] = placed.indices.map { $0 == placed.count - 1 ? chrome : nil }
            // The top screen's bottom toolbar takes a band under it too.
            let bottomBand = mountBottomBar(over: groups.last ?? [])
            let bottoms: [CGFloat] = placed.indices.map { $0 == placed.count - 1 ? bottomBand : 0 }
            if placed.isEmpty { placed = [] }
            var box = CGSize(width: frame.width, height: frame.height)
            for (((group, bar), chrome), bottom) in zip(zip(placed, chromes), bottoms) {
                let taken = (bar?.height ?? 0) + (chrome?.top ?? 0) + (chrome?.bottom ?? 0) + bottom
                let inner = taken > 0 ? ProposedViewSize(width: proposal.width, height: proposal.height.map { max(0, $0 - taken) }) : proposal
                for node in group {
                    let size = node.sizeThatFits(inner)
                    box.width = max(box.width, size.width)
                    box.height = max(box.height, size.height + taken)
                }
            }
            for (((group, bar), chrome), bottom) in zip(zip(placed, chromes), bottoms) {
                let above = (bar?.height ?? 0) + (chrome?.top ?? 0)
                let taken = above + (chrome?.bottom ?? 0) + bottom
                let inner = taken > 0 ? ProposedViewSize(width: proposal.width, height: proposal.height.map { max(0, $0 - taken) }) : proposal
                for node in group {
                    let size = node.sizeThatFits(inner)
                    node.place(at: CGPoint(x: (box.width - size.width) / 2, y: above + (box.height - taken - size.height) / 2),
                               anchor: .topLeading, proposal: inner, by: self)
                }
            }
            layoutSearchChrome(chrome, barHeight: (bars.last ?? nil)?.height ?? 0)
            layoutItemsBar(bars.last ?? nil)
            placeBottomBar(band: bottomBand, below: chrome?.bottom ?? 0)
            // Placing the content may have scrolled it (a programmatic target) past the large
            // title: the screen is placed again under the inline bar.
            guard pass == 0, collapseChanged else { break }
            collapseChanged = false
            bars = self.bars
        }
        // The back button sits at the leading edge of the top screen's bar.
        backButton.isShown = (bars.last ?? nil)?.back ?? false
        if backButton.isShown {
            let inset = PlatformMetrics.navigationBackButtonInset
            backButton.place(at: CGPoint(x: inset, y: inset + barTopInset), anchor: .topLeading, proposal: .unspecified, by: self)
        }
    }

    // MARK: Painting

    override package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        let bars = self.bars
        guard let (slide, progress) = activeSlide else {
            paintScreen(groups.last ?? [], bar: bars.last ?? nil, shift: 0, barOpacity: 1, into: &list, context: context)
            for node in chromeNodes { node.paint(into: &list, context: context.child(at: node.presentedFrame)) }
            return
        }
        let bounds = absoluteBounds(context)
        let width = bounds.width
        let parallax = PlatformMetrics.navigationPushParallax
        let lowerBar = slide.push ? (bars.count >= 2 ? bars[bars.count - 2] : nil) : bars.last ?? nil
        let upperBar = slide.push ? bars.last ?? nil : slide.upperBar
        // The upper screen's cover of the lower one: the pushed screen arriving, or the popped one still there.
        let cover = slide.push ? progress : 1 - progress
        list.append(.save)
        list.append(.clipRect(bounds))
        paintScreen(slide.lower, bar: lowerBar, shift: -width * parallax * cover, barOpacity: 1 - cover, into: &list, context: context)
        if cover > 0 { list.append(.fillRect(bounds, RGBA(r: 0, g: 0, b: 0, a: PlatformMetrics.navigationPushDim * cover))) }
        paintScreen(slide.upper, bar: upperBar, shift: width * (1 - cover), barOpacity: cover, into: &list, context: context)
        list.append(.restore)
        for node in chromeNodes { node.paint(into: &list, context: context.child(at: node.presentedFrame)) }
    }

    /// One screen shifted sideways by `shift`: its ground (a grouped list's continues under the
    /// bar, as on iOS: ios/nav/basic is grey throughout), its nodes, then its bar, which travels
    /// with the screen and fades to `barOpacity` (iOS cross-fades the bars' contents while they
    /// slide part of the way; the whole way keeps the two titles apart).
    private func paintScreen(_ nodes: [ViewNode], bar: Bar?, shift: CGFloat, barOpacity: Double,
                             into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        if shift != 0 {
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: shift, y: 0)))
        }
        if bar != nil, let top = nodes.first,
           let ground = (top.descendants(where: { $0 is any _ListGroundProviding }).first as? any _ListGroundProviding)?._groundColor {
            list.append(.fillRect(bounds, ground.resolve(in: environment)))
        } else if environment.platformProfile.isIOS {
            // An iOS screen is opaque: the window's colour (white; black in the dark appearance)
            // behind content without a ground of its own (ios/dark/nav `push`).
            list.append(.fillRect(bounds, environment.platformProfile.resolve(.windowBackground, scheme: environment.colorScheme)))
        }
        for node in nodes { node.paint(into: &list, context: context.child(at: node.presentedFrame)) }
        if let bar, barOpacity > 0 { paintBar(bar, opacity: barOpacity, into: &list, context: context) }
        if shift != 0 { list.append(.restore) }
    }

    /// The bar's title and back button at `opacity` (multiplied into the colours: an opacity
    /// group would composite the whole canvas offscreen twice per frame of a slide).
    /// The bar's glass on iOS 26, over content that has scrolled under it (a large title fading,
    /// or the collapsed bar): a tint of the ink at 37/255 at the window's top easing out over
    /// 80 pt (ios/nav/scroll `row1`, `row8`: 218 at the top, 231 at 40 pt, 246 at 60, 253 at
    /// 80 over white), full once the content has moved a quarter of the collapse. At rest there
    /// is none.
    private func paintGlass(strength: Double, into list: inout DisplayList, bounds: CGRect) {
        guard strength > 0 else { return }
        let zone = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: PlatformMetrics.navigationGlassHeight)
        let ink = environment._isDark ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0)
        let stops = [(0.0, 37.0), (0.25, 34.0), (0.5, 24.0), (0.75, 9.0), (1.0, 1.0)].map {
            DisplayGradient.Stop(location: $0.0, color: ink.multiplyingAlpha(by: $0.1 / 255 * strength))
        }
        let gradient = DisplayGradient(kind: .linear(start: zone.origin, end: CGPoint(x: zone.minX, y: zone.maxY)), stops: stops)
        list.append(.fillGradient(Path(zone), gradient))
    }

    private func paintBar(_ bar: Bar, opacity: Double, into list: inout DisplayList, context: PaintContext) {
        var bounds = absoluteBounds(context)
        let profile = environment.platformProfile
        let color = (environment.foregroundColor ?? .primary).resolve(in: environment).multiplyingAlpha(by: opacity)
        // The band fills from the stack's top; the title, glass and back button sit `barTopInset` lower.
        let band = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bar.height)
        bounds.origin.y += barTopInset
        // `toolbarBackground(_, for: .navigationBar)`: a style (or the window colour when
        // `.visible`) fills the bar's band behind the title and items; `.hidden` leaves iOS 26's
        // bare top and no glass (sw-toolbar, unmeasured).
        let background = runtime.toolbarBackground(for: .navigationBar)
        if let style = background.style {
            style._fill(Path(band), in: band, eoFill: false, environment: environment, scale: context.scale, into: &list)
        } else if background.visibility == .visible {
            list.append(.fillRect(band, environment._windowBackground))
        }
        if profile.isIOS, bar.large, bar.collapsed, background.visibility != .hidden, background.style == nil { paintGlass(strength: 1, into: &list, bounds: bounds) }
        if let title = bar.title {
            if bar.showsLargeTitle {
                // The large title scrolls up with the content until it is under the inline zone
                // (the bar collapses once it is gone).
                let font = Font.largeTitle.bold().resolve(profile: profile)
                let metrics = profile.systemFontMetrics(for: font)
                let scroll = largeTitleScroll
                let origin = CGPoint(x: bounds.minX + PlatformMetrics.navigationTitleInset, y: bounds.minY + PlatformMetrics.navigationLargeTitleTop + metrics.baseline - scroll)
                if scroll > 0, profile.isIOS {
                    // iOS 26 (ios/nav/scroll `row1`): the title fades as it travels under the bar's
                    // glass, the window colour thinning to nothing over the inline zone; it is
                    // not clipped.
                    let progress = min(1, scroll / PlatformMetrics.navigationLargeTitleCollapse)
                    list.append(.drawText(title, DisplayFont(font), origin: origin, color.multiplyingAlpha(by: 1 - progress)))
                    paintGlass(strength: min(1, progress * 4), into: &list, bounds: bounds)
                } else {
                    if scroll > 0 {
                        list.append(.save)
                        list.append(.clipRect(CGRect(x: bounds.minX, y: bounds.minY + PlatformMetrics.navigationBarInlineHeight, width: bounds.width,
                                                     height: PlatformMetrics.navigationBarLargeHeight - PlatformMetrics.navigationBarInlineHeight)))
                    }
                    list.append(.drawText(title, DisplayFont(font), origin: origin, color))
                    if scroll > 0 { list.append(.restore) }
                }
            } else {
                let font = Font.headline.resolve(profile: profile)
                let metrics = profile.systemFontMetrics(for: font)
                let width = runtime.layoutText(title, font: font, width: nil).size.width
                let origin = CGPoint(x: bounds.midX - width / 2, y: bounds.minY + (PlatformMetrics.navigationBarInlineHeight - metrics.lineHeight) / 2 + metrics.baseline)
                list.append(.drawText(title, DisplayFont(font), origin: origin, color))
            }
        }
        if bar.back { backButton.paintLook(into: &list, at: bounds.origin, opacity: opacity, context: context) }
    }

    override package var paintedChildren: [ViewNode] {
        var children: [ViewNode] = groups.last ?? []
        if backButton.isShown { children.append(backButton) }
        children += itemsBarNodes
        children += shownBottomBarNodes
        children += searchChromeNodes
        return children
    }
    override package var structuralChildren: [ViewNode] { [root as ViewNode] + entries.compactMap(\.node) + [scopeBar, searchBar, itemsBar, bottomItemsBar].compactMap { $0 } }

    /// Preferences come from the root and the top screen when the top is a pushed view
    /// (nav/path-change `present`: a value screen under a presented one reports no probe); the
    /// path's own screens all report under a value on top (nav/steps `push2`, macOS 26.2).
    override package func preferenceValue<K: PreferenceKey>(for key: K.Type) -> K.Value? {
        var sources: [ViewNode] = [root]
        if let top = entries.last {
            if case .value = top.kind {
                sources += entries.compactMap(\.node)
            } else if let node = top.node {
                sources.append(node)
            }
        }
        // The bar's items (iOS) report too: ios/sheet/nav probes a button in the bar.
        if let itemsBar { sources.append(itemsBar) }
        if let bottomItemsBar { sources.append(bottomItemsBar) }
        var result: K.Value?
        for child in sources {
            guard let value = child.preferenceValue(for: key) else { continue }
            if result == nil {
                result = value
            } else {
                K.reduce(value: &result!, nextValue: { value })
            }
        }
        return transformPreference(key, result)
    }
    override package var nodeDescription: String { "NavigationStack" }

    override package func unmount() {
        finishSlide()
        for entry in entries { entry.node?.unmount() }
        entries.removeAll()
        searchBar?.unmount()
        searchBar = nil
        itemsBar?.unmount()
        itemsBar = nil
        bottomItemsBar?.unmount()
        bottomItemsBar = nil
        scopeBar?.unmount()
        scopeBar = nil
        super.unmount()
    }
}

@MainActor private var nextNavigationIdentifier = 9_950_000

/// The back button in an iOS navigation bar: a 44 pt glass circle with a chevron at the bar's
/// leading edge (ios/nav/push, ios/nav/push-inline); pressing it pops the stack. The stack
/// places it and paints it with the bar (`paintLook`), so it has no drawing of its own.
@MainActor
package final class NavigationBackButtonNode: LeafNode<_NavigationBackButton>, _Interactive {
    private let identifier: Int
    /// Whether the top screen's bar shows it (hit-tested and exposed only then).
    package var isShown = false
    package private(set) var isPressed = false

    override package init(_ context: _NodeContext<_NavigationBackButton>) {
        nextNavigationIdentifier += 1
        identifier = nextNavigationIdentifier
        super.init(context)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: PlatformMetrics.navigationBackButtonDiameter, height: PlatformMetrics.navigationBackButtonDiameter)
    }

    package func pressBegan() {
        isPressed = true
        runtime.setNeedsDisplay()
    }

    package func pressEnded(inside: Bool) {
        isPressed = false
        runtime.setNeedsDisplay()
        if inside { (parent as? NavigationStackNode)?.pop() }
    }

    package var semantics: SemanticsNode {
        SemanticsNode(role: .button, label: "Back", frame: frameInRoot, identifier: identifier)
    }

    /// The circle and chevron at the bar whose origin is `barOrigin` (absolute). The chevron is
    /// the accent colour, as on iOS: Catalyst's inactive window draws it grey (Docs/elements/iOS.md).
    package func paintLook(into list: inout DisplayList, at barOrigin: CGPoint, opacity: Double = 1, context: PaintContext) {
        let inset = PlatformMetrics.navigationBackButtonInset
        let diameter = PlatformMetrics.navigationBackButtonDiameter
        let circle = context.absoluteRect(CGRect(x: barOrigin.x - context.origin.x + inset, y: barOrigin.y - context.origin.y + inset, width: diameter, height: diameter))
        let fill = environment.colorScheme == .dark ? PlatformMetrics.navigationBackFillDark : PlatformMetrics.navigationBackFill
        list.append(.fillRRect(circle, cornerRadius: diameter / 2, fill.multiplyingAlpha(by: opacity)))
        if isPressed { list.append(.fillRRect(circle, cornerRadius: diameter / 2, environment._ink(PlatformMetrics.navigationBackPressedAlpha * opacity))) }
        let size = PlatformMetrics.navigationBackChevronSize
        let centre = CGPoint(x: circle.midX + PlatformMetrics.navigationBackChevronOffset.x, y: circle.midY + PlatformMetrics.navigationBackChevronOffset.y)
        var chevron = Path()
        chevron.move(to: CGPoint(x: centre.x + size.width / 2, y: centre.y - size.height / 2))
        chevron.addLine(to: CGPoint(x: centre.x - size.width / 2, y: centre.y))
        chevron.addLine(to: CGPoint(x: centre.x + size.width / 2, y: centre.y + size.height / 2))
        let tint = (environment.isEnabled ? Color.accentColor.resolve(in: environment) : environment._ink(PlatformMetrics.disabledLabelOpacity)).multiplyingAlpha(by: opacity)
        list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: PlatformMetrics.navigationBackChevronStroke, lineCap: .round, lineJoin: .round), tint))
    }
}

/// A node that sets the navigation bar's visibility (`toolbar(_:for:)`, `toolbarVisibility`).
@MainActor
package protocol _NavigationBarVisibilityProviding: AnyObject {
    var _navigationBarVisibility: Visibility? { get }
}

/// Records a `navigationBarBackButtonHidden`; transparent for layout.
@MainActor
package protocol _NavigationBackButtonHiddenProviding: AnyObject {
    var _hidesBackButton: Bool { get }
}

@MainActor
package final class NavigationBackButtonHiddenNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationBackButtonHiddenModifier>, _NavigationBackButtonHiddenProviding {
    package var _hidesBackButton: Bool { modifier.hidden }
}

/// Registers its destination builder with the enclosing stack; transparent for layout.
@MainActor
package final class NavigationDestinationNode<Content: View, D: Hashable>: UnaryLayoutModifierNode<Content, _NavigationDestinationModifier<D>> {
    private let type: ObjectIdentifier

    package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationDestinationModifier<D>>>, type: ObjectIdentifier) {
        self.type = type
        super.init(context)
        register()
    }

    override package func update(view: ModifiedContent<Content, _NavigationDestinationModifier<D>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        register()
    }

    private func register() {
        environment._navigationContext?.stack?.destinations[type] = modifier.builder
    }
}

/// Pushes its destination while its binding is true.
@MainActor
package final class NavigationPresentedDestinationNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationPresentedSync> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationPresentedSync>>) {
        super.init(context)
        sync()
    }

    override package func update(view: ModifiedContent<Content, _NavigationPresentedSync>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        sync()
    }

    private func sync() {
        guard let stack = environment._navigationContext?.stack else { return }
        if modifier.presented {
            stack.present(modifier.destination, isPresented: modifier.binding, owner: ObjectIdentifier(self))
        } else {
            stack.dismiss(owner: ObjectIdentifier(self))
        }
    }
}

/// The title and display mode a navigation stack finds in its top view's subtree (iOS bar).
@MainActor
package protocol _NavigationTitleProviding: AnyObject {
    var _navigationTitle: String { get }
}

@MainActor
package protocol _NavigationTitleDisplayModeProviding: AnyObject {
    var _titleDisplayMode: NavigationBarItem.TitleDisplayMode { get }
}

/// Records a `navigationBarTitleDisplayMode`; transparent for layout.
@MainActor
package final class NavigationTitleDisplayModeNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationTitleDisplayModeModifier>, _NavigationTitleDisplayModeProviding {
    package var _titleDisplayMode: NavigationBarItem.TitleDisplayMode { modifier.mode }
}

/// Records the navigation title on the runtime (the window's title); transparent for layout.
/// A title inside a sheet or other presentation is that presentation's, not the window's.
@MainActor
package final class NavigationTitleNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationTitleModifier>, _NavigationTitleProviding {
    package var _navigationTitle: String { modifier.title }

    private var isPresented: Bool {
        var current = parent
        while let node = current {
            if node is PresentationNode { return true }
            current = node.parent
        }
        return false
    }

    override package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationTitleModifier>>) {
        super.init(context)
        if !isPresented { runtime.navigationTitle = modifier.title }
    }

    override package func update(view: ModifiedContent<Content, _NavigationTitleModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        if !isPresented { runtime.navigationTitle = modifier.title }
    }
}

extension Runtime {
    /// Pops the innermost navigation stack that has something pushed (a host's back button or
    /// key). Returns false when nothing was popped.
    @discardableResult
    public func navigateBack() -> Bool {
        let stacks = root.descendants(where: { $0 is NavigationStackNode }).compactMap { $0 as? NavigationStackNode }
        for stack in stacks.reversed() where stack.pop() { return true }
        return false
    }
}
