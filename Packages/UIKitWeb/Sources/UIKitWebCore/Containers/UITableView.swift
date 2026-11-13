// UITableView (Docs/elements/UIKit/TableView.md): rows from a data source in one scrolling
// view, the plain and inset grouped styles, section headers and footers, the default, subtitle
// and value1 cell styles with accessories, selection. Geometry from UIKit on the iPhone SE
// simulator (iOS 26): 56 pt text rows, 73 pt subtitle rows, 1 pt separators 16 in, grouped
// cards 16 in with 26 pt corners.

// `NSObject` and `NSObjectProtocol`, which data sources and delegates subclass, are
// WebFoundation's on wasm (Responder.swift; one declaration) and Foundation's elsewhere.
import WebFoundation

extension IndexPath {
    /// A table row's position (UIKit's additions to Foundation's index path).
    public init(row: Int, section: Int) { self.init(indexes: [section, row]) }
    /// A collection item's position.
    public init(item: Int, section: Int) { self.init(indexes: [section, item]) }
    public var row: Int { get { self[1] } set { self[1] = newValue } }
    public var item: Int { get { self[1] } set { self[1] = newValue } }
    public var section: Int { get { self[0] } set { self[0] = newValue } }
}

/// The methods that an object adopts to manage data and provide cells for a table view.
@preconcurrency @MainActor
public protocol UITableViewDataSource: AnyObject {
    func numberOfSections(in tableView: UITableView) -> Int
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
    func sectionIndexTitles(for tableView: UITableView) -> [String]?
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int
}

extension UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int { 1 }
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { nil }
    public func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { nil }
    public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
    public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { false }
    public func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {}
    public func sectionIndexTitles(for tableView: UITableView) -> [String]? { nil }
    public func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int { index }
}

/// Methods for managing selections, configuring section headers and footers, deleting and
/// reordering cells, and performing other actions in a table view.
@preconcurrency @MainActor
public protocol UITableViewDelegate: UIScrollViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath?
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath)
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle
    func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String?
    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath)
    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?)
}

extension UITableViewDelegate {
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat { UITableView.automaticDimension }
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? { nil }
    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? { nil }
    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? { indexPath }
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .delete }
    public func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? { nil }
    public func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { true }
    public func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
    public func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? { nil }
    public func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {}
    public func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {}
}

/// A view that presents data using rows in a single column.
@preconcurrency @MainActor
open class UITableView: UIScrollView, UIGestureRecognizerDelegate {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public enum Style: Int, Sendable { case plain = 0, grouped, insetGrouped }
    public enum ScrollPosition: Int, Sendable { case none = 0, top, middle, bottom }
    public enum RowAnimation: Int, Sendable { case fade = 0, right, left, top, bottom, none, middle, automatic = 100 }

    public static let automaticDimension: CGFloat = -1

    public let style: Style
    open weak var dataSource: (any UITableViewDataSource)? { didSet { setNeedsReload() } }
    open weak var tableDelegate: (any UITableViewDelegate)?
    /// Keyboard focus (Events/Keyboard.swift): whether the cells take it, and whether it selects.
    open var allowsFocus = true

    // MARK: Drag and drop (Events/DragDrop.swift)

    open weak var dragDelegate: (any UITableViewDragDelegate)? { didSet { installDragLiftIfNeeded() } }
    open weak var dropDelegate: (any UITableViewDropDelegate)?
    open var dragInteractionEnabled = true { didSet { installDragLiftIfNeeded() } }
    public var hasActiveDrag: Bool { UIKitScene.shared.dragSession?.sourceView === self }
    public var hasActiveDrop: Bool { activeDropSession != nil }
    var draggedIndexPaths: [IndexPath] = []
    var activeDropSession: DragDropSession?
    var lastDropProposal: UITableViewDropProposal?
    private var dragLift: _DragLiftGestureRecognizer?

    private func installDragLiftIfNeeded() {
        if dragDelegate != nil, dragInteractionEnabled, dragLift == nil {
            let lift = _DragLiftGestureRecognizer()
            lift.addTarget { [weak self] recognizer in self?.handleDragLift(recognizer) }
            addGestureRecognizer(lift)
            dragLift = lift
        } else if let dragLift, dragDelegate == nil || !dragInteractionEnabled {
            removeGestureRecognizer(dragLift)
            self.dragLift = nil
        }
    }

