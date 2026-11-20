// The presentation layer: sheets, popovers, alerts and menus are nodes owned by the runtime,
// laid out over the window after the main tree, painted last and hit-tested first
// (Docs/elements/Presentation.md).

/// A presented panel and its content, positioned relative to the window (and an anchor node for
/// popovers and menus).
@MainActor
package final class PresentationNode: ViewNode, _FrameSubscriber, _StartsOnScreen {
    package let kind: _PresentationKind
    package private(set) var content: TypedNode<AnyView>!
    package weak var anchor: ViewNode?
    /// Where a menu without an anchor node opens (context menus: the pointer).
    package let anchorPoint: CGPoint?
    /// Resets the presenting binding; runs `onDismiss`.
    package let onDismissRequested: @MainActor () -> Void
    /// The element focused when the presentation opened, focused again when it closes.
    package var focusToRestore: (identifier: Int, keyboard: Bool)?
    package private(set) var panel: CGRect = .zero
    package private(set) var contentFrame: CGRect = .zero
    /// The menu row the arrow keys highlighted (an index into `interactiveNodes`).
    package private(set) var highlightedIndex: Int?

    /// Hover over a menu: the row under `point` (window coordinates) is highlighted, none when
    /// the pointer is elsewhere. Returns whether the highlight changed.
    @discardableResult
    package func highlightRow(at point: CGPoint?) -> Bool {
        guard kind.isMenu else { return false }
        var index: Int?
        if let point, panel.contains(point) {
            index = interactiveNodes.firstIndex { $0.frameInRoot.contains(point) }
        }
        guard index != highlightedIndex else { return false }
        highlightedIndex = index
        return true
    }
    private var arrow: (edge: Edge, tip: CGPoint)?

    package init(runtime: Runtime, kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?,
                 anchorPoint: CGPoint? = nil, onDismissRequested: @escaping @MainActor () -> Void) {
        self.kind = kind
        self.anchor = anchor
        self.anchorPoint = anchorPoint
        self.onDismissRequested = onDismissRequested
        super.init(parent: runtime.root, runtime: runtime, environment: environment)
        var contentEnvironment = environment
        contentEnvironment.dismiss = DismissAction { [weak self] in self?.dismiss() }
        contentEnvironment.isPresented = true
        content = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: contentEnvironment))
        if preferredColorScheme != nil { applyPreferredColorScheme() }
        // A sheet presented once its presenter is on screen slides up; one there from the first
        // frame (a scene restored, a fixture) is simply there.
        slidesIn = kind == .sheet && environment.platformProfile.isIOS && anchor?.hasBeenPlaced == true
        // An iOS alert, confirmation dialog or menu presented once the app is on screen comes
        // in with the iPhone's motion; one there from the first frame is simply there.
        popsIn = pops && anchor?.hasBeenPlaced == true
    }

    // MARK: iOS alerts, dialogs and menus coming and going (new-website#649)

    /// Whether this presentation comes and goes with the iPhone's motion: an iOS alert (fades in
    /// from 1.2 times its size, fades out), confirmation dialog (grows out of and back into its
    /// arrow's tip) or menu (glass growing out of and back into its button).
    package var pops: Bool {
        guard environment.platformProfile.isIOS else { return false }
        switch kind {
        case .alert: return true
        case .dialog: return metrics.dialogsArePopovers
        case .menu: return metrics.menusAreGlassPanels
        default: return false
        }
    }

    /// How far in the presentation is (1 shown, 0 gone), per channel: one for an alert or a
    /// dialog; a menu's morph has three, its width and horizontal centre, its height, and its
    /// vertical centre, each on its own spring.
    package private(set) var pop: [Motion] = []
    private var popsIn = false
    private var popRunning = false
    private var popClock: Double?
    private var popBegan = 0.0
    /// A menu's button, where its glass grows from and shrinks back to.
    package private(set) var popSource: CGRect = .zero

    /// The springs iOS 27 runs, read from Core Animation in the simulator (a probe app reading
    /// the layers' own animations and presentation frames, swipe-harness/overlay-probe-649):
    /// each with the speed it starts at, in channel units a second.
    package static func popSprings(kind: _PresentationKind, entering: Bool) -> [(SpringModel, Double)] {
        switch kind {
        case .alert:
            // UIKit's alert transition: mass 1, stiffness 522.35, damping 45.71 (critically
            // damped), both ways.
            return [(SpringModel(mass: 1, stiffness: 522.3503, damping: 45.71), 0)]
        case .dialog:
            // The popover's transform and opacity: in on stiffness 331.90, damping 29.149; out on
            // 283.97, 28.648.
            return [entering ? (SpringModel(mass: 1, stiffness: 331.9007, damping: 29.149), 0)
                             : (SpringModel(mass: 1, stiffness: 283.9735, damping: 28.6476), 0)]
        default:
            // The menu's morph, fitted to its presentation frame every display frame: opening,
            // the width and horizontal centre on omega 18, zeta 0.74 from 4/s, the height on
            // omega 16.8, zeta 0.78 from 10/s, the vertical centre on a bouncier omega 20,
            // zeta 0.54 from 14/s (it dips past its place and settles back); closing, all on
            // UIKit's default spring (0.5 s, bounce 0.2).
            if entering {
                return [(SpringModel(omega: 18, zeta: 0.74), 4), (SpringModel(omega: 16.8, zeta: 0.78), 10), (SpringModel(omega: 20, zeta: 0.54), 14)]
            }
            let close = SpringModel(duration: 0.5, bounce: 0.2)
            return [(close, 0), (close, 0), (close, 0)]
        }
    }

    private func runPop(entering: Bool) {
        let springs = Self.popSprings(kind: kind, entering: entering)
        if pop.count != springs.count {
            pop = springs.map { _ in Motion(position: entering ? 0 : 1, restDistance: 0.0005, restSpeed: 0.01) }
        }
        for index in pop.indices {
            let (spring, speed) = springs[index]
            pop[index].animate(to: entering ? 1 : 0, spring: spring, velocity: entering ? speed : -speed)
        }
        if !popRunning {
            popRunning = true
            popClock = nil
            popBegan = runtime.animationClock
            runtime.paintAnimations += 1
            runtime.subscribeFrames(self)
        }
        runtime.requestRepaint()
    }

    private func stopPopFrames() {
        guard popRunning else { return }
        popRunning = false
        runtime.paintAnimations -= 1
        if !slideRunning { runtime.unsubscribeFrames(self) }
    }

    private func popFinished() {
        stopPopFrames()
        if isLeaving { runtime.finishLeaving(self) }
        runtime.requestRepaint()
    }

    /// The main channel's progress (1 when nothing animates).
    package var popProgress: Double { pop.first?.position ?? 1 }

    // MARK: The slide of an iOS sheet

    /// How far below its place the panel is drawn (points). An iOS sheet slides up from below
    /// the window when presented, follows a finger dragging it down, and slides off when
    /// dismissed, all on UIKit's navigation spring (`SpringModel.navigation`, which matches a
    /// system sheet in the simulator, new-website#262) and from the speed the finger left with.
    package private(set) var slide = Motion(position: 0)
    /// The slide waits for the first layout, which tells it how far below the window starts.
    private var slidesIn = false
    /// The animation clock at the last frame of the slide; nil before its first frame is shown.
    private var slideClock: Double?
    private var slideRunning = false
    private var slideBegan = 0.0
    /// Laid out at least once (a sheet never shown is removed at once).
    package private(set) var hasLaidOut = false
    /// Dismissed, sliding off: no longer hit, unmounted at the bottom.
    package private(set) var isLeaving = false

    /// Whether this presentation slides (iOS sheets and covers) and follows a dragging finger
    /// (sheets only: a cover is not dragged away, nor a sheet with `interactiveDismissDisabled`).
    package var slides: Bool { kind == .sheet && environment.platformProfile.isIOS }
    package var dragsToDismiss: Bool { slides && !options.fullScreen && !options.interactiveDismissDisabled && !isLeaving }

    /// The distance from the panel's place to just below the window.
    package var slideDistance: CGFloat { max(1, runtime.layoutSize.height - panel.minY) }

    /// How much of the presentation is in (1 at its place, 0 below the window): the dim follows.
    package var slideProgress: Double { min(1, max(0, 1 - slide.position / Double(slideDistance))) }

    private func runSlide(to target: Double, velocity: Double? = nil) {
        slide.animate(to: target, spring: .navigation, velocity: velocity)
        guard slide.isMoving else { slideFinished(); return }
        if !slideRunning {
            slideRunning = true
            slideClock = nil
            slideBegan = runtime.animationClock
            runtime.paintAnimations += 1
            runtime.subscribeFrames(self)
        }
        runtime.requestRepaint()
    }

    private func stopSlideFrames() {
        guard slideRunning else { return }
        slideRunning = false
        runtime.paintAnimations -= 1
        if !popRunning { runtime.unsubscribeFrames(self) }
    }

    private func slideFinished() {
        stopSlideFrames()
        if isLeaving { runtime.finishLeaving(self) }
        runtime.requestRepaint()
    }

    /// Each frame steps the slide by the real time since the last one, from when its first
    /// frame was shown (`startOnScreen`): a slow first frame (laying out the sheet's content)
    /// does not eat into it.
    package func frameDidAdvance() {
        let now = runtime.animationClock
        if slideRunning {
            let last = slideClock ?? slideBegan
            slideClock = now
            if !slide.step(now - last) { slideFinished() } else { runtime.requestRepaint() }
        }
        if popRunning {
            let last = popClock ?? popBegan
            popClock = now
            var moving = false
            for index in pop.indices where pop[index].step(now - last) { moving = true }
            if !moving { popFinished() } else { runtime.requestRepaint() }
        }
    }

    /// A slide or pop begun in this frame starts when the frame is shown (`Runtime.beginAnimationsOnScreen`).
    package func startOnScreen(now: Double, lateness: Double) {
        if slideRunning, slideClock == nil, slideBegan == now { slideBegan += lateness }
        if popRunning, popClock == nil, popBegan == now { popBegan += lateness }
    }

    /// A finger dragging the sheet: `offset` points below its place (none above it).
    package func dragSlide(to offset: Double, velocity: Double) {
        if slideRunning { stopSlideFrames() }
        slide.hold(at: max(0, offset), velocity: velocity)
        runtime.requestRepaint()
    }

    /// The finger lifted at `velocity` (points per second, down positive): the sheet goes when
    /// where it would coast to (UIKit's projection) is past half its height, else springs back.
    package func endDragSlide(velocity: Double) {
        let projected = slide.position + DecayModel.normal.projectedOffset(velocity: velocity)
        if projected > Double(slideDistance) / 2 {
            slide.hold(at: slide.position, velocity: velocity)
            dismiss()
        } else {
            runSlide(to: 0, velocity: velocity)
        }
    }

    /// Starts sliding off (the runtime moved it to its leaving list).
    package func beginLeaving() {
        isLeaving = true
        if pops { runPop(entering: false) } else { runSlide(to: Double(slideDistance)) }
    }

    package var isModal: Bool {
        switch kind {
        case .sheet, .alert, .dialog: return true
        case .popover, .menu, .submenu, .window: return false
        }
    }

    /// A sheet's options, told by the `presentationDetents` and `presentationDragIndicator`
    /// modifiers inside its content (`PresentationOptionsNode`).
    package struct Options {
        package var detents: Set<PresentationDetent> = [.large]
        package var dragIndicator: Visibility = .automatic
        package var interactiveDismissDisabled = false
        /// `fullScreenCover`: the content fills the window, undimmed, with no card.
        package var fullScreen = false
        /// `presentationBackground`: the card's (a cover's window's) fill instead of the system
        /// background; a clear style paints nothing.
        package var background: AnyShapeStyle?
    }
    package var options = Options()

    /// The platform's metrics, read explicitly: presentations lay out and paint outside a node's
    /// own profile selection.
    private var metrics: PlatformMetricsTable { environment.platformProfile.metrics }

    /// The frame the platform's window for this presentation would have: the panel, or a
    /// popover's panel plus its window margin (macOS 27; the harness records the windows).
    package var windowFrame: CGRect {
        if case .popover = kind, metrics.sheetsCentred { return panel.insetBy(dx: -metrics.popoverWindowMargin, dy: -metrics.popoverWindowMargin) }
        return panel
    }

    /// iOS: the medium detent when it is the only one offered (`sheetsFillWindow`).
    private var mediumDetent: Bool { options.detents.contains(.medium) && !options.detents.contains(.large) }

    /// Secondary windows: the title bar above the content and the close button in it.
    package static let windowTitleBarHeight: CGFloat = 28
    package static let windowCornerRadius: CGFloat = 10
    package static let windowCascade: CGFloat = 24
    package var closeButtonFrame: CGRect {
        CGRect(x: panel.minX + 13, y: panel.minY + (Self.windowTitleBarHeight - 12) / 2, width: 12, height: 12)
    }

    /// A secondary window's scene options (sw-windows): where it opens, whether its corner
    /// resizes it, whether it has a title bar.
    package struct WindowOptions {
        package var defaultPosition: UnitPoint?
        package var resizable = true
        package var hidesTitleBar = false
    }
    package var windowOptions = WindowOptions()
    /// The title bar's height for this window (none when hidden; the lights still show).
    package var titleBarHeight: CGFloat { windowOptions.hidesTitleBar ? 0 : Self.windowTitleBarHeight }
    /// Where the user dragged the window to, and the size its corner was dragged to.
    package var windowOrigin: CGPoint?
    package var windowSize: CGSize?
    /// A window the host shows as a real window of its own (`Runtime.realWindowHost`): its
    /// frame is not clamped to the main window and the main list does not paint it.
    package var isHostedWindow = false
    /// The 16 pt square at the bottom-trailing corner that resizes a resizable window.
    package var resizeGripFrame: CGRect { CGRect(x: panel.maxX - 16, y: panel.maxY - 16, width: 16, height: 16) }
    /// The title bar's draggable part (beside the lights), or the top 16 pt without a bar.
    package var dragBarFrame: CGRect {
        let height = windowOptions.hidesTitleBar ? 16 : Self.windowTitleBarHeight
        return CGRect(x: panel.minX + 72, y: panel.minY, width: max(0, panel.width - 72), height: height)
    }

    /// Removes the presentation and resets its binding.
    package func dismiss() {
        runtime.remove(presentation: self)
        onDismissRequested()
    }

    package func update(view: AnyView) {
        content.update(view: view, environment: content.environment, force: false)
    }

    /// `preferredColorScheme` inside the presentation: the presentation (its panel and content)
    /// takes the scheme on its own, the window keeps its appearance (sw-dark, 2026-10-11).
    package var preferredColorScheme: ColorScheme? {
        didSet { if preferredColorScheme != oldValue { applyPreferredColorScheme() } }
    }

    // MARK: Sheet toolbars (sw-toolbar)

    /// `toolbar` modifiers inside the presentation: a macOS sheet (or a window) shows their
    /// items in a bar of its own across its top (unmeasured: the bar is the window toolbar's
    /// 52 pt row, the sheet's panel grows by it).
    package private(set) var toolbarSources: [ToolbarSource] = []
    package private(set) var toolbarBar: ToolbarChromeNode?

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

    private var toolbarItems: [_ToolbarItemData] { toolbarSources.filter { $0.node?.isMounted == true }.flatMap(\.items) }

    /// The bar's height when the presentation has one: a sheet or window with toolbar items.
    private var toolbarHeight: CGFloat {
        guard kind == .sheet || kind.isWindow, !metrics.sheetsFillWindow, !toolbarItems.isEmpty else { return 0 }
        return Runtime.toolbarHeight
    }

    /// Builds or drops the bar and lays it out across the panel's top (below a window's title bar).
    private func layoutToolbar(top: CGFloat) {
        let items = toolbarItems
        guard !items.isEmpty, toolbarHeight > 0 else {
            toolbarBar?.unmount()
            toolbarBar = nil
            return
        }
        let view = AnyView(_ToolbarBarView(items: items, title: nil, search: nil, scopes: nil))
        if let toolbarBar {
            toolbarBar.update(view: view, environment: environment)
        } else {
            toolbarBar = ToolbarChromeNode(runtime: runtime, view: view, environment: environment)
        }
        toolbarBar?.layout(in: CGSize(width: panel.width, height: Runtime.toolbarHeight))
        toolbarBar?.frame.origin = CGPoint(x: panel.minX, y: panel.minY + top)
    }

    /// Moves the presentation and its content to the preferred scheme (the modifier may tell
    /// it while the content is still being built: `init` applies it afterwards), or to the
    /// root's when that moved under an open presentation (Ember's onboarding cover picks Dark
    /// and shows it at once, decision 0021).
    package func applyPreferredColorScheme() {
        guard let content else { return }
        let scheme = preferredColorScheme ?? runtime.rootEnvironment.colorScheme
        guard scheme != environment.colorScheme else { return }
        environment.colorScheme = scheme
        var contentEnvironment = content.environment
        contentEnvironment.colorScheme = scheme
        content.update(view: content.view, environment: contentEnvironment, force: true)
        runtime.requestLayout(invalidatingSizes: true)
    }

    private var target: ViewNode? { content.layoutChildren.first }

    // MARK: Layout

    package func layout(in window: CGSize) {
        guard let target else { return }
        defer {
            hasLaidOut = true
            if popsIn {
                popsIn = false
                runPop(entering: true)
            }
            if slidesIn {
                slidesIn = false
                slide.hold(at: Double(slideDistance))
                runSlide(to: 0)
            }
        }
        isHostedWindow = kind.isWindow && runtime.realWindowHost != nil
        let m = metrics
        // macOS 27 sheets, alerts and popovers are windows the size of their content (which pads
        // itself); menus pad nothing either.
        var padsNothing = kind.isMenu
        if m.sheetsCentred, !environment.platformProfile.isIOS {
            switch kind {
            case .sheet, .alert, .dialog, .popover: padsNothing = true
            default: break
            }
        }
        let padding: CGFloat = padsNothing ? 0 : PlatformMetrics.presentationPadding
        switch kind {
        case .sheet where options.fullScreen:
            // A full-screen cover: the window is the panel; the content is laid out in the
            // window's safe area as the root view is (a scroll view or `ignoresSafeArea` reaching
            // under the status bar and the home indicator).
            panel = CGRect(origin: .zero, size: window)
            arrow = nil
            runtime.root.place(target, in: panel, insets: runtime.safeAreaInsets)
            contentFrame = target.frame
            return
        case .sheet where m.sheetsFillWindow:
            // iOS: the large detent's card from `sheetTopInset` to the bottom, or from the
            // window's safe top where that is lower (an iPhone 16 on iOS 27: the card's top at
            // 59, the status bar's depth), the medium detent's card floating in from the sides
            // and the bottom. The card has no unsafe region above it; at the bottom the content
            // keeps clear of the home indicator unless it extends into it, as in the window.
            let safe = runtime.safeAreaInsets
            if mediumDetent {
                let height = (window.height * m.sheetMediumHeightFraction).rounded()
                panel = CGRect(x: m.sheetMediumSideInset, y: window.height - height, width: window.width - 2 * m.sheetMediumSideInset, height: height - m.sheetMediumBottomInset)
            } else {
                let top = max(m.sheetTopInset, safe.top)
                panel = CGRect(x: 0, y: top, width: window.width, height: window.height - top)
            }
            arrow = nil
            let insets = EdgeInsets(top: 0, leading: max(0, safe.leading - panel.minX),
                                    bottom: max(0, panel.maxY - (window.height - safe.bottom)),
                                    trailing: max(0, panel.maxX - (window.width - safe.trailing)))
            runtime.root.place(target, in: panel, insets: insets)
            contentFrame = target.frame
            return
        case .dialog where m.dialogsArePopovers:
            // iOS: a panel of `dialogWidth` centred on its source and floating above it, an arrow
            // pointing down at the source (below it when there is no room above); iOS 27 centres
            // the panel on the source itself, no arrow, kept inside the window.
            let size = target.sizeThatFits(ProposedViewSize(width: m.dialogWidth, height: nil))
            let source = anchor?.frameInRoot ?? CGRect(x: window.width / 2, y: window.height / 2, width: 0, height: 0)
            let x = min(max(0, (source.midX - size.width / 2).rounded(.down)), max(0, window.width - size.width))
            if m.dialogCentredOnSource {
                (panel, arrow) = Self.popoverPlacement(size: size, source: source, window: window, safe: runtime.safeAreaInsets, metrics: m)
                contentFrame = panel
                target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(size), by: runtime.root)
                return
            }
            let above = source.minY - m.dialogSourceGap - m.dialogArrowHeight - size.height
            if above >= 0 {
                panel = CGRect(x: x, y: above, width: size.width, height: size.height)
                arrow = (.bottom, CGPoint(x: source.midX, y: source.minY - m.dialogSourceGap))
            } else {
                panel = CGRect(x: x, y: source.maxY + m.dialogSourceGap + m.dialogArrowHeight, width: size.width, height: size.height)
                arrow = (.top, CGPoint(x: source.midX, y: source.maxY + m.dialogSourceGap))
            }
            contentFrame = panel
            target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(size), by: runtime.root)
            return
        case .sheet:
            // The content's ideal size, limited to the window less the margins (a taller content is
            // proposed the limit, so a ScrollView inside scrolls); a toolbar inside adds its bar
            // across the top.
            let bar = toolbarHeight
            let limit = ProposedViewSize(width: window.width - 2 * PlatformMetrics.sheetMargin - 2 * padding, height: nil)
            var size = target.sizeThatFits(limit)
            let maximumHeight = max(0, window.height - 2 * PlatformMetrics.sheetMargin - 2 * padding - bar)
            if size.height > maximumHeight { size = target.sizeThatFits(ProposedViewSize(width: limit.width, height: maximumHeight)); size.height = min(size.height, maximumHeight) }
            if m.sheetsCentred {
                // macOS 27 (presentation/mac-sheet): the sheet window is the content's size in
                // whole points, centred in the window as AppKit rounds (x up at a half, y from the
                // bottom), no padding of its own.
                let width = (size.width + 2 * padding).rounded(.up), height = (size.height + 2 * padding + bar).rounded(.up)
                let x = ((window.width - width) / 2).rounded(.toNearestOrAwayFromZero)
                let y = window.height - height - ((window.height - height) / 2).rounded(.toNearestOrAwayFromZero)
                panel = CGRect(x: x, y: y, width: width, height: height)
            } else {
                panel = CGRect(x: (window.width - size.width) / 2 - padding, y: 0, width: size.width + 2 * padding, height: size.height + 2 * padding + bar)
            }
            arrow = nil
            if bar > 0 {
                layoutToolbar(top: 0)
                contentFrame = CGRect(x: panel.minX + padding, y: panel.minY + bar + padding, width: size.width, height: size.height)
                target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
                return
            }
            layoutToolbar(top: 0)
        case .alert, .dialog:
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            if m.sheetsCentred {
                // macOS 27 (presentation/mac-alert): the alert window centred with AppKit's rounding.
                let height = size.height.rounded(.up), width = size.width.rounded(.up)
                let x = ((window.width - width) / 2).rounded(.toNearestOrAwayFromZero)
                let y = window.height - height - ((window.height - height) / 2).rounded(.toNearestOrAwayFromZero)
                panel = CGRect(x: x, y: y, width: width, height: height)
            } else {
                panel = CGRect(x: (window.width - size.width) / 2, y: (window.height - size.height) / 2, width: size.width, height: size.height)
            }
            arrow = nil
        case .popover(let edge, let attachment):
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let width = size.width + 2 * padding, height = size.height + 2 * padding
            let bounds = anchor?.frameInRoot ?? CGRect(x: window.width / 2, y: window.height / 2, width: 0, height: 0)
            // The attachment anchor: the view's bounds, a rect in them, or a point of them.
            let source: CGRect
            switch attachment {
            case .rect(.bounds): source = bounds
            case .rect(.rect(let rect)): source = rect.offsetBy(dx: bounds.minX, dy: bounds.minY)
            case .point(let unit): source = CGRect(x: bounds.minX + unit.x * bounds.width, y: bounds.minY + unit.y * bounds.height, width: 0, height: 0)
            }
            let gap = PlatformMetrics.popoverArrowHeight
            var origin: CGPoint
            if m.sheetsCentred {
                // macOS 27 (presentation/mac-popover): the popover window is the content plus a
                // 15 pt margin all round (the arrow lives in it), its edge on the source's — the
                // default `.top` arrow edge puts it above the source, `.bottom` below — centred
                // on the source at whole points.
                let margin = m.popoverWindowMargin
                let panelWidth = size.width.rounded(.up), panelHeight = size.height.rounded(.up)
                switch edge {
                case .top: origin = CGPoint(x: (source.midX - panelWidth / 2).rounded(), y: source.minY - margin - panelHeight)
                case .bottom: origin = CGPoint(x: (source.midX - panelWidth / 2).rounded(), y: source.maxY + margin)
                case .leading: origin = CGPoint(x: source.minX - margin - panelWidth, y: (source.midY - panelHeight / 2).rounded())
                case .trailing: origin = CGPoint(x: source.maxX + margin, y: (source.midY - panelHeight / 2).rounded())
                }
                origin.x = min(max(origin.x, margin), max(margin, window.width - panelWidth - margin))
                origin.y = min(max(origin.y, margin), max(margin, window.height - panelHeight - margin))
                panel = CGRect(origin: origin, size: CGSize(width: panelWidth, height: panelHeight))
                let tip: CGPoint
                switch edge {
                case .top: tip = CGPoint(x: source.midX, y: panel.maxY + gap)
                case .bottom: tip = CGPoint(x: source.midX, y: panel.minY - gap)
                case .leading: tip = CGPoint(x: panel.maxX + gap, y: source.midY)
                case .trailing: tip = CGPoint(x: panel.minX - gap, y: source.midY)
                }
                // The arrow points away from the panel toward the source: its edge is the opposite one.
                let arrowEdge: Edge = edge == .top ? .bottom : edge == .bottom ? .top : edge == .leading ? .trailing : .leading
                arrow = (arrowEdge, tip)
                contentFrame = panel
                target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
                return
            }
            switch edge {
            case .top: origin = CGPoint(x: source.midX - width / 2, y: source.maxY + gap)
            case .bottom: origin = CGPoint(x: source.midX - width / 2, y: source.minY - gap - height)
            case .leading: origin = CGPoint(x: source.maxX + gap, y: source.midY - height / 2)
            case .trailing: origin = CGPoint(x: source.minX - gap - width, y: source.midY - height / 2)
            }
            origin.x = min(max(origin.x, PlatformMetrics.sheetMargin), max(PlatformMetrics.sheetMargin, window.width - width - PlatformMetrics.sheetMargin)).rounded()
            origin.y = min(max(origin.y, PlatformMetrics.sheetMargin), max(PlatformMetrics.sheetMargin, window.height - height - PlatformMetrics.sheetMargin)).rounded()
            panel = CGRect(origin: origin, size: CGSize(width: width, height: height))
            let tip: CGPoint
            switch edge {
            case .top: tip = CGPoint(x: source.midX, y: source.maxY)
            case .bottom: tip = CGPoint(x: source.midX, y: source.minY)
            case .leading: tip = CGPoint(x: source.maxX, y: source.midY)
            case .trailing: tip = CGPoint(x: source.minX, y: source.midY)
            }
            arrow = (edge, tip)
        case .menu where m.menusAreGlassPanels:
            // iOS 27: the panel covers its source, pinned by the source's corner nearest the
            // window's edges (Paulo's ••• button top right: the panel's top-right corner on the
            // button's), kept inside the window's safe area.
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let source = anchor?.frameInRoot ?? anchorPoint.map { CGRect(origin: $0, size: .zero) } ?? .zero
            panel = Self.menuPlacement(size: size, source: source, window: window, safe: runtime.safeAreaInsets, margin: m.menuWindowMargin)
            popSource = source
            arrow = nil
            contentFrame = panel
            target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(size), by: runtime.root)
            return
        case .menu:
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let source = anchor?.frameInRoot ?? anchorPoint.map { CGRect(origin: $0, size: .zero) } ?? .zero
            var origin = CGPoint(x: source.minX, y: source.maxY + PlatformMetrics.menuGap)
            origin.x = min(max(origin.x, 0), max(0, window.width - size.width))
            if origin.y + size.height > window.height { origin.y = max(0, source.minY - PlatformMetrics.menuGap - size.height) }
            panel = CGRect(origin: origin, size: size)
            arrow = nil
        case .window(_, let defaultSize):
            // Content-sized (or the scene's default size, or the size its corner was dragged
            // to), clamped to the window with a margin; at the scene's default position (else
            // centred) cascaded by the number of windows already open, or where it was dragged.
            let margin = PlatformMetrics.sheetMargin
            let bar = titleBarHeight + toolbarHeight
            let available = isHostedWindow ? CGSize(width: 1e6, height: 1e6) : CGSize(width: max(0, window.width - 2 * margin), height: max(0, window.height - 2 * margin - bar))
            var size: CGSize
            if let dragged = windowSize {
                size = CGSize(width: min(dragged.width, available.width), height: min(dragged.height, available.height))
            } else if let defaultSize {
                size = CGSize(width: min(defaultSize.width, available.width), height: min(defaultSize.height, available.height))
            } else {
                let natural = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
                size = CGSize(width: min(natural.width + 2 * padding, available.width), height: min(natural.height + 2 * padding, available.height))
            }
            var origin: CGPoint
            if let dragged = windowOrigin {
                origin = dragged
            } else {
                let index = runtime.presentations.filter { $0.kind.isWindow }.firstIndex { $0 === self } ?? 0
                let cascade = CGFloat(index) * Self.windowCascade
                let unit = windowOptions.defaultPosition ?? .center
                origin = CGPoint(x: ((window.width - size.width) * unit.x + cascade).rounded(), y: ((window.height - size.height - bar) * unit.y + cascade).rounded())
            }
            if !isHostedWindow {
                origin.x = min(max(margin, origin.x), max(margin, window.width - size.width - margin))
                origin.y = min(max(margin, origin.y), max(margin, window.height - size.height - bar - margin))
            }
            panel = CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height + bar)
            arrow = nil
            layoutToolbar(top: titleBarHeight)
            contentFrame = CGRect(x: panel.minX + padding, y: panel.minY + bar + padding, width: size.width - 2 * padding, height: size.height - 2 * padding)
            target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
            return
        case .submenu:
            // Beside the parent row, its first item level with the row; flipped to the left
            // when it would overflow.
            let size = target.sizeThatFits(ProposedViewSize(width: nil, height: nil))
            let source = anchor?.frameInRoot ?? .zero
            var origin = CGPoint(x: source.maxX, y: source.minY - PlatformMetrics.menuVerticalPadding)
            if origin.x + size.width > window.width { origin.x = max(0, source.minX - size.width) }
            origin.y = min(max(origin.y, 0), max(0, window.height - size.height))
            panel = CGRect(origin: origin, size: size)
            arrow = nil
        }
        // iOS alerts carry their insets in their content.
        let inset = kind == .alert && m.alertInsets.top != PlatformMetrics.presentationPadding && environment.platformProfile.isIOS ? 0 : padding
        contentFrame = panel.insetBy(dx: inset, dy: inset)
        target.place(at: contentFrame.origin, anchor: .topLeading, proposal: ProposedViewSize(contentFrame.size), by: runtime.root)
    }

    /// An iOS menu's panel over its source: the corner of the source nearest the window's
    /// edges is the panel's, the panel then kept inside the safe area less `margin`.
    package static func menuPlacement(size: CGSize, source: CGRect, window: CGSize, safe: EdgeInsets, margin: CGFloat) -> CGRect {
        let x = source.midX > window.width / 2 ? source.maxX - size.width : source.minX
        let y = source.midY > window.height / 2 ? source.maxY - size.height : source.minY
        let left = max(margin, safe.leading), right = window.width - max(margin, safe.trailing)
        let top = max(margin, safe.top), bottom = window.height - max(margin, safe.bottom)
        return CGRect(x: min(max(left, x), max(left, right - size.width)).rounded(),
                      y: min(max(top, y), max(top, bottom - size.height)).rounded(),
                      width: size.width, height: size.height)
    }

    /// Where iOS 27 puts a confirmation dialog for its source, as UIKit places a popover with
    /// any arrow direction (the simulator's `ios/dialog/…` goldens, new-website#649): on the
    /// side of the source with the most room among those the panel fits on, centred on the source
    /// along that side and kept inside the window, its arrow touching the source; under a wide
    /// button above it, beside a small trailing button to its left. Where it fits on no side (a
    /// source filling the window) it is centred on the source with no arrow.
    package static func popoverPlacement(size: CGSize, source: CGRect, window: CGSize, safe: EdgeInsets,
                                         metrics m: PlatformMetricsTable) -> (CGRect, (edge: Edge, tip: CGPoint)?) {
        let margin = PlatformMetrics.sheetMargin
        let reach = m.dialogSourceGap + m.dialogArrowHeight
        let top = max(margin, safe.top), bottom = window.height - max(margin, safe.bottom)
        let left = max(margin, safe.leading), right = window.width - max(margin, safe.trailing)
        // Room on each side of the source, and whether the panel fits there.
        let above = source.minY - reach - top, below = bottom - source.maxY - reach
        let before = source.minX - reach - left, after = right - source.maxX - reach
        var best: (Edge, CGFloat)?
        for (edge, room, fits) in [(Edge.top, above * (right - left), above >= size.height && right - left >= size.width),
                                   (.bottom, below * (right - left), below >= size.height && right - left >= size.width),
                                   (.leading, before * (bottom - top), before >= size.width && bottom - top >= size.height),
                                   (.trailing, after * (bottom - top), after >= size.width && bottom - top >= size.height)]
        where fits && room > (best?.1 ?? -1) { best = (edge, room) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(left, x), max(left, right - size.width)).rounded() }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(top, y), max(top, bottom - size.height)).rounded() }
        guard let (edge, _) = best else {
            let panel = CGRect(x: clampX(source.midX - size.width / 2), y: clampY(source.midY - size.height / 2), width: size.width, height: size.height)
            return (panel, nil)
        }
        // The arrow stays clear of the panel's rounded corners.
        let inset = m.dialogCornerRadius + m.dialogArrowWidth / 2
        switch edge {
        case .top, .bottom:
            let x = clampX(source.midX - size.width / 2)
            let y = edge == .top ? source.minY - reach - size.height : source.maxY + reach
            let tipX = min(max(source.midX, x + inset), x + size.width - inset)
            let tip = CGPoint(x: tipX, y: edge == .top ? source.minY - m.dialogSourceGap : source.maxY + m.dialogSourceGap)
            // The arrow is on the panel's side facing the source.
            return (CGRect(x: x, y: y, width: size.width, height: size.height), (edge == .top ? .bottom : .top, tip))
        case .leading, .trailing:
            let y = clampY(source.midY - size.height / 2)
            let x = edge == .leading ? source.minX - reach - size.width : source.maxX + reach
            let tipY = min(max(source.midY, y + inset), y + size.height - inset)
            let tip = CGPoint(x: edge == .leading ? source.minX - m.dialogSourceGap : source.maxX + m.dialogSourceGap, y: tipY)
            return (CGRect(x: x, y: y, width: size.width, height: size.height), (edge == .leading ? .trailing : .leading, tip))
        }
    }

    // MARK: Painting

    /// A hosted window's content for its own window: the background, the toolbar and the
    /// content, with the panel's content origin at `context.origin` (the title bar is the real
    /// window's).
    package func paintHostedWindowContent(into list: inout DisplayList, context: PaintContext) {
        let bar = titleBarHeight
        let content = CGRect(x: panel.minX, y: panel.minY + bar, width: panel.width, height: panel.height - bar)
        list.append(.fillRect(context.absoluteRect(content), environment._windowBackground))
        if let toolbarBar { toolbarBar.paint(into: &list, context: context.child(at: toolbarBar.frame)) }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
    }

    /// A `presentationBackground` style over `path`: nothing for a clear colour, else the style's
    /// fill (a colour, gradient or material).
    private func fillBackground(_ style: AnyShapeStyle, _ path: Path, in bounds: CGRect, context: PaintContext, into list: inout DisplayList) {
        if style.base is Color, style.resolveColor(in: environment).alpha == 0 { return }
        style._fill(path, in: bounds, eoFill: false, environment: environment, scale: context.scale, into: &list)
    }

    /// A popover's arrow on the panel's `edge`, pointing out of it to `tip`: iOS 27 draws it with
    /// soft sides that flare into the panel and a rounded point (ios/dialog/wide-button), and it
    /// overlaps the panel by a point so no seam shows.
    package static func dialogArrowPath(edge: Edge, tip: CGPoint, height h: CGFloat, width: CGFloat) -> Path {
        let w = width / 2
        // In the arrow's own frame: the tip at the origin, the base `h` behind it along -y.
        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            switch edge {
            case .bottom: return CGPoint(x: tip.x + across, y: tip.y - along)
            case .top: return CGPoint(x: tip.x + across, y: tip.y + along)
            case .trailing: return CGPoint(x: tip.x - along, y: tip.y + across)
            case .leading: return CGPoint(x: tip.x + along, y: tip.y + across)
            }
        }
        var path = Path()
        path.move(to: point(h + 1, -w - 2))
        path.addQuadCurve(to: point(1.2, -1.6), control: point(h * 0.55, -w * 0.3))
        path.addQuadCurve(to: point(1.2, 1.6), control: point(0, 0))
        path.addQuadCurve(to: point(h + 1, w + 2), control: point(h * 0.55, w * 0.3))
        path.closeSubpath()
        return path
    }

    package func paintPresentation(into list: inout DisplayList, context: PaintContext) {
        if isHostedWindow { return }
        // The dim is always black; the panel, its shadow and border follow the appearance (unverified in dark).
        let black = { (alpha: Double) in self.environment._ink(alpha) }
        let m = metrics
        let iOS = environment.platformProfile.isIOS
        if isModal && !(kind == .dialog && m.dialogsArePopovers) && !options.fullScreen {
            let alpha = m.presentationDimAlpha * (slides ? slideProgress : 1) * (pops ? min(1, max(0, popProgress)) : 1)
            list.append(.fillRect(context.absoluteRect(CGRect(origin: .zero, size: runtime.layoutSize)), RGBA(red: 0, green: 0, blue: 0, alpha: alpha)))
        }
        // A sliding sheet is drawn lower by its slide, at whole device pixels.
        var context = context
        if slides, slide.position != 0 { context.origin.y += context.round(CGFloat(slide.position)) }
        let rect = context.absoluteRect(panel)
        if kind == .sheet && options.fullScreen {
            // The cover's ground is the system background (or the content's
            // `presentationBackground`); its content paints over it.
            if let background = options.background {
                fillBackground(background, Path(rect), in: rect, context: context, into: &list)
            } else {
                list.append(.fillRect(rect, environment._controlBackground))
            }
            // No card: a cover is not a floating panel (no shadow ring, rounded fill or border,
            // which hid a clear background).
            if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
            return
        } else if kind == .sheet && m.sheetsFillWindow {
            // iOS: the large card's top corners only (it runs off the window), the medium card
            // in the glass fill with the grabber when asked for.
            if mediumDetent {
                list.append(.fillRRect(rect, cornerRadius: m.sheetCornerRadius, m.presentationGlassFill))
                if options.dragIndicator == .visible {
                    let grabber = CGRect(x: rect.midX - m.sheetGrabberSize.width / 2, y: rect.minY + m.sheetGrabberTop, width: m.sheetGrabberSize.width, height: m.sheetGrabberSize.height)
                    list.append(.fillRRect(grabber, cornerRadius: m.sheetGrabberSize.height / 2, black(m.sheetGrabberAlpha)))
                }
            } else {
                let extended = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + m.sheetCornerRadius)
                if let background = options.background {
                    fillBackground(background, Path(roundedRect: extended, cornerRadius: m.sheetCornerRadius), in: extended, context: context, into: &list)
                } else {
                    list.append(.fillRRect(extended, cornerRadius: m.sheetCornerRadius, environment._windowBackground))
                }
            }
            // The content is clipped to the card: a navigation stack's ground (ios/sheet/nav)
            // would square the corners.
            let card = mediumDetent ? rect : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + m.sheetCornerRadius)
            list.append(.save)
            list.append(.clipRRect(card, cornerRadius: m.sheetCornerRadius))
            if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
            list.append(.restore)
            return
        }
        if iOS && (kind == .alert || (kind == .dialog && m.dialogsArePopovers)) {
            // Coming and going (new-website#649): the alert fades in from 1.2 times its size
            // and fades out where it is; the dialog grows out of its arrow's tip (its centre
            // without an arrow) from a hundredth of its size, fading in, and shrinks back into it.
            let progress = popProgress
            let popping = pops && abs(progress - 1) > 0.0005
            if popping {
                let scale: Double
                let origin: CGPoint
                if kind == .alert {
                    scale = isLeaving ? 1 : 1 + 0.2 * (1 - progress)
                    origin = CGPoint(x: rect.midX, y: rect.midY)
                } else {
                    scale = 0.01 + 0.99 * progress
                    origin = arrow.map { CGPoint(x: context.origin.x + $0.tip.x, y: context.origin.y + $0.tip.y) } ?? CGPoint(x: rect.midX, y: rect.midY)
                }
                list.append(.beginGroup(opacity: min(1, max(0, progress))))
                list.append(.save)
                list.append(.concat(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x * (1 - scale), ty: origin.y * (1 - scale))))
            }
            defer {
                if popping {
                    list.append(.restore)
                    list.append(.endGroup)
                }
            }
            // iOS: a glass card; the dialog with its arrow and a soft shadow around, no border.
            let dialog = kind == .dialog
            let fill = dialog ? m.dialogGlassFill : (m.alertFill ?? m.presentationGlassFill)
            let radius = dialog ? m.dialogCornerRadius : m.alertCornerRadius
            for (spread, alpha) in [(3.0, 0.03), (8.0, 0.02), (16.0, 0.012), (28.0, 0.008)] {
                list.append(.fillRRect(rect.insetBy(dx: -spread, dy: -spread).offsetBy(dx: 0, dy: spread / 4), cornerRadius: radius + spread, black(alpha)))
            }
            list.append(.fillRRect(rect, cornerRadius: radius, fill))
            if let arrow {
                list.append(.fillPath(Self.dialogArrowPath(edge: arrow.edge, tip: CGPoint(x: context.origin.x + arrow.tip.x, y: context.origin.y + arrow.tip.y),
                                                           height: m.dialogArrowHeight, width: m.dialogArrowWidth), fill))
            }
            if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
            return
        }
        if iOS && kind.isMenu && m.menusAreGlassPanels {
            paintGlassMenu(rect: rect, into: &list, context: context)
            return
        }
        let radius = kind.isMenu ? PlatformMetrics.menuCornerRadius : kind.isWindow ? Self.windowCornerRadius : PlatformMetrics.presentationCornerRadius
        // A soft shadow ring, then the panel and its border.
        list.append(.fillRRect(rect.insetBy(dx: -2, dy: -2), cornerRadius: radius + 2, black(PlatformMetrics.presentationShadowAlpha)))
        list.append(.fillRRect(rect, cornerRadius: radius, environment._windowBackground))
        list.append(.strokePath(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius),
                                style: StrokeStyle(lineWidth: 1), black(PlatformMetrics.presentationBorderAlpha)))
        if let arrow {
            let h = PlatformMetrics.popoverArrowHeight, w = PlatformMetrics.popoverArrowWidth / 2
            let tip = CGPoint(x: context.origin.x + arrow.tip.x, y: context.origin.y + arrow.tip.y)
            var path = Path()
            path.move(to: tip)
            switch arrow.edge {
            case .top: path.addLine(to: CGPoint(x: tip.x - w, y: tip.y + h)); path.addLine(to: CGPoint(x: tip.x + w, y: tip.y + h))
            case .bottom: path.addLine(to: CGPoint(x: tip.x - w, y: tip.y - h)); path.addLine(to: CGPoint(x: tip.x + w, y: tip.y - h))
            case .leading: path.addLine(to: CGPoint(x: tip.x + h, y: tip.y - w)); path.addLine(to: CGPoint(x: tip.x + h, y: tip.y + w))
            case .trailing: path.addLine(to: CGPoint(x: tip.x - h, y: tip.y - w)); path.addLine(to: CGPoint(x: tip.x - h, y: tip.y + w))
            }
            path.closeSubpath()
            list.append(.fillPath(path, environment._windowBackground))
        }
        if case .window(let title, _) = kind {
            // The title bar: a hairline under it, the traffic lights, the title centred (a
            // hidden title bar keeps the lights over the content); a resizable window's grip.
            let bar = CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: Self.windowTitleBarHeight)
            if !windowOptions.hidesTitleBar {
                let separator = context.absoluteRect(CGRect(x: bar.minX, y: bar.maxY - 0.5, width: bar.width, height: 0.5))
                list.append(.fillRect(separator, black(0.1)))
            }
            let lights: [RGBA] = [RGBA(r: 255, g: 95, b: 87), RGBA(r: 254, g: 188, b: 46), RGBA(r: 40, g: 200, b: 64)]
            for (i, color) in lights.enumerated() {
                let dot = CGRect(x: closeButtonFrame.minX + CGFloat(i) * 20, y: closeButtonFrame.minY, width: 12, height: 12)
                list.append(.fillPath(Path(ellipseIn: context.absoluteRect(dot)), color))
            }
            if windowOptions.resizable {
                let grip = context.absoluteRect(resizeGripFrame)
                var lines = Path()
                for offset in [4.0, 8.0] {
                    lines.move(to: CGPoint(x: grip.maxX - offset, y: grip.maxY - 3))
                    lines.addLine(to: CGPoint(x: grip.maxX - 3, y: grip.maxY - offset))
                }
                list.append(.strokePath(lines, style: StrokeStyle(lineWidth: 1), black(0.25)))
            }
            if let title, !title.isEmpty, !windowOptions.hidesTitleBar {
                let font = Font.system(size: 13, weight: .semibold).resolve(profile: environment.platformProfile)
                let layout = runtime.layoutText(title, font: font, width: nil)
                let x = bar.midX - layout.size.width / 2
                let y = bar.minY + (Self.windowTitleBarHeight - layout.size.height) / 2 + layout.firstBaseline
                let color = environment._ink(0.85)
                for line in layout.lines {
                    for fragment in line.fragments where !fragment.text.isEmpty {
                        list.append(.drawText(fragment.text, DisplayFont(font), origin: context.absoluteRect(CGRect(x: x + fragment.x, y: y, width: 0, height: 0)).origin, color))
                    }
                }
            }
        }
        if let highlightedIndex, kind.isMenu {
            let rows = interactiveNodes
            if highlightedIndex < rows.count {
                let row = context.absoluteRect(rows[highlightedIndex].frameInRoot).insetBy(dx: PlatformMetrics.menuHighlightInset, dy: 0)
                list.append(.fillRRect(row, cornerRadius: PlatformMetrics.menuHighlightCornerRadius, black(PlatformMetrics.menuHighlightAlpha)))
            }
        }
        if let toolbarBar { toolbarBar.paint(into: &list, context: context.child(at: toolbarBar.frame)) }
        if let target { target.paint(into: &list, context: context.child(at: target.presentedFrame)) }
    }

    /// Where a menu's glass is while it grows out of its button or shrinks back into it: each
    /// channel moves its part of the rectangle from the button's to the panel's.
    package func menuMorphRect(panel rect: CGRect, source: CGRect) -> CGRect {
        guard pop.count == 3 else { return rect }
        let across = pop[0].position, height = pop[1].position, down = pop[2].position
        let width = max(1, source.width + (rect.width - source.width) * across)
        let tall = max(1, source.height + (rect.height - source.height) * height)
        let midX = source.midX + (rect.midX - source.midX) * across
        let midY = source.midY + (rect.midY - source.midY) * down
        return CGRect(x: midX - width / 2, y: midY - tall / 2, width: width, height: tall)
    }

    /// An iOS menu: a soft shadow, what is behind blurred under a near-white fill, a hairline
    /// edge, then the rows (a highlighted one under a light fill). While it grows or shrinks
    /// (new-website#649) the glass is a lens between the button and the panel: rounder the
    /// smaller it is, bending what lies beneath toward its rim, the rows squeezed into it and
    /// showing only as it nears its size, as the simulator shows.
    private func paintGlassMenu(rect panelRect: CGRect, into list: inout DisplayList, context: PaintContext) {
        let m = metrics
        let moving = pop.count == 3 && pop.contains { abs($0.position - 1) > 0.0005 }
        let source = context.absoluteRect(popSource)
        let rect = moving ? menuMorphRect(panel: panelRect, source: source) : panelRect
        // How far it has grown: 0 at the button, 1 at its size (past 1 while it overshoots).
        let grown = pop.count == 3 ? min(pop[0].position, pop[1].position) : 1
        func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
            let t = min(1, max(0, (x - a) / (b - a)))
            return t * t * (3 - 2 * t)
        }
        let settle = smooth(0.7, 1.0, grown)
        let round = min(rect.width, rect.height) / 2
        let radius = moving ? round + (min(m.menuCornerRadius, round) - round) * settle : m.menuCornerRadius
        let shape = Path(roundedRect: rect, cornerRadius: radius)
        // Shrunk nearly into its button the glass fades away, giving the button back.
        let fade = moving ? smooth(0.02, 0.22, grown) : 1
        if fade < 0.999 { list.append(.beginGroup(opacity: fade)) }
        defer { if fade < 0.999 { list.append(.endGroup) } }
        for (spread, alpha) in [(2.0, 0.025), (8.0, 0.02), (20.0, 0.014), (36.0, 0.008)] {
            list.append(.fillRRect(rect.insetBy(dx: -spread, dy: -spread).offsetBy(dx: 0, dy: spread / 3), cornerRadius: radius + spread, environment._ink(alpha)))
        }
        if moving {
            // The lens: what lies beneath bends in up to 14 pt at the rim while the glass is in
            // motion, less as it settles.
            list.append(.backdropLens(shape, bounds: rect, radius: m.menuGlassSigma, bend: 14 * (1 - settle), cornerRadius: radius))
        } else {
            list.append(.backdropBlur(shape, bounds: rect, radius: m.menuGlassSigma))
        }
        // In motion the glass is clearer, the bent page showing through it (the simulator's
        // frames); it whitens as it settles.
        var fill = m.menuGlassFill
        if moving { fill.alpha = 0.45 + (fill.alpha - 0.45) * settle }
        list.append(.fillPath(shape, fill))
        list.append(.strokePath(Path(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), cornerRadius: radius - 0.25),
                                style: StrokeStyle(lineWidth: 0.5), environment._ink(m.menuEdgeAlpha)))
        if let highlightedIndex {
            let rows = interactiveNodes
            if highlightedIndex < rows.count {
                let row = context.absoluteRect(rows[highlightedIndex].frameInRoot).insetBy(dx: 10, dy: 0)
                list.append(.fillRRect(row, cornerRadius: 12, environment._ink(0.06)))
            }
        }
        list.append(.save)
        list.append(.clipRRect(rect, cornerRadius: radius))
        if let target {
            if moving {
                // The rows squeezed into the glass, showing as it nears its size.
                let rows = smooth(0.55, 0.98, grown)
                if rows > 0.001 {
                    let sx = rect.width / max(1, panelRect.width), sy = rect.height / max(1, panelRect.height)
                    list.append(.beginGroup(opacity: rows))
                    list.append(.save)
                    list.append(.concat(CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: rect.minX - panelRect.minX * sx, ty: rect.minY - panelRect.minY * sy)))
                    target.paint(into: &list, context: context.child(at: target.presentedFrame))
                    list.append(.restore)
                    list.append(.endGroup)
                }
            } else {
                target.paint(into: &list, context: context.child(at: target.presentedFrame))
            }
        }
        list.append(.restore)
    }

    // MARK: Keyboard

    /// Menus: Up/Down move the highlight over the rows (wrapping), Return or Space activates the
    /// highlighted row, Escape closes the menu.
    package func handleKey(_ press: KeyPress) -> Bool {
        guard kind.isMenu, press.modifiers.shortcutModifiers.isEmpty else { return false }
        let rows = interactiveNodes
        switch press.key {
        case .downArrow:
            guard !rows.isEmpty else { return true }
            highlightedIndex = highlightedIndex.map { ($0 + 1) % rows.count } ?? 0
        case .upArrow:
            guard !rows.isEmpty else { return true }
            highlightedIndex = highlightedIndex.map { ($0 + rows.count - 1) % rows.count } ?? rows.count - 1
        case .return, .space:
            guard let highlightedIndex, highlightedIndex < rows.count else { return false }
            let row = rows[highlightedIndex]
            row.pressBegan()
            row.pressEnded(inside: true)
        case .escape:
            dismiss()
        default:
            return false
        }
        runtime.setNeedsDisplay()
        return true
    }

    // MARK: Hit testing

    /// The interactive node under `point` (window coordinates), if inside the panel.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        var point = point
        if slides { point.y -= CGFloat(slide.position) }
        guard panel.contains(point), let target else { return nil }
        if kind.isWindow, closeButtonFrame.insetBy(dx: -4, dy: -4).contains(point) { return closeButton }
        if kind.isWindow, windowOptions.resizable, resizeGripFrame.contains(point) { windowHandle.mode = .resize; return windowHandle }
        if kind.isWindow, dragBarFrame.contains(point) { windowHandle.mode = .move; return windowHandle }
        if let toolbarBar, let hit = toolbarBar.interactiveNode(at: point) { return hit }
        let local = CGPoint(x: point.x - target.frame.minX, y: point.y - target.frame.minY)
        guard target.contains(local) else { return nil }
        return target.hitTest(local, where: { $0.isInteractiveNode }) as? (ViewNode & _Interactive)
    }

    /// The traffic-light close control of a secondary window.
    private lazy var closeButton: WindowCloseButton = WindowCloseButton(presentation: self)
    /// The title bar (moves the window) and the corner grip (resizes it).
    private lazy var windowHandle: WindowHandle = WindowHandle(presentation: self)

    /// The pointer style over a window's grip or bar (`Runtime.updateHover`).
    package func pointerStyle(at point: CGPoint) -> PointerStyle? {
        guard kind.isWindow, panel.contains(point) else { return nil }
        if windowOptions.resizable, resizeGripFrame.contains(point) { return .frameResize(position: .bottomTrailing) }
        return nil
    }

    package var interactiveNodes: [ViewNode & _Interactive] {
        (toolbarBar?.interactiveNodes ?? []) + (target?.collectNodes(where: { $0.isInteractiveNode }) ?? []).compactMap { $0 as? (ViewNode & _Interactive) }
    }

    override package var structuralChildren: [ViewNode] { [content] }
    override package var layoutChildren: [ViewNode] { [] }
    /// The content's layout nodes, where the semantics walk starts (it follows painted children,
    /// which only layout nodes have); the toolbar's before them.
    package var semanticsRoots: [ViewNode] { (toolbarBar?.layoutChildren ?? []) + content.layoutChildren }
    override package var nodeDescription: String { "Presentation(\(kind))" }

    override package func unmount() {
        stopSlideFrames()
        stopPopFrames()
        toolbarBar?.unmount()
        toolbarBar = nil
        content.unmount()
        super.unmount()
    }
}

