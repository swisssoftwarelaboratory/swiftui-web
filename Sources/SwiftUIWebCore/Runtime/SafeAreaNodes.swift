// `position` and the safe-area nodes (API/Position.swift).

/// `position`: the modified view takes the proposed size (the child's where nothing is
/// proposed) and centres the child at the point.
@MainActor
package final class PositionNode<Content: View>: UnaryLayoutModifierNode<Content, _PositionLayout> {
    override package var changesChildSize: Bool { true }
    override package var paintsOutsideFrame: Bool { true }

    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? childSize.width, height: proposal.height ?? childSize.height)
    }

    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        CGPoint(x: modifier.position.x - child.width / 2, y: modifier.position.y - child.height / 2)
    }
}

/// Shared by `safeAreaInset` and `safeAreaPadding`: `insets` (measured per layout) shrink a plain
/// child's bounds; a child that extends into the safe area keeps the full bounds and reads the
/// insets as its overlap (scroll views inset their content).
@MainActor
package class SafeAreaNode<Content: View, Modifier: ViewModifier>: UnaryLayoutModifierNode<Content, Modifier> {
    override package var changesChildSize: Bool { true }
    /// Nested safe-area modifiers keep an extending child (a scroll view) extending; the
    /// overlaps accumulate through placement.
    override package var extendsIntoSafeArea: Bool { targets.count == 1 && targets[0].extendsIntoSafeArea }

    /// The insets this node adds, for the given proposal (an inset view is measured against it).
    package func insets(for proposal: ProposedViewSize) -> EdgeInsets { EdgeInsets() }

    override package func providedSafeAreaInsets(for child: ViewNode) -> EdgeInsets { insets(for: ProposedViewSize(frame.size)) }

    /// What an extending target overlaps once placed in the full bounds: this node's own overlap
    /// plus its insets. Set before measuring so the first layout sizes with it.
    private func presetOverlap(of target: ViewNode, for proposal: ProposedViewSize) {
        let own = insets(for: proposal)
        let overlap = safeAreaOverlap
        target.safeAreaOverlap = EdgeInsets(top: overlap.top + own.top, leading: overlap.leading + own.leading,
                                            bottom: overlap.bottom + own.bottom, trailing: overlap.trailing + own.trailing)
    }

    private func extends(_ target: ViewNode) -> Bool { target.extendsIntoSafeArea }

    override package func measure(_ target: ViewNode, proposal: ProposedViewSize) -> CGSize {
        let insets = insets(for: proposal)
        if extends(target) {
            presetOverlap(of: target, for: proposal)
            return target.sizeThatFits(proposal)
        }
        let reduced = Self.reduce(proposal, by: insets)
        let size = target.sizeThatFits(reduced)
        return CGSize(width: size.width + insets.leading + insets.trailing, height: size.height + insets.top + insets.bottom)
    }

    override package func dimensions(of target: ViewNode, in proposal: ProposedViewSize) -> ViewDimensions {
        let insets = insets(for: proposal)
        if extends(target) {
            presetOverlap(of: target, for: proposal)
            return target.dimensions(in: proposal)
        }
        let dims = target.dimensions(in: Self.reduce(proposal, by: insets))
        let size = CGSize(width: dims.width + insets.leading + insets.trailing, height: dims.height + insets.top + insets.bottom)
        return dims.offset(by: CGPoint(x: insets.leading, y: insets.top), size: size)
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        let insets = insets(for: proposal)
        if extends(target) {
            target.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size), by: placer)
        } else {
            // A plain child is centred in the safe region when it is smaller (a 50 pt stack under
            // a bottom inset sits at (82 − 50) / 2, measured on `position/zz` probes, 2026-10-11).
            let inner = CGRect(x: bounds.minX + insets.leading, y: bounds.minY + insets.top,
                               width: max(0, bounds.width - insets.leading - insets.trailing), height: max(0, bounds.height - insets.top - insets.bottom))
            target.place(at: CGPoint(x: inner.midX, y: inner.midY), anchor: .center, proposal: ProposedViewSize(inner.size), by: placer)
        }
        placeInset(for: target, in: bounds, by: placer)
    }

    /// Places the inset view (if any) for a target along its edge.
    package func placeInset(for target: ViewNode, in bounds: CGRect, by placer: ViewNode) {}

    package static func reduce(_ proposal: ProposedViewSize, by insets: EdgeInsets) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { max(0, $0 - insets.leading - insets.trailing) },
                         height: proposal.height.map { max(0, $0 - insets.top - insets.bottom) })
    }
}

