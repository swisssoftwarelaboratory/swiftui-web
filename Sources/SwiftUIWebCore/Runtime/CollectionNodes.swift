// Nodes for the data-driven list views. `ForEach` is the one place the runtime reconciles by
// key (Docs/ARCHITECTURE.md, invariant 1); `Section` is a transparent three-part list.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

// MARK: ForEach

/// Keeps one child per element identity. On update, elements whose id already has a node reuse
/// it (state survives moves); new ids get fresh subtrees; vanished ids are unmounted. Children
/// are ordered like the data. Duplicate ids get independent nodes, as SwiftUI does (it warns).
@MainActor
package final class ForEachNode<Data: RandomAccessCollection, ID: Hashable, Content: View>:
    TypedNode<ForEach<Data, ID, Content>>, _ForEachNodeProviding, _LazyMaterializing, _LazyEstimating
{
    package struct Entry {
        package let id: ID
        /// The element's subtree, or nil while a placeholder stands for it (lazy containers).
        package fileprivate(set) var node: TypedNode<Content>?
        fileprivate var placeholder: LazyPlaceholderNode?
        package var view: ViewNode { node ?? placeholder! }
    }

    package private(set) var entries: [Entry] = []

    package var _onDelete: ((IndexSet) -> Void)? { view._onDelete }
    package var _onMove: ((IndexSet, Int) -> Void)? { view._onMove }
    package var _dropInsert: _ForEachDrop? { view._dropInsert }

    /// Number of subtrees created over the node's life, for tests.
    package private(set) var created = 0

    /// The axis of the lazy container this `ForEach` is in: elements beyond the first are
    /// placeholders until they scroll into view (Runtime/LazyNodes.swift).
    private var lazyAxis: Axis?
    private var estimate: (generation: UInt64, proposal: ProposedViewSize, size: CGSize)?

    init(_ context: _NodeContext<ForEach<Data, ID, Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        reconcile(previous: [], environment: context.environment, force: false)
    }

    override package func update(view: ForEach<Data, ID, Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        reconcile(previous: entries, environment: environment, force: force)
    }

    private func reconcile(previous: [Entry], environment: EnvironmentValues, force: Bool) {
        // Lazy only inside a scroll view: everything else shows every element anyway.
        lazyAxis = hasEnclosingScrollView ? environment._lazyContainerAxis : nil
        // Group survivors by id; a queue per id keeps duplicates stable in order.
        var available: [ID: [TypedNode<Content>]] = [:]
        var placeholders: [ID: [LazyPlaceholderNode]] = [:]
        for entry in previous.reversed() {
            if let node = entry.node { available[entry.id, default: []].append(node) }
            if let placeholder = entry.placeholder { placeholders[entry.id, default: []].append(placeholder) }
        }
        var next: [Entry] = []
        next.reserveCapacity(view.data.count)
        var hasRealNode = !available.isEmpty
        for element in view.data {
            let id = view.id(of: element)
            if let node = available[id]?.popLast() {
                node.update(view: view.content(element), environment: environment, force: force)
                next.append(Entry(id: id, node: node, placeholder: nil))
            } else if lazyAxis != nil, let placeholder = placeholders[id]?.popLast() {
                next.append(Entry(id: id, node: nil, placeholder: placeholder))
            } else if lazyAxis != nil, hasRealNode {
                // Created when it scrolls into view; the first element seeds the size estimate.
                next.append(Entry(id: id, node: nil, placeholder: LazyPlaceholderNode(owner: self)))
            } else {
                created += 1
                hasRealNode = true
                let node = Content._makeNode(_NodeContext(view: view.content(element), parent: self, environment: environment))
                next.append(Entry(id: id, node: node, placeholder: nil))
                if !previous.isEmpty { noteInserted(node) }
            }
        }
        for nodes in available.values {
            for node in nodes { retire(node) }
        }
        for nodes in placeholders.values {
            for node in nodes { node.unmount() }
        }
        entries = next
    }

    // MARK: Laziness

    private var hasEnclosingScrollView: Bool {
        var node = parent
        while let current = node {
            if current is any _ScrollViewport { return true }
            node = current.parent
        }
        return false
    }

    private func placeholderRect(_ placeholder: LazyPlaceholderNode, contentOrigin origin: CGPoint) -> CGRect {
        let frame = placeholder.frameInRoot
        return CGRect(x: frame.minX - origin.x, y: frame.minY - origin.y, width: frame.width, height: frame.height)
    }

    private func placeholderOverlaps(_ placeholder: LazyPlaceholderNode, visible: CGRect, contentOrigin origin: CGPoint) -> Bool {
        let rect = placeholderRect(placeholder, contentOrigin: origin)
        guard !rect.isNull, !visible.isEmpty else { return false }
        func overlaps(_ lower: CGFloat, _ upper: CGFloat, _ visibleLower: CGFloat, _ visibleUpper: CGFloat) -> Bool {
            // An empty first child can seed a zero-sized estimate for nonempty later children.
            // Such a point estimate inside the window must be measured, not left lazy forever.
            if lower == upper { return lower >= visibleLower && lower < visibleUpper }
            // A positive-sized estimate that only touches the window is still outside it.
            return upper > visibleLower && lower < visibleUpper
        }
        return overlaps(rect.minX, rect.maxX, visible.minX, visible.maxX)
            && overlaps(rect.minY, rect.maxY, visible.minY, visible.maxY)
    }

    package func needsMaterialization(visible: CGRect, contentOrigin origin: CGPoint) -> Bool {
        guard lazyAxis != nil else { return false }
        return entries.contains { entry in
            guard let placeholder = entry.placeholder else { return false }
            return placeholderOverlaps(placeholder, visible: visible, contentOrigin: origin)
        }
    }

    package func materialize(visible: CGRect, contentOrigin origin: CGPoint) -> Bool {
        guard lazyAxis != nil, entries.contains(where: { $0.placeholder != nil }) else { return false }
        var changed = false
        var index = 0
        for element in view.data {
            defer { index += 1 }
            guard index < entries.count, let placeholder = entries[index].placeholder,
                  placeholderOverlaps(placeholder, visible: visible, contentOrigin: origin) else { continue }
            created += 1
            let node = Content._makeNode(_NodeContext(view: view.content(element), parent: self, environment: environment))
            placeholder.unmount()
            entries[index].node = node
            entries[index].placeholder = nil
            changed = true
        }
        if changed { didMaterialize() }
        return changed
    }

    /// Elements were created inside a layout pass: the estimate the remaining placeholders are
    /// sized by changes, so their memos go, with this node's and its ancestors'; nothing else on
    /// the page is re-measured.
    private func didMaterialize() {
        estimate = nil
        noteMemoReset("collection placeholders")
        for entry in entries { entry.placeholder?.invalidateSizeMemo() }
        invalidateSizeMemosUpward()
    }

    /// The placeholder element identified by `id` (its own id, or the `id(_:)` on its content).
    private func placeholderIndex(id: AnyHashable) -> Int? {
        guard lazyAxis != nil, entries.contains(where: { $0.placeholder != nil }) else { return nil }
        var index = 0
        for element in view.data {
            defer { index += 1 }
            guard index < entries.count, entries[index].placeholder != nil else { continue }
            if AnyHashable(entries[index].id) == id { return index }
            if let identified = view.content(element) as? any _IDProviding, identified._identifier == id { return index }
        }
        return nil
    }

    package func hasPlaceholder(id: AnyHashable) -> Bool { placeholderIndex(id: id) != nil }

    package func materialize(id: AnyHashable) -> Bool {
        guard let index = placeholderIndex(id: id), let placeholder = entries[index].placeholder else { return false }
        let element = view.data[view.data.index(view.data.startIndex, offsetBy: index)]
        created += 1
        let node = Content._makeNode(_NodeContext(view: view.content(element), parent: self, environment: environment))
        placeholder.unmount()
        entries[index].node = node
        entries[index].placeholder = nil
        didMaterialize()
        return true
    }

    /// The average size of the created elements for `proposal`: their layout children summed
    /// along the lazy axis and the widest across it.
    package func estimatedSize(for proposal: ProposedViewSize) -> CGSize {
        if let estimate, estimate.generation == runtime.fullLayoutCount, estimate.proposal == proposal { return estimate.size }
        let axis = lazyAxis ?? .vertical
        var total = CGSize.zero
        var count = 0
        for entry in entries {
            guard let node = entry.node else { continue }
            var along: CGFloat = 0, across: CGFloat = 0
            for child in node.layoutChildren {
                let size = child.sizeThatFits(proposal)
                along += size[axis]
                across = max(across, size[axis == .vertical ? .horizontal : .vertical])
            }
            total[axis] += along
            total[axis == .vertical ? .horizontal : .vertical] = max(total[axis == .vertical ? .horizontal : .vertical], across)
            count += 1
        }
        var size = total
        if count > 0 { size[axis] = total[axis] / CGFloat(count) }
        estimate = (runtime.fullLayoutCount, proposal, size)   // per full layout: the elements' sizes may have changed with an update
        return size
    }

    package var children: [TypedNode<Content>] { entries.compactMap(\.node) }

    package var _entries: [(AnyHashable, ViewNode)] { entries.map { (AnyHashable($0.id), $0.view) } }

    override package var structuralChildren: [ViewNode] { entries.map(\.view) }
    override package var layoutChildren: [ViewNode] { entries.flatMap { $0.view.layoutChildren } }
    override package var nodeDescription: String { "ForEach(\(entries.count))" }
}