extension Runtime {
    /// Presents `view` in a panel of `kind` over the window.
    @discardableResult
    package func present(kind: _PresentationKind, view: AnyView, environment: EnvironmentValues, anchor: ViewNode?, at point: CGPoint? = nil,
                         onDismissRequested: @escaping @MainActor () -> Void) -> PresentationNode {
        let node = PresentationNode(runtime: self, kind: kind, view: view, environment: environment, anchor: anchor, anchorPoint: point,
                                    onDismissRequested: onDismissRequested)
        node.focusToRestore = focusedIdentifier.map { ($0, focusVisible) }
        presentations.append(node)
        requestLayout()
        return node
    }

    package func remove(presentation node: PresentationNode) {
        guard let index = presentations.firstIndex(where: { $0 === node }) else { return }
        presentations.remove(at: index)
        // An iOS sheet on screen slides off first; its content stays until it is gone.
        if node.slides || node.pops, node.hasLaidOut, hostIsVisible {
            leavingPresentations.append(node)
            node.beginLeaving()
        } else {
            node.unmount()
        }
        // Focus goes back to the element that had it before the presentation, when focus was
        // inside the presentation (its element is gone now) or nowhere.
        if let restore = node.focusToRestore, focusedIdentifier.flatMap({ interactiveNode(semanticsIdentifier: $0) }) == nil,
           interactiveNode(semanticsIdentifier: restore.identifier) != nil {
            focus(semanticsIdentifier: restore.identifier, keyboard: restore.keyboard)
        }
        requestLayout()
    }