/// `safeAreaInset`: the inset view sits at its edge over the safe area it creates (its length
/// plus the spacing, default 8). On a list (a `ForEach`) every element gets an inset view of its
/// own (`position/safe-area-elements`).
@MainActor
package final class SafeAreaInsetNode<Content: View, Inset: View>: SafeAreaNode<Content, _SafeAreaInsetModifier<Inset>> {
    /// One inset view per target, made as targets are placed.
    private var insets: [ObjectIdentifier: TypedNode<Inset>] = [:]
    private var insetOrder: [ObjectIdentifier] = []

    override package init(_ context: _NodeContext<ModifiedContent<Content, _SafeAreaInsetModifier<Inset>>>) {
        super.init(context)
    }

    private func insetNode(for target: ViewNode) -> TypedNode<Inset> {
        let key = ObjectIdentifier(target)
        if let existing = insets[key] { return existing }
        let node = Inset._makeNode(_NodeContext(view: modifier.inset, parent: self, environment: environment))
        insets[key] = node
        insetOrder.append(key)
        return node
    }

    /// The inset views in target order, dropping those of targets that went away.
    private var insetNodes: [TypedNode<Inset>] {
        let live = Set(targets.map(ObjectIdentifier.init))
        for key in insetOrder where !live.contains(key) {
            insets[key]?.unmount()
            insets[key] = nil
        }
        insetOrder.removeAll { !live.contains($0) }
        return insetOrder.compactMap { insets[$0] }
    }

    override package func update(view: ModifiedContent<Content, _SafeAreaInsetModifier<Inset>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        for node in insetNodes { node.update(view: view.modifier.inset, environment: environment, force: force) }
    }

    override package func unmount() {
        for node in insets.values { node.unmount() }
        super.unmount()
    }

    private var spacing: CGFloat { modifier.spacing ?? 8 }
    private var isVertical: Bool { modifier.edge == .top || modifier.edge == .bottom }

    /// The inset view's proposal: the cross length, nothing along the edge's axis.
    private func insetProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        isVertical ? ProposedViewSize(width: proposal.width, height: nil) : ProposedViewSize(width: nil, height: proposal.height)
    }

    private func insetLength(for proposal: ProposedViewSize) -> CGFloat {
        let node = insetNode(for: targets.first ?? self)
        let sizes = node.layoutChildren.map { $0.sizeThatFits(insetProposal(proposal)) }
        return sizes.map { isVertical ? $0.height : $0.width }.max() ?? 0
    }

    override package func insets(for proposal: ProposedViewSize) -> EdgeInsets {
        let length = insetLength(for: proposal) + spacing
        switch modifier.edge {
        case .top: return EdgeInsets(top: length, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: length, trailing: 0)
        case .leading: return EdgeInsets(top: 0, leading: length, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: length)
        }
    }

    override package func placeInset(for target: ViewNode, in bounds: CGRect, by placer: ViewNode) {
        // The inset view sits inside the safe area this node already has: on a scroll view
        // reaching the screen's bottom, a footer stays above the home indicator.
        let overlap = safeAreaOverlap
        let bounds = CGRect(x: bounds.minX + overlap.leading, y: bounds.minY + overlap.top,
                            width: max(0, bounds.width - overlap.leading - overlap.trailing),
                            height: max(0, bounds.height - overlap.top - overlap.bottom))
        let proposal = insetProposal(ProposedViewSize(bounds.size))
        for node in insetNode(for: target).layoutChildren {
            let dims = node.dimensions(in: proposal)
            var origin: CGPoint
            switch modifier.edge {
            case .top: origin = CGPoint(x: 0, y: 0)
            case .bottom: origin = CGPoint(x: 0, y: bounds.height - dims.height)
            case .leading: origin = CGPoint(x: 0, y: 0)
            case .trailing: origin = CGPoint(x: bounds.width - dims.width, y: 0)
            }
            // Aligned across the edge within the bounds.
            let container = ViewDimensions(size: bounds.size)
            if isVertical {
                origin.x = container[modifier.alignment.horizontal] - dims[modifier.alignment.horizontal]
            } else {
                origin.y = container[modifier.alignment.vertical] - dims[modifier.alignment.vertical]
            }
            node.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading, proposal: proposal, by: placer)
        }
    }

    /// The inset views sit in the region they create; the safe area a target gets is not theirs
    /// (a horizontal scroll view as the inset would otherwise push its chips down by the bar's
    /// own height). The frame's unsafe depth beyond the bar stays theirs through the walk.
    override package func providedSafeAreaInsets(for child: ViewNode) -> EdgeInsets {
        if insets.values.contains(where: { $0 === child || $0.layoutChildren.contains { $0 === child } }) { return EdgeInsets() }
        return super.providedSafeAreaInsets(for: child)
    }

    override package var structuralChildren: [ViewNode] { [child] + insetNodes }
    /// Each target's inset view paints (and is hit tested) over it.
    override package func paintedChildren(of target: ViewNode) -> [ViewNode] {
        super.paintedChildren(of: target) + insetNode(for: target).layoutChildren
    }

    override package var nodeDescription: String { "SafeAreaInset" }
}

