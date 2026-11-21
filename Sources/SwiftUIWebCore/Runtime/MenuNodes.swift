// Menu nodes (Docs/elements/Menu.md): the pull-down button (`MenuButtonNode`), a submenu row
// inside a presented menu (`SubmenuRowNode`), context menus (`ContextMenuNode`) and the runtime's
// secondary-click entry point. Menus themselves are presentations (`PresentationNode`).

@MainActor
private var nextMenuIdentifier = 6_000_000

/// The pull-down button: an `NSPopUpButton`-style box around the label with a single chevron;
/// a press presents the content as a menu under the button. With a primary action the button
/// is split: the label part runs the action, the indicator part opens the menu.
@MainActor
package final class MenuButtonNode: LayoutNode<_MenuHost>, _Interactive {
    private var label: TypedNode<AnyView>!
    private let identifier: Int
    private var labelFrame: CGRect = .zero
    /// The split button's divider (x in the node's space), when there is a primary action.
    private var dividerX: CGFloat?

    package init(_ context: _NodeContext<_MenuHost>) {
        nextMenuIdentifier += 1
        identifier = nextMenuIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        label = AnyView._makeNode(_NodeContext(view: context.view.label, parent: self, environment: labelEnvironment()))
    }

    private var enabled: Bool { environment.isEnabled }

    private var plainLabel: Bool { environment.platformProfile.metrics.menuIsPlainLabel }

    private func labelEnvironment() -> EnvironmentValues {
        var environment = environment
        if plainLabel {
            // iOS: the label in the body font and the accent colour, nothing around it.
            environment.font = .body
            environment.foregroundColor = enabled ? Color.accentColor : Color.primary.opacity(environment.platformProfile.metrics.menuDisabledLabelAlpha)
            return environment
        }
        environment.font = .system(size: PlatformMetrics.buttonLabelSize)
        if !enabled { environment.foregroundColor = Color.black.opacity(PlatformMetrics.popUpDisabledTextAlpha) }
        return environment
    }

    override package func update(view: _MenuHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        label.update(view: view.label, environment: labelEnvironment(), force: force)
    }

    private var target: ViewNode? { label.layoutChildren.first }

    // MARK: Layout

    private struct Plan {
        var size: CGSize
        var label: CGRect
        var dividerX: CGFloat?
    }

    private func plan() -> Plan {
        let labelSize = target?.sizeThatFits(.unspecified) ?? .zero
        if plainLabel { return Plan(size: labelSize, label: CGRect(origin: .zero, size: labelSize), dividerX: nil) }
        let trailing: CGFloat
        var dividerX: CGFloat?
        if view.primaryAction != nil {
            dividerX = PlatformMetrics.popUpTextInset + labelSize.width + PlatformMetrics.menuSplitGap
            trailing = PlatformMetrics.menuSplitGap + PlatformMetrics.menuSplitDividerWidth + PlatformMetrics.menuSplitTrailing
        } else if view.indicator {
            trailing = PlatformMetrics.popUpChevronGap + PlatformMetrics.popUpChevronWidth + PlatformMetrics.popUpChevronTrailing
        } else {
            trailing = PlatformMetrics.popUpTextInset
        }
        let width = PlatformMetrics.popUpTextInset + labelSize.width + trailing
        let height = max(PlatformMetrics.popUpHeight, labelSize.height)
        return Plan(size: CGSize(width: width, height: height),
                    label: CGRect(x: PlatformMetrics.popUpTextInset, y: (height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height),
                    dividerX: dividerX)
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { plan().size }

    /// iOS: the label's own dimensions, so a baseline-aligned row lines the menu up with text
    /// (ios/menu/basic `row`).
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        if plainLabel, let target { return target.dimensions(in: proposal) }
        return super.dimensions(in: proposal)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let plan = plan()
        labelFrame = plan.label
        dividerX = plan.dividerX
        target?.place(at: plan.label.origin, anchor: .topLeading, proposal: ProposedViewSize(plan.label.size), by: self)
    }

    override package var layoutSpacing: ViewSpacing { PlatformMetrics.controlsUsePlainSpacing ? ViewSpacing() : .textLikeControl }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [label] }
    override package var nodeDescription: String { "Menu" }

    override package func unmount() {
        label.unmount()
        super.unmount()
    }

    // MARK: Painting

    private func black(_ alpha: Double) -> RGBA { environment._ink(alpha) }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        if plainLabel {
            if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
            return
        }
        if view.bordered {
            list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.popUpCornerRadius,
                                   black(enabled ? PlatformMetrics.popUpFill : PlatformMetrics.popUpDisabledFill)))
        }
        if isOpen {
            // The active look while the menu is open: the indicator part of a split button, the
            // whole box of a pull-down, darkened (approximate: no golden shows an open menu).
            let active = dividerX.map { CGRect(x: bounds.minX + $0, y: bounds.minY, width: bounds.width - $0, height: bounds.height) } ?? bounds
            list.append(.fillRRect(active, cornerRadius: PlatformMetrics.popUpCornerRadius, black(PlatformMetrics.menuOpenFillAlpha)))
        }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
        let chevronAlpha = enabled ? PlatformMetrics.radioDotAlpha : PlatformMetrics.popUpDisabledTextAlpha
        if let dividerX {
            let x = context.round(bounds.minX + dividerX)
            list.append(.fillRect(CGRect(x: x, y: bounds.minY + PlatformMetrics.menuSplitDividerInset, width: PlatformMetrics.menuSplitDividerWidth,
                                         height: bounds.height - 2 * PlatformMetrics.menuSplitDividerInset), black(PlatformMetrics.menuSplitDividerAlpha)))
            appendChevron(into: &list, centerX: bounds.maxX - PlatformMetrics.menuSplitChevronTrailing, midY: bounds.midY,
                          stroke: PlatformMetrics.menuSplitChevronStroke, alpha: chevronAlpha)
        } else if view.indicator {
            appendChevron(into: &list, centerX: bounds.maxX - PlatformMetrics.pullDownChevronTrailing, midY: bounds.midY,
                          stroke: PlatformMetrics.popUpChevronStroke, alpha: chevronAlpha)
        }
    }

    /// A single downward chevron centred at `centerX`, `midY`.
    private func appendChevron(into list: inout DisplayList, centerX: CGFloat, midY: CGFloat, stroke: CGFloat, alpha: Double) {
        let halfWidth = PlatformMetrics.popUpChevronWidth / 2, rise = PlatformMetrics.pullDownChevronHalfHeight
        var chevron = Path()
        chevron.move(to: CGPoint(x: centerX - halfWidth, y: midY - rise))
        chevron.addLine(to: CGPoint(x: centerX, y: midY + rise))
        chevron.addLine(to: CGPoint(x: centerX + halfWidth, y: midY - rise))
        list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round), black(alpha)))
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) { pressEnded(inside: inside, at: CGPoint(x: frame.width, y: 0)) }

    package func pressEnded(inside: Bool, at point: CGPoint) {
        guard inside, enabled else { return }
        if let dividerX, let action = view.primaryAction, point.x < dividerX {
            action.run()
            runtime.setNeedsDisplay()
            return
        }
        presentMenu()
    }

    /// Whether this button's menu is open: the indicator (or the whole pull-down) darkens.
    package private(set) var isOpen = false

    package func presentMenu() {
        // Open or closed changes how the button paints, never its size: a repaint, not a layout
        // that re-measures the app (30 to 40 ms in Paulo's release build, new-website#649).
        isOpen = true
        runtime.requestRepaint()
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: view.content)), environment: environment, anchor: self) { [weak self] in
            self?.isOpen = false
            self?.runtime.requestRepaint()
        }
    }

    package var semantics: SemanticsNode {
        let text = label.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .popUpButton, label: text, frame: frameInRoot, identifier: identifier)
    }
}