    /// A sheet that slid off: gone now.
    package func finishLeaving(_ node: PresentationNode) {
        leavingPresentations.removeAll { $0 === node }
        if node.isMounted { node.unmount() }
        requestLayout()
    }

    /// Dismisses the topmost presentation, if any (hosts call this for Escape). Returns whether one was.
    @discardableResult
    public func dismissTopmostPresentation() -> Bool {
        guard let top = presentations.last else { return false }
        // `interactiveDismissDisabled` keeps it (Escape is consumed).
        if !top.options.interactiveDismissDisabled { top.dismiss() }
        return true
    }

    /// Whether anything is presented over the window.
    public var hasPresentations: Bool { !presentations.isEmpty }

    package func layoutPresentations(in size: CGSize) {
        for presentation in leavingPresentations + presentations { presentation.layout(in: size) }
    }

    package func paintPresentations(into list: inout DisplayList, context: PaintContext) {
        for presentation in leavingPresentations + presentations { presentation.paintPresentation(into: &list, context: context) }
    }

    /// The interactive node a press at `point` reaches through the presentations: a hit in the
    /// topmost panel, nothing under a modal panel, and a press outside a popover or menu
    /// dismisses it (and is consumed). Returns `nil` with `handled` when the main tree must not
    /// be searched.
    package func presentationHit(at point: CGPoint) -> (node: (ViewNode & _Interactive)?, handled: Bool) {
        for presentation in presentations.reversed() {
            if let hit = presentation.interactiveNode(at: point) {
                if presentation.kind.isWindow, presentations.last !== presentation {
                    presentations.removeAll { $0 === presentation }
                    presentations.append(presentation)
                    setNeedsDisplay()
                }
                return (hit, true)
            }
            if presentation.panel.contains(point) { return (nil, true) }
            if presentation.isModal { return (nil, true) }
            // A press beside a window leaves it open and goes on to what is under it.
            if presentation.kind.isWindow { continue }
            // `interactiveDismissDisabled`: the press is consumed, the presentation stays.
            if presentation.options.interactiveDismissDisabled { return (nil, true) }
            presentation.dismiss()
            // A press outside a submenu closes it and goes on to its parent menu.
            if presentation.kind == .submenu { continue }
            return (nil, true)
        }
        return (nil, false)
    }
}