// MARK: Section

/// Header, content and footer in order, each transparent to layout.
@MainActor
package final class SectionNode<Parent: View, Content: View, Footer: View>:
    TypedNode<Section<Parent, Content, Footer>>
{
    package private(set) var header: TypedNode<Parent>!
    package private(set) var content: TypedNode<Content>!
    package private(set) var footer: TypedNode<Footer>!
    /// In a menu the header is a small secondary row (`_MenuSectionHeader`) instead.
    private var menuHeader: TypedNode<AnyView>?

    init(_ context: _NodeContext<Section<Parent, Content, Footer>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        header = Parent._makeNode(_NodeContext(view: context.view.header, parent: self, environment: Self.headerEnvironment(context.environment)))
        content = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        footer = Footer._makeNode(_NodeContext(view: context.view.footer, parent: self, environment: Self.headerEnvironment(context.environment, footer: true)))
        if context.environment._inMenu, !(context.view.header is EmptyView) {
            menuHeader = AnyView._makeNode(_NodeContext(view: AnyView(_MenuSectionHeader(header: AnyView(context.view.header))), parent: self, environment: context.environment))
        }
    }

    override package func update(view: Section<Parent, Content, Footer>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        header.update(view: view.header, environment: Self.headerEnvironment(environment), force: force)
        content.update(view: view.content, environment: environment, force: force)
        footer.update(view: view.footer, environment: Self.headerEnvironment(environment, footer: true), force: force)
        menuHeader?.update(view: AnyView(_MenuSectionHeader(header: AnyView(view.header))), environment: environment, force: force)
    }

    /// Inside a `List` the header and footer take the container's styling (`_sectionStyling`).
    private static func headerEnvironment(_ environment: EnvironmentValues, footer: Bool = false) -> EnvironmentValues {
        guard let styling = environment._sectionStyling else { return environment }
        var styled = environment
        styled.font = footer ? styling.footerFont ?? styling.font : styling.font
        styled.foregroundColor = footer ? styling.footerForeground ?? styling.foreground : styling.foreground
        styled._sectionStyling = nil
        return styled
    }

    override package var structuralChildren: [ViewNode] { [menuHeader ?? header, content, footer] }
    override package var layoutChildren: [ViewNode] {
        (menuHeader ?? header).layoutChildren + content.layoutChildren + footer.layoutChildren
    }
    override package var nodeDescription: String { "Section" }
}

extension SectionNode: _SectionNodeProviding {
    package var _headerNode: ViewNode { header }
    package var _contentNode: ViewNode { content }
    package var _footerNode: ViewNode { footer }
}
