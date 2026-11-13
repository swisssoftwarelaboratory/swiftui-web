// The scene the substrate's hosts drive (WebGraphics `HostedScene`, decision 0014): the
// windows, one frame (layout, then the layer tree painted into the display list), touches from
// the host's pointer, and the semantics tree from the views' accessibility properties.

/// The UIKit app as a hosted scene. One per process, like `UIApplication.shared`.
@preconcurrency @MainActor
public final class UIKitScene: HostedScene {
    public static let shared = UIKitScene()

    private init() {}

    // MARK: Windows

    public private(set) var windows: [UIWindow] = []
    /// The window the app delegate keeps (`UIApplicationDelegate.window`).
    var delegateWindow: UIWindow?
    /// The responder taking key input (a text field).
    var firstResponder: UIResponder? {
        didSet {
            guard firstResponder !== oldValue else { return }
            for entry in hostedTrees { entry.tree?.firstResponderDidChange(from: oldValue, to: firstResponder) }
        }
    }

    // MARK: Trees hosted in other scenes (decision 0014: SwiftUIWeb's representables)

    private struct WeakTree { weak var tree: UIKitHostedTree? }
    private var hostedTrees: [WeakTree] = []
    /// Views hosting another framework's scene (App/HostingViewSPI.swift).
    var hostingViews: [WeakView] = []

    func register(_ tree: UIKitHostedTree) {
        hostedTrees.removeAll { $0.tree == nil }
        hostedTrees.append(WeakTree(tree: tree))
    }

    func unregister(_ tree: UIKitHostedTree) {
        hostedTrees.removeAll { $0.tree == nil || $0.tree === tree }
    }

    func add(_ window: UIWindow) {
        guard !windows.contains(where: { $0 === window }) else { return }
        windows.append(window)
        window.frame = UIScreen.main.bounds
        window.didJoinScene()
        setNeedsFrame()
    }

    func remove(_ window: UIWindow) {
        windows.removeAll { $0 === window }
        setNeedsFrame()
    }

    /// Drops every window, and the timers and animations they had running (tests mount one
    /// fixture after another in the shared scene).
    public func removeAllWindows() {
        for window in windows { window.rootViewController?.viewIfLoaded?.removeFromSuperview() }
        windows.removeAll()
        delegateWindow = nil
        firstResponder = nil
        timers.removeAll()
        animationGroups.removeAll()
        decelerating.removeAll()
        displayLinks.removeAll()
        spinners.removeAll()
        // A press or a hover in flight belonged to the windows that just went (a test that
        // pressed without releasing must not turn the next test's pointer moves into drags).
        touches.dropActiveTouch()
        hover.update(to: nil, in: nil)
        setNeedsFrame()
    }

