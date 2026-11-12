// The window toolbar (API/Toolbar.swift): `ToolbarNode`s register items while mounted; a host that
// paints window chrome gets a 52 pt bar across the top of the window (the macOS unified toolbar,
// measured 2026-09-04) holding the navigation title and the items in 36 pt capsule platters, and
// the content is laid out below it.

/// `toolbar`: transparent to layout; registers its items with the runtime — or with the sheet
/// or other presentation it sits in, which shows them in a bar of its own (sw-toolbar). On iOS
/// the items belong to the navigation bar of the nearest `NavigationStack` (ios/sheet/nav: a
/// stack inside a sheet shows its own items), and there is no window bar.
@MainActor
package final class ToolbarNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarModifier> {
    private enum Owner { case runtime, presentation(PresentationNode), stack(NavigationStackNode) }

    private var owner: Owner {
        let isIOS = environment.platformProfile.isIOS
        var current = parent
        while let node = current {
            if let presentation = node as? PresentationNode { return .presentation(presentation) }
            if isIOS, let stack = node as? NavigationStackNode { return .stack(stack) }
            current = node.parent
        }
        return .runtime
    }

    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarModifier>>) {
        super.init(context)
        register(modifier.items)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        register(view.modifier.items)
    }

    private func register(_ items: [_ToolbarItemData]) {
        // Each item carries the environment here, for the bar that mounts it elsewhere.
        let environment = environment
        let items = items.map { item in
            var item = item
            item.environment = environment
            return item
        }
        switch owner {
        case .presentation(let presentation): presentation.registerToolbar(self, items: items)
        case .stack(let stack): stack.registerToolbar(self, items: items)
        case .runtime: runtime.registerToolbar(self, items: items)
        }
    }

    override package func unmount() {
        switch owner {
        case .presentation(let presentation): presentation.unregisterToolbar(self)
        case .stack(let stack): stack.unregisterToolbar(self)
        case .runtime: runtime.unregisterToolbar(self)
        }
        super.unmount()
    }
}

/// `toolbarBackground`: registers a style or visibility for its bars while mounted.
@MainActor
package final class ToolbarBackgroundNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarBackgroundModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarBackgroundModifier>>) {
        super.init(context)
        runtime.setToolbarBackground(self, modifier)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarBackgroundModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.setToolbarBackground(self, view.modifier)
    }

    override package func unmount() {
        runtime.setToolbarBackground(self, nil)
        super.unmount()
    }
}

/// `toolbarRole`: registers the role while mounted.
@MainActor
package final class ToolbarRoleNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarRoleModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarRoleModifier>>) {
        super.init(context)
        runtime.setToolbarRole(self, modifier.role)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarRoleModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.setToolbarRole(self, view.modifier.role)
    }

    override package func unmount() {
        runtime.setToolbarRole(self, nil)
        super.unmount()
    }
}

/// `toolbar(_:for:)`: hides the bar while mounted with `.hidden`.
@MainActor
package final class ToolbarVisibilityNode<Content: View>: UnaryLayoutModifierNode<Content, _ToolbarVisibilityModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _ToolbarVisibilityModifier>>) {
        super.init(context)
        runtime.setToolbarVisibility(self, modifier.visibility)
    }

    override package func update(view: ModifiedContent<Content, _ToolbarVisibilityModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.setToolbarVisibility(self, view.modifier.visibility)
    }

    override package func unmount() {
        runtime.setToolbarVisibility(self, nil)
        super.unmount()
    }
}

extension ToolbarVisibilityNode: _NavigationBarVisibilityProviding {
    /// The iOS navigation bar's visibility (the modifier names the window toolbar or the
    /// navigation bar; on iOS only the bar exists).
    package var _navigationBarVisibility: Visibility? { isMounted && modifier.visibility != .automatic ? modifier.visibility : nil }
}