/// Presents while its `presented` flag is true; dismisses when it turns false or the node leaves.
@MainActor
package final class PresentationSyncNode<Content: View>: UnaryLayoutModifierNode<Content, _PresentationSync> {
    private var presented: PresentationNode?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _PresentationSync>>) {
        super.init(context)
        sync()
    }

    override package func update(view: ModifiedContent<Content, _PresentationSync>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        sync()
    }

    private func sync() {
        if modifier.presented {
            if let presented, presented.isMounted {
                presented.update(view: modifier.content.make())
            } else {
                let binding = modifier.binding, onDismiss = modifier.onDismiss
                presented = runtime.present(kind: modifier.kind, view: modifier.content.make(), environment: environment, anchor: anchorNode) {
                    binding.wrappedValue = false
                    onDismiss?.run()
                }
                presented?.options.fullScreen = modifier.fullScreen
            }
        } else if let presented {
            self.presented = nil
            if presented.isMounted { runtime.remove(presentation: presented) }
            modifier.onDismiss?.run()
        }
    }

    /// What the presentation opens on: this view, or for an iOS confirmation dialog the control
    /// inside it whose press presented it (the simulator opens Paulo's Sign out sheet on its
    /// button, not on the settings column the modifier sits on, new-website#649).
    private var anchorNode: ViewNode {
        guard modifier.kind == .dialog, environment.platformProfile.metrics.dialogsArePopovers,
              let pressed = runtime.lastActivatedNode, pressed.isMounted else { return self }
        var current: ViewNode? = pressed
        while let node = current {
            if node === self { return pressed }
            current = node.parent
        }
        return self
    }

    override package func unmount() {
        if let presented, presented.isMounted { runtime.remove(presentation: presented) }
        presented = nil
        super.unmount()
    }
}