/// A row inside a presented menu that opens its content as a submenu beside the row.
@MainActor
package final class SubmenuRowNode: LayoutNode<_SubmenuHost>, _Interactive {
    private var child: TypedNode<AnyView>!
    private let identifier: Int

    package init(_ context: _NodeContext<_SubmenuHost>) {
        nextMenuIdentifier += 1
        identifier = nextMenuIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = AnyView._makeNode(_NodeContext(view: Self.row(for: context.view), parent: self, environment: context.environment))
    }

    private static func row(for view: _SubmenuHost) -> AnyView {
        AnyView(_MenuRowLabel(label: view.label, submenu: true))
    }

    override package func update(view: _SubmenuHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: Self.row(for: view), environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize { target?.sizeThatFits(proposal) ?? .zero }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions { target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero) }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Submenu" }

    override package func unmount() {
        child.unmount()
        super.unmount()
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.present(kind: .submenu, view: AnyView(_MenuContent(content: view.content)), environment: environment, anchor: self) {}
    }

    package var semantics: SemanticsNode {
        let text = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .popUpButton, label: text, frame: frameInRoot, identifier: identifier)
    }
}

/// A node that presents a menu on a secondary click inside it.
@MainActor
package protocol _ContextMenuProviding: AnyObject {
    func presentContextMenu(at point: CGPoint)
}

