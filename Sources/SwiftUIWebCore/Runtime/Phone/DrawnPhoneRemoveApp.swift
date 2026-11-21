#if !os(WASI)
import Foundation
#endif
import WebFoundation   // `_PhonePrompts`; never full Foundation on wasm: it links ICU (decisions 0006, 0017)

// Remove App on the drawn iPhone's home screen (new-website#709, decided in #625): holding the
// app's icon opens iOS 27's glass menu under its name, Edit Home Screen and Remove App in red,
// the home screen left as it is behind it; Remove App asks as iOS does (Remove from Home Screen,
// Delete App or Cancel, then that deleting the app deletes its data), the icon shrinks away,
// and the app starts again as a fresh install: everything the browser kept for it is forgotten
// (`_AppSandbox`, its permission answers included) and the page loads again onto the home
// screen, the app not running until it is opened, its name marked with iOS's blue dot for a new
// app. The made-up apps take no hold, as they take no tap. Neither the home screen's edit mode
// nor App Library is drawn, so Edit Home Screen and Remove from Home Screen only close what is
// open. Checked against the iOS 27 simulator holding an app's icon on an iPhone 16.
//
// The menu and the alerts are the ones an app's own `Menu` and `.alert` draw, in a view tree of
// the phone's own over the home screen (the app's tree is not on screen there).

extension _DrawnPhoneSystem {
    /// Forgets the app's data and starts it again as a fresh install (set by the browser host,
    /// which loads the page again). Without one the phone goes back to its home screen with
    /// the app's answers forgotten and its next open a fresh launch.
    nonisolated(unsafe) public static var reinstall: (@MainActor () -> Void)?
}

extension Runtime {
    /// The drawn iPhone starts on its home screen with the app freshly installed: not running
    /// until it is opened, when `launch` starts it (new-website#709).
    public func phoneStartsFreshlyInstalled(launch: @escaping @MainActor () -> Void) {
        guard let phone = drawnPhone else { launch(); return }
        phone.startFreshlyInstalled(launch: launch)
    }
}

extension DrawnPhone {
    /// How long a press on the icon is held before the menu opens (iOS's Haptic Touch).
    static let holdDelay: Double = 0.5
    /// The icon shrinking away once Delete is pressed (651's critical spring).
    static let removeSpring = SpringModel(response: 0.3, dampingFraction: 1)
    /// The blue dot before a new app's name.
    static let newDot = RGBA(r: 0, g: 122, b: 255)

    /// The words of the menu and the alerts, in the phone's language.
    private var german: Bool { _PhonePrompts.german }
    private var quoted: String { german ? "\u{201E}\(homeName)\u{201C}" : "\u{201C}\(homeName)\u{201D}" }

    // MARK: A fresh install

    func startFreshlyInstalled(launch: @escaping @MainActor () -> Void) {
        reset()
        mode = .home
        behind = .home
        cardShown = false
        cover.hold(at: -height)
        pendingLaunch = launch
        freshlyInstalled = true
        changed()
    }

    /// The app starts the first time it is opened after a fresh install.
    func launchIfNeeded() {
        freshlyInstalled = false
        guard let launch = pendingLaunch else { return }
        pendingLaunch = nil
        launch()
    }

    // MARK: Holding the icon

    /// Whether the press on the home screen is held on the app's icon, waiting to open its menu.
    var holdIsArmed: Bool {
        guard let d = drag, d.kind == .home, !d.moved, iconMenu == nil, !removing else { return false }
        return iconRect.insetBy(dx: -8, dy: -8).contains(d.start)
    }

    /// Counts the hold on; opens the menu once it is long enough.
    func advanceHold(elapsed: Double) {
        guard holdIsArmed else { holdTime = 0; return }
        holdTime += elapsed
        guard holdTime >= Self.holdDelay else { return }
        holdTime = 0
        // The rest of this press is the menu's: lifting the finger leaves it open.
        drag?.kind = .iconMenu
        openIconMenu()
    }