/// The bar's view: leading items, the title, principal items centred, trailing items.
struct _ToolbarBarView: View {
    let items: [_ToolbarItemData]
    let title: String?
    let search: SearchSource?
    let scopes: SearchScopeSource?
    /// `.editor` leads with the title.
    var role: ToolbarRole = .automatic
    /// A `NavigationSplitView` in the window: the sidebar toggle leads the bar (macOS puts it
    /// in the toolbar's leading group; `Runtime.toggleSidebar`).
    var sidebarToggle: (@MainActor () -> Void)?

    private func platters(_ group: ToolbarItemPlacement.Group) -> some View {
        ForEach(Array(items.enumerated()).filter { $0.element.placement.group == group }, id: \.offset) { entry in
            entry.element.view.fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if let scopes {
                _ToolbarScopeRowView(scopes: scopes)
            }
        }
    }

    private var titleView: some View {
        Group {
            if let title {
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).padding(.leading, 8)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            if let sidebarToggle {
                Button(action: sidebarToggle) { Image(systemName: "sidebar.leading") }.accessibilityLabel(Text("Toggle Sidebar")).help("Toggle Sidebar")
            }
            if role == .editor { titleView }
            platters(.leading)
            if role != .editor { titleView }
            Spacer(minLength: 8)
            platters(.principal)
            Spacer(minLength: 8)
            platters(.trailing)
            if let search {
                _SearchFieldView(source: search, presented: search.presented)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Runtime.toolbarHeight)
        .buttonStyle(_ToolbarButtonStyle())
        .font(.system(size: 13, weight: .semibold))
    }
}

/// Toolbar buttons: the label in a 36 pt capsule platter (macOS 26's glass pill, approximated
/// as a translucent grey), darker while pressed.
struct _ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 36, maxHeight: 36)
            .background(Capsule().fill(Color(.sRGB, white: 0.5, opacity: configuration.isPressed ? 0.3 : 0.12)))
    }
}

/// The runtime-owned bar node, laid out over the top of the window.
@MainActor
package final class ToolbarChromeNode: ViewNode {
    package private(set) var content: TypedNode<AnyView>!

    package init(runtime: Runtime, view: AnyView, environment: EnvironmentValues) {
        var environment = environment
        environment._automaticLabelContext = .toolbar
        super.init(parent: runtime.root, runtime: runtime, environment: environment)
        content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: environment))
    }

    package func update(view: AnyView, environment: EnvironmentValues) {
        var environment = environment
        environment._automaticLabelContext = .toolbar
        self.environment = environment
        content.update(view: view, environment: environment, force: false)
    }

    package func layout(in window: CGSize) {
        let height = Runtime.toolbarHeight + (runtime.activeSearchScopes != nil ? Runtime.toolbarScopeRowHeight : 0)
        frame = CGRect(x: 0, y: 0, width: window.width, height: height)
        for node in content.layoutChildren {
            node.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(frame.size), by: self)
        }
    }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bar = context.absoluteRect(frame)
        // The ground: the window colour under a 12 % hairline; a `toolbarBackground` style
        // instead, or nothing at all when hidden.
        let background = runtime.toolbarBackground(for: .windowToolbar)
        if background.visibility != .hidden {
            if let style = background.style {
                style._fill(Path(bar), in: bar, eoFill: false, environment: environment, scale: context.scale, into: &list)
            } else {
                list.append(.fillRect(bar, environment._windowBackground))
            }
            let hairline = 1 / context.scale
            list.append(.fillRect(CGRect(x: bar.minX, y: bar.maxY - hairline, width: bar.width, height: hairline), environment._ink(0.12)))
        }
        for node in content.layoutChildren {
            node.paint(into: &list, context: context.child(at: node.presentedFrame))
        }
    }

    /// A secondary click on the bar (not on an item) of a customisable toolbar: a menu of every
    /// item to show or hide.
    package func presentCustomizationMenu(at point: CGPoint) -> Bool {
        guard frame.contains(point), interactiveNode(at: point) == nil else { return false }
        let items = runtime.toolbarItems.filter { $0.customizationID != nil && $0.id != nil }
        guard !items.isEmpty else { return false }
        let runtime = self.runtime
        let rows = AnyView(ForEach(Array(items.enumerated()), id: \.offset) { entry in
            let item = entry.element
            Toggle(isOn: Binding(get: { runtime.isToolbarItemVisible(item) }, set: { runtime.setToolbarItem(item.id!, visible: $0, in: item.customizationID!) })) {
                item.view
            }
        })
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: rows)), environment: environment, anchor: nil, at: point) {}
        return true
    }

    override package var isLayoutNode: Bool { true }
    override package var structuralChildren: [ViewNode] { [content] }
    override package var layoutChildren: [ViewNode] { content.layoutChildren }
    override package var paintedChildren: [ViewNode] { content.layoutChildren }
    override package var nodeDescription: String { "Toolbar" }

    package var interactiveNodes: [ViewNode & _Interactive] {
        content.layoutChildren.flatMap { $0.collectNodes(where: { $0.isInteractiveNode }) }.compactMap { $0 as? (ViewNode & _Interactive) }
    }

    /// The interactive node under a window point, if the point is in the bar.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        guard frame.contains(point) else { return nil }
        for node in content.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            if let hit = node.hitTest(local, where: { $0.isInteractiveNode }) { return hit as? (ViewNode & _Interactive) }
        }
        return nil
    }
}