/// `presentationDetents` / `presentationDragIndicator`: transparent to layout; tells the
/// presentation above it (the nearest `PresentationNode` ancestor) the sheet's options.
@MainActor
package final class PresentationOptionsNode<Content: View>: UnaryLayoutModifierNode<Content, _PresentationOptionsModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _PresentationOptionsModifier>>) {
        super.init(context)
        tell()
    }

    override package func update(view: ModifiedContent<Content, _PresentationOptionsModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        tell()
    }

    private func tell() {
        var current = parent
        while let node = current {
            if let presentation = node as? PresentationNode {
                if let detents = modifier.detents { presentation.options.detents = detents }
                if let indicator = modifier.dragIndicator { presentation.options.dragIndicator = indicator }
                if let disabled = modifier.interactiveDismissDisabled { presentation.options.interactiveDismissDisabled = disabled }
                if let background = modifier.background { presentation.options.background = background }
                return
            }
            current = node.parent
        }
    }
}

/// A secondary window's title bar and corner grip: dragging the bar moves the window, dragging
/// the grip resizes it (the content lays out again at the new size); both clamp to the host.
@MainActor
package final class WindowHandle: ViewNode, _Interactive {
    package enum Mode { case move, resize }
    private weak var owner: PresentationNode?
    package var mode = Mode.move
    private var start: (point: CGPoint, origin: CGPoint, size: CGSize)?

    package init(presentation: PresentationNode) {
        self.owner = presentation
        super.init(parent: presentation.runtime.root, runtime: presentation.runtime, environment: presentation.environment)
    }

    /// The handle covers the whole panel, so press points are panel-relative.
    override package var frame: CGRect {
        get { owner?.panel ?? .zero }
        set {}
    }

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        guard let owner else { return }
        start = (point, owner.panel.origin, CGSize(width: owner.panel.width, height: owner.panel.height - owner.titleBarHeight))
    }

    package func pressMoved(to point: CGPoint) {
        guard let owner, let start else { return }
        let dx = point.x - start.point.x, dy = point.y - start.point.y
        switch mode {
        case .move: owner.windowOrigin = CGPoint(x: start.origin.x + dx, y: start.origin.y + dy)
        case .resize: owner.windowSize = CGSize(width: max(120, start.size.width + dx), height: max(60, start.size.height + dy))
        }
        runtime.requestLayout(invalidatingSizes: mode == .resize)
    }

    package func pressEnded(inside: Bool) { start = nil }
    package var semantics: SemanticsNode {
        SemanticsNode(role: .group, label: "", frame: owner?.dragBarFrame ?? .zero, identifier: ObjectIdentifier(self).hashValue)
    }
    override package var nodeDescription: String { "WindowHandle" }
}

/// The close control in a secondary window's title bar.
@MainActor
package final class WindowCloseButton: ViewNode, _Interactive {
    private weak var owner: PresentationNode?

    package init(presentation: PresentationNode) {
        self.owner = presentation
        super.init(parent: presentation, runtime: presentation.runtime, environment: presentation.environment)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) { if inside { owner?.dismiss() } }
    package var semantics: SemanticsNode {
        SemanticsNode(role: .button, label: "Close", frame: owner?.closeButtonFrame ?? .zero, identifier: ObjectIdentifier(self).hashValue)
    }
    override package var nodeDescription: String { "WindowClose" }
}
