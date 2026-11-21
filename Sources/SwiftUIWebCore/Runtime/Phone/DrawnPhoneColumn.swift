#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// The lock screen's and the pull-down's column (new-website#627, built in #643): the app's Live
// Activities on top, drawn live by its own view, then its notifications, newest first. On the
// lock screen they stack as iOS stacks them by default (the newest in full, "N more
// notifications" under it, edges behind) until a tap opens the stack into the list; the
// pull-down always shows the list. The column sits on the bottom, above the home indicator, and
// scrolls once it is taller than its room. A tap on a notification (or the banner) opens the app
// at the screen it leads to, through the app's own `didReceive`, and takes it off the list.

extension DrawnPhone {
    /// What a press on the column landed on.
    package enum CoverItem: Equatable {
        case activity(Int)
        case note(Int)
        case stack
    }

    package struct ColumnEntry {
        package var item: CoverItem
        /// In the cover's own points (its top at 0), scroll included.
        package var rect: CGRect
    }

    // Numbers from the picked look (#627, look B).
    static let columnSide: CGFloat = 8
    static let columnBottom: CGFloat = 40
    static let columnGap: CGFloat = 8
    static let lockColumnHeight: CGFloat = 470
    static let pullColumnTop: CGFloat = 214
    static let widgetRow: CGFloat = 76
    static let cardCorner: CGFloat = 16
    static let notePad = CGSize(width: 14, height: 12)
    static let noteIcon: CGFloat = 38
    static let noteLine: CGFloat = 20
    static let noteBodyLines = 4
    static let moreLine: CGFloat = 20
    static let stackEdge: CGFloat = 9

    /// The cover's top edge now (0 over the screen).
    package var coverTop: CGFloat { CGFloat(cover.position) }

    var columnWidth: CGFloat { CGFloat(width) - 2 * Self.columnSide }

    /// Whether the column shows every notification (the pull-down, or an opened stack).
    var showsFullList: Bool { coverIsPullDown || stackOpen || notes.count < 2 }

    /// The room the column has, top to bottom, in the cover's points.
    var columnRoom: (top: CGFloat, bottom: CGFloat) {
        let h = CGFloat(height)
        let widgets: CGFloat = lockWidgets.isEmpty ? 0 : Self.widgetRow
        let bottom = h - Self.columnBottom
        if coverIsPullDown { return (Self.pullColumnTop + widgets, bottom) }
        return (max(Self.pullColumnTop + widgets, bottom - Self.lockColumnHeight), bottom)
    }

    /// The column's entries and how much taller than its room it is (0 when it fits).
    package func columnLayout() -> (entries: [ColumnEntry], overflow: CGFloat) {
        let w = columnWidth
        var items: [(CoverItem, CGFloat)] = []
        for (index, activity) in activities.enumerated() {
            items.append((.activity(index), activity.tree.layout(width: w).height))
        }
        if showsFullList {
            for index in notes.indices { items.append((.note(index), noteHeight(notes[index], width: w, more: false))) }
        } else if let first = notes.first {
            items.append((.stack, noteHeight(first, width: w, more: true) + Self.stackEdge * (notes.count > 2 ? 2 : 1)))
        }
        guard !items.isEmpty else { return ([], 0) }
        let content = items.reduce(0) { $0 + $1.1 } + Self.columnGap * CGFloat(items.count - 1)
        let room = columnRoom
        let overflow = max(0, content - (room.bottom - room.top))
        var y = overflow > 0 ? room.top - CGFloat(listScroll.position) : room.bottom - content
        var entries: [ColumnEntry] = []
        for (item, itemHeight) in items {
            entries.append(ColumnEntry(item: item, rect: CGRect(x: Self.columnSide, y: y, width: w, height: itemHeight)))
            y += itemHeight + Self.columnGap
        }
        return (entries, overflow)
    }

    /// The column entry under a point on the screen.
    func coverItem(at point: CGPoint) -> CoverItem? {
        guard coverAmount > 0 else { return nil }
        let local = CGPoint(x: point.x, y: point.y - CGFloat(cover.position))
        return columnLayout().entries.first { $0.rect.contains(local) }?.item
    }

    package func columnRect(_ item: CoverItem) -> CGRect? {
        columnLayout().entries.first { $0.item == item }?.rect
    }

    // MARK: Presses on the column

    func coverPressBegan(_ item: CoverItem?, at point: CGPoint, type: PointerType, time: Double) {
        pressedItem = item
        pressScroll = listScroll.position
        columnScrolled = false
        listScroll.hold(at: listScroll.position)
        guard case .activity(let index)? = item, index < activities.count, let rect = columnRect(.activity(index)) else {
            activityTookPress = false
            return
        }
        let local = CGPoint(x: point.x - rect.minX, y: point.y - CGFloat(cover.position) - rect.minY)
        activityTookPress = activities[index].tree.pointerDown(at: local, type: type, time: time)
    }

    /// A move of a press on the column. Returns true when it should lift the lock screen
    /// instead (a move up with nothing to scroll).
    func coverPressMoved(to point: CGPoint, dx: Double, dy: Double, time: Double) -> Bool {
        let overflow = Double(columnLayout().overflow)
        if !columnScrolled, abs(dy) > Self.slop, abs(dy) > abs(dx) {
            if overflow > 0 {
                columnScrolled = true
                cancelCoverPress(keepingItem: true)
            } else if dy < 0, mode == .locked || mode == .pullDown {
                cancelCoverPress()
                return true
            }
        }
        if columnScrolled {
            let moved = pressScroll - dy
            let held = moved < 0 ? -RubberBand.offset(forOvershoot: -moved, dimension: height)
                : moved > overflow ? overflow + RubberBand.offset(forOvershoot: moved - overflow, dimension: height) : moved
            listScroll.hold(at: held)
            return false
        }
        if activityTookPress, case .activity(let index)? = pressedItem, index < activities.count, let rect = columnRect(.activity(index)) {
            activities[index].tree.pointerMoved(to: CGPoint(x: point.x - rect.minX, y: point.y - CGFloat(cover.position) - rect.minY), time: time)
        }
        return false
    }