    private func handleDragLift(_ recognizer: UIGestureRecognizer) {
        let scene = UIKitScene.shared
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began: scene.beginDrag(from: self, pressedAt: (recognizer as? _DragLiftGestureRecognizer)?.startLocation ?? point, at: point)
        case .changed: scene.updateDrag(to: point)
        case .ended: scene.endDrag(at: point)
        case .cancelled, .failed: scene.cancelDrag()
        default: break
        }
    }
    open var selectionFollowsFocus = false
    open var rowHeight: CGFloat = UITableView.automaticDimension { didSet { setNeedsReload() } }
    open var estimatedRowHeight: CGFloat = 0
    open var sectionHeaderHeight: CGFloat = UITableView.automaticDimension
    open var sectionFooterHeight: CGFloat = UITableView.automaticDimension
    /// The space above the first section's header in the plain style (22 with a header).
    open var sectionHeaderTopPadding: CGFloat = UITableView.automaticDimension
    open var separatorStyle: UITableViewCell.SeparatorStyle = .singleLine { didSet { setNeedsDisplay() } }
    open var separatorColor: UIColor? = .separator
    open var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    open var allowsSelection = true
    open var allowsMultipleSelection = false
    open var tableHeaderView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = tableHeaderView { addSubview(view) }; setNeedsReload() } }
    open var tableFooterView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = tableFooterView { addSubview(view) }; setNeedsReload() } }
    /// Editing mode: editable rows shift right behind delete or insert controls, movable ones
    /// show a reorder grip (uikit/table/editing).
    open var allowsSelectionDuringEditing = false
    /// The section index strip (Containers/SectionIndex.swift): shown when the data source
    /// gives titles, over the rows at the right edge.
    open var sectionIndexColor: UIColor? { didSet { sectionIndex.setNeedsDisplay() } }
    open var sectionIndexBackgroundColor: UIColor? { didSet { sectionIndex.setNeedsDisplay() } }
    open var sectionIndexTrackingBackgroundColor: UIColor?
    open var sectionIndexMinimumDisplayRowCount = 0
    let sectionIndex: SectionIndexView = {
        let view = SectionIndexView()
        view.isHidden = true
        return view
    }()
    open var isEditing = false { didSet { if isEditing != oldValue { closeSwipe(animated: false); applyEditingState() } } }
    open func setEditing(_ editing: Bool, animated: Bool) {
        guard editing != isEditing else { return }
        if animated {
            UIView.animate(withDuration: batchUpdateDuration) { self.isEditing = editing; self.layoutIfNeeded() }
        } else {
            isEditing = editing
        }
    }
    /// The row whose swipe actions are open, and the recognizer that reveals them (and drags a
    /// row by its reorder grip in editing mode).
    private(set) var swipedRow: IndexPath?
    private var swipeRecognizer: UIPanGestureRecognizer!
    private var swipeTrailing = true
    /// The row being dragged by its grip, where it started and where it would drop.
    private(set) var reorderingRow: IndexPath?
    private var reorderTarget: IndexPath?
    private var reorderStartFrame = CGRect.zero
    open var cellLayoutMarginsFollowReadableWidth = false
    open var insetsContentViewsToSafeArea = true

    /// The delegate is a table view delegate too.
    open override weak var delegate: (any UIScrollViewDelegate)? {
        didSet { tableDelegate = delegate as? any UITableViewDelegate }
    }

    private var registeredCells: [String: () -> UITableViewCell] = [:]
    private var reusePool: [String: [UITableViewCell]] = [:]
    private var visibleCellsByPath: [IndexPath: UITableViewCell] = [:]
    private var headerViews: [Int: UIView] = [:]
    /// Each plain-style header's place in the content and the end of its section, for pinning.
    private var headerNaturalFrames: [Int: CGRect] = [:]
    private var sectionEnds: [Int: CGFloat] = [:]
    private var footerViews: [Int: UIView] = [:]
    private var needsReload = true
    private var rowFrames: [IndexPath: CGRect] = [:]
    private var selected: Set<IndexPath> = []

    public init(frame: CGRect, style: Style) {
        self.style = style
        super.init(frame: frame)
        // The grouped ground is (242, 242, 247) on the iPhone (uikit/table/grouped).
        backgroundColor = style == .plain ? .systemBackground : UIColor(light: RGBA(r: 242, g: 242, b: 247), dark: .black)
        alwaysBounceVertical = true
        let swipe = UIPanGestureRecognizer()
        swipe.allowsSimultaneousRecognition = true
        swipe.delegate = self
        swipe.addTarget { [weak self] recognizer in self?.handleSwipe(recognizer as! UIPanGestureRecognizer) }
        addGestureRecognizer(swipe)
        swipeRecognizer = swipe
        panGestureRecognizer.delegate = self
        let tap = UITapGestureRecognizer()
        tap.allowsSimultaneousRecognition = true
        tap.delegate = self
        tap.addTarget { [weak self] recognizer in self?.handleTap(recognizer) }
        addGestureRecognizer(tap)
    }

    public override convenience init(frame: CGRect) { self.init(frame: frame, style: .plain) }

    // MARK: Cells

    open func register(_ cellClass: AnyClass?, forCellReuseIdentifier identifier: String) {
        guard let type = cellClass as? UITableViewCell.Type else { return }
        #if _runtime(_ObjC)
        registeredCells[identifier] = { _makeRegisteredCell(type, reuseIdentifier: identifier) }
        #else
        registeredCells[identifier] = { type.init(style: .default, reuseIdentifier: identifier) }
        #endif
    }

    open func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? {
        if let cell = reusePool[identifier]?.popLast() {
            cell.prepareForReuse()
            return cell
        }
        return registeredCells[identifier]?()
    }

    open func dequeueReusableCell(withIdentifier identifier: String, for indexPath: IndexPath) -> UITableViewCell {
        dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .default, reuseIdentifier: identifier)
    }

    open var visibleCells: [UITableViewCell] { visibleCellsByPath.sorted { $0.key < $1.key }.map(\.value) }
    open var indexPathsForVisibleRows: [IndexPath]? { visibleCellsByPath.keys.sorted() }
    open func cellForRow(at indexPath: IndexPath) -> UITableViewCell? { visibleCellsByPath[indexPath] }
    open func indexPath(for cell: UITableViewCell) -> IndexPath? { visibleCellsByPath.first { $0.value === cell }?.key }
    open func rectForRow(at indexPath: IndexPath) -> CGRect { rowFrames[indexPath] ?? .zero }
    open func indexPathForRow(at point: CGPoint) -> IndexPath? { rowFrames.first { $0.value.contains(point) }?.key }
    open var numberOfSections: Int { dataSource?.numberOfSections(in: self) ?? 0 }
    open func numberOfRows(inSection section: Int) -> Int { dataSource?.tableView(self, numberOfRowsInSection: section) ?? 0 }

    // MARK: Selection

    open var indexPathForSelectedRow: IndexPath? { selected.sorted().first }
    open var indexPathsForSelectedRows: [IndexPath]? { selected.isEmpty ? nil : selected.sorted() }

    open func selectRow(at indexPath: IndexPath?, animated: Bool, scrollPosition: ScrollPosition) {
        if !allowsMultipleSelection { for path in selected { visibleCellsByPath[path]?.setSelected(false, animated: false) }; selected.removeAll() }
        guard let indexPath else { setNeedsDisplay(); return }
        selected.insert(indexPath)
        visibleCellsByPath[indexPath]?.setSelected(true, animated: animated)
        if scrollPosition != .none { scrollToRow(at: indexPath, at: scrollPosition, animated: animated) }
        setNeedsDisplay()
    }

    open func deselectRow(at indexPath: IndexPath, animated: Bool) {
        selected.remove(indexPath)
        visibleCellsByPath[indexPath]?.setSelected(false, animated: animated)
        setNeedsDisplay()
    }

    open func scrollToRow(at indexPath: IndexPath, at scrollPosition: ScrollPosition, animated: Bool) {
        guard let frame = rowFrames[indexPath] else { return }
        var offset = contentOffset
        switch scrollPosition {
        case .top: offset.y = frame.minY
        case .middle: offset.y = frame.midY - bounds.height / 2
        case .bottom: offset.y = frame.maxY - bounds.height
        case .none: if frame.minY < offset.y { offset.y = frame.minY } else if frame.maxY > offset.y + bounds.height { offset.y = frame.maxY - bounds.height }
        }
        setContentOffset(offset, animated: animated)
    }

    // MARK: Editing and swipe actions (Containers/SwipeActions.swift)

    /// Editable rows take the editing state; the cells lay out again.
    private func applyEditingState() {
        for (path, cell) in visibleCellsByPath { configureEditing(of: cell, at: path) }
        setNeedsLayout()
    }

    private func configureEditing(of cell: UITableViewCell, at path: IndexPath) {
        let editable = dataSource?.tableView(self, canEditRowAt: path) ?? false
        cell.editingStyle = editable ? (tableDelegate?.tableView(self, editingStyleForRowAt: path) ?? .delete) : .none
        cell.canMove = editable && (dataSource?.tableView(self, canMoveRowAt: path) ?? false)
        cell.setEditing(isEditing && editable, animated: false)
    }

    /// A swipe action button takes its own taps and the section index its own touches: the
    /// table's recognizers (tap, swipe, scroll) leave them alone.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view, current !== self {
            if current is SwipeActionButton || current is SectionIndexView { return false }
            view = current.superview
        }
        return true
    }

    /// A horizontal pan on a row with actions on that side reveals them; vertical pans scroll.
    open override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === swipeRecognizer, let pan = recognizer as? UIPanGestureRecognizer else { return super.gestureRecognizerShouldBegin(recognizer) }
        let translation = pan.translation(in: self)
        // Where the finger went down (the pan begins after the slop).
        let current = pan.location(in: self)
        let location = CGPoint(x: current.x - translation.x, y: current.y - translation.y)
        // In editing mode a pan starting on a movable row's grip drags the row.
        if isEditing, let path = indexPathForRow(at: location), let cell = visibleCellsByPath[path], cell.showsGrip,
           location.x >= cell.frame.maxX - UITableViewCell.reorderControlWidth - 24 {
            reorderingRow = path
            reorderTarget = path
            reorderStartFrame = cell.frame
            bringSubviewToFront(cell)
            return true
        }
        guard abs(translation.x) > abs(translation.y) else { return false }
        if let open = swipedRow, visibleCellsByPath[open] != nil { return true }
        guard let path = indexPathForRow(at: location), let cell = visibleCellsByPath[path] else { return false }
        let trailing = translation.x < 0
        guard let configuration = trailing ? tableDelegate?.tableView(self, trailingSwipeActionsConfigurationForRowAt: path) ?? defaultDeleteActions(for: path)
                                          : tableDelegate?.tableView(self, leadingSwipeActionsConfigurationForRowAt: path), !configuration.actions.isEmpty else { return false }
        cell.installSwipeActions(configuration, trailing: trailing, table: self, indexPath: path)
        swipedRow = path
        swipeTrailing = trailing
        tableDelegate?.tableView(self, willBeginEditingRowAt: path)
        return true
    }

    /// An editable row without a trailing configuration deletes with a "Delete" button, as
    /// UIKit's `commit editingStyle` path does.
    private func defaultDeleteActions(for path: IndexPath) -> UISwipeActionsConfiguration? {
        guard dataSource?.tableView(self, canEditRowAt: path) ?? false,
              (tableDelegate?.tableView(self, editingStyleForRowAt: path) ?? .delete) == .delete else { return nil }
        let title = tableDelegate?.tableView(self, titleForDeleteConfirmationButtonForRowAt: path) ?? "Delete"
        let delete = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, done in
            guard let self else { return }
            dataSource?.tableView(self, commit: .delete, forRowAt: path)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func handleSwipe(_ pan: UIPanGestureRecognizer) {
        if reorderingRow != nil { handleReorder(pan); return }
        guard let path = swipedRow, let cell = visibleCellsByPath[path] else { return }
        let translation = pan.translation(in: self)
        switch pan.state {
        case .began, .changed:
            cell.dragSwipe(by: translation.x)
        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: self).x
            cell.endSwipe(velocity: velocity) { [weak self] open in
                guard let self else { return }
                if !open { self.swipedRow = nil; self.tableDelegate?.tableView(self, didEndEditingRowAt: path) }
            }
        default: break
        }
    }

    /// The dragged row follows the finger within its section; the rows it passes make way,
    /// and on release the data source moves it and the rows settle.
    private func handleReorder(_ pan: UIPanGestureRecognizer) {
        guard let origin = reorderingRow, let cell = visibleCellsByPath[origin] else { return }
        let translation = pan.translation(in: self)
        switch pan.state {
        case .began, .changed:
            let count = rowCounts[origin.section] ?? 1
            guard let firstFrame = rowFrames[IndexPath(row: 0, section: origin.section)], let lastFrame = rowFrames[IndexPath(row: count - 1, section: origin.section)] else { return }
            let y = min(max(reorderStartFrame.minY + translation.y, firstFrame.minY), lastFrame.maxY - reorderStartFrame.height)
            cell.frame.origin.y = y
            // The slot whose centre the dragged row's centre has crossed.
            let centre = y + reorderStartFrame.height / 2
            var target = origin
            for row in 0..<count {
                let path = IndexPath(row: row, section: origin.section)
                guard let frame = rowFrames[path] else { continue }
                if row < origin.row, centre < frame.midY { target = path; break }
                if row > origin.row, centre > frame.midY { target = path }
            }
            guard target != reorderTarget else { return }
            reorderTarget = target
            UIView.animate(withDuration: 0.2) {
                for (path, other) in self.visibleCellsByPath where path != origin {
                    guard let frame = self.rowFrames[path] else { continue }
                    var shifted = frame
                    if origin.row < target.row, path.row > origin.row, path.row <= target.row { shifted.origin.y -= self.reorderStartFrame.height }
                    if origin.row > target.row, path.row >= target.row, path.row < origin.row { shifted.origin.y += self.reorderStartFrame.height }
                    other.frame = shifted
                }
            }
        case .ended, .cancelled, .failed:
            let target = reorderTarget ?? origin
            reorderingRow = nil
            reorderTarget = nil
            if target != origin { dataSource?.tableView(self, moveRowAt: origin, to: target) }
            var update = BatchUpdateMapping(oldCounts: (0..<(rowCounts.keys.max().map { $0 + 1 } ?? 0)).map { rowCounts[$0] ?? 0 })
            update.moves = [origin: target]
            let retained = update.retained()
            animateUpdate(retained: target == origin ? [:] : retained.mapping, replaced: [], completion: nil)
            if target == origin { UIView.animate(withDuration: batchUpdateDuration) { cell.frame = self.reorderStartFrame } }
        default: break
        }
    }

    /// Closes the open row's actions.
    open func closeSwipe(animated: Bool) {
        guard let path = swipedRow else { return }
        swipedRow = nil
        visibleCellsByPath[path]?.closeSwipe(animated: animated)
        tableDelegate?.tableView(self, didEndEditingRowAt: path)
    }

    /// A tapped action runs its handler, then the row closes.
    func perform(_ action: UIContextualAction, at path: IndexPath) {
        guard let cell = visibleCellsByPath[path] else { return }
        action.handler(action, cell) { [weak self] _ in self?.closeSwipe(animated: true) }
    }

    /// The editing control of a row: the delete control reveals the Delete button, the insert
    /// control commits an insert.
    func editingControlTapped(at path: IndexPath) {
        guard let cell = visibleCellsByPath[path] else { return }
        switch cell.editingStyle {
        case .insert:
            dataSource?.tableView(self, commit: .insert, forRowAt: path)
        case .delete:
            if swipedRow == path { closeSwipe(animated: true); return }
            closeSwipe(animated: true)
            guard let configuration = tableDelegate?.tableView(self, trailingSwipeActionsConfigurationForRowAt: path) ?? defaultDeleteActions(for: path) else { return }
            cell.installSwipeActions(configuration, trailing: true, table: self, indexPath: path)
            swipedRow = path
            swipeTrailing = true
            cell.openSwipe(animated: true)
        case .none: break
        }
    }

    private func handleTap(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.location(in: self)
        // A tap while a row's actions are open closes them (the buttons take their own taps).
        if swipedRow != nil { closeSwipe(animated: true); return }
        guard let path = indexPathForRow(at: point) else { return }
        if isEditing {
            if let cell = visibleCellsByPath[path], cell.isEditing, point.x - cell.frame.minX < UITableViewCell.editingContentInset { editingControlTapped(at: path) }
            guard allowsSelectionDuringEditing else { return }
        }
        guard allowsSelection else { return }
        if selected.contains(path), allowsMultipleSelection {
            deselectRow(at: path, animated: false)
            tableDelegate?.tableView(self, didDeselectRowAt: path)
            return
        }
        var target = path
        if let tableDelegate {
            guard let allowed = tableDelegate.tableView(self, willSelectRowAt: path) else { return }
            target = allowed
        }
        let previous = selected
        selectRow(at: target, animated: false, scrollPosition: .none)
        for old in previous where old != target { tableDelegate?.tableView(self, didDeselectRowAt: old) }
        tableDelegate?.tableView(self, didSelectRowAt: target)
    }

    // MARK: Loading

    open func reloadData() { setNeedsReload() }
    // MARK: Batch updates (Containers/BatchUpdates.swift)

    /// The update being recorded between `beginUpdates` and `endUpdates`.
    private var pendingUpdate: BatchUpdateMapping?
    private var updateDepth = 0
    /// Cells kept across an animated update, by their new index path (`cellForRow` takes them
    /// before asking the data source).
    private var retainedCells: [IndexPath: UITableViewCell] = [:]

    private func record(_ change: (inout BatchUpdateMapping) -> Void) {
        if pendingUpdate != nil {
            change(&pendingUpdate!)
        } else {
            beginUpdates()
            change(&pendingUpdate!)
            endUpdates()
        }
    }

    open func reloadRows(at indexPaths: [IndexPath], with animation: RowAnimation) { record { $0.reloadedItems.formUnion(indexPaths) } }
    open func reloadSections(_ sections: IndexSet, with animation: RowAnimation) { record { $0.reloadedSections.formUnion(sections) } }
    open func insertRows(at indexPaths: [IndexPath], with animation: RowAnimation) {
        for path in indexPaths { insertionAnimations[path] = animation }
        record { $0.insertedItems.formUnion(indexPaths) }
    }
    open func deleteRows(at indexPaths: [IndexPath], with animation: RowAnimation) {
        for path in indexPaths { deletionAnimations[path] = animation }
        record { $0.deletedItems.formUnion(indexPaths) }
    }
    /// The `RowAnimation` of each inserted (by its new path) and deleted (by its old path)
    /// row of the pending update: fade (and `automatic`) fades; left and right slide the cell
    /// in from or out to that side; top and bottom slide it from or to the row above or below;
    /// middle grows it from its centre line; none applies at once.
    var insertionAnimations: [IndexPath: RowAnimation] = [:]
    var deletionAnimations: [IndexPath: RowAnimation] = [:]
    open func moveRow(at indexPath: IndexPath, to newIndexPath: IndexPath) { record { $0.moves[indexPath] = newIndexPath } }
    open func insertSections(_ sections: IndexSet, with animation: RowAnimation) { record { $0.insertedSections.formUnion(sections) } }
    open func deleteSections(_ sections: IndexSet, with animation: RowAnimation) { record { $0.deletedSections.formUnion(sections) } }
    open func moveSection(_ section: Int, toSection newSection: Int) { record { $0.deletedSections.insert(section); $0.insertedSections.insert(newSection) } }

    open func beginUpdates() {
        if pendingUpdate == nil {
            let sections = rowCounts.keys.max().map { $0 + 1 } ?? 0
            pendingUpdate = BatchUpdateMapping(oldCounts: (0..<sections).map { rowCounts[$0] ?? 0 })
        }
        updateDepth += 1
    }

    open func endUpdates() { endUpdates(completion: nil) }

    private func endUpdates(completion: ((Bool) -> Void)?) {
        updateDepth = max(0, updateDepth - 1)
        guard updateDepth == 0, let update = pendingUpdate else { return }
        pendingUpdate = nil
        let retained = update.retained()
        animateUpdate(retained: retained.mapping, replaced: retained.reloaded, completion: completion)
    }

    open func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        beginUpdates()
        updates?()
        endUpdates(completion: completion)
    }

    /// Lays the table out for the new data keeping the cells of `retained` rows (old index path
    /// to new), which slide to their new frames; other rows' cells fade out, new rows' cells
    /// fade in; `replaced` rows (reloaded) get a new cell at once. Off screen or before the
    /// first layout the table just reloads.
    func animateUpdate(retained: [IndexPath: IndexPath], replaced: Set<IndexPath>, completion: ((Bool) -> Void)?) {
        guard window != nil, !visibleCellsByPath.isEmpty, !needsReload else {
            reloadData()
            if let completion { _ = UIKitScene.shared.schedule(after: 0) { completion(true) } }
            return
        }
        var startFrames: [IndexPath: CGRect] = [:]
        var fading: [UITableViewCell] = []
        var deletedKinds: [ObjectIdentifier: RowAnimation] = [:]
        for (oldPath, cell) in visibleCellsByPath {
            if let newPath = retained[oldPath], !replaced.contains(newPath) {
                retainedCells[newPath] = cell
                startFrames[newPath] = cell.frame
            } else {
                fading.append(cell)
                deletedKinds[ObjectIdentifier(cell)] = deletionAnimations[oldPath] ?? .fade
            }
        }
        let insertedKinds = insertionAnimations
        insertionAnimations.removeAll()
        deletionAnimations.removeAll()
        visibleCellsByPath.removeAll()
        let before = Set(fading.map { ObjectIdentifier($0) }).union(retainedCells.values.map { ObjectIdentifier($0) })
        reload()
        // Retained rows now out of view go back to the pool.
        for cell in retainedCells.values {
            cell.removeFromSuperview()
            if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
        }
        retainedCells.removeAll()
        var inserted: [(UITableViewCell, RowAnimation)] = []
        for (path, cell) in visibleCellsByPath {
            if let start = startFrames[path] {
                let target = cell.frame
                UIView.performWithoutAnimation { cell.frame = start }
                UIView.animate(withDuration: batchUpdateDuration) { cell.frame = target }
            } else if !before.contains(ObjectIdentifier(cell)) {
                inserted.append((cell, insertedKinds[path] ?? .fade))
            }
        }
        for cell in fading { bringSubviewToFront(cell) }
        // Where a row animation starts (inserts) or ends (deletes): its frame shifted off a side,
        // onto the row above or below, or squeezed to its middle line.
        func displaced(_ frame: CGRect, by kind: RowAnimation) -> CGRect {
            switch kind {
            case .left: return frame.offsetBy(dx: -frame.width, dy: 0)
            case .right: return frame.offsetBy(dx: frame.width, dy: 0)
            case .top: return frame.offsetBy(dx: 0, dy: -frame.height)
            case .bottom: return frame.offsetBy(dx: 0, dy: frame.height)
            case .middle: return CGRect(x: frame.minX, y: frame.midY, width: frame.width, height: 0)
            default: return frame
            }
        }
        let targets = inserted.map { ($0.0, $0.0.frame, $0.1) }
        UIView.performWithoutAnimation {
            for (cell, frame, kind) in targets {
                switch kind {
                case .none: break
                case .fade, .automatic: cell.alpha = 0
                default: cell.frame = displaced(frame, by: kind); cell.alpha = kind == .middle ? 1 : cell.alpha
                }
            }
        }
        UIView.animate(withDuration: batchUpdateDuration, animations: {
            for (cell, frame, kind) in targets {
                cell.alpha = 1
                if kind != .none, kind != .fade, kind != .automatic { cell.frame = frame }
            }
            for cell in fading {
                let kind = deletedKinds[ObjectIdentifier(cell)] ?? .fade
                switch kind {
                case .none: break
                case .fade, .automatic: cell.alpha = 0
                default: cell.frame = displaced(cell.frame, by: kind)
                }
            }
        }, completion: { [weak self] _ in
            guard let self else { return }
            for cell in fading {
                cell.removeFromSuperview()
                cell.alpha = 1
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
            }
            completion?(true)
        })
    }

    private func setNeedsReload() {
        pendingUpdate = nil
        updateDepth = 0
        measuredHeights.removeAll()
        needsReload = true
        setNeedsLayout()
    }

    // MARK: Geometry (measured, Docs/elements/UIKit/TableView.md)

    var isGrouped: Bool { style != .plain }
    /// The inset grouped style's cards sit 16 in.
    var cardInset: CGFloat { style == .insetGrouped ? 16 : 0 }
    static let cardCornerRadius: CGFloat = 26

    open override func layoutSubviews() {
        super.layoutSubviews()
        if needsReload { reload() } else { updateVisibleCells() }
    }

    /// Builds every row (the tables here are short; no recycling of off-screen rows yet).
    private func reload() {
        needsReload = false
        for cell in visibleCellsByPath.values {
            cell.removeFromSuperview()
            if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
        }
        visibleCellsByPath.removeAll()
        for view in headerViews.values { view.removeFromSuperview() }
        for view in footerViews.values { view.removeFromSuperview() }
        headerViews.removeAll()
        footerViews.removeAll()
        headerNaturalFrames.removeAll()
        sectionEnds.removeAll()
        rowFrames.removeAll()
        rowCounts.removeAll()
        guard let dataSource else { contentSize = .zero; return }
        // The index strip's presence first: rows built below lay out beside it.
        let titles = dataSource.sectionIndexTitles(for: self) ?? []
        sectionIndex.titles = titles
        sectionIndex.isHidden = titles.isEmpty

        var y: CGFloat = 0
        let width = bounds.width
        let rowWidth = width - 2 * cardInset
        if let header = tableHeaderView {
            header.frame = CGRect(x: 0, y: y, width: width, height: header.frame.height)
            y += header.frame.height
        }
        let sections = dataSource.numberOfSections(in: self)
        for section in 0..<sections {
            let headerTitle = dataSource.tableView(self, titleForHeaderInSection: section)
            let footerTitle = dataSource.tableView(self, titleForFooterInSection: section)
            let customHeader = tableDelegate?.tableView(self, viewForHeaderInSection: section)
            // The header: the plain style pads 22 above a titled first header; grouped sections
            // start under a 55.5 tall header (a first one) or 38 (later ones), untitled grouped
            // sections keep a 35 pt gap.
            if let customHeader {
                var height = tableDelegate?.tableView(self, heightForHeaderInSection: section) ?? Self.automaticDimension
                if height == Self.automaticDimension { height = customHeader.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height }
                customHeader.frame = CGRect(x: 0, y: y, width: width, height: height)
                addSubview(customHeader)
                headerViews[section] = customHeader
                y += height
            } else if isGrouped {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = headerTitle
                view.isHeader = true
                view.style = style
                let height: CGFloat = headerTitle == nil ? (section == 0 ? 35 : 35) : (section == 0 ? 55.5 : 38)
                view.frame = CGRect(x: 0, y: y, width: width, height: height)
                view.inset = cardInset
                addSubview(view)
                headerViews[section] = view
                y += height
            } else if let headerTitle {
                // Every titled plain header sits 22 below what precedes it (uikit/table/pinned:
                // the second section's header at 296 after rows ending at 274).
                y += sectionHeaderTopPadding == Self.automaticDimension ? 22 : sectionHeaderTopPadding
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = headerTitle
                view.isHeader = true
                view.style = style
                view.frame = CGRect(x: 0, y: y, width: width, height: 28)
                addSubview(view)
                headerViews[section] = view
                y += 28
            }
            if let header = headerViews[section] { headerNaturalFrames[section] = header.frame }
            let rows = dataSource.tableView(self, numberOfRowsInSection: section)
            for row in 0..<rows {
                let path = IndexPath(row: row, section: section)
                // A known height (the delegate's, `rowHeight`, or an estimate) lays the row out
                // without its cell, which appears when the row scrolls into view; an automatic
                // height without an estimate needs the cell now.
                var height = knownHeight(for: path)
                var cell: UITableViewCell?
                if height == nil {
                    let made = cellForRow(path, rows: rows)
                    height = made.preferredHeight(width: rowWidth)
                    cell = made
                }
                let frame = CGRect(x: cardInset, y: y, width: rowWidth, height: height!)
                rowFrames[path] = frame
                rowCounts[section] = rows
                if let cell {
                    place(cell, at: path, frame: frame)
                }
                y += height!
            }
            if let footerTitle, isGrouped {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = footerTitle
                view.isHeader = false
                view.style = style
                view.inset = cardInset
                // 4.5 above and below the label, which is 21 tall for one 13 pt line (uikit/table/grouped).
                let text = view.textLabel?.sizeThatFits(CGSize(width: rowWidth - 32, height: .greatestFiniteMagnitude)).height ?? 0
                let height = max(21, text) + 9
                view.frame = CGRect(x: 0, y: y, width: width, height: height)
                addSubview(view)
                footerViews[section] = view
                y += height
            } else if let footerTitle {
                let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
                view.textLabel?.text = footerTitle
                view.isHeader = false
                view.style = style
                view.frame = CGRect(x: 0, y: y, width: width, height: 28)
                addSubview(view)
                footerViews[section] = view
                y += 28
            }
            sectionEnds[section] = y
        }
        if let footer = tableFooterView {
            footer.frame = CGRect(x: 0, y: y, width: width, height: footer.frame.height)
            y += footer.frame.height
        }
        contentSize = CGSize(width: width, height: y)
        let totalRows = rowCounts.values.reduce(0, +)
        sectionIndex.isHidden = titles.isEmpty || totalRows < sectionIndexMinimumDisplayRowCount
        if !sectionIndex.isHidden {
            sectionIndex.table = self
            if sectionIndex.superview !== self { addSubview(sectionIndex) }
        }
        updateVisibleCells()
    }

    /// The index strip rides the visible bounds at the right edge, above everything.
    private func placeSectionIndex() {
        guard !sectionIndex.isHidden, sectionIndex.superview === self else { return }
        sectionIndex.frame = CGRect(x: bounds.width - SectionIndexView.width, y: contentOffset.y, width: SectionIndexView.width, height: bounds.height)
        bringSubviewToFront(sectionIndex)
    }

    /// Scrolls so the section the index title names starts at the top.
    func jumpToIndexTitle(_ title: String, at index: Int) {
        guard let dataSource else { return }
        let section = dataSource.tableView(self, sectionForSectionIndexTitle: title, at: index)
        guard section >= 0 else { return }
        let target = headerNaturalFrames[section]?.minY ?? rowFrames[IndexPath(row: 0, section: section)]?.minY ?? 0
        let maxOffset = max(0, contentSize.height - bounds.height)
        contentOffset = CGPoint(x: 0, y: min(max(0, target), maxOffset))
    }

    /// The header view of a section on show (a plain header pins while its section scrolls).
    open func headerView(forSection section: Int) -> UITableViewHeaderFooterView? { headerViews[section] as? UITableViewHeaderFooterView }
    open func footerView(forSection section: Int) -> UITableViewHeaderFooterView? { footerViews[section] as? UITableViewHeaderFooterView }

    /// Plain-style headers stick to the top of the visible bounds while their section is
    /// under them, and the next section's header pushes them up (uikit/table/pinned).
    private func pinHeaders() {
        guard !isGrouped else { return }
        for (section, header) in headerViews {
            guard let natural = headerNaturalFrames[section] else { continue }
            var y = max(natural.minY, contentOffset.y + contentInset.top)
            if let end = sectionEnds[section] { y = min(y, end - natural.height) }
            y = max(y, natural.minY)
            if header.frame.minY != y { header.frame = CGRect(x: natural.minX, y: y, width: natural.width, height: natural.height) }
            (header as? UITableViewHeaderFooterView)?.isPinned = y > natural.minY
            bringSubviewToFront(header)
        }
    }

    /// The rows per section, from the last reload.
    private var rowCounts: [Int: Int] = [:]
    /// Automatic heights measured from cells that appeared, replacing the estimate they were
    /// laid out with (cleared by `reloadData`).
    private var measuredHeights: [IndexPath: CGFloat] = [:]

    /// Whether the row's height is an estimate until its cell measures it.
    private func isEstimated(_ path: IndexPath) -> Bool {
        if let delegateHeight = tableDelegate?.tableView(self, heightForRowAt: path), delegateHeight != Self.automaticDimension { return false }
        if rowHeight != Self.automaticDimension { return false }
        return estimatedRowHeight > 0 && measuredHeights[path] == nil
    }

    /// The row's height when it can be known without its cell.
    private func knownHeight(for path: IndexPath) -> CGFloat? {
        if let delegateHeight = tableDelegate?.tableView(self, heightForRowAt: path), delegateHeight != Self.automaticDimension { return delegateHeight }
        if rowHeight != Self.automaticDimension { return rowHeight }
        if let measured = measuredHeights[path] { return measured }
        if estimatedRowHeight > 0 { return estimatedRowHeight }
        return nil
    }

    /// Asks the data source for the cell and marks its place in the section.
    private func cellForRow(_ path: IndexPath, rows: Int) -> UITableViewCell {
        guard let dataSource else { return UITableViewCell(style: .default, reuseIdentifier: nil) }
        let cell = retainedCells.removeValue(forKey: path) ?? dataSource.tableView(self, cellForRowAt: path)
        cell.tableStyle = style
        cell.isFirstInSection = path.row == 0
        cell.isLastInSection = path.row == rows - 1
        return cell
    }

    private func place(_ cell: UITableViewCell, at path: IndexPath, frame: CGRect) {
        cell.frame = frame
        cell.besideSectionIndex = !sectionIndex.isHidden
        // Grouped cards are the secondary grouped background (white; 28 grey in the dark).
        if isGrouped, cell.backgroundColor == .systemBackground { cell.backgroundColor = .secondarySystemGroupedBackground }
        cell.setSelected(selected.contains(path), animated: false)
        configureEditing(of: cell, at: path)
        if path != swipedRow { cell.closeSwipe(animated: false) }
        tableDelegate?.tableView(self, willDisplay: cell, forRowAt: path)
        if cell.superview !== self { addSubview(cell) }
        visibleCellsByPath[path] = cell
    }

    /// Makes the rows in view have cells and returns the cells of rows out of view to the pool
    /// (a page of rows above and below stays).
    private func updateVisibleCells() {
        let visible = bounds.insetBy(dx: 0, dy: -bounds.height / 2)
        for (path, cell) in visibleCellsByPath where !(rowFrames[path]?.intersects(visible) ?? false) {
            cell.removeFromSuperview()
            visibleCellsByPath.removeValue(forKey: path)
            if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
        }
        // Cells are made for the rows in the bounds only (UIKit makes no cell ahead; probes of
        // uikit/table/indexed), while the ones half a viewport away are kept.
        var corrected = false
        for (path, frame) in rowFrames.sorted(by: { $0.key < $1.key }) where frame.intersects(bounds) && visibleCellsByPath[path] == nil {
            let cell = cellForRow(path, rows: rowCounts[path.section] ?? path.row + 1)
            // An estimated row measures itself once its cell exists; a different height lays
            // the rows out again below (the cells made so far are kept).
            if isEstimated(path) {
                let measured = cell.preferredHeight(width: frame.width)
                measuredHeights[path] = measured
                if measured != frame.height { corrected = true }
            }
            place(cell, at: path, frame: frame)
        }
        if corrected {
            let kept = visibleCellsByPath
            visibleCellsByPath.removeAll()
            retainedCells = kept
            reload()
            for cell in retainedCells.values {
                cell.removeFromSuperview()
                if let identifier = cell.reuseIdentifier { reusePool[identifier, default: []].append(cell) }
            }
            retainedCells.removeAll()
            return
        }
        pinHeaders()
        placeSectionIndex()
    }

    /// Scrolling brings other rows into view.
    open override var contentOffset: CGPoint {
        didSet { if contentOffset != oldValue, !needsReload { setNeedsLayout() } }
    }
}