    /// The glass menu under the icon's name.
    func openIconMenu() {
        let tree = _HostedTree(AnyView(Color.clear), host: runtime)
        tree.setFixedSize(CGSize(width: width, height: height))
        tree.layout(width: CGFloat(width))
        tree.onNeedsRepaint = { [weak self] in self?.runtime.requestRepaint() }
        iconMenu = tree
        menuTookPress = false
        let rows = _IconMenuRows(edit: german ? "Home-Bildschirm bearbeiten" : "Edit Home Screen", remove: german ? "App entfernen" : "Remove App") { [weak self] in
            // The menu closes first; the alert comes once it is gone.
            self?.menuHandoff = true
            Task { @MainActor in self?.askToRemove() }
        }
        let icon = iconRect
        tree.runtime.present(kind: .menu, view: AnyView(_MenuContent(content: AnyView(rows))), environment: tree.runtime.rootEnvironment,
                             anchor: nil, at: CGPoint(x: icon.minX - 3, y: icon.maxY + 26)) {}
        changed()
    }

    /// Remove App: iOS's first alert, Delete App in red.
    private func askToRemove() {
        guard let tree = iconMenu else { return }
        let actions = _RemoveAppButtons(other: german ? "Vom Home-Bildschirm entfernen" : "Remove from Home Screen",
                                        cancel: german ? "Abbrechen" : "Cancel", confirm: german ? "App l\u{00F6}schen" : "Delete App",
                                        cancelled: { [weak self] in self?.closeIconMenu() },
                                        confirmed: { [weak self] in
                                            self?.menuHandoff = true
                                            Task { @MainActor in self?.askToDelete() }
                                        })
        let message = german ? "Beim Entfernen vom Home-Bildschirm bleibt die App in deiner App-Mediathek."
                             : "Removing from Home Screen will keep the app in your App Library."
        presentAlert(in: tree, title: german ? "\(quoted) entfernen?" : "Remove \(quoted)?", message: message, actions: AnyView(actions))
    }

    /// Delete App: iOS's confirm that the app's data goes with it.
    private func askToDelete() {
        guard let tree = iconMenu else { return }
        let actions = _RemoveAppButtons(other: nil, cancel: german ? "Abbrechen" : "Cancel", confirm: german ? "L\u{00F6}schen" : "Delete",
                                        cancelled: { [weak self] in self?.closeIconMenu() },
                                        confirmed: { [weak self] in self?.removeApp() })
        let message = german ? "Wenn du diese App l\u{00F6}schst, werden auch ihre Daten gel\u{00F6}scht." : "Deleting this app will also delete its data."
        presentAlert(in: tree, title: german ? "\(quoted) l\u{00F6}schen?" : "Delete \(quoted)?", message: message, actions: AnyView(actions))
    }

    private func presentAlert(in tree: _HostedTree, title: String, message: String?, actions: AnyView) {
        menuHandoff = false
        let body = message.map { AnyView(Text(verbatim: $0)) } ?? AnyView(EmptyView())
        let view = AnyView(_AlertContent(title: Text(verbatim: title), message: body, actions: actions))
        let node = tree.runtime.present(kind: .alert, view: view, environment: tree.runtime.rootEnvironment, anchor: tree.runtime.root) {}
        // Only a button answers a system alert: presses beside it do nothing.
        node.options.interactiveDismissDisabled = true
        runtime.requestRepaint()
    }

    /// The menu or the alert is gone without removing anything.
    func closeIconMenu() {
        iconMenu = nil
        menuHandoff = false
        menuTookPress = false
        if drag?.kind == .iconMenu { drag = nil }
        changed()
    }

    /// Delete: the icon shrinks away, then the app is installed again.
    private func removeApp() {
        iconMenu = nil
        if drag?.kind == .iconMenu { drag = nil }
        removing = true
        removal.hold(at: 1)
        removal.animate(to: 0, spring: Self.removeSpring)
        changed()
    }