    func coverPressEnded(at point: CGPoint, velocity: Double, moved: Bool, time: Double) {
        let item = pressedItem
        pressedItem = nil
        if columnScrolled {
            columnScrolled = false
            let overflow = Double(columnLayout().overflow)
            let target = min(overflow, max(0, listScroll.position - velocity * 0.3))
            listScroll.animate(to: target, spring: Self.coverSpring, velocity: -velocity)
            return
        }
        switch item {
        case .activity(let index)?:
            guard index < activities.count else { return }
            let activity = activities[index]
            if activityTookPress, let rect = columnRect(.activity(index)) {
                // A press on the activity's own button (Skip): the app's intent runs, the
                // phone stays locked.
                activityTookPress = false
                activity.tree.pointerUp(at: CGPoint(x: point.x - rect.minX, y: point.y - CGFloat(cover.position) - rect.minY), time: time)
            } else if !moved {
                activity.opensApp()
                openAppFromCover()
            }
        case .note(let index)?:
            guard !moved, index < notes.count else { return }
            let note = notes[index]
            openAppFromCover()
            open(note)
        case .stack?:
            guard !moved else { return }
            stackOpen = true
        case nil:
            break
        }
    }

    func cancelCoverPress(keepingItem: Bool = false) {
        if activityTookPress, case .activity(let index)? = pressedItem, index < activities.count {
            activities[index].tree.pointerCancelled(time: 0)
        }
        activityTookPress = false
        if !keepingItem { pressedItem = nil }
    }

    /// The cover slides away and the app opens, from the home screen if it was there.
    func openAppFromCover() {
        let wasHome = behind == .home || !cardShown
        behind = .app
        stackOpen = false
        cover.animate(to: -height, spring: Self.coverSpring)
        if wasHome { openApp() } else { mode = .app }
        changed()
    }

    /// The person opened a notification: it leaves the list, and the app hears of it.
    func open(_ note: Note) {
        notes.removeAll { $0.identifier == note.identifier }
        note.onOpen()
        changed()
    }

    // MARK: What arrives

    /// A notification arrives: on top of the list, as a banner over the app or the home screen,
    /// and a dark screen wakes to its lock screen.
    func receive(_ note: Note, banner: Bool, list: Bool) {
        if list {
            notes.removeAll { $0.identifier == note.identifier }
            notes.insert(note, at: 0)
            if listScroll.position != 0 { listScroll.hold(at: 0) }
        }
        switch mode {
        case .off:
            if list { wakeUp() }
        case .app, .home:
            if banner { showBanner(note) }
        case .locked, .pullDown:
            break
        }
        changed()
    }

    func withdraw(_ identifiers: [String]) {
        notes.removeAll { identifiers.contains($0.identifier) }
        if let shown = bannerNote, identifiers.contains(shown.identifier), bannerShown { hideBanner(atOnce: false) }
        if notes.count < 2 { stackOpen = false }
        changed()
    }

    func withdrawAll() {
        notes.removeAll()
        if bannerNote != nil, bannerShown { hideBanner(atOnce: false) }
        stackOpen = false
        changed()
    }

    func startActivity(id: String, view: AnyView, opensApp: @escaping @MainActor () -> Void) {
        endActivity(id: id)
        let tree = _HostedTree(view, host: runtime)
        tree.onNeedsRepaint = { [weak self] in
            guard let self, self.coverAmount > 0 else { return }
            self.runtime.requestRepaint()
        }
        activities.append(LiveActivity(id: id, tree: tree, opensApp: opensApp))
        changed()
    }

    func updateActivity(id: String, view: AnyView) {
        activities.first { $0.id == id }?.tree.update(view)
    }

    func endActivity(id: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if case .activity? = pressedItem { cancelCoverPress() }
        activities.remove(at: index)
        changed()
    }

    func setLockScreenWidgets(_ trees: [_HostedTree]) {
        lockWidgets = trees
        for tree in trees {
            tree.onNeedsRepaint = { [weak self] in
                guard let self, self.coverAmount > 0 else { return }
                self.runtime.requestRepaint()
            }
        }
        changed()
    }

    // MARK: A notification's card

    /// The card's height: the title line, the body up to four lines, "N more notifications".
    func noteHeight(_ note: Note, width: CGFloat, more: Bool) -> CGFloat {
        let lines = noteBodyLayout(note, width: width).lines.count
        return 2 * Self.notePad.height + Self.noteLine + CGFloat(lines) * Self.noteLine + (more ? Self.moreLine : 0)
    }

    var noteTextLeft: CGFloat { Self.notePad.width + Self.noteIcon + 10 }

    func noteBodyLayout(_ note: Note, width: CGFloat) -> TextLayout {
        let text = note.subtitle.isEmpty ? note.body : note.subtitle + "\n" + note.body
        guard !text.isEmpty else { return TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: []) }
        let font = phoneFont(size: 15, weight: .regular)
        return runtime.layoutText([StyledRun(text, font: font)], options: TextLayoutOptions(lineLimit: Self.noteBodyLines),
                                  width: width - noteTextLeft - Self.notePad.width)
    }

    /// When it came: "now", "26m ago", or its time.
    func whenText(_ date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        return "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
    }

    func phoneFont(size: CGFloat, weight: Font.Weight) -> ResolvedFont {
        Font.system(size: size, weight: weight).resolve(profile: runtime.rootEnvironment.platformProfile)
    }
}