/// The header or footer of a table section: a 17 pt semibold title (plain: 16 in, 2 down in
/// 28; grouped: 32 in, 27 down in a 55.5 first header, 9.5 in a 38 pt later one) or a 13 pt
/// footer 4.5 down.
@preconcurrency @MainActor
open class UITableViewHeaderFooterView: UIView {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public let reuseIdentifier: String?
    public private(set) var textLabel: UILabel?
    public private(set) var detailTextLabel: UILabel?
    public let contentView = UIView()
    var isHeader = true {
        didSet {
            // The fonts before the first layout, so the table can measure the title.
            textLabel?.font = isHeader ? .systemFont(ofSize: 17, weight: .semibold) : .systemFont(ofSize: 13)
            textLabel?.textColor = isHeader && style == .plain ? .label : .secondaryLabel
        }
    }
    var style: UITableView.Style = .plain
    var inset: CGFloat = 0
    /// A plain header held at the visible top by scrolling (uikit/table/pinned): it draws a
    /// scrim, black at 15 % fading over 60 pt from its top, over the rows passing under it.
    var isPinned = false { didSet { if isPinned != oldValue { setNeedsDisplay() } } }

    public init(reuseIdentifier: String?) {
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        textLabel = label
        addSubview(contentView)
        contentView.addSubview(label)
    }