extension Runtime {
    /// The unified toolbar's height (macOS 26, measured on a titled window).
    public static let toolbarHeight: CGFloat = 52
    /// The scope bar's row under it while a search with scopes is active (unmeasured).
    public static let toolbarScopeRowHeight: CGFloat = 30

    package func registerToolbar(_ node: ViewNode, items: [_ToolbarItemData]) {
        if let index = toolbarSources.firstIndex(where: { $0.node === node }) {
            toolbarSources[index].items = items
        } else {
            toolbarSources.append(ToolbarSource(node: node, items: items))
        }
        requestLayout()
    }

    package func unregisterToolbar(_ node: ViewNode) {
        toolbarSources.removeAll { $0.node === node || $0.node == nil }
        requestLayout()
    }

    package func setToolbarVisibility(_ node: ViewNode, _ visibility: Visibility?) {
        toolbarVisibility.removeAll { $0.node === node || $0.node == nil }
        if let visibility { toolbarVisibility.append(ToolbarVisibilitySource(node: node, visibility: visibility)) }
        requestLayout()
    }

    /// The items every mounted `toolbar` contributes, in tree order, the customisable ones the
    /// user hid (or that hide by default) left out.
    public var toolbarItems: [_ToolbarItemData] {
        toolbarSources.filter { $0.node?.isMounted == true }.flatMap(\.items).filter { isToolbarItemVisible($0) }
    }

    /// Whether a customisable toolbar shows an item: the user's choice for the session, else
    /// `showsByDefault`; items outside customisable toolbars always show.
    public func isToolbarItemVisible(_ item: _ToolbarItemData) -> Bool {
        guard let toolbarID = item.customizationID, let id = item.id else { return true }
        return toolbarCustomization[toolbarID]?[id] ?? item.showsByDefault
    }

    /// Shows or hides an item of a customisable toolbar (`toolbar(id:)`) for the session.
    public func setToolbarItem(_ id: AnyHashable, visible: Bool, in toolbarID: String) {
        toolbarCustomization[toolbarID, default: [:]][id] = visible
        requestLayout()
    }

    package func setToolbarBackground(_ node: ViewNode, _ modifier: _ToolbarBackgroundModifier?) {
        toolbarBackgrounds.removeAll { $0.node === node || $0.node == nil }
        if let modifier { toolbarBackgrounds.append(ToolbarBackgroundSource(node: node, modifier: modifier)) }
        setNeedsDisplay()
    }