    /// Modal presentation: a container over the window holds the dimming and the presented
    /// controller's view as the card its style calls for (Containers/UIAlertController.swift).
    /// Presented with `animated`, an alert scales in from 1.15 with a spring over 0.4 s as its
    /// dimming fades in; a sheet slides up from the bottom, eased out over 0.45 s (followed,
    /// not measured: the goldens hold the end states). `completion` runs when the animation ends.
    func present(_ controller: UIViewController, from presenter: UIViewController, animated: Bool = false, completion: (() -> Void)? = nil) {
        guard let window = presenter.viewIfLoaded?.window ?? windows.first else { completion?(); return }
        controller.window = window
        let container = PresentationContainerView(controller: controller, frame: window.bounds)
        controller.presentationContainer = container
        let view = controller.view!
        view.autoresizingMask = []
        controller.beginAppearanceTransition(true, animated: animated)
        container.addSubview(view)
        window.addSubview(container)
        controller.pendingAppearance = true
        setNeedsFrame()
        guard animated, UIView.areAnimationsEnabled else { completion?(); return }
        container.layoutIfNeeded()
        // A transitioning delegate's animator moves the views itself.
        if let animator = controller.transitioningDelegate?.animationController(forPresented: controller, presenting: presenter, source: presenter) {
            let context = TransitionContext(containerView: container, from: presenter, to: controller, presentationStyle: controller.modalPresentationStyle,
                                            initialFrames: [ObjectIdentifier(presenter): presenter.viewIfLoaded?.frame ?? .zero],
                                            finalFrames: [ObjectIdentifier(controller): view.frame, ObjectIdentifier(presenter): presenter.viewIfLoaded?.frame ?? .zero],
                                            onComplete: { completed in
                                                animator.animationEnded(completed)
                                                completion?()
                                            })
            animator.animateTransition(using: context)
            setNeedsFrame()
            return
        }
        container.dimming.alpha = 0
        let isAlert = controller is UIAlertController
        if isAlert {
            view.alpha = 0
            view.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } else {
            view.transform = CGAffineTransform(translationX: 0, y: window.bounds.height - view.frame.minY)
        }
        let animations = {
            container.dimming.alpha = 1
            view.alpha = 1
            view.transform = .identity
        }
        if isAlert {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, animations: animations, completion: { _ in completion?() })
        } else {
            UIView.animate(withDuration: 0.45, delay: 0, options: .curveEaseOut, animations: animations, completion: { _ in completion?() })
        }
    }

    /// Dismissal reverses the presentation; the container leaves the window when it ends.
    func dismiss(_ controller: UIViewController, animated: Bool = false, completion: (() -> Void)? = nil) {
        controller.beginAppearanceTransition(false, animated: animated)
        let finish = { [weak self] in
            controller.viewIfLoaded?.removeFromSuperview()
            controller.presentationContainer?.removeFromSuperview()
            controller.presentationContainer = nil
            controller.endAppearanceTransition()
            controller.window = nil
            self?.setNeedsFrame()
            completion?()
        }
        guard animated, UIView.areAnimationsEnabled, let container = controller.presentationContainer as? PresentationContainerView, let view = controller.viewIfLoaded, view.window != nil else {
            finish()
            return
        }
        controller.presentationContainer = nil   // no second dismissal reaches the container
        if let animator = controller.transitioningDelegate?.animationController(forDismissed: controller) {
            let presenter = controller.presentingViewController ?? windows.last?.rootViewController
            let context = TransitionContext(containerView: container, from: controller, to: presenter, presentationStyle: controller.modalPresentationStyle,
                                            initialFrames: [ObjectIdentifier(controller): view.frame],
                                            finalFrames: [ObjectIdentifier(controller): view.frame],
                                            onComplete: { completed in
                                                container.removeFromSuperview()
                                                animator.animationEnded(completed)
                                                controller.viewIfLoaded?.removeFromSuperview()
                                                controller.endAppearanceTransition()
                                                controller.window = nil
                                                self.setNeedsFrame()
                                                completion?()
                                            })
            animator.animateTransition(using: context)
            setNeedsFrame()
            return
        }
        let isAlert = controller is UIAlertController
        UIView.animate(withDuration: isAlert ? 0.25 : 0.4, delay: 0, options: isAlert ? .curveEaseIn : .curveEaseIn, animations: {
            container.dimming.alpha = 0
            if isAlert {
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            } else {
                view.transform = CGAffineTransform(translationX: 0, y: container.bounds.height - view.frame.minY)
            }
        }, completion: { _ in
            container.removeFromSuperview()
            view.transform = .identity
            view.alpha = 1
            finish()
        })
        setNeedsFrame()
    }

    // MARK: Services the host installs

    public var textEngine: any TextEngine = PlaceholderTextEngine()
    public var assetCatalog: AssetCatalog = .empty { didSet { UIKitScene._catalog = assetCatalog; setNeedsFrame() } }
    /// The catalog as the image and colour initializers read it: Apple's `UIImage(named:)` and
    /// `UIColor(named:)` are callable from any context, and a wasm page has one thread.
    nonisolated(unsafe) private static var ownCatalog: AssetCatalog = .empty
    /// The scene's catalog, else the app's (`AssetCatalog.app`, a SwiftUI host's): a SwiftUI
    /// app's `UIImage(named:)` finds its images before any UIKit view has been shown.
    nonisolated static var _catalog: AssetCatalog {
        get { ownCatalog == .empty ? AssetCatalog.app : ownCatalog }
        set { ownCatalog = newValue }
    }
    public var imageLoader: (any _ImageLoading)?
    /// Rasterises a recorded drawing for `UIImage.pngData()` (installed by hosts that can).
    public var imageRasterizer: ImageRasterizer?
    /// Recorded (UIKit's `UIAccessibility.isReduceMotionEnabled` reads it).
    public var hostReducesMotion = false
    public var hostIncreasesContrast = false
    /// The user's text size from the host (a category short name): the screen's preferred
    /// content size category follows it (sw-dynamic-type).
    public var hostDynamicTypeSize: String? {
        didSet {
            guard hostDynamicTypeSize != oldValue else { return }
            let category = hostDynamicTypeSize.flatMap { name in UIContentSizeCategory.ordered.first { $0.shortName == name } } ?? .large
            preferredContentSizeCategory = category
        }
    }
    /// The host's visibility and focus drive the app's lifecycle (App/UIScene.swift).
    public var hostIsVisible = true {
        didSet { if hostIsVisible != oldValue { applyLifecycle(from: (oldValue, hostIsFocused)) } }
    }
    public var hostIsFocused = true {
        didSet { if hostIsFocused != oldValue { applyLifecycle(from: (hostIsVisible, oldValue)) } }
    }
    /// The one window scene (uk-scenes), its delegate once connected, and the class to connect.
    public private(set) lazy var windowScene = UIWindowScene(session: UISceneSession())
    public internal(set) var sceneDelegate: (any UISceneDelegate)?
    public var sceneDelegateType: (any UISceneDelegate.Type)?
    /// The window a scene delegate without a stored `window` keeps (the protocol's default).
    public var sceneDelegateWindow: UIWindow?
    /// The on-screen keyboard's frame (`keyboardFrame`, Keyboard.swift).
    var storedKeyboardFrame: CGRect?
    /// The URL a UIKit app would receive through its scene delegate (recorded only).
    public private(set) var lastOpenedURL: String?
    public func handleOpenURL(_ url: String) { lastOpenedURL = url }

    public var hostColorScheme: ColorScheme = .light {
        didSet {
            guard hostColorScheme != oldValue else { return }
            let previous = UIScreen.main.traitCollection
            UIScreen.main.traitCollection.userInterfaceStyle = hostColorScheme == .dark ? .dark : .light
            UITraitCollection.current = UIScreen.main.traitCollection
            for window in windows { window.propagateTraitChange(from: previous) }
            setNeedsFrame()
        }
    }
    public var clipboardWriter: ((String) -> Void)?
    /// The host's share sheet and file panels (Containers/SystemSheets.swift); a hosting
    /// runtime hands its own down (SwiftUIWebUIKit).
    public var shareHandler: ((HostShareRequest) -> Void)?
    // `@Sendable` spelled out: WebGraphics's `HostedScene` declares these in Swift 6 mode, where a
    // `@MainActor` function type is `Sendable` by itself; this module is in Swift 5 mode (decision 0027).
    public var fileOpenHandler: ((HostFileOpenRequest, _ completion: @escaping @MainActor @Sendable ([HostFile]) -> Void) -> Void)?
    public var fileSaveHandler: ((HostFile) -> Void)?
    /// A hosting runtime's pasteboard (SwiftUIWebUIKit installs these): what it holds, with the
    /// generation its copies advance, and where `UIPasteboard.general`'s text goes.
    public var pasteboardSource: (() -> (generation: Int, text: String?))?
    public var pasteboardSink: ((String?) -> Void)?
    public var onNeedsFrame: (@MainActor @Sendable () -> Void)?
    /// The host's link opener (`UIApplication.open`).
    public var openURL: ((String) -> Void)?

    /// Sets the screen's size and scale (hosts do this before launching the app).
    /// The content size category (Dynamic Type) of every trait collection; text-style fonts of
    /// labels with `adjustsFontForContentSizeCategory` follow it.
    public var preferredContentSizeCategory: UIContentSizeCategory {
        get { UIScreen.main.traitCollection.preferredContentSizeCategory }
        set {
            guard newValue != UIScreen.main.traitCollection.preferredContentSizeCategory else { return }
            let previous = UIScreen.main.traitCollection
            UIScreen.main.traitCollection.preferredContentSizeCategory = newValue
            UITraitCollection.current = UIScreen.main.traitCollection
            for window in windows { window.propagateTraitChange(from: previous) }
            setNeedsFrame()
        }
    }

    public func configureScreen(size: CGSize, scale: CGFloat) {
        UIScreen.main.bounds = CGRect(origin: .zero, size: size)
        UIScreen.main.scale = scale
        UIScreen.main.traitCollection.displayScale = scale
        Self.applySizeClasses(for: size)
        UITraitCollection.current = UIScreen.main.traitCollection
        UIDevice.current.screenDidResize(to: size)
    }

    /// The idiom and size classes a host size gives (an iPhone in portrait is compact wide
    /// and regular tall, in landscape compact both ways; narrower than 500 counts as a phone,
    /// shorter than 400 as compact, so the 400 pt fixtures stay regular as the simulator's
    /// harness holds them).
    static func applySizeClasses(for size: CGSize) {
        UIScreen.main.traitCollection.userInterfaceIdiom = size.width < 500 ? .phone : .pad
        UIScreen.main.traitCollection.horizontalSizeClass = size.width < 500 ? .compact : .regular
        UIScreen.main.traitCollection.verticalSizeClass = size.height < 400 ? .compact : .regular
    }

    // MARK: Scroll to top

    /// A status bar tap: the frontmost scroll view that scrolls vertically and allows it goes
    /// to its top (UIKit asks the one under the status bar; the key window's deepest visible
    /// scroll view with `scrollsToTop` stands in). Returns whether one scrolled.
    @discardableResult
    public func scrollToTop() -> Bool {
        guard let window = windows.last else { return false }
        func candidates(in view: UIView) -> [UIScrollView] {
            var found: [UIScrollView] = []
            for subview in view.subviews where !subview.isHidden && subview.alpha > 0 {
                found += candidates(in: subview)
                if let scroll = subview as? UIScrollView, scroll.scrollsToTop,
                   scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height + 0.5 { found.append(scroll) }
            }
            return found
        }
        for scroll in candidates(in: window).reversed() where scroll.scrollToTop() { return true }
        return false
    }

    // MARK: Frames

    public private(set) var needsFrame = false
    public var isAnimating: Bool { !animationGroups.isEmpty || !decelerating.isEmpty || !spinners.isEmpty || !displayLinks.isEmpty || hostingViewsAnimating }
    /// The activity indicators animating (Controls/MoreControls.swift); their spokes turn on this clock.
    var spinners: [WeakActivityIndicator] = []
    /// The display links added to the run loop (Layers/CADisplayLink.swift); they tick every frame.
    var displayLinks: [WeakDisplayLink] = []
    /// Seconds of frames delivered so far: the display links' timestamps.
    private var frameClock: Double = 0

    /// Ticks the display links; true while any runs (a paused one keeps the loop alive).
    private func advanceDisplayLinks(elapsed: Double) -> Bool {
        displayLinks.removeAll { $0.link == nil }
        guard !displayLinks.isEmpty else { return false }
        frameClock += elapsed
        var alive = false
        for entry in displayLinks {
            if let link = entry.link, link.tick(elapsed: elapsed, now: frameClock) { alive = true }
        }
        displayLinks.removeAll { $0.link == nil || $0.link?.isValid == false }
        return alive
    }
    /// The running `UIView.animate` groups (Layers/LayerAnimation.swift).
    var animationGroups: [UIViewAnimationGroup] = []
    /// Scroll views carried by momentum (Controls/UIScrollView.swift).
    var decelerating: [UIScrollView] = []
    public var windowTitle: String? { nil }
    public var probeFrames: [String: CGRect] { probes }
    /// Frames published under a name for tests (`UIView.publishFrame(as:)`).
    var probes: [String: CGRect] = [:]

    /// Asks the host for a frame (and every host of a tree hosted elsewhere).
    public func setNeedsFrame() {
        for entry in hostedTrees { entry.tree?.sceneNeedsFrame() }
        guard !needsFrame else { return }
        needsFrame = true
        onNeedsFrame?()
    }

    public func advanceFrame(elapsed: Double) -> Bool {
        CATransaction.commitImplicit()
        runTimers(elapsed: elapsed)
        let linked = advanceDisplayLinks(elapsed: elapsed)
        let animating = advanceAnimations(elapsed: elapsed)
        let scrolling = advanceScrolling(elapsed: elapsed)
        let spinning = advanceSpinners(elapsed: elapsed)
        return advanceHostingViews(elapsed: elapsed) || animating || scrolling || spinning || linked
    }

    /// Turns the animating activity indicators; true while any is on screen.
    private func advanceSpinners(elapsed: Double) -> Bool {
        spinners.removeAll { $0.view == nil || $0.view?.isAnimating == false }
        for spinner in spinners { spinner.view?.advance(elapsed: elapsed) }
        return !spinners.isEmpty
    }

    /// Advances the timers and animations for a host whose frame loop drives a hosted tree (the
    /// scene's own host goes through `advanceFrame`); returns whether either still runs.
    func advanceTimers(elapsed: Double, hostFrame: AnyHashable? = nil) -> Bool {
        if let hostFrame {
            guard hostFrame != lastHostFrame else { return isAnimating || !decelerating.isEmpty || !timers.isEmpty }
            lastHostFrame = hostFrame
        }
        runTimers(elapsed: elapsed)
        let linked = advanceDisplayLinks(elapsed: elapsed)
        let animating = advanceAnimations(elapsed: elapsed)
        let scrolling = advanceScrolling(elapsed: elapsed)
        let spinning = advanceSpinners(elapsed: elapsed)
        let hosting = advanceHostingViews(elapsed: elapsed)
        return animating || scrolling || spinning || hosting || linked || !timers.isEmpty
    }
    /// The host frame the clocks were last advanced for (`UIKitHostedTree.advanceFrame`).
    private var lastHostFrame: AnyHashable?

    public func layout(in size: CGSize) {
        needsFrame = false
        if UIScreen.main.bounds.size != size {
            UIScreen.main.bounds = CGRect(origin: .zero, size: size)
            for window in windows { window.frame = UIScreen.main.bounds }
            // The size classes follow the host's size; a change reaches every tree.
            let previous = UIScreen.main.traitCollection
            Self.applySizeClasses(for: size)
            if UIScreen.main.traitCollection != previous {
                UITraitCollection.current = UIScreen.main.traitCollection
                for window in windows { window.propagateTraitChange(from: previous) }
            }
        }
        for window in windows {
            window.layoutIfNeeded()
            window.completePendingAppearances()
        }
        // Appearance callbacks may have changed the tree.
        for window in windows { window.layoutIfNeeded() }
    }

    public func render(scale: CGFloat) -> DisplayList { render(scale: scale, background: true) }

    /// The frame's display list; `background` paints the black screen behind the windows (off
    /// for goldens, which are transparent outside the views).
    public func render(scale: CGFloat, background: Bool) -> DisplayList {
        var list = DisplayList()
        let context = PaintContext(origin: .zero, scale: scale)
        let style = UIScreen.main.traitCollection.userInterfaceStyle
        // The screen behind the windows is black, as on a device.
        if background { list.append(.fillRect(context.absoluteRect(UIScreen.main.bounds), .black)) }
        for window in windows where !window.isHidden {
            window.layer.paint(into: &list, context: context, style: style)
        }
        focusSystem.paintFocusRing(into: &list, context: context)
        paintDragPreview(into: &list, context: context, style: style)
        return list
    }

    /// The drag in flight (Events/DragDrop.swift).
    var dragSession: DragDropSession?

    public func imageLoadDidFinish() { setNeedsFrame() }

    // MARK: Timers (long presses; `Timer` does not fire on wasm)

    public final class Timer {
        var remaining: Double
        let action: @MainActor () -> Void
        var cancelled = false
        init(remaining: Double, action: @escaping @MainActor () -> Void) { self.remaining = remaining; self.action = action }
        public func cancel() { cancelled = true }
    }

    private var timers: [Timer] = []

    /// Runs `action` after `seconds` of frame time.
    @discardableResult
    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(remaining: seconds, action: action)
        timers.append(timer)
        setNeedsFrame()
        return timer
    }

    private func runTimers(elapsed: Double) {
        guard !timers.isEmpty else { return }
        for timer in timers where !timer.cancelled {
            timer.remaining -= elapsed
        }
        let due = timers.filter { !$0.cancelled && $0.remaining <= 0 }
        timers.removeAll { $0.cancelled || $0.remaining <= 0 }
        for timer in due { timer.action() }
        if !timers.isEmpty { setNeedsFrame() }
    }

    // MARK: Touches

    private let touches = TouchRouter()

    public func pointerDown(at point: CGPoint, type: PointerType, time: Double) {
        guard let window = windows.last(where: { !$0.isHidden }) else { return }
        touches.pointerDown(at: point, in: window, type: type, time: time)
    }

    /// A move while pressing drags; one without a press hovers the view under the pointer.
    public func pointerMoved(to point: CGPoint, time: Double) {
        if touches.isPressing {
            touches.pointerMoved(to: point, time: time)
        } else {
            hover.update(to: point, in: windows.last(where: { !$0.isHidden }))
        }
    }

    public func pointerLeft() {
        hover.update(to: nil, in: nil)
    }

    private let hover = HoverRouter()

    public func pointerUp(at point: CGPoint, time: Double) {
        touches.pointerUp(at: point, time: time, cancelled: point.x < 0 && point.y < 0)
    }

    public func secondaryPointerDown(at point: CGPoint) {}

    /// The pinch and rotation recognizers on the view under the pinch's centre and its
    /// superviews, fixed when the pinch begins; both see every phase (the first to begin wins
    /// unless a delegate lets them recognize simultaneously).
    private var pinchRecognizers: [UIGestureRecognizer] = []

    public func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: Double, at point: CGPoint, time: Double) {
        if phase == .began {
            guard let window = windows.last(where: { !$0.isHidden }) else { return }
            var recognizers: [UIGestureRecognizer] = []
            var view = window.hitTest(window.convert(point, from: nil), with: nil)
            while let v = view {
                recognizers += (v.gestureRecognizers ?? []).filter { $0.isEnabled && ($0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer) }
                view = v.superview
            }
            pinchRecognizers = recognizers
            for recognizer in recognizers { recognizer.outcomeThisTouch = nil; recognizer.deferredState = nil; recognizer.pinchPeers = recognizers }
        }
        for recognizer in pinchRecognizers { recognizer.pinch(phase, scale: scale, rotation: rotation, location: point, time: time) }
        TouchRouter.arbitrate(pinchRecognizers, touchEnded: phase == .ended || phase == .cancelled)
        if phase == .ended || phase == .cancelled {
            for recognizer in pinchRecognizers { recognizer.hasRecognizedThisFrame = false; recognizer.outcomeThisTouch = nil; recognizer.pinchPeers = nil }
            pinchRecognizers = []
        }
        setNeedsFrame()
    }

    public func scrollWheel(by delta: CGSize, at point: CGPoint) {
        guard let window = windows.last(where: { !$0.isHidden }) else { return }
        var view = window.hitTest(point, with: nil)
        while let v = view {
            if v._hostedScrollWheel(by: delta, at: v.convert(point, from: nil)) { setNeedsFrame(); return }
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled {
                if scroll.scroll(by: delta) { setNeedsFrame(); return }
            }
            view = v.superview
        }
    }

    /// Keys (Events/Keyboard.swift): key commands, presses down the responder chain, focus navigation.
    public let focusSystem = UIFocusSystem()
    var activePresses: [KeyEquivalent: UIPress] = [:]
    var pressUnhandled = false
    public func keyDown(_ event: KeyEvent) -> Bool { dispatchKeyDown(event) }
    public func keyUp(_ event: KeyEvent) -> Bool { dispatchKeyUp(event) }

    /// A bundled font the host loaded is available: labels measured with a fallback face lay
    /// out again (frames an app fixed with `sizeToFit` before the font arrived stay as they are).
    /// UIKit's symbols take their sizes from the built-in table (the SwiftUI runtime loads the full one).
    public var onNeedsSymbolMetrics: (() -> Void)?
    /// A UIKit scene has no colour wells; the hook is for SwiftUI runtimes.
    public var colorPanelHandler: ((ColorPanelRequest) -> Bool)?
    public func symbolMetricsDidLoad(_ table: [String: [Double]]) {}

    public func fontsDidLoad() {
        for window in windows { window.fontsDidLoadRecursively() }
        setNeedsFrame()
    }
    /// The cursor the hovered pointer interaction asks for (Events/Hover.swift).
    public var pointerCursor: String? { dragSession != nil ? "grabbing" : hover.cursor }

    // MARK: Semantics

    /// Above every range SwiftUIWeb's own elements use (its static elements sit at
    /// 10_000_000 plus 23 bits), so a hosted tree's identifiers never collide with the host's.
    nonisolated(unsafe) private static var identifierCounter = 20_000_000

    static func nextSemanticsIdentifier() -> Int {
        identifierCounter += 1
        return identifierCounter
    }

    public func semanticsTree() -> [SemanticsNode] {
        var nodes: [SemanticsNode] = []
        for window in windows where !window.isHidden {
            window.collectSemantics(into: &nodes)
        }
        return nodes
    }

    private func view(withSemanticsIdentifier identifier: Int) -> UIView? {
        for window in windows {
            if let found = window.descendant(withSemanticsIdentifier: identifier) { return found }
        }
        return nil
    }

    public func activate(semanticsIdentifier: Int) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedActivate(semanticsIdentifier: semanticsIdentifier); setNeedsFrame(); return }
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        view.accessibilityActivate()
        setNeedsFrame()
    }

    /// Runs an element's custom action by name (the overlay's action buttons); "escape" and
    /// "magicTap" run the view's `accessibilityPerformEscape` / `accessibilityPerformMagicTap`.
    public func performAccessibilityAction(semanticsIdentifier: Int, name: String) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedPerformAccessibilityAction(semanticsIdentifier: semanticsIdentifier, name: name); setNeedsFrame(); return }
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        switch name {
        case "escape": _ = view.accessibilityPerformEscape()
        case "magicTap": _ = view.accessibilityPerformMagicTap()
        default: _ = view.performAccessibilityCustomAction(named: name)
        }
        setNeedsFrame()
    }

    /// What `UIAccessibility.post` queued for the host's assistive layer (announcements, focus
    /// moves); the host takes them after it has synced the overlay for the frame.
    public var accessibilityEvents: [AccessibilityEvent] = []

    public func takeAccessibilityEvents() -> [AccessibilityEvent] {
        var events = accessibilityEvents
        accessibilityEvents.removeAll()
        for entry in hostingViews { events += entry.view?._hostedTakeAccessibilityEvents() ?? [] }
        return events
    }

    public func adjust(semanticsIdentifier: Int, increment: Bool) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedAdjust(semanticsIdentifier: semanticsIdentifier, increment: increment); setNeedsFrame(); return }
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        if increment { view.accessibilityIncrement() } else { view.accessibilityDecrement() }
        setNeedsFrame()
    }

    public func setValue(semanticsIdentifier: Int, value: Double) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedSetValue(semanticsIdentifier: semanticsIdentifier, value: value); setNeedsFrame(); return }
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier) else { return }
        view.accessibilitySetValue(value)
        setNeedsFrame()
    }

    public func focus(semanticsIdentifier: Int?, keyboard: Bool) {
        if let semanticsIdentifier, let host = hostingView(handling: semanticsIdentifier) {
            host._hostedFocus(semanticsIdentifier: semanticsIdentifier, keyboard: keyboard)
            return
        }
        guard let semanticsIdentifier, let view = view(withSemanticsIdentifier: semanticsIdentifier) else {
            // Focus left every element: the hosting views hear about it.
            for entry in hostingViews { entry.view?._hostedFocus(semanticsIdentifier: nil, keyboard: keyboard) }
            return
        }
        if view.canBecomeFirstResponder { _ = view.becomeFirstResponder() }
    }

    public func blur(semanticsIdentifier: Int) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedBlur(semanticsIdentifier: semanticsIdentifier); return }
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier), view.isFirstResponder else { return }
        _ = view.resignFirstResponder()
    }

    public var focusedIdentifier: Int? { (firstResponder as? UIView)?.semanticsIdentifier ?? hostedFocusedTextFieldIdentifier }
    public var focusedTextFieldIdentifier: Int? {
        if let field = firstResponder as? any HostTextInput { return field.semanticsIdentifier }
        if let view = firstResponder as? UIView, view is any UIKeyInput { return view.semanticsIdentifier }
        return hostedFocusedTextFieldIdentifier
    }
    /// The shadows of the key-input views the host types into (Controls/UITextInput.swift).
    var keyInputShadows: [ObjectIdentifier: (shadow: HostKeyInputShadow, view: WeakView)] = [:]

    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedTextField(semanticsIdentifier, didChange: text); setNeedsFrame(); return }
        let target = view(withSemanticsIdentifier: semanticsIdentifier)
        if let field = target as? any HostTextInput { field.hostDidChange(text) } else if let view = target, view is any UIKeyInput { relayHostText(text, to: view) }
        setNeedsFrame()
    }

    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedTextFieldDidSubmit(semanticsIdentifier); setNeedsFrame(); return }
        let target = view(withSemanticsIdentifier: semanticsIdentifier)
        if let field = target as? any HostTextInput { field.hostDidSubmit() } else if let view = target, view is any UIKeyInput { relayHostSubmit(to: view) }
        setNeedsFrame()
    }

    public func textField(_ semanticsIdentifier: Int, selectionStart start: Int, end: Int) {
        guard let view = view(withSemanticsIdentifier: semanticsIdentifier), view is any UITextInput else { return }
        relayHostSelection(start: start, end: end, to: view)
    }

    public func textField(_ semanticsIdentifier: Int, focused: Bool) {
        if let host = hostingView(handling: semanticsIdentifier) { host._hostedTextField(semanticsIdentifier, focused: focused); setNeedsFrame(); return }
        guard let field = view(withSemanticsIdentifier: semanticsIdentifier), field is any HostTextInput || field is any UIKeyInput else { return }
        if focused { _ = field.becomeFirstResponder() } else if field.isFirstResponder { _ = field.resignFirstResponder() }
        setNeedsFrame()
    }
}