@MainActor
package final class ContextMenuNode<Content: View>: UnaryLayoutModifierNode<Content, _ContextMenuModifier>, _ContextMenuProviding {
    package func presentContextMenu(at point: CGPoint) {
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: modifier.content)), environment: environment, anchor: nil, at: point) {}
    }
}

extension Runtime {
    /// A secondary (right) click at `point` (window coordinates): presents the context menu of
    /// the deepest view under it that has one. Over a presentation it behaves as a primary press
    /// (a click outside a menu dismisses it).
    public func secondaryPointerDown(at point: CGPoint) {
        if hasPresentations {
            let presented = presentationHit(at: point)
            if presented.handled { return }
        }
        // The window toolbar's customisation menu (`toolbar(id:)`).
        if let toolbar, toolbar.presentCustomizationMenu(at: point) { return }
        for node in root.layoutChildren.reversed() {
            let shift = node.hitTestOffset
            let local = CGPoint(x: point.x - node.frame.minX - shift.x, y: point.y - node.frame.minY - shift.y)
            if node.clipsHitTesting, !node.contains(local) { continue }
            if let hit = node.hitTest(local, where: { $0 is _ContextMenuProviding }) as? _ContextMenuProviding {
                hit.presentContextMenu(at: point)
                return
            }
        }
    }

    /// Dismisses every presented menu and submenu (a menu item ran).
    package func dismissMenus() {
        for presentation in presentations.reversed() where presentation.kind.isMenu { presentation.dismiss() }
    }
}


// MARK: - A picker's rows in a menu

/// Node for `_MenuPickerRows`: the picker's options stacked as rows the menu's width, the
/// selected option checked; a press selects and closes the menu (unless the dismiss behaviour
/// keeps it open). Options are the content's leaves with their tags, like a pop-up picker's.
@MainActor
package final class MenuPickerNode: LayoutNode<_MenuPickerRows> {
    private var content: TypedNode<AnyView>!
    package private(set) var rows: [MenuPickerRowNode] = []

    package init(_ context: _NodeContext<_MenuPickerRows>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        content = AnyView._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        rebuildRows()
    }

    override package func update(view: _MenuPickerRows, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        content.update(view: view.content, environment: environment, force: force)
        rebuildRows()
    }

    /// One row per option, keyed by tag; rows keep their nodes across updates.
    private func rebuildRows() {
        let options = _collectOptions(content)
        var kept: [MenuPickerRowNode] = []
        for (index, option) in options.enumerated() {
            let tag = option.node.layoutValue(for: TagKey.self) ?? option.id ?? AnyHashable(index)
            let row = rows.first { candidate in candidate.tag == tag && !kept.contains(where: { $0 === candidate }) }
                ?? MenuPickerRowNode(picker: self, option: option.node, tag: tag)
            row.option = option.node
            row.checked = tag == view.selected
            kept.append(row)
        }
        rows = kept
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        var size = CGSize.zero
        for row in rows {
            let rowSize = row.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            size.width = max(size.width, rowSize.width)
            size.height += rowSize.height
        }
        return size
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        var y: CGFloat = 0
        for row in rows {
            let rowSize = row.sizeThatFits(ProposedViewSize(width: frame.width, height: nil))
            row.place(at: CGPoint(x: 0, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: frame.width, height: rowSize.height), by: self)
            y += rowSize.height
        }
    }

    package func select(_ tag: AnyHashable) {
        view.select.select(tag)
        if environment._dismissesOnActivation, environment._menuActionDismissBehavior.dismisses { runtime.dismissMenus() }
        runtime.requestLayout()
    }

    override package var paintedChildren: [ViewNode] { rows }
    override package var structuralChildren: [ViewNode] { [content] + rows }
    override package var nodeDescription: String { "MenuPicker" }

    override package func unmount() {
        content.unmount()
        super.unmount()
    }
}