    public override convenience init(frame: CGRect) { self.init(reuseIdentifier: nil) }

    open func prepareForReuse() {}

    open override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = CGRect(x: inset, y: 0, width: bounds.width - 2 * inset, height: bounds.height)
        guard let label = textLabel else { return }
        if isHeader {
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            // A grouped header's title is in the secondary label colour (133 grey on the light
            // ground, 141 on black), a plain one's in the label colour.
            label.textColor = style == .plain ? .label : .secondaryLabel
            let size = label.sizeThatFits(CGSize(width: contentView.bounds.width - 32, height: .greatestFiniteMagnitude))
            let y: CGFloat = style == .plain ? 2 : (bounds.height > 40 ? 27 : 9.5)
            label.frame = CGRect(x: 16, y: y, width: size.width, height: style == .plain ? 25 : 24.5)
        } else {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            let size = label.sizeThatFits(CGSize(width: contentView.bounds.width - 32, height: .greatestFiniteMagnitude))
            label.frame = CGRect(x: 16, y: 4.5, width: size.width, height: size.height)
        }
        // Right-to-left: the title at the trailing (right) edge.
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            label.frame.origin.x = contentView.bounds.width - 16 - label.frame.width
            label.textAlignment = .right
        } else {
            label.textAlignment = .natural
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        if isPinned, isHeader, style == .plain {
            // The scrim: 0.15 at the header's top easing to nothing 60 pt down ((1 - t)^1.2,
            // sampled from the golden: 217, 230, 238, 247, 254 grey at 0, 20, 30, 45, 60 pt).
            let top = context.absoluteRect(CGRect(x: 0, y: 0, width: bounds.width, height: 60))
            let ink: RGBA = userStyle == .dark ? RGBA(r: 255, g: 255, b: 255) : RGBA(r: 0, g: 0, b: 0)
            let stops = [(0.0, 0.15), (0.25, 0.106), (0.5, 0.065), (0.75, 0.028), (1.0, 0.0)].map { DisplayGradient.Stop(location: $0.0, color: ink.multiplyingAlpha(by: $0.1)) }
            let gradient = DisplayGradient(kind: .linear(start: CGPoint(x: top.minX, y: top.minY), end: CGPoint(x: top.minX, y: top.maxY)), stops: stops)
            list.append(.fillGradient(Path(top), gradient))
        }
    }

}