/// The engine before a host installs one: nothing measures, so layout stays finite.
@preconcurrency @MainActor
final class PlaceholderTextEngine: TextEngine {
    func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        TextLayout(size: .zero, firstBaseline: 0, lastBaseline: 0, lines: [])
    }
    func metrics(for font: ResolvedFont) -> FontMetrics { .plain }
}

extension UIView {
    /// Publishes this view's window frame under `name` in the scene's probe frames (tests and
    /// the gallery read them like SwiftUIWeb's `_probe`).
    public func publishFrame(as name: String) {
        UIKitScene.shared.probes[name] = convert(bounds, to: nil)
    }

    /// The semantics node for this view, or nil when it is not an accessibility element.
    func semanticsNode() -> SemanticsNode? {
        // A key-input view is an element whatever the app said: the host's text element needs it.
        guard isAccessibilityElement || (self is any UIKeyInput && canBecomeFirstResponder) else { return nil }
        let role: SemanticsNode.Role
        let traits = accessibilityTraits
        if traits.contains(.button) { role = .button }
        else if traits.contains(.link) { role = .link }
        else if traits.contains(.image) { role = .image }
        else if traits.contains(.header) { role = .heading }
        else if traits.contains(.adjustable) { role = .slider }
        else if self is UITextField { role = .textField }
        else if self is UISwitch { role = .switch }
        else { role = .text }
        var node = SemanticsNode(role: role, label: accessibilityLabel ?? "", frame: accessibilityFrame, identifier: semanticsIdentifier)
        node.value = accessibilityValue
        node.hint = accessibilityHint
        node.accessibilityIdentifier = accessibilityIdentifier
        node.isAdjustable = traits.contains(.adjustable)
        node.isEnabled = !traits.contains(.notEnabled)
        if traits.contains(.selected) { node.isSelected = true }
        node.isLive = traits.contains(.updatesFrequently)
        node.customActions = accessibilityCustomActions?.map { $0.name } ?? []
        decorateSemantics(&node)
        // An app's own key-input view takes the host's text element (Controls/UITextInput.swift).
        if node.textInput == nil, let info = UIKitScene.shared.keyInputInfo(for: self) {
            node.role = .textField
            node.textInput = info
        }
        return node
    }
}