/// One option row: the option laid out after the check column, the check painted when selected.
@MainActor
package final class MenuPickerRowNode: ViewNode, _Interactive {
    private unowned let picker: MenuPickerNode
    package var option: ViewNode
    package let tag: AnyHashable
    package var checked = false
    private let identifier: Int

    init(picker: MenuPickerNode, option: ViewNode, tag: AnyHashable) {
        self.picker = picker
        self.option = option
        self.tag = tag
        nextMenuIdentifier += 1
        identifier = nextMenuIdentifier
        super.init(parent: picker, runtime: picker.runtime, environment: picker.environment)
    }

    override package var isLayoutNode: Bool { true }
    override package var layoutChildren: [ViewNode] { [self] }

    private var insets: (leading: CGFloat, trailing: CGFloat) { (PlatformMetrics.menuCheckWidth, PlatformMetrics.menuTrailingPadding) }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let inner = option.sizeThatFits(.unspecified)
        return CGSize(width: max(PlatformMetrics.menuMinimumWidth, inner.width + insets.leading + insets.trailing),
                      height: max(PlatformMetrics.menuRowHeight, inner.height))
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        let inner = option.sizeThatFits(.unspecified)
        option.place(at: CGPoint(x: insets.leading, y: (frame.height - inner.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(inner), by: self)
    }

    override package var paintedChildren: [ViewNode] { [option] }
    override package var structuralChildren: [ViewNode] { [] }
    override package var nodeDescription: String { "MenuPickerRow" }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        guard checked else { return }
        let size = PlatformMetrics.menuCheckSize
        let rect = CGRect(x: PlatformMetrics.menuCheckInset, y: (frame.height - size.height) / 2, width: size.width, height: size.height)
        let path = _MenuCheckMark().path(in: context.absoluteRect(rect))
        list.append(.strokePath(path, style: StrokeStyle(lineWidth: PlatformMetrics.menuCheckStroke, lineCap: .round, lineJoin: .round),
                                (environment.foregroundColor ?? .primary).resolve(in: environment)))
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        picker.select(tag)
    }

    package var semantics: SemanticsNode {
        let label = option.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .checkbox, label: label, frame: frameInRoot, identifier: identifier, isOn: checked)
    }
}

// MARK: - contextMenu(forSelectionType:)

/// `contextMenu(forSelectionType:menu:primaryAction:)` on a list: a secondary click on a row
/// presents the menu for the selection (the clicked row's identifier, or the whole selection
/// when the row is part of it); a primary action runs on a double click of a selected row.
@MainActor
package final class SelectionContextMenuNode<Content: View>: UnaryLayoutModifierNode<Content, _SelectionContextMenuModifier>, _ContextMenuProviding {
    package func presentContextMenu(at point: CGPoint) {
        guard let list = child.descendants(where: { $0 is any _ListRowIdentifying }).first as? any _ListRowIdentifying,
              let listNode = list as? ViewNode else { return }
        let listOrigin = listNode.frameInRoot.origin
        let selection = list.contextSelection(at: CGPoint(x: point.x - listOrigin.x, y: point.y - listOrigin.y))
        guard let menu = modifier.menu(selection) else { return }
        runtime.present(kind: .menu, view: AnyView(_MenuContent(content: menu)), environment: environment, anchor: nil, at: point) {}
    }
}

/// A list that can say which rows a point and the selection name.
@MainActor
package protocol _ListRowIdentifying: AnyObject {
    /// The row identifiers a context menu applies to at `point` (the list's coordinates): the
    /// selection when the row under the point is selected, else that row alone, else none.
    func contextSelection(at point: CGPoint) -> Set<AnyHashable>
}
