// Table node (Docs/elements/Table.md): a 28 pt header (titles 10 pt into their columns, 1 pt
// dividers at the end of each 3 pt intercell gap, a bottom line), 24 pt rows from 33 with cells
// 8 pt in and 4 down, alternating rounded bands running to the bottom, the selection band, and
// sorting by header presses. The corners (sw-table): hidden headers start the rows 5 down, the
// bordered style runs its columns from a 1 pt border to the other with 1 pt row separators and
// no bands, an outline table indents its first column 10 pt for the disclosure chevrons and 16
// more per level, rows scroll when they do not fit (and columns sideways when they overflow),
// header dividers drag the columns, and a secondary press opens the row's context menu.
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

@MainActor
private var nextTableIdentifier = 9_800_000

@MainActor
package final class TableNode: LayoutNode<_TableHost>, _Interactive, _KeyHandling, _Scrollable, _HoverTracking, _PointerStyled, _ListRowIdentifying {
    private let identifier: Int
    private struct CellKey: Hashable { let row: AnyHashable; let column: Int }
    private var cells: [CellKey: TypedNode<AnyView>] = [:]
    private var order: [CellKey] = []
    /// The columns' content frames in the table's content space (unscrolled).
    package private(set) var columnFrames: [CGRect] = []
    /// Pitches set by dragging a header divider, by column index.
    package private(set) var pitchOverrides: [Int: CGFloat] = [:]
    package private(set) var contentOffset = CGPoint.zero

    package init(_ context: _NodeContext<_TableHost>) {
        nextTableIdentifier += 1
        identifier = nextTableIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        reconcile(force: false)
    }

    override package func update(view: _TableHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        reconcile(force: force)
    }

    /// One node per cell, reused by row identity and column.
    private func reconcile(force: Bool) {
        var kept: [CellKey: TypedNode<AnyView>] = [:]
        order = []
        for row in view.rows {
            for (column, cell) in row.cells.enumerated() {
                let key = CellKey(row: row.id, column: column)
                if let node = cells[key] {
                    node.update(view: cell, environment: environment, force: force)
                    kept[key] = node
                } else {
                    kept[key] = AnyView._makeNode(_NodeContext(view: cell, parent: self, environment: environment))
                }
                order.append(key)
            }
        }
        for (key, node) in cells where kept[key] == nil { node.unmount() }
        cells = kept
    }

    // MARK: Geometry

    private var options: _TableOptions { view.options }
    /// The header's height: nothing when the headers are hidden.
    package var headerHeight: CGFloat { options.hidesHeaders ? 0 : PlatformMetrics.tableHeaderHeight }
    /// Where the rows start: 33 under a header, 5 without one, 29 in the bordered style.
    package var rowsTop: CGFloat {
        if options.hidesHeaders { return PlatformMetrics.tableHiddenHeadersRowsTop }
        return headerHeight + (options.bordered ? PlatformMetrics.tableBorderedRowsTop : PlatformMetrics.tableRowsTop)
    }
    private var leadingMargin: CGFloat { options.bordered ? PlatformMetrics.tableBorderedMargin : PlatformMetrics.tableLeadingMargin }
    private var trailingMargin: CGFloat { options.bordered ? PlatformMetrics.tableBorderedMargin : PlatformMetrics.tableTrailingMargin }
    private var cellInset: CGFloat { PlatformMetrics.tableCellInset }
    private var headerTitleInset: CGFloat { PlatformMetrics.tableHeaderTitleInset }
    /// The first column's extra inset for its title and cells: 2 pt less in the bordered style,
    /// and an outline table makes room for its chevrons.
    private var firstColumnIndent: CGFloat {
        (options.bordered ? PlatformMetrics.tableBorderedFirstColumnIndent : 0) + (options.outline ? PlatformMetrics.tableOutlineIndent : 0)
    }
    /// The bordered style's titles sit a point lower (its header line is under the header).
    private var headerTitleOffset: CGFloat { options.bordered ? PlatformMetrics.tableBorderedHeaderTitleOffset : 0 }

    /// The content frames of the columns across `width` (NSTableView's layout, measured in
    /// `Docs/elements/Table.md`): every column has an ideal pitch (its SwiftUI width plus the 14 pt
    /// cell insets and the 3 pt intercell spacing; 117 for automatic columns) and the pitches fill
    /// the width less the 15 pt margins, the surplus shared equally by the growable columns in
    /// half points. Ideals that do not fit shrink by 15 pt in all, shared by the non-fixed columns,
    /// as long as the ideals themselves fit the width; otherwise the columns keep their ideals and
    /// overflow. A frame is a column's content: its pitch less the intercell spacing. The bordered
    /// style has 1 pt margins and gives its surplus to all but the last column in whole points,
    /// the remainder to the first (121, 120, 117 across 360). A dragged column keeps its pitch.
    package static func columnFrames(_ columns: [_TableColumnDescriptor], width: CGFloat, options: _TableOptions = _TableOptions(), overrides: [Int: CGFloat] = [:]) -> [CGRect] {
        let extra = PlatformMetrics.tableCellInset + PlatformMetrics.tableCellTrailingInset + PlatformMetrics.tableIntercellSpacing
        func half(_ value: CGFloat) -> CGFloat { (value * 2 + 0.5).rounded(.down) / 2 }
        struct Column { var ideal: CGFloat; var min: CGFloat; var max: CGFloat; var fixed: Bool }
        let specs = columns.enumerated().map { index, column -> Column in
            if let pitch = overrides[index] { return Column(ideal: pitch, min: pitch, max: pitch, fixed: true) }
            switch column.width {
            case .fixed(let value): return Column(ideal: value + extra, min: value + extra, max: value + extra, fixed: true)
            case .flexible(let min, let ideal, let max):
                let idealPitch = (ideal ?? PlatformMetrics.tableColumnIdealWidth) + extra
                return Column(ideal: idealPitch, min: Swift.min((min ?? PlatformMetrics.tableColumnMinWidth) + extra, idealPitch),
                              max: Swift.max(max.map { $0 + extra } ?? .infinity, idealPitch), fixed: false)
            case .automatic:
                return Column(ideal: PlatformMetrics.tableColumnIdealWidth + extra, min: PlatformMetrics.tableColumnMinWidth + extra, max: .infinity, fixed: false)
            }
        }
        let leading = options.bordered ? PlatformMetrics.tableBorderedMargin : PlatformMetrics.tableLeadingMargin
        let trailing = options.bordered ? PlatformMetrics.tableBorderedMargin : PlatformMetrics.tableTrailingMargin
        var pitches = specs.map(\.ideal)
        let idealTotal = pitches.reduce(0, +)
        let available = width - leading - trailing
        if idealTotal <= available {
            var remaining = available - idealTotal
            var open = specs.indices.filter { specs[$0].max > specs[$0].ideal }
            if options.bordered, open.count > 1 { open.removeLast() }
            while remaining > 0, !open.isEmpty {
                let share = options.bordered ? (remaining / CGFloat(open.count)).rounded(.down) : half(remaining / CGFloat(open.count))
                var next: [Int] = []
                for (position, index) in open.enumerated() {
                    let room = specs[index].max - pitches[index]
                    // The bordered style's whole-point remainder goes to the first columns.
                    let want = options.bordered && position < Int(remaining - share * CGFloat(open.count)) ? share + 1 : share
                    let grow = Swift.min(want, room)
                    pitches[index] += grow
                    remaining -= grow
                    if pitches[index] < specs[index].max { next.append(index) }
                }
                if next.count == open.count, share <= 0 { break }
                open = next
            }
        } else if idealTotal <= width {
            let shrinkable = specs.indices.filter { !specs[$0].fixed }
            if !shrinkable.isEmpty {
                let share = half((leading + trailing) / CGFloat(shrinkable.count))
                for index in shrinkable { pitches[index] = Swift.max(specs[index].min, pitches[index] - share) }
            }
        }
        var x = leading
        return pitches.map { pitch in
            defer { x += pitch }
            return CGRect(x: x, y: 0, width: pitch - PlatformMetrics.tableIntercellSpacing, height: PlatformMetrics.tableHeaderHeight)
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tableIdealSize.width,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.tableIdealSize.height)
    }

    /// The hosted scroll view's bounds in the node's space: the table's frame keeps SwiftUI's
    /// fractions (a stack of three gets 114.667 each) while AppKit aligns the view inside it to
    /// the pixel, so the rows, border and columns are drawn from the rounded edges.
    package var aligned: CGRect {
        let scale = max(1, environment.displayScale)
        let root = frameInRoot
        func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return CGRect(x: pixel(root.minX) - root.minX, y: pixel(root.minY) - root.minY,
                      width: pixel(root.maxX) - pixel(root.minX), height: pixel(root.maxY) - pixel(root.minY))
    }

    /// A row's frame in the table's content space (unscrolled).
    package func rowFrame(_ index: Int) -> CGRect {
        let aligned = aligned
        return CGRect(x: aligned.minX, y: aligned.minY + rowsTop + CGFloat(index) * PlatformMetrics.tableRowHeight, width: aligned.width, height: PlatformMetrics.tableRowHeight)
    }

    /// A row's frame as shown: scrolled by the content offset.
    private func visibleRowFrame(_ index: Int) -> CGRect { rowFrame(index).offsetBy(dx: 0, dy: -contentOffset.y) }
    private func visibleColumnFrame(_ index: Int) -> CGRect { columnFrames[index].offsetBy(dx: aligned.minX - contentOffset.x, dy: aligned.minY) }

    /// The leading inset of a cell in `column` of `row`: the cell inset, plus the outline indent
    /// and a level's worth per level in the first column.
    private func cellLeading(column: Int, level: Int) -> CGFloat {
        cellInset + (column == 0 ? firstColumnIndent + CGFloat(level) * PlatformMetrics.tableOutlineLevelIndent : 0)
    }

    /// The rows' total height and the columns' total width (for scrolling).
    private var contentSize: CGSize {
        CGSize(width: (columnFrames.last.map { $0.maxX } ?? 0) + trailingMargin,
               height: rowsTop + CGFloat(view.rows.count) * PlatformMetrics.tableRowHeight)
    }

    private func clampOffset() {
        let size = contentSize, aligned = aligned
        contentOffset.x = min(max(0, contentOffset.x), max(0, size.width - aligned.width))
        contentOffset.y = min(max(0, contentOffset.y), max(0, size.height - aligned.height))
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        runtime.wholePlacements += 1
        defer { runtime.wholePlacements -= 1 }
        columnFrames = Self.columnFrames(view.columns, width: aligned.width, options: options, overrides: pitchOverrides)
        clampOffset()
        for (rowIndex, row) in view.rows.enumerated() {
            let rowFrame = visibleRowFrame(rowIndex)
            for column in row.cells.indices where column < columnFrames.count {
                guard let cell = cells[CellKey(row: row.id, column: column)] else { continue }
                let columnFrame = visibleColumnFrame(column)
                let leading = cellLeading(column: column, level: row.level)
                let area = CGRect(x: columnFrame.minX + leading, y: rowFrame.minY + PlatformMetrics.tableCellTop,
                                  width: max(0, columnFrame.width - leading - PlatformMetrics.tableCellTrailingInset),
                                  height: rowFrame.height - 2 * PlatformMetrics.tableCellTop)
                for node in cell.layoutChildren {
                    let size = node.sizeThatFits(ProposedViewSize(area.size))
                    node.place(at: CGPoint(x: area.minX, y: area.minY), anchor: .topLeading, proposal: ProposedViewSize(width: area.width, height: size.height), by: self)
                }
            }
        }
    }

    override package var paintedChildren: [ViewNode] { order.compactMap { cells[$0] }.flatMap(\.layoutChildren) }
    override package var structuralChildren: [ViewNode] { order.compactMap { cells[$0] } }
    override package var nodeDescription: String { "Table" }
    override package var clipsHitTesting: Bool { true }

    override package func unmount() {
        for node in cells.values { node.unmount() }
        super.unmount()
    }

    // MARK: Painting

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let aligned = aligned
        let bounds = context.absoluteRect(aligned)
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        list.append(.fillRect(bounds, environment._controlBackground))
        let headerHeight = headerHeight
        let rowsArea = CGRect(x: bounds.minX, y: bounds.minY + headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
        list.withSavedState { list in
            list.append(.clipRect(rowsArea))
            // Row bands: every second slot to the bottom, and the selected rows. The bordered
            // style separates its rows with 1 pt lines instead.
            let bandInset = PlatformMetrics.tableBandInset
            var index = 0
            while visibleRowFrame(index).minY < aligned.maxY {
                let rowFrame = visibleRowFrame(index)
                if rowFrame.maxY <= aligned.minY + headerHeight { index += 1; continue }
                let row = context.absoluteRect(rowFrame).insetBy(dx: bandInset, dy: 0)
                let selected = index < view.rows.count && (view.selection?.isSelected(view.rows[index].id) ?? false)
                if selected {
                    list.append(.fillRRect(row, cornerRadius: PlatformMetrics.tableBandCornerRadius, black(PlatformMetrics.tableSelectionAlpha)))
                } else if options.bands, index % 2 == 1 {
                    list.append(.fillRRect(row, cornerRadius: PlatformMetrics.tableBandCornerRadius, black(PlatformMetrics.tableBandAlpha)))
                }
                if options.bordered, index < view.rows.count {
                    let separator = context.absoluteRect(CGRect(x: aligned.minX, y: rowFrame.maxY - 1, width: aligned.width, height: 1))
                    list.append(.fillRect(separator, black(PlatformMetrics.tableSeparatorAlpha)))
                }
                index += 1
            }
            // Outline chevrons: right for a collapsed group, down for an expanded one.
            if options.outline, !columnFrames.isEmpty {
                for (index, row) in view.rows.enumerated() where row.hasChildren {
                    let rowFrame = visibleRowFrame(index)
                    guard rowFrame.maxY > aligned.minY + headerHeight, rowFrame.minY < aligned.maxY else { continue }
                    // The chevron's box is its outer extent (5 × 8 with the stroke); the path sits
                    // half a stroke inside it.
                    let size = PlatformMetrics.tableOutlineChevronSize, half = PlatformMetrics.tableChevronStroke / 2
                    let x = visibleColumnFrame(0).minX + PlatformMetrics.tableOutlineChevronOffset + CGFloat(row.level) * PlatformMetrics.tableOutlineLevelIndent
                    let outer = context.absoluteRect(CGRect(x: x, y: rowFrame.minY + (rowFrame.height - size.height) / 2, width: size.width, height: size.height))
                    var chevron = Path()
                    if row.isExpanded {
                        let box = CGRect(x: outer.midX - size.height / 2, y: outer.midY - size.width / 2, width: size.height, height: size.width).insetBy(dx: half, dy: half)
                        chevron.move(to: CGPoint(x: box.minX, y: box.minY))
                        chevron.addLine(to: CGPoint(x: box.midX, y: box.maxY))
                        chevron.addLine(to: CGPoint(x: box.maxX, y: box.minY))
                    } else {
                        let box = outer.insetBy(dx: half, dy: half)
                        chevron.move(to: CGPoint(x: box.minX, y: box.minY))
                        chevron.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                        chevron.addLine(to: CGPoint(x: box.minX, y: box.maxY))
                    }
                    list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: PlatformMetrics.tableChevronStroke, lineCap: .round, lineJoin: .round),
                                            black(PlatformMetrics.tableOutlineChevronAlpha)))
                }
            }
            paintChildren(into: &list, context: context)
        }
        if headerHeight > 0 { paintHeader(into: &list, context: context, bounds: bounds) }
        if options.bordered {
            let border = PlatformMetrics.tableBorderAlpha
            list.append(.fillRect(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: 1), black(border)))
            list.append(.fillRect(CGRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1), black(border)))
            list.append(.fillRect(CGRect(x: bounds.minX, y: bounds.minY, width: 1, height: bounds.height), black(border)))
            list.append(.fillRect(CGRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height), black(border)))
        }
    }

    /// The header: titles (bold when sorted, with a chevron), dividers and the bottom line. A
    /// header cell runs to the next column; the last one ends with its content, and its divider
    /// is drawn only when the intercell gap after it fits before the trailing margin.
    private func paintHeader(into list: inout DisplayList, context: PaintContext, bounds: CGRect) {
        let ink = environment; let black = { (alpha: Double) in ink._ink(alpha) }
        list.append(.fillRect(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight), environment._controlBackground))
        // The bottom line: from a point inside the header, or from its end in the bordered style.
        let lineTop = bounds.minY + headerHeight - (options.bordered ? 0 : 1)
        list.append(.fillRect(CGRect(x: bounds.minX, y: lineTop, width: bounds.width, height: PlatformMetrics.tableHeaderLineThickness), black(PlatformMetrics.tableLineAlpha)))
        let primary = Color.primary.resolve(in: environment)
        let dividerY = bounds.minY + PlatformMetrics.tableDividerInset
        let dividerHeight = headerHeight - 2 * PlatformMetrics.tableDividerInset
        list.withSavedState { list in
            list.append(.clipRect(CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: headerHeight)))
            for (index, column) in view.columns.enumerated() where index < columnFrames.count {
                let rect = context.absoluteRect(visibleColumnFrame(index))
                let isLast = index == columnFrames.count - 1
                let cellEnd = isLast ? rect.maxX : rect.maxX + PlatformMetrics.tableIntercellSpacing
                let font = _fontFor(size: PlatformMetrics.tableHeaderFontSize, weight: column.sortOrder == nil ? .regular : .bold)
                let line = environment.platformProfile.systemFontMetrics(for: font).lineHeight
                let titleInset = headerTitleInset + (index == 0 ? firstColumnIndent : 0)
                list.withSavedState { list in
                    list.append(.clipRect(CGRect(x: rect.minX, y: rect.minY, width: cellEnd - rect.minX, height: rect.height)))
                    _drawText(column.title, font: font, lineTop: CGPoint(x: rect.minX + titleInset, y: rect.minY + (rect.height - line) / 2 + headerTitleOffset),
                              color: primary, into: &list)
                }
                if let order = column.sortOrder {
                    let size = PlatformMetrics.tableChevronSize
                    let right = cellEnd - PlatformMetrics.tableChevronTrailing
                    let top = rect.minY + (rect.height - size.height) / 2
                    var chevron = Path()
                    let apexY = order == .forward ? top : top + size.height, baseY = order == .forward ? top + size.height : top
                    chevron.move(to: CGPoint(x: right - size.width, y: baseY))
                    chevron.addLine(to: CGPoint(x: right - size.width / 2, y: apexY))
                    chevron.addLine(to: CGPoint(x: right, y: baseY))
                    list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: PlatformMetrics.tableChevronStroke, lineCap: .round, lineJoin: .round),
                                            Color.secondary.resolve(in: environment)))
                    if index == 0 {
                        // The sorted first column also draws a divider inside its leading edge.
                        list.append(.fillRect(CGRect(x: rect.minX + 1, y: dividerY, width: 1, height: dividerHeight), black(PlatformMetrics.tableLineAlpha)))
                    }
                }
                let trailingRoom = bounds.maxX - trailingMargin
                if !isLast || rect.maxX + PlatformMetrics.tableIntercellSpacing < trailingRoom {
                    let divider = CGRect(x: cellEnd - 1, y: dividerY, width: 1, height: dividerHeight)
                    if divider.maxX <= bounds.maxX {
                        list.append(.fillRect(divider, black(PlatformMetrics.tableLineAlpha)))
                    }
                }
            }
        }
    }

    // MARK: Scrolling

    /// Lays the rows out again at the new offset or pitches (a scrolled node, so a frame that
    /// only scrolled still runs the pass: the cells move).
    private func relayout() {
        runtime.noteScrolled(self)
        runtime.requestLayout(invalidatingSizes: false)
    }

    package func scroll(by delta: CGSize) -> CGSize {
        let size = contentSize, aligned = aligned
        let maxX = max(0, size.width - aligned.width), maxY = max(0, size.height - aligned.height)
        let target = CGPoint(x: min(max(0, contentOffset.x + delta.width), maxX), y: min(max(0, contentOffset.y + delta.height), maxY))
        let consumed = CGSize(width: target.x - contentOffset.x, height: target.y - contentOffset.y)
        guard consumed != .zero else { return delta }
        contentOffset = target
        relayout()
        return CGSize(width: delta.width - consumed.width, height: delta.height - consumed.height)
    }
    package func showIndicators() {}
    package func beginMomentum(velocity: CGSize) {}
    package var isDecelerating: Bool { false }
    package func pull(by distance: CGFloat) -> Bool { false }
    package func endPull() {}
    package func stopMomentum() {}
    package func advance(elapsed: Double) -> Bool { false }
    package var canMoveContentOnly: Bool { false }
    package func moveContent() {}
    package func beginTracking() {}
    package func endTracking(velocity: CGSize) {}
    package var dismissesKeyboardOnScroll: Bool { false }

    // MARK: Interaction

    /// The header divider within reach of `point`, by the column it ends: the last column's
    /// only where its divider is drawn.
    private static let dragZone: CGFloat = 4
    private func divider(at point: CGPoint) -> Int? {
        let aligned = aligned
        guard headerHeight > 0, point.y < aligned.minY + headerHeight else { return nil }
        for index in columnFrames.indices {
            let rect = visibleColumnFrame(index)
            let isLast = index == columnFrames.count - 1
            if isLast, rect.maxX + PlatformMetrics.tableIntercellSpacing >= aligned.maxX - trailingMargin { continue }
            let cellEnd = isLast ? rect.maxX : rect.maxX + PlatformMetrics.tableIntercellSpacing
            if abs(point.x - (cellEnd - 0.5)) <= Self.dragZone { return index }
        }
        return nil
    }

    private var drag: (column: Int, startX: CGFloat, startPitch: CGFloat)?
    private var hoveredDivider: Int?

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        drag = nil
        guard environment.isEnabled, let column = divider(at: point) else { return }
        let pitch = columnFrames[column].width + PlatformMetrics.tableIntercellSpacing
        drag = (column, point.x, pitch)
    }

    package func pressMoved(to point: CGPoint) {
        guard let drag else { return }
        let minimum = PlatformMetrics.tableColumnMinWidth + PlatformMetrics.tableCellInset + PlatformMetrics.tableCellTrailingInset + PlatformMetrics.tableIntercellSpacing
        pitchOverrides[drag.column] = max(minimum, (drag.startPitch + point.x - drag.startX).rounded())
        relayout()
    }

    package var dragAxes: Axis.Set { drag == nil ? [] : .horizontal }
    package func pressEnded(inside: Bool) {}

    package func pressEnded(inside: Bool, at point: CGPoint) {
        if drag != nil {
            drag = nil
            runtime.setNeedsDisplay()
            return
        }
        guard inside, environment.isEnabled else { return }
        if point.y < aligned.minY + headerHeight {
            if let sort = view.sort, let index = columnFrames.indices.first(where: { let f = visibleColumnFrame($0); return point.x >= f.minX && point.x < f.maxX + PlatformMetrics.tableIntercellSpacing }), view.columns[index].sortable {
                sort.sort(index)
                runtime.setNeedsDisplay()
            }
            return
        }
        for index in view.rows.indices where visibleRowFrame(index).contains(point) {
            let row = view.rows[index]
            // A press on an outline row's chevron (or the indent before it) toggles its children.
            if options.outline, row.hasChildren, let toggle = view.toggle, !columnFrames.isEmpty {
                let start = visibleColumnFrame(0).minX
                let end = start + cellLeading(column: 0, level: row.level)
                if point.x >= start, point.x < end {
                    toggle.toggle(row.id)
                    runtime.setNeedsDisplay()
                    return
                }
            }
            guard let selection = view.selection else { return }
            selection.toggle(row.id)
            selectionAnchor = index
            runtime.focus(semanticsIdentifier: identifier)
            runtime.setNeedsDisplay()
            return
        }
    }

    package func hoverChanged(inside: Bool, at point: CGPoint) {
        let divider = inside ? divider(at: point) : nil
        if divider != hoveredDivider { hoveredDivider = divider }
    }

    /// The column-resize cursor over a header divider.
    package var pointerStyle: PointerStyle? { hoveredDivider != nil || drag != nil ? .columnResize(directions: .all) : nil }

    /// The row identifiers a context menu applies to at `point`: the selection when the row under
    /// it is selected, else that row alone.
    package func contextSelection(at point: CGPoint) -> Set<AnyHashable> {
        guard let index = view.rows.indices.first(where: { visibleRowFrame($0).contains(point) }) else { return [] }
        let id = view.rows[index].id
        let selected = Set(view.rows.map(\.id).filter { view.selection?.isSelected($0) ?? false })
        return selected.contains(id) ? selected : [id]
    }

    private var selectionAnchor: Int?

    /// Up/Down move the selection, Shift extends it, Home/End jump; Left/Right collapse and
    /// expand an outline row.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard let selection = view.selection, press.modifiers.shortcutModifiers.isSubset(of: [.shift]), !view.rows.isEmpty else { return false }
        let ids = view.rows.map(\.id)
        let current = ids.lastIndex { selection.isSelected($0) }
        if options.outline, let toggle = view.toggle, let current, press.key == .leftArrow || press.key == .rightArrow {
            let row = view.rows[current]
            guard row.hasChildren, row.isExpanded == (press.key == .leftArrow) else { return true }
            toggle.toggle(row.id)
            runtime.setNeedsDisplay()
            return true
        }
        let target: Int
        switch press.key {
        case .downArrow: target = current.map { min($0 + 1, ids.count - 1) } ?? 0
        case .upArrow: target = current.map { max($0 - 1, 0) } ?? ids.count - 1
        case .home: target = 0
        case .end: target = ids.count - 1
        default: return false
        }
        if press.modifiers.contains(.shift), let anchor = selectionAnchor ?? current {
            selectionAnchor = anchor
            selection.select(Array(ids[min(anchor, target)...max(anchor, target)]))
        } else {
            selectionAnchor = target
            selection.select([ids[target]])
        }
        // The selected row scrolls into view.
        let rowFrame = rowFrame(target), aligned = aligned
        if rowFrame.minY - contentOffset.y < aligned.minY + rowsTop { contentOffset.y = max(0, rowFrame.minY - aligned.minY - rowsTop) }
        if rowFrame.maxY - contentOffset.y > aligned.maxY { contentOffset.y = rowFrame.maxY - aligned.maxY }
        relayout()
        return true
    }

    package var semantics: SemanticsNode {
        var node = SemanticsNode(role: view.selection == nil ? .group : .list, label: view.columns.map(\.title).joined(separator: ", "), frame: frameInRoot, identifier: identifier)
        node.isFocusable = view.selection != nil
        return node
    }
    package var exposesChildren: Bool { true }
}