/// The visual representation of a single row in a table view.
@preconcurrency @MainActor
open class UITableViewCell: UIView {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    override open var canBecomeFocused: Bool { (closestCollectionContainer as? UITableView)?.allowsFocus ?? true }
    #if _runtime(_ObjC)
    @objc public enum CellStyle: Int, Sendable { case `default` = 0, value1, value2, subtitle }
    #else
    public enum CellStyle: Int, Sendable { case `default` = 0, value1, value2, subtitle }
    #endif
    public enum AccessoryType: Int, Sendable { case none = 0, disclosureIndicator, detailDisclosureButton, checkmark, detailButton }
    public enum SelectionStyle: Int, Sendable { case none = 0, blue, gray, `default` }
    public enum SeparatorStyle: Int, Sendable { case none = 0, singleLine }
    public enum EditingStyle: Int, Sendable { case none = 0, delete, insert }

    public let style: CellStyle
    public let reuseIdentifier: String?
    public let contentView = UIView()
    public private(set) var textLabel: UILabel?
    public private(set) var detailTextLabel: UILabel?
    public private(set) var imageView: UIImageView?
    open var accessoryType: AccessoryType = .none { didSet { setNeedsLayout() } }
    open var accessoryView: UIView? { didSet { oldValue?.removeFromSuperview(); if let view = accessoryView { addSubview(view) }; setNeedsLayout() } }
    open var selectionStyle: SelectionStyle = .default
    open private(set) var isSelected = false
    open private(set) var isHighlighted = false
    open var backgroundView: UIView?
    open var selectedBackgroundView: UIView?
    open var indentationLevel = 0
    open var separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
    var tableStyle: UITableView.Style = .plain
    var isFirstInSection = false
    var isLastInSection = false