    /// Moves the menu, its alerts and the removal on; returns whether any still moves.
    func advanceRemoval(elapsed: Double) -> Bool {
        advanceHold(elapsed: elapsed)
        var moving = holdIsArmed
        if let tree = iconMenu {
            if tree.advance(elapsed: elapsed) { moving = true }
            // A press beside the menu closed it: the home screen is back.
            if !tree.runtime.hasPresentations, tree.runtime.leavingPresentations.isEmpty, !menuHandoff { closeIconMenu() } else { moving = true }
            runtime.requestRepaint()
        }
        if removing {
            _ = removal.step(elapsed)
            runtime.requestRepaint()
            if removal.isMoving { moving = true } else { finishRemoval() }
        }
        return moving
    }

    private func finishRemoval() {
        removing = false
        removal.hold(at: 1)
        _PhonePrompts.forgetAnswers()
        if let reinstall = _DrawnPhoneSystem.reinstall {
            reinstall()
        } else {
            freshlyInstalled = true
            changed()
        }
    }

    // MARK: The finger while the menu is up

    /// A press while the menu or an alert is up goes to them.
    func menuPointerDown(at point: CGPoint, type: PointerType, time: Double) {
        guard let tree = iconMenu else { return }
        var d = Drag(kind: .iconMenu, start: point, startTime: time, type: type)
        d.tracker.add(point, at: time)
        drag = d
        menuTookPress = true
        tree.pointerDown(at: point, type: type, time: time)
        runtime.requestRepaint()
    }

    func menuPointerMoved(to point: CGPoint, time: Double) {
        guard menuTookPress, let tree = iconMenu else { return }
        tree.pointerMoved(to: point, time: time)
        runtime.requestRepaint()
    }

    func menuPointerUp(at point: CGPoint, time: Double) {
        guard menuTookPress, let tree = iconMenu else { return }
        menuTookPress = false
        tree.pointerUp(at: point, time: time)
        runtime.requestRepaint()
    }

    func menuPointerCancelled(time: Double) {
        guard menuTookPress, let tree = iconMenu else { return }
        menuTookPress = false
        tree.pointerCancelled(time: time)
    }

    /// What the phone's tree over the home screen shows: `menu`, `alert` or `none`.
    var iconMenuDebug: String {
        guard let tree = iconMenu else { return "none" }
        return tree.runtime.presentations.map { item in item.kind.isMenu ? "menu" : "alert" }.joined(separator: ",")
    }

    // MARK: Painting

    /// The icon's scale while it is removed (1 otherwise).
    var iconScale: CGFloat { removing ? CGFloat(max(0, removal.position)) : 1 }

    /// The menu or an alert over the home screen, which stays as it is behind them (iOS 27).
    func paintIconMenu(into list: inout DisplayList) {
        guard let tree = iconMenu else { return }
        let screen = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        tree.setFixedSize(screen.size)
        tree.layout(width: screen.width)
        tree.paint(into: &list, at: .zero, scale: runtime.hostDisplayScale)
    }
}

/// The icon's menu as iOS 27 has it for an app: Edit Home Screen, then Remove App in red.
private struct _IconMenuRows: View {
    let edit: String
    let remove: String
    let removePressed: @MainActor () -> Void

    var body: some View {
        // No edit mode is drawn: the menu only closes.
        // Its icon in the label's colour, as iOS draws the system's own rows.
        Button {} label: { Label(edit, systemImage: "iphone") }.accentColor(Color.primary)
        Button(role: .destructive) { removePressed() } label: { Label(remove, systemImage: "minus.circle") }
    }
}

/// An alert's buttons as iOS's Remove App alerts have them: another choice first when there is
/// one (Remove from Home Screen, which only closes it here), the red confirm, and Cancel.
private struct _RemoveAppButtons: View {
    let other: String?
    let cancel: String
    let confirm: String
    let cancelled: @MainActor () -> Void
    let confirmed: @MainActor () -> Void

    var body: some View {
        if let other {
            Button { cancelled() } label: { Text(verbatim: other) }
            Button(role: .destructive) { confirmed() } label: { Text(verbatim: confirm) }
            Button(role: .cancel) { cancelled() } label: { Text(verbatim: cancel) }
        } else {
            Button(role: .cancel) { cancelled() } label: { Text(verbatim: cancel) }
            Button(role: .destructive) { confirmed() } label: { Text(verbatim: confirm) }
        }
    }
}