    /// The background a bar takes: the last mounted `toolbarBackground` naming it (or every bar).
    package func toolbarBackground(for bar: ToolbarPlacement) -> (style: AnyShapeStyle?, visibility: Visibility?) {
        var style: AnyShapeStyle?
        var visibility: Visibility?
        for source in toolbarBackgrounds where source.node?.isMounted == true {
            guard source.modifier.bars.contains(where: { $0 == bar || $0 == .automatic }) else { continue }
            if let s = source.modifier.style { style = s }
            if let v = source.modifier.visibility { visibility = v }
        }
        return (style, visibility)
    }

    package func setToolbarRole(_ node: ViewNode, _ role: ToolbarRole?) {
        toolbarRoles.removeAll { $0.node === node || $0.node == nil }
        if let role { toolbarRoles.append(ToolbarRoleSource(node: node, role: role)) }
        requestLayout()
    }

    /// The toolbar's role: the last mounted `toolbarRole`, else automatic.
    package var toolbarRole: ToolbarRole { toolbarRoles.last { $0.node?.isMounted == true }?.role ?? .automatic }

    /// Whether the window holds a navigation split view (its toggle leads the toolbar).
    package var hasSplitView: Bool { !root.descendants(where: { $0 is NavigationSplitViewNode }).isEmpty }

    /// Whether the host should show a toolbar: chrome painting on, items (or a split view's
    /// toggle, or a search field) present, not hidden. An iOS window has no toolbar: items go
    /// to a navigation bar, and the search field to the stack's bottom band.
    package var showsToolbar: Bool {
        paintsWindowChrome && !rootEnvironment.platformProfile.isIOS && (!toolbarItems.isEmpty || searchField != nil || hasSplitView) && !toolbarVisibility.contains { $0.node?.isMounted == true && $0.visibility == .hidden }
    }

    /// The bar's frame while it shows; the content is laid out below it.
    public var toolbarFrame: CGRect? { toolbar.map(\.frame) }

    /// Creates, refreshes or drops the bar for this layout pass.
    package func layoutToolbar(in size: CGSize) {
        guard showsToolbar else {
            toolbar?.unmount()
            toolbar = nil
            return
        }
        var environment = rootEnvironment
        environment.colorScheme = root.environment.colorScheme
        var toggle: (@MainActor () -> Void)?
        if hasSplitView { toggle = { [weak self] in _ = self?.toggleSidebar() } }
        let view = AnyView(_ToolbarBarView(items: toolbarItems, title: chromeShowsTitle ? navigationTitle : nil, search: searchField, scopes: activeSearchScopes, role: toolbarRole, sidebarToggle: toggle))
        if let toolbar {
            toolbar.update(view: view, environment: environment)
        } else {
            toolbar = ToolbarChromeNode(runtime: self, view: view, environment: environment)
        }
        toolbar?.layout(in: size)
    }
}

/// One `toolbar` modifier's contribution.
package struct ToolbarSource {
    weak var node: ViewNode?
    var items: [_ToolbarItemData]
}

package struct ToolbarBackgroundSource {
    weak var node: ViewNode?
    var modifier: _ToolbarBackgroundModifier
}

package struct ToolbarRoleSource {
    weak var node: ViewNode?
    var role: ToolbarRole
}

package struct ToolbarVisibilitySource {
    weak var node: ViewNode?
    var visibility: Visibility
}

/// The toolbar's search field: a magnifier and a plain text field in a 36 pt capsule; tokens
/// precede the text as small grey tags (approximate: the toolbar is not capturable). The
/// field's focus is the search's presentation.
struct _SearchFieldView: View {
    let source: SearchSource
    let presented: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            if let tokens = source.tokens, tokens.count() > 0 {
                HStack(spacing: 3) {
                    ForEach(Array(tokens.views().enumerated()), id: \.offset) { entry in
                        entry.element
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(PlatformMetrics.searchTokenFill)))
                    }
                }
            }
            TextField(source.prompt ?? "Search", text: source.text).textFieldStyle(.plain).font(.system(size: 13)).focused($focused)
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 120, maxWidth: 325, minHeight: 36, maxHeight: 36)
        .background(Capsule().fill(Color(.sRGB, white: 0.5, opacity: 0.12)))
        .layoutPriority(1)
        .onChange(of: focused) { _, now in
            if now != presented { source.setPresented(now) }
        }
        .onChange(of: presented, initial: true) { _, now in
            if focused != now { focused = now }
        }
    }
}