    // MARK: Editing (Containers/SwipeActions.swift)

    /// Editing mode (uikit/table/editing): the content view starts 40 in behind the control,
    /// a 22 pt circle centred at (28, 22); a reorder grip 27 wide ends 16 from the right.
    static let editingContentInset: CGFloat = 40
    static let reorderControlWidth: CGFloat = 27
    open private(set) var isEditing = false { didSet { if isEditing != oldValue { setNeedsUpdateConfiguration() } } }
    open var editingStyle: UITableViewCell.EditingStyle = .none { didSet { setNeedsLayout(); setNeedsDisplay() } }
    open var showsReorderControl = false { didSet { setNeedsLayout() } }
    open var editingAccessoryType: AccessoryType = .none
    open var shouldIndentWhileEditing = true
    var canMove = false { didSet { setNeedsLayout() } }
    var showsGrip: Bool { isEditing && canMove && showsReorderControl }
    /// The table shows a section index: the content ends before the 15 pt strip and the title
    /// 8 before the content's edge (uikit/table/indexed: a 281 wide label in a 320 row).
    var besideSectionIndex = false { didSet { if besideSectionIndex != oldValue { setNeedsLayout() } } }

    open func setEditing(_ editing: Bool, animated: Bool) {
        guard editing != isEditing else { return }
        isEditing = editing
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Swipe actions: the content slides sideways by `swipeOffset` (negative for trailing
    /// actions) and the buttons fill the room it leaves.
    private(set) var swipeOffset: CGFloat = 0
    private var swipeButtons: [SwipeActionButton] = []
    private var swipeTrailing = true
    private var swipeConfiguration: UISwipeActionsConfiguration?
    private var swipeStartOffset: CGFloat = 0
    var swipeActionsWidth: CGFloat { swipeButtons.reduce(0) { $0 + $1.preferredWidth } }
    var isSwipeOpen: Bool { swipeConfiguration != nil && abs(swipeOffset) >= swipeActionsWidth - 0.5 }

    func installSwipeActions(_ configuration: UISwipeActionsConfiguration, trailing: Bool, table: UITableView, indexPath: IndexPath) {
        if swipeConfiguration === configuration { return }
        for button in swipeButtons { button.removeFromSuperview() }
        swipeConfiguration = configuration
        swipeTrailing = trailing
        swipeButtons = configuration.actions.map { action in
            let button = SwipeActionButton(action: action)
            button.addAction(UIAction { [weak table] _ in table?.perform(action, at: indexPath) }, for: .primaryActionTriggered)
            insertSubview(button, at: 0)
            return button
        }
        swipeStartOffset = swipeOffset
        setNeedsLayout()
    }

    private var swipeTravel: CGFloat = 0

    func dragSwipe(by translation: CGFloat) {
        let width = swipeActionsWidth
        var offset = swipeStartOffset + translation
        swipeTravel = abs(offset)
        if swipeTrailing {
            offset = min(0, offset)
            if -offset > width { offset = -(width + (-offset - width) * 0.3) }
        } else {
            offset = max(0, offset)
            if offset > width { offset = width + (offset - width) * 0.3 }
        }
        swipeOffset = offset
        setNeedsLayout()
    }

    /// Settles past half the actions' width (or a flick) open, else closed; a full swipe
    /// past the row's midpoint performs the first action when the configuration allows.
    func endSwipe(velocity: CGFloat, completion: @escaping (Bool) -> Void) {
        guard let configuration = swipeConfiguration else { completion(false); return }
        let width = swipeActionsWidth
        let travel = abs(swipeOffset)
        if configuration.performsFirstActionWithFullSwipe, swipeTravel > bounds.width * 0.5, let first = configuration.actions.first, let table = superview as? UITableView, let path = table.indexPath(for: self) {
            table.perform(first, at: path)
            completion(true)
            return
        }
        let flick = swipeTrailing ? velocity < -300 : velocity > 300
        let open = travel > width / 2 || flick
        if open { openSwipe(animated: true) } else { closeSwipe(animated: true) }
        completion(open)
    }

    func openSwipe(animated: Bool) {
        let target = swipeTrailing ? -swipeActionsWidth : swipeActionsWidth
        let apply = { self.swipeOffset = target; self.swipeStartOffset = target; self.setNeedsLayout(); self.layoutIfNeeded() }
        if animated { UIView.animate(withDuration: batchUpdateDuration, animations: apply) } else { apply() }
    }

    func closeSwipe(animated: Bool) {
        guard swipeConfiguration != nil else { return }
        let buttons = swipeButtons
        let finish = {
            for button in buttons { button.removeFromSuperview() }
        }
        swipeButtons = []
        swipeConfiguration = nil
        swipeStartOffset = 0
        if animated {
            UIView.animate(withDuration: batchUpdateDuration, animations: { self.swipeOffset = 0; self.setNeedsLayout(); self.layoutIfNeeded() }, completion: { _ in finish() })
        } else {
            swipeOffset = 0
            setNeedsLayout()
            finish()
        }
    }

    #if _runtime(_ObjC)
    /// Not `required`, as UIKit's isn't, so a subclass may have only initializers of its own;
    /// `register(_:forCellReuseIdentifier:)` makes a registered class through the runtime, as
    /// UIKit does, which reaches a subclass's override.
    @objc(initWithStyle:reuseIdentifier:)
    public init(style: CellStyle, reuseIdentifier: String?) {
        self.style = style
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        setUpCell()
    }
    #else
    /// Required without the Objective-C runtime: registration makes the class through its type.
    public required init(style: CellStyle, reuseIdentifier: String?) {
        self.style = style
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
        setUpCell()
    }
    #endif

    private func setUpCell() {
        backgroundColor = .systemBackground
        addSubview(contentView)
        // The labels use the body and subheadline text styles, as UIKit's do (a wrapping
        // title's lines are 26 apart, the body style's pitch; uikit/table/selfsizing).
        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .body)
        textLabel = title
        contentView.addSubview(title)
        if style != .default {
            let detail = UILabel()
            detail.font = .preferredFont(forTextStyle: style == .subtitle ? .subheadline : .body)
            detail.textColor = .secondaryLabel
            detailTextLabel = detail
            contentView.addSubview(detail)
        }
        let image = UIImageView()
        imageView = image
        contentView.addSubview(image)
        isAccessibilityElement = false
    }

    public override convenience init(frame: CGRect) { self.init(style: .default, reuseIdentifier: nil) }

    open func prepareForReuse() {
        isSelected = false
        isHighlighted = false
        setNeedsUpdateConfiguration()
        accessoryType = .none
        accessoryView = nil
        closeSwipe(animated: false)
        isEditing = false
    }

    open func setSelected(_ selected: Bool, animated: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        setNeedsUpdateConfiguration()
        setNeedsDisplay()
    }

    open func setHighlighted(_ highlighted: Bool, animated: Bool) {
        guard isHighlighted != highlighted else { return }
        isHighlighted = highlighted
        setNeedsUpdateConfiguration()
        setNeedsDisplay()
    }

    // MARK: Configuration state (ios/representable/hostingstate)

    public typealias ConfigurationUpdateHandler = (UITableViewCell, UICellConfigurationState) -> Void

    /// The cell's state as a configuration sees it: selected, highlighted, editing, the traits.
    open var configurationState: UICellConfigurationState {
        var state = UICellConfigurationState(traitCollection: traitCollection)
        state.isSelected = isSelected
        state.isHighlighted = isHighlighted
        state.isEditing = isEditing
        return state
    }
    /// Runs after the automatic updates whenever the state changes, and before the cell first
    /// lays out; it may set the content and background configurations for the state.
    open var configurationUpdateHandler: ConfigurationUpdateHandler? { didSet { setNeedsUpdateConfiguration() } }
    open var automaticallyUpdatesContentConfiguration = true
    open var automaticallyUpdatesBackgroundConfiguration = true
    private var needsConfigurationUpdate = true

    open func setNeedsUpdateConfiguration() {
        needsConfigurationUpdate = true
        setNeedsLayout()
    }

    /// Updates the configurations for `state`: each `updated(for:)`, then the handler.
    open func updateConfiguration(using state: UICellConfigurationState) {
        if automaticallyUpdatesContentConfiguration, let configuration = contentConfiguration {
            contentConfiguration = configuration.updated(for: state)
        }
        configurationUpdateHandler?(self, state)
    }

    func updateConfigurationIfNeeded() {
        guard needsConfigurationUpdate else { return }
        needsConfigurationUpdate = false
        updateConfiguration(using: configurationState)
    }

    /// The row height UIKit gives the cell's content: 56 for a text row (the default and
    /// value1 styles), 73 for a subtitle row.
    /// The row's automatic height: the content configuration's fit for the width, at least the
    /// 56 pt default row (ios/representable/hostingcells: a one-line hosted row is 56, a row with
    /// an 80 pt minimum size 80); else the style's.
    var preferredHeight: CGFloat { preferredHeight(width: bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width) }

    /// The row's automatic height for a width (uikit/table/selfsizing): a content
    /// configuration's fit (at least 56); constrained content's compressed fitting size (a
    /// label 12 above and below gives 61 for two 15 pt lines); a default cell's wrapping text
    /// label plus the row's margins (104 for four 17 pt lines); else the style's 56 or 73.
    func preferredHeight(width: CGFloat) -> CGFloat {
        updateConfigurationIfNeeded()
        if let content = configuredContent?.view as UIView? {
            // The fit, at least 56. A list content view's fit carries the table's separator
            // (uikit/table/configured: 57, 76.5); a hosted content view's does not, so the row
            // adds the point (ios/representable/hostingcells, hostingmargins: 57, 61, 81, 91;
            // a collection cell adds nothing, hostingcollection: 56, 90, 130).
            let fitted = content.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            // A sidebar cell is as tall as its content (53 for a line; uikit/table/rest).
            let minimum: CGFloat = (content as? UIListContentView)?.isSidebar == true ? 0 : 56
            return max(minimum, fitted) + (content is any _HostedCellContentView ? 1 : 0)
        }
        if contentView.subviews.contains(where: { !$0.translatesAutoresizingMaskIntoConstraints }) {
            if bounds.width != width { frame.size.width = width }
            contentView.frame = CGRect(x: 0, y: 0, width: width, height: contentView.frame.height)
            // The row's width is required, the height what fits, as UIKit sizes cells.
            let fitted = contentView.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
            if fitted > 0 { return fitted }
        }
        if style == .default, let title = textLabel, title.numberOfLines != 1, let text = title.text, !text.isEmpty {
            let accessory = accessorySize
            let contentWidth = accessory.width > 0 ? width - (accessoryType == .checkmark ? 18.5 : 16) - accessory.width : width
            let labelWidth = contentWidth - 32 - (imageView?.image.map { $0.size.width + 16 } ?? 0)
            let text = title.sizeThatFits(CGSize(width: labelWidth, height: .greatestFiniteMagnitude)).height
            return max(56, text + 2 * Self.wrappingTextMargin)
        }
        return style == .subtitle ? 73 : 56
    }

    /// Above and below a default cell's wrapping text label (uikit/table/selfsizing: three
    /// body lines, 76.5 tall, in a 104 pt row).
    static let wrappingTextMargin: CGFloat = 13.75

    /// A content configuration makes the content view that fills the cell's content view and
    /// sizes the row (Containers/ContentConfiguration.swift).
    open var contentConfiguration: (any UIContentConfiguration)? {
        didSet {
            // A sidebar preset in a table takes the table's fonts (its margins are its own).
            if var list = contentConfiguration as? UIListContentConfiguration, list.sidebar, !list.tableMetrics, !list.listMetrics {
                list.tableMetrics = true
                contentConfiguration = list   // an assignment inside the observer does not observe again
            }
            installConfiguredContent()
        }
    }
    open var backgroundConfiguration: UIBackgroundConfiguration? {
        didSet { if let color = backgroundConfiguration?.backgroundColor { backgroundColor = color } }
    }
    var configuredContent: ConfiguredContent?

    open func defaultContentConfiguration() -> UIListContentConfiguration {
        var configuration: UIListContentConfiguration
        switch style {
        case .subtitle: configuration = .subtitleCell()
        case .value1, .value2: configuration = .valueCell()
        default: configuration = .cell()
        }
        configuration.tableMetrics = true
        return configuration
    }

    private func installConfiguredContent() {
        // A content view that supports the new configuration takes it (a hosted configuration
        // re-mounts its content); else a new one is made.
        if let contentConfiguration, let current = configuredContent?.view, current.supports(contentConfiguration) {
            current.configuration = contentConfiguration
            setNeedsLayout()
            return
        }
        configuredContent?.view.removeFromSuperview()
        configuredContent = nil
        guard let contentConfiguration else { setNeedsLayout(); return }
        let view = contentConfiguration.makeContentView()
        view.frame = contentView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(view)
        configuredContent = ConfiguredContent(view: view)
        setNeedsLayout()
    }

    /// The accessory's size: the disclosure chevron 10.5 × 14, the checkmark 19 × 18.
    private var accessorySize: CGSize {
        switch accessoryType {
        case .disclosureIndicator, .detailDisclosureButton: return CGSize(width: 10.5, height: 14)
        case .checkmark: return CGSize(width: 19, height: 18)
        case .detailButton: return CGSize(width: 22, height: 22)
        case .none: return accessoryView?.frame.size ?? .zero
        }
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        updateConfigurationIfNeeded()
        let width = bounds.width
        // The content view ends where the accessory starts (16 from the right for a chevron,
        // 18.5 for a checkmark), else spans the row. Editing hides the accessory: the content
        // starts 40 in and ends before the reorder grip (43 from the right) or at the edge.
        let accessory = isEditing ? .zero : accessorySize
        let accessoryRight: CGFloat = accessoryType == .checkmark ? 18.5 : 16
        let contentLeft: CGFloat = isEditing && shouldIndentWhileEditing ? Self.editingContentInset : 0
        let contentRight: CGFloat = showsGrip ? Self.reorderControlWidth + 16 : (besideSectionIndex ? SectionIndexView.width : 0)
        let contentWidth = accessory.width > 0 ? width - accessoryRight - accessory.width : width - contentLeft - contentRight
        contentView.frame = CGRect(x: contentLeft + swipeOffset, y: 0, width: contentWidth, height: bounds.height)
        if let accessoryView {
            accessoryView.isHidden = isEditing
            accessoryView.frame = CGRect(x: contentWidth, y: (bounds.height - accessoryView.frame.height) / 2, width: accessoryView.frame.width, height: accessoryView.frame.height)
        }
        // Swipe action buttons fill the room the content leaves, from the row's edge inward.
        if !swipeButtons.isEmpty {
            let total = swipeActionsWidth
            let revealed = abs(swipeOffset)
            var edge: CGFloat = swipeTrailing ? width : 0
            for button in swipeButtons {
                let share = total > 0 ? button.preferredWidth / total * revealed : 0
                if swipeTrailing {
                    button.frame = CGRect(x: edge - share, y: 0, width: share, height: bounds.height)
                    edge -= share
                } else {
                    button.frame = CGRect(x: edge, y: 0, width: share, height: bounds.height)
                    edge += share
                }
            }
        }
        var x: CGFloat = 16
        if let imageView, let image = imageView.image {
            imageView.frame = CGRect(x: 16, y: (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height)
            x += image.size.width + 16
        } else {
            imageView?.frame = .zero
        }
        guard let title = textLabel else { return }
        // Before a reorder grip, an accessory or the section index the title ends 8 in, else 16.
        let trailing: CGFloat = showsGrip || accessory.width > 0 || besideSectionIndex ? 8 : 16
        switch style {
        case .default:
            title.frame = CGRect(x: x, y: 0, width: contentWidth - x - trailing, height: bounds.height)
        case .subtitle:
            let titleWidth = title.intrinsicContentSize.width
            title.frame = CGRect(x: x, y: 11, width: min(titleWidth, contentWidth - x - 16), height: 24.5)
            if let detail = detailTextLabel {
                let detailWidth = detail.intrinsicContentSize.width
                detail.frame = CGRect(x: x, y: 38.5, width: min(detailWidth, contentWidth - x - 16), height: 21)
            }
        case .value1, .value2:
            let titleWidth = title.intrinsicContentSize.width
            title.frame = CGRect(x: x, y: 16, width: min(titleWidth, contentWidth - x - 16), height: 24.5)
            if let detail = detailTextLabel {
                let detailWidth = detail.intrinsicContentSize.width
                // The detail ends 16 from the row's right, or 8 before the accessory.
                let right = accessory.width > 0 ? contentWidth - 8 : contentWidth - 16
                detail.frame = CGRect(x: right - detailWidth, y: 16, width: detailWidth, height: 24.5)
                detail.textAlignment = .right
            }
        }
        mirrorForRightToLeft(contentWidth: contentWidth, accessoryWidth: accessory.width)
    }

    /// Right-to-left (uikit/table/rtl, approximate: the mirror of the left-to-right layout):
    /// the content view and accessory swap sides, the labels right-align within the content.
    private func mirrorForRightToLeft(contentWidth: CGFloat, accessoryWidth: CGFloat) {
        guard effectiveUserInterfaceLayoutDirection == .rightToLeft else { return }
        let width = bounds.width
        contentView.frame = CGRect(x: width - contentView.frame.maxX, y: 0, width: contentView.frame.width, height: contentView.frame.height)
        if let accessoryView { accessoryView.frame.origin.x = width - accessoryView.frame.maxX }
        for label in [textLabel, detailTextLabel].compactMap({ $0 }) {
            label.frame.origin.x = contentWidth - label.frame.maxX
            label.textAlignment = style == .value1 || style == .value2 ? (label === detailTextLabel ? .left : .right) : .right
        }
        if let imageView { imageView.frame.origin.x = contentWidth - imageView.frame.maxX }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        // The selection: a grey fill over the row (the default selection style).
        if isSelected || isHighlighted, selectionStyle != .none {
            let fill = UIColor.systemGray4.rgba(for: userStyle)
            if tableStyle == .insetGrouped {
                list.append(.fillPath(cardPath(rect), fill))
            } else {
                list.append(.fillRect(rect, fill))
            }
        }
        let ink = UIColor.tertiaryLabel.rgba(for: userStyle)
        let contentWidth = contentView.bounds.width
        if isEditing {
            // The editing control: a 22 pt red (delete) or green (insert) circle centred at
            // (28, 22) with a white minus or plus, and the grip: three grey lines 23 wide.
            if editingStyle != .none {
                let circle = context.absoluteRect(CGRect(x: 17, y: 11, width: 22, height: 22))
                list.append(.fillPath(Path(ellipseIn: circle), (editingStyle == .delete ? UIColor.systemRed : UIColor.systemGreen).rgba(for: userStyle)))
                let white = RGBA(r: 255, g: 255, b: 255)
                list.append(.fillRect(context.absoluteRect(CGRect(x: 22, y: 21, width: 12, height: 2)), white))
                if editingStyle == .insert { list.append(.fillRect(context.absoluteRect(CGRect(x: 27, y: 16, width: 2, height: 12)), white)) }
            }
            if showsGrip {
                let grey = UIColor.systemGray3.rgba(for: userStyle)
                let left = bounds.width - 16 - Self.reorderControlWidth + 2
                for line in 0..<3 {
                    list.append(.fillRect(context.absoluteRect(CGRect(x: left, y: (bounds.height - 15) / 2 + 2 + CGFloat(line) * 4.5, width: 23, height: 1.5)), grey))
                }
            }
        }
        // Right-to-left mirrors the accessory to the left edge, the chevron pointing left.
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        switch isEditing ? .none : accessoryType {
        case .disclosureIndicator, .detailDisclosureButton:
            // The chevron: 10.5 × 14 at the content view's right, centred; a 2 pt stroke.
            let box = context.absoluteRect(CGRect(x: rightToLeft ? bounds.width - contentWidth - 10.5 : contentWidth, y: (bounds.height - 14) / 2, width: 10.5, height: 14))
            var chevron = Path()
            if rightToLeft {
                chevron.move(to: CGPoint(x: box.maxX - 2, y: box.minY + 1.5))
                chevron.addLine(to: CGPoint(x: box.minX + 1.5, y: box.midY))
                chevron.addLine(to: CGPoint(x: box.maxX - 2, y: box.maxY - 1.5))
            } else {
                chevron.move(to: CGPoint(x: box.minX + 2, y: box.minY + 1.5))
                chevron.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.midY))
                chevron.addLine(to: CGPoint(x: box.minX + 2, y: box.maxY - 1.5))
            }
            list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round), ink))
        case .checkmark:
            let box = context.absoluteRect(CGRect(x: rightToLeft ? bounds.width - contentWidth - 19 : contentWidth, y: (bounds.height - 18) / 2, width: 19, height: 18))
            var mark = Path()
            mark.move(to: CGPoint(x: box.minX + 1.5, y: box.midY + 1))
            mark.addLine(to: CGPoint(x: box.minX + 7, y: box.maxY - 2))
            mark.addLine(to: CGPoint(x: box.maxX - 1.5, y: box.minY + 2))
            list.append(.strokePath(mark, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round), tintColor.rgba(for: userStyle)))
        default:
            break
        }
        // The separator: 1 pt at the bottom, from the content's leading inset (16) to the row's
        // right (the plain style keeps 16 on the right too); a grouped section's last row has none.
        if !(tableStyle != .plain && isLastInSection) {
            let separatorColor = UIColor.separator.rgba(for: userStyle)
            // The separator starts where the content's text does (56 after a list content symbol).
            var left = max(separatorInset.left, (configuredContent?.view as? UIListContentView)?.textLeading ?? 0)
            var right: CGFloat = tableStyle == .plain ? 16 : (accessorySize.width > 0 ? 16 : 0)
            if rightToLeft { swap(&left, &right) }
            let line = context.absoluteRect(CGRect(x: left, y: bounds.height - 1, width: bounds.width - left - right, height: 1))
            list.append(.fillRect(line, separatorColor))
        }
    }

    /// The card corners of an inset grouped row: 26 pt on the section's first row's top and its
    /// last row's bottom.
    func cardPath(_ rect: CGRect) -> Path {
        let radius = UITableView.cardCornerRadius
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: isFirstInSection ? radius : 0, bottomLeading: isLastInSection ? radius : 0,
            bottomTrailing: isLastInSection ? radius : 0, topTrailing: isFirstInSection ? radius : 0), style: .continuous)
    }

    /// Grouped rows paint their background as a card slice (the layer's background stays clear).
    open override var backgroundColor: UIColor? {
        didSet { if tableStyle != .plain { layer.backgroundColor = nil } }
    }
}