/// `safeAreaPadding`: fixed insets, no view.
@MainActor
package final class SafeAreaPaddingNode<Content: View>: SafeAreaNode<Content, _SafeAreaPaddingModifier> {
    override package func insets(for proposal: ProposedViewSize) -> EdgeInsets { modifier.resolvedInsets }
    override package var nodeDescription: String { "SafeAreaPadding" }
}

/// `ignoresSafeArea`: the modified view keeps the frame its parent gives it inside the safe
/// area; its content is proposed that frame grown by the unsafe depth beyond the ignored edges
/// it touches (`safeAreaExtension`) and placed in the grown rect, centred when it is smaller,
/// so a colour or a scroll view extends under a bar while a background or probe outside the
/// modifier still sees the safe frame (ios/representable/safearea-color, safearea-rule). The
/// content gets no safe area on the ignored edges; the geometry stays for hosted platform views.
@MainActor
package final class IgnoresSafeAreaNode<Content: View>: UnaryLayoutModifierNode<Content, _IgnoresSafeAreaModifier> {
    override package var paintsOutsideFrame: Bool { true }
    override package var changesChildSize: Bool { true }

    /// The unsafe depth beyond each ignored edge (zero on the others).
    private var ignored: EdgeInsets {
        var insets = safeAreaExtension
        let edges = modifier.edges
        if !edges.contains(.top) { insets.top = 0 }
        if !edges.contains(.bottom) { insets.bottom = 0 }
        if !edges.contains(.leading) { insets.leading = 0 }
        if !edges.contains(.trailing) { insets.trailing = 0 }
        return insets
    }

    override package func childProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        let insets = ignored
        return ProposedViewSize(width: proposal.width.map { $0 + insets.leading + insets.trailing },
                                height: proposal.height.map { $0 + insets.top + insets.bottom })
    }

    /// The child's size less what it took of the extension: a filling child reports the safe
    /// size, a fixed one its own.
    override package func size(forChild childSize: CGSize, proposal: ProposedViewSize) -> CGSize {
        let insets = ignored
        var size = childSize
        if let width = proposal.width { size.width -= min(insets.leading + insets.trailing, max(0, childSize.width - width)) }
        if let height = proposal.height { size.height -= min(insets.top + insets.bottom, max(0, childSize.height - height)) }
        return size
    }

    /// A child no larger than the safe frame moves into the extension on the side it reaches
    /// (an iPhone app's bottom bar with `ignoresSafeArea(edges: .bottom)` sits on the home
    /// indicator: Paulo's tab bar 25 pt above the screen's bottom, not the safe area's, in the
    /// iOS 27 simulator), centred in the grown rect when it reaches both ways and in the safe
    /// frame when it reaches neither; a larger one spreads into the extension in proportion to
    /// the depth on each side (a filling child covers it all).
    override package func childOrigin(_ child: ViewDimensions, in size: CGSize) -> CGPoint {
        let insets = ignored
        func offset(_ childLength: CGFloat, _ length: CGFloat, _ before: CGFloat, _ after: CGFloat) -> CGFloat {
            if childLength <= length + 1e-9 {
                switch (before > 0, after > 0) {
                case (true, false): return -before
                case (false, true): return length + after - childLength
                case (true, true): return (length + after - before - childLength) / 2
                case (false, false): return (length - childLength) / 2
                }
            }
            let total = before + after
            return total > 0 ? -before * min(1, (childLength - length) / total) : (length - childLength) / 2
        }
        return CGPoint(x: offset(child.width, size.width, insets.leading, insets.trailing),
                       y: offset(child.height, size.height, insets.top, insets.bottom))
    }

    override package func assignSafeArea(to child: ViewNode) {
        super.assignSafeArea(to: child)
        let edges = modifier.edges
        if edges.contains(.top) { child.safeAreaOverlap.top = 0; child.safeAreaExtension.top = 0 }
        if edges.contains(.bottom) { child.safeAreaOverlap.bottom = 0; child.safeAreaExtension.bottom = 0 }
        if edges.contains(.leading) { child.safeAreaOverlap.leading = 0; child.safeAreaExtension.leading = 0 }
        if edges.contains(.trailing) { child.safeAreaOverlap.trailing = 0; child.safeAreaExtension.trailing = 0 }
    }

    override package var nodeDescription: String { "IgnoresSafeArea" }
}