/// The scope bar under the macOS toolbar while the search is active (approximate, unmeasured:
/// the toolbar is not capturable): a centred segmented control in a 30 pt row.
struct _ToolbarScopeRowView: View {
    let scopes: SearchScopeSource

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            _SearchScopePicker(scopes: scopes).fixedSize()
            Spacer(minLength: 0)
        }
        .frame(height: Runtime.toolbarScopeRowHeight)
    }
}

/// The items of an iOS navigation bar (ios/sheet/nav, iOS 27): the leading group at the bar's
/// leading inset, the trailing group at its trailing one, principal items centred, each
/// button a glass pill (`_IOSBarButtonStyle`).
struct _IOSBarItemsView: View {
    let items: [_ToolbarItemData]

    private func pills(_ group: ToolbarItemPlacement.Group) -> some View {
        ForEach(Array(items.enumerated()).filter { $0.element.placement.iOSGroup == group }, id: \.offset) { entry in
            entry.element.view
                .buttonStyle(_IOSBarButtonStyle(prominent: entry.element.placement.isProminentOnIOS))
                .font(.body)
                .fixedSize(horizontal: true, vertical: false)
                .modifier(_ToolbarItemEnvironment(captured: entry.element.environment))
        }
    }

    var body: some View {
        HStack(spacing: PlatformMetrics.navigationBarItemSpacing) {
            pills(.leading)
            Spacer(minLength: PlatformMetrics.navigationBarItemSpacing)
            pills(.principal)
            Spacer(minLength: PlatformMetrics.navigationBarItemSpacing)
            pills(.trailing)
        }
        .padding(.horizontal, PlatformMetrics.navigationBarItemInset)
        .padding(.top, PlatformMetrics.navigationBarItemTop)
        .frame(maxHeight: .infinity, alignment: .top)
        .font(.body)
    }
}

/// An iOS 26 navigation bar button: the label in the body size (semibold for a confirmation
/// action) in a 36 pt capsule of glass (approximate: a faint rim and a soft shadow over the
/// bar, the interior a touch lighter than what is behind it), pressed darker.
struct _IOSBarButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(prominent ? .semibold : nil)
            .padding(.horizontal, PlatformMetrics.navigationBarItemPadding)
            .frame(minWidth: PlatformMetrics.navigationBarItemHeight, minHeight: PlatformMetrics.navigationBarItemHeight, maxHeight: PlatformMetrics.navigationBarItemHeight)
            .background(
                Capsule()
                    .fill(Color(.sRGB, white: 1, opacity: configuration.isPressed ? 0.3 : 0.45))
                    .shadow(color: Color(.sRGB, white: 0, opacity: 0.08), radius: 4, y: 2)
            )
            .overlay(Capsule().strokeBorder(Color(.sRGB, white: 0, opacity: 0.06), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// An iOS screen's bottom toolbar (`ToolbarItem(placement: .bottomBar)`): the items in a row
/// across the bottom of the navigation stack, each in the bar's glass pills; an item that
/// spaces itself (`HStack { Spacer(); Button }`) takes the row's free width. Unmeasured: the
/// row sits where the search field rests (ios/search), 20 pt in from the window's sides.
struct _IOSBottomBarItemsView: View {
    let items: [_ToolbarItemData]

    var body: some View {
        HStack(spacing: PlatformMetrics.navigationBarItemSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                entry.element.view
                    .buttonStyle(_IOSBarButtonStyle(prominent: entry.element.placement.isProminentOnIOS))
                    .font(.body)
                    .modifier(_ToolbarItemEnvironment(captured: entry.element.environment))
            }
        }
    }
}