#if _runtime(_ObjC)
/// A registered cell made as UIKit makes one: `+alloc`, then `-initWithStyle:reuseIdentifier:`
/// sent to the new object, so the subclass's own override runs. Each method is looked up and
/// called with its own signature (WebAssembly checks the type of every indirect call).
@MainActor
func _makeRegisteredCell(_ type: UITableViewCell.Type, reuseIdentifier: String) -> UITableViewCell {
    typealias Alloc = @convention(c) (UnsafeRawPointer, Selector) -> UnsafeMutableRawPointer?
    typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, Int, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    let cls: AnyClass = type
    let alloc = sel_registerName("alloc")   // Swift's `#selector` cannot name +alloc
    let initialize = #selector(UITableViewCell.init(style:reuseIdentifier:))
    // The class object as an object (no bridging): its class is the metaclass, which holds `+alloc`.
    guard let metaclass = object_getClass(unsafeBitCast(cls, to: AnyObject.self)),
          let allocate = class_getMethodImplementation(metaclass, alloc),
          let initializer = class_getMethodImplementation(cls, initialize),
          let instance = unsafeBitCast(allocate, to: Alloc.self)(unsafeBitCast(cls, to: UnsafeRawPointer.self), alloc) else {
        fatalError("UITableView: cannot make a \(type) cell")
    }
    // `init` consumes the allocated object and returns the initialized one retained.
    let identifier = reuseIdentifier._bridgeToObjectiveC()
    let made = withExtendedLifetime(identifier) {
        unsafeBitCast(initializer, to: Initialize.self)(instance, initialize, UITableViewCell.CellStyle.default.rawValue,
                                                        Unmanaged.passUnretained(identifier).toOpaque())
    }
    guard let made else { fatalError("UITableView: \(type).init(style:reuseIdentifier:) returned nil") }
    return Unmanaged<UITableViewCell>.fromOpaque(made).takeRetainedValue()
}
#endif
