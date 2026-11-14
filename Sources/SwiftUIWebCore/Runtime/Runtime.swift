#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
/// Owns one mounted view tree, its scheduler and (from step 9) the layout and painting
/// pipeline. Hosts (canvas, headless) create one runtime per window.
@MainActor
public final class Runtime {
    package let scheduler = UpdateScheduler()
    package private(set) var root: RootNode!

    /// Measures and breaks text. Hosts install their engine before the first layout.
    public var textEngine: any TextEngine = ZeroTextEngine() {
        didSet {
            textLayouts.removeAll()
            if !(textEngine is ZeroTextEngine) { Self.hostTextEngine = textEngine }
        }
    }

    /// The text engine and asset catalog a host last installed: a runtime a view makes on its
    /// own (`ImageRenderer`) measures and draws with them.
    package static var hostTextEngine: (any TextEngine)?
    package static var hostAssetCatalog: AssetCatalog?

    /// Finished text layouts by their inputs, kept across frames: a scroll or an unrelated state
    /// change lays the whole tree out again, and line breaking every text on a page each frame
    /// dominated frame times (1.2 s on the landing page). Bounded by size, cleared when the
    /// engine changes.
    private var textLayouts: [TextLayoutKey: TextLayout] = [:]
    private struct TextLayoutKey: Hashable {
        let runs: [StyledRun]
        let options: TextLayoutOptions
        let width: CGFloat?
    }

    /// `textEngine.layout` through the cross-frame cache.
    package func layoutText(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let key = TextLayoutKey(runs: runs, options: options, width: width)
        if let cached = textLayouts[key] { return cached }
        if textLayouts.count >= 8192 { textLayouts.removeAll(keepingCapacity: true) }
        let layout = textEngine.layout(runs, options: options, width: width)
        textLayouts[key] = layout
        return layout
    }

    /// A single string in one font through the cache.
    package func layoutText(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout {
        layoutText([StyledRun(string, font: font)], options: .default, width: width)
    }

    /// Environment the root view is mounted in.
    package var rootEnvironment: EnvironmentValues
    /// The last `navigationTitle` applied in the tree, for hosts (window or document title).
    public internal(set) var navigationTitle: String?

    /// The system appearance, set by hosts; the root environment follows it unless the tree
    /// prefers one (`preferredColorScheme`).
    public var hostColorScheme: ColorScheme = .light {
        didSet { if hostColorScheme != oldValue { requestLayout() } }
    }
    /// The system's reduce-motion setting, set by hosts (`prefers-reduced-motion`); the root
    /// environment's `accessibilityReduceMotion` follows it.
    public var hostReducesMotion = false {
        didSet {
            guard hostReducesMotion != oldValue else { return }
            rootEnvironment.accessibilityReduceMotion = hostReducesMotion
            root.environment = rootEnvironment
            root.reapply?(rootEnvironment)
            requestFullLayout()
        }
    }
    /// The system's increase-contrast setting, set by hosts; the root environment's
    /// `colorSchemeContrast` follows it (views decide what to strengthen; nothing built in does).
    public var hostIncreasesContrast = false {
        didSet {
            guard hostIncreasesContrast != oldValue else { return }
            rootEnvironment.colorSchemeContrast = hostIncreasesContrast ? .increased : .standard
            root.environment = rootEnvironment
            root.reapply?(rootEnvironment)
            requestFullLayout()
        }
    }
    /// The user's text size (a content size category short name), set by hosts; the root
    /// environment's `dynamicTypeSize` follows it (sw-dynamic-type).
    public var hostDynamicTypeSize: String? {
        didSet {
            guard hostDynamicTypeSize != oldValue else { return }
            rootEnvironment.dynamicTypeSize = hostDynamicTypeSize.flatMap { DynamicTypeSize(_categoryName: $0) } ?? .large
            root.environment = rootEnvironment
            root.reapply?(rootEnvironment)
            sizesInvalidated = true
            requestFullLayout()
        }
    }
    /// The host's pixels per point, set by hosts; the root environment's `displayScale`.
    public var hostDisplayScale: CGFloat = 2 {
        didSet {
            guard hostDisplayScale != oldValue, hostDisplayScale > 0 else { return }
            rootEnvironment.displayScale = hostDisplayScale
            root.environment = rootEnvironment
            root.reapply?(rootEnvironment)
            requestFullLayout()
        }
    }
    /// Whether the page is visible and focused, set by hosts; `scenePhase` follows (active while
    /// visible and focused, inactive while visible, background while hidden).
    public var hostIsVisible = true {
        didSet {
            guard hostIsVisible != oldValue else { return }
            applyScenePhase()
            hostVisibilityChangedForTimelines()
            for observer in Self._hostLifecycleObservers { observer(hostIsVisible, hostIsFocused) }
        }
    }
    public var hostIsFocused = true {
        didSet {
            guard hostIsFocused != oldValue else { return }
            applyScenePhase()
            for observer in Self._hostLifecycleObservers { observer(hostIsVisible, hostIsFocused) }
        }
    }
    /// Told of every visibility or focus change of any runtime (a UIKit app delegate's scene
    /// follows the page, decision 0021).
    public static var _hostLifecycleObservers: [@MainActor (_ visible: Bool, _ focused: Bool) -> Void] = []
    public var scenePhase: ScenePhase { !hostIsVisible ? .background : (hostIsFocused ? .active : .inactive) }

    private func applyScenePhase() {
        guard rootEnvironment.scenePhase != scenePhase else { return }
        rootEnvironment.scenePhase = scenePhase
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
        requestFullLayout()
    }

    /// The modifier keys held as the last pointer event arrived (`pointerModifiersChanged`).
    public var pointerModifiers: EventModifiers = []
    /// The host's time of the last key event (type-to-select groups keys within a second).
    package var lastKeyTime: Double = 0
    /// The `simultaneousGesture` nodes above the pressed node, fed the press in flight.
    package var simultaneousPressNodes: [ViewNode & _Interactive] = []
    /// The gesture nodes taking the pinch in flight.
    package var pinchNodes: [ViewNode & _PinchTarget] = []
    /// The mounted `focusedValue` nodes and the views reading focused values.
    package var focusedValueNodes: [WeakNode] = []
    package var focusedValueObservers: [WeakNode] = []
    /// The mounted `onOpenURL` and `onContinueUserActivity` handlers, in tree order.
    package var openURLHandlers: [WeakNode] = []
    package var activityHandlers: [WeakNode] = []
    /// Completion callbacks claimed from transactions, waiting for the next layout to start
    /// their animation's clock.
    package var pendingAnimationCompletions: [_AnimationCompletion] = []
    package var activeAnimationCompletions: [(entry: _AnimationCompletion, animation: Animation?, start: Double)] = []
    /// The platform whose look the tree reproduces, set by hosts (the canvas host picks iOS on a
    /// touch device, macOS elsewhere; `Docs/elements/iOS.md`). A subtree can still select the
    /// other one through the `platformProfile` environment value.
    public var hostPlatformProfile: PlatformProfile {
        get { rootEnvironment.platformProfile }
        set { applyPlatformProfile(newValue) }
    }
    /// The `preferredColorScheme` in the tree, if any.
    package var preferredColorScheme: ColorScheme? {
        didSet { if preferredColorScheme != oldValue { requestLayout() } }
    }
    /// The window's override, set through UIKit (`UIWindow.overrideUserInterfaceStyle` on the
    /// window a SwiftUI app's scene stands behind; Ember's appearance setting, decision 0021):
    /// between the tree's preference and the host's scheme.
    public var interfaceStyleOverride: ColorScheme? {
        didSet { if interfaceStyleOverride != oldValue { requestLayout() } }
    }
    /// The scheme the window shows: the preferred one, else the window's override, else the
    /// host's. Hosts paint their background with it (`paintsWindowBackground`).
    public var effectiveColorScheme: ColorScheme { rootEnvironment.colorScheme }
    /// Whether `render` starts with the window background (hosts: yes; fixtures and tests: no,
    /// their goldens are transparent).
    public var paintsWindowBackground = false

    /// The host's safe area (a `UIHostingController` under a navigation bar; a browser page has
    /// none): the root view is laid out inside it unless it extends into it, as under a
    /// `safeAreaPadding` (ios/representable/hostingsafearea).
    public var safeAreaInsets = EdgeInsets() {
        didSet { if safeAreaInsets != oldValue { requestLayout(invalidatingSizes: true) } }
    }

    /// Whether the runtime draws window chrome a browser page lacks: the toolbar
    /// (`Runtime/ToolbarNodes.swift`). Hosts with a real title bar leave it off or keep the title
    /// out of the bar (`chromeShowsTitle`).
    public var paintsWindowChrome = false {
        didSet { if paintsWindowChrome != oldValue { requestFullLayout() } }
    }
    public var chromeShowsTitle = true
    package var toolbarSources: [ToolbarSource] = []
    /// The `toolbar` items registered in the tree, for hosts that show them in their own bars
    /// (a `UIHostingController`'s navigation item).
    public var _toolbarItems: [_ToolbarItemData] { toolbarSources.flatMap(\.items) }
    package var toolbarVisibility: [ToolbarVisibilitySource] = []
    package var toolbarBackgrounds: [ToolbarBackgroundSource] = []
    package var toolbarRoles: [ToolbarRoleSource] = []
    /// The user's show/hide choices per customisable toolbar (`toolbar(id:)`), for the session.
    package var toolbarCustomization: [String: [AnyHashable: Bool]] = [:]
    package var toolbar: ToolbarChromeNode?
    package var searchSources: [SearchSource] = []
    /// Whether controls paint as in an active window: the accent-coloured checkbox and switch
    /// track. Off by default, as the goldens come from inactive windows; a host may turn it on
    /// (Docs/elements/Toggle.md).
    public var windowIsActive = false
    package var searchSuggestionSources: [SearchSuggestionSource] = []
    package var searchScopeSources: [SearchScopeSource] = []
    package var _imageLoader: (any _ImageLoading)?
    /// `AsyncImage` views per URL still mounted (cancellation on the last unmount).
    package var imageLoadUses: [String: Int] = [:]
    /// The host's rasteriser for recorded drawings (`UIImage.pngData()` inside a representable;
    /// hosted trees take it from the runtime).
    public var imageRasterizer: ImageRasterizer?
    package var asyncImageNodes: [WeakAsyncImageNode] = []

    // Animation (Runtime/AnimationNodes.swift)
    /// Seconds of animation time, advanced by hosts through `advanceAnimations(elapsed:)`.
    package var animationClock: Double = 0
    /// The transaction animation recorded when state changed; consumed by the next layout.
    package var pendingAnimation: Animation?
    /// The nodes a repeating transaction animation (`repeatForever`) invalidated: it animates
    /// their subtrees alone. The flush and layout apply every change of a pass together, so a
    /// transaction's animation otherwise reaches changes made outside it — harmless for one
    /// that ends, not for one that does not: a skeleton's shimmer landing on a list row that
    /// appeared in the same pass would keep the scene animating, and laying out, for good.
    package var pendingRepeatingScopes: [WeakNode] = []
    package var repeatingAnimationScopes: [WeakNode] = []
    /// The animation in effect while nodes update (transitions, opacity and colour changes).
    package var updateAnimation: Animation?
    /// The animation in effect while nodes are placed (frame changes).
    package var layoutAnimation: Animation?
    package var isLayingOut = false
    /// Set for the whole of a full `layout(in:)` — the flush of pending updates included, which
    /// precedes `isLayingOut` — so an update knows which pass it belongs to.
    package private(set) var inLayoutPass = false
    /// The full layout pass an update applied now belongs to: the one running, else the next
    /// (an animation scope marks its subtree's placements for that pass; the memo generation
    /// no longer moves with every update, so it cannot name the pass).
    package var upcomingLayoutPass: UInt64 { inLayoutPass ? fullLayoutCount : fullLayoutCount + 1 }
    package var activeAnimationScopes = 0
    package var animatingNodes: [WeakNode] = []
    /// Paint-only animations in flight (a navigation stack's slide): frames keep coming through
    /// the frame subscribers, sizes stay valid.
    package var paintAnimations = 0

    /// Sheets, popovers, alerts and menus over the window, bottom to top (Runtime/PresentationNodes.swift).
    package var presentations: [PresentationNode] = []
    /// iOS sheets dismissed but still sliding off the bottom: painted under the presentations,
    /// never hit, unmounted when they are gone (Runtime/PresentationNodes.swift).
    package var leavingPresentations: [PresentationNode] = []
    /// The app's pasteboard (Runtime/PasteboardNodes.swift) and the host's clipboard writer for text.
    package var pasteboard: [_TransferItem] = []
    public var clipboardWriter: ((String) -> Void)?
    /// The host's share sheet and file panels (hosted UIKit trees use them too; the runtime's
    /// own sharing goes through `ShareAction.systemHandler`, its documents through the handlers
    /// in Runtime/DocumentNodes.swift).
    public var shareHandler: ((HostShareRequest) -> Void)?
    public var fileOpenHandler: ((HostFileOpenRequest, _ completion: @escaping @MainActor @Sendable ([HostFile]) -> Void) -> Void)?
    public var fileSaveHandler: ((HostFile) -> Void)?
    /// Window scenes and the secondary windows opened from them (Runtime/WindowNodes.swift).
    package var windowDescriptors: [_WindowDescriptor] = []
    package var windowStore: (get: () -> String?, set: (String) -> Void)?
    package var documentOpen: ((_ types: [UTType], _ completion: @escaping @MainActor @Sendable (Data, String, URL?) -> Void) -> Void)?
    package var documentSave: ((_ data: Data, _ name: String, _ type: UTType, _ existing: URL?) -> URL?)?
    /// The app's menu commands (`Scene.commands`), mounted in a hidden tree so their shortcuts
    /// work; hosts with a menu bar read `commandMenus` (Runtime/CommandMenuNodes.swift).
    package var commandMenuData: [_CommandMenuData] = []
    package var commandsRoots: [TypedNode<AnyView>] = []
    /// The secondary window a press last landed in: Tab cycles its controls (sw-windows).
    package weak var keyWindow: PresentationNode?
    package var openWindows: [OpenWindow] = []
    package var nextWindowIdentity = 1
    /// Drag and drop (Runtime/DragDropNodes.swift): the drag in progress and the source a press may lift.
    package var dragSession: DragSession?
    package var pendingDrag: (source: ViewNode & _DragSource, start: CGPoint)?
    /// Frames recorded by `matchedGeometryEffect` sources (Runtime/MatchedGeometryNodes.swift).
    package var matchedGeometry: [MatchedGeometryKey: MatchedGeometryRecord] = [:]
    /// Timeline views re-rendering every frame (Runtime/TimelineNodes.swift).
    package var frameSubscribers: [WeakFrameSubscriber] = []
    /// The mounted timeline views, told when the host hides or shows (`TimelineNode`).
    package var timelines: [WeakTimeline] = []
    /// Focus states told when the focused text field changes (Runtime/FocusNodes.swift).
    package var focusBoxes: [WeakFocusBox] = []

    private let assetStore = _AssetStore()

    /// The app's asset catalogs (images and colours by name). Hosts install theirs before the
    /// first layout; replacing it later re-evaluates the mounted tree.
    public var assetCatalog: AssetCatalog {
        get { assetStore.catalog }
        set {
            assetStore.catalog = newValue
            Self.hostAssetCatalog = newValue
            AssetCatalog.app = newValue
            CustomFontRegistry.register(newValue)
            textLayouts.removeAll()
            root.child?.invalidate()
            // Images and custom-font texts size from the catalog, not from their view values:
            // every memoised size goes (the next layout bumps the generation).
            requestLayout()
        }
    }

    /// A bundled font arrived in the host: text laid out with a fallback face is measured again.
    public func fontsDidLoad() {
        textLayouts.removeAll()
        requestLayout()
    }

    /// Set by a host that can fetch the full symbol layout table; called once, on the first
    /// symbol outside the built-in set (`ImageNode` sizes it like the star until then).
    public var onNeedsSymbolMetrics: (() -> Void)?
    /// The host's system colour chooser, when it has one (`HostedScene.colorPanelHandler`).
    public var colorPanelHandler: ((ColorPanelRequest) -> Bool)?
    private var requestedSymbolMetrics = false
    /// The full catalog's layout sizes once loaded (`SystemSymbolMetricsTable.parse`), this
    /// scene's own so tests and scenes never share mutable state.
    public private(set) var extendedSymbolMetrics: [String: [Double]] = [:]
    package var isSymbolMetricsExtended: Bool { !extendedSymbolMetrics.isEmpty }

    package func requestSymbolMetrics() {
        guard !requestedSymbolMetrics, !isSymbolMetricsExtended, let onNeedsSymbolMetrics else { return }
        requestedSymbolMetrics = true
        onNeedsSymbolMetrics()
    }

    /// The full table arrived: symbols laid out with the fallback size measure again.
    public func symbolMetricsDidLoad(_ table: [String: [Double]]) {
        extendedSymbolMetrics = table
        // The symbol images resolve again (their sizes were the star's); a tree not yet laid
        // out keeps its lifecycle counts (`ios/representable/lifecycle`) and lays out once.
        for node in root.descendants(where: { $0 is ImageNode }) { (node as? ImageNode)?.symbolMetricsDidLoad() }
        sizesInvalidated = true
        layoutGeneration += 1
        guard fullLayoutCount > 0 else { return }
        requestLayout()
    }

    public init(environment: EnvironmentValues = EnvironmentValues()) {
        var environment = environment
        environment[AssetStoreKey.self] = assetStore
        self.rootEnvironment = environment
        hostColorScheme = environment.colorScheme
        self.root = RootNode(runtime: self, environment: environment)
        installPasteboard()
        rootEnvironment.resetFocus = ResetFocusAction(runtime: self)
        root.environment = rootEnvironment
    }

    /// Moves the root environment to the effective scheme when it changed, re-applying the
    /// root view so every node resolves its colours again.
    private func applyColorScheme() {
        let effective = preferredColorScheme ?? interfaceStyleOverride ?? hostColorScheme
        guard effective != rootEnvironment.colorScheme else { return }
        rootEnvironment.colorScheme = effective
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
        for presentation in presentations { presentation.applyPreferredColorScheme() }
        sizesInvalidated = true
        layoutGeneration += 1
    }

    /// Moves the root environment to another platform profile, re-applying the root view so
    /// every node lays out and paints in the new look.
    private func applyPlatformProfile(_ profile: PlatformProfile) {
        guard profile.name != rootEnvironment.platformProfile.name else { return }
        rootEnvironment.platformProfile = profile
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
        sizesInvalidated = true
        layoutGeneration += 1
        requestLayout()
    }

    /// Asks the host for another frame without a state change (an image finished loading).
    public func setNeedsDisplay(file: StaticString = #fileID, line: UInt = #line) {
        requestLayout(file: file, line: line)
    }

    /// Mounts `view` as the root, replacing any previous root view.
    @discardableResult
    public func mount<V: View>(_ view: V) -> TypedNode<V> {
        // A root replaced or updated outside the scheduler changes sizes like any update would.
        sizesInvalidated = true
        return root.mount(view)
    }

    /// Applies pending invalidations (top-down by depth). Hosts call this once per frame.
    package func flush() {
        scheduler.flush()
    }

    /// Applies pending invalidations before a host measures the tree outside a layout pass (a
    /// hosting view's `sizeThatFits`): a re-mounted or updated root drops the memoised sizes,
    /// which only a layout would otherwise do (ios/representable/hostingcollection: a reused
    /// cell measured its previous content).
    package func flushForMeasurement() {
        let pending = scheduler.hasPendingWork
        flush()
        guard pending || sizesInvalidated else { return }
        // The flushed change still needs a layout: the next `layout(in:)` must not take a
        // no-work path (ios/representable/hostingsizing: the stack measured the hosting view
        // before its layout).
        layoutGeneration += 1
        sizesInvalidated = true
        layoutRequested = true
    }

    /// Incremented at the start of every layout pass; size caches are keyed by it.
    package private(set) var layoutGeneration: UInt64 = 0

    /// Forgets every memoised size within a layout pass (lazy elements were just created).
    package func invalidateSizeMemos() { layoutGeneration += 1 }

    /// Counts the layout passes that walked the tree (not the ones that only moved scrolled
    /// content); the semantics tree is cached against it (`semanticsTree()`).
    package private(set) var fullLayoutCount: UInt64 = 0
    package var semanticsCache: [SemanticsEntry] = []
    package var semanticsCacheLayout: UInt64 = .max
    /// Whether the cached semantics tree still describes the nodes: no full layout since it was
    /// walked, and no state update or invalidation waiting for the next one (a typed character
    /// or a slider press changes a binding before any layout runs).
    package var semanticsCacheIsValid: Bool {
        semanticsCacheLayout == fullLayoutCount && !scheduler.hasPendingWork && !sizesInvalidated
    }

    /// The size most recently laid out into.
    package private(set) var layoutSize: CGSize = .zero

    /// Frames recorded by `_probe` modifiers during the most recent layout pass.
    public internal(set) var probeFrames: [String: CGRect] = [:]

    /// `onPreferenceChange` nodes, evaluated after each layout pass.
    package var preferenceObservers: [WeakObserver] = []

    /// The interactive node a pointer is currently pressing, and the last pointer position.
    package var pressedNode: (ViewNode & _Interactive)?
    /// The `focusable` view the press began on while an interactive ancestor took the press.
    package var focusPressNode: (ViewNode & _Interactive)?
    /// The text whose selection is showing (`textSelection(.enabled)`): a press elsewhere clears it.
    package weak var textSelectionOwner: TextNode? {
        didSet { if let old = oldValue, old !== textSelectionOwner { old.clearSelection() } }
    }

    /// The text field with keyboard focus (its semantics identifier), for the focus ring.
    public internal(set) var focusedTextFieldIdentifier: Int?
    /// The element with keyboard focus (any interactive or focusable view; a focused text field
    /// sets both), and whether the focus ring shows (Runtime/KeyboardNodes.swift).
    public internal(set) var focusedIdentifier: Int?
    public internal(set) var focusVisible = false
    package var pointerPosition: CGPoint = .zero
    /// The host's time (seconds) of the last pointer event, for gesture timing.
    package var lastPointerTime: Double = 0
    /// The kind of pointer the last press came from (a hosted UIKit tree makes touches of it).
    package var lastPointerType: PointerType = .mouse
    /// The nodes hosting another framework's view trees (Runtime/PlatformViewNodes.swift).
    package var platformHosts: [WeakPlatformHost] = []
    /// The AppKit views representables made (API/NSViewRepresentable.swift) and the host that
    /// places them, when there is one.
    package var nativeViews: [WeakNativeView] = []
    package var nativeViewHostStorage: (any _NativeViewHosting)?
    /// The host showing window presentations as real windows (Runtime/HostedWindows.swift).
    package var realWindowHostStorage: (any _RealWindowHosting)?
    /// The host elements painted this render and the last complete one (API/HostElement.swift).
    package var hostElementsThisFrame: [HostElement] = []
    package var hostElementsLastFrame: [HostElement] = []
    /// The identifiers given to platform views that are host elements, by the view's identity
    /// (a web view keeps its frame across frames).
    package var platformHostElementIdentifiers: [ObjectIdentifier: Int] = [:]
    package var hostElementCounter = 0
    /// Counts the frames the hosted trees were advanced for (`_HostFrame`).
    package var hostFrameNumber: UInt64 = 0

    /// Hover state (Runtime/HoverNodes.swift): the nodes the pointer is over, the memoised
    /// tracking nodes, a pending or shown tooltip and the pointer style hosts apply.
    package var hovered: [ViewNode & _HoverTracking] = []
    package var hoverNodes: [ViewNode & _HoverTracking] = []
    package var hoverNodesGeneration: UInt64 = .max
    package var tooltip: TooltipState?
    /// The pointer style of the deepest hovered `pointerStyle` view, for the host's cursor.
    public private(set) var pointerStyle: PointerStyle?
    package func setPointerStyle(_ style: PointerStyle?) { pointerStyle = style }

    package func forgetHover(_ node: ViewNode) {
        hovered.removeAll { $0 === node }
    }

    /// A touch pan of scroll views in progress.
    package var pan: PanState?

    /// The trackpad gesture the last wheel event belonged to (`wheelGestureEvent`).
    package var wheelGesture: WheelGesture?
    /// The time of the wheel event being handled, when the host gave one.
    package var wheelEventTime: Double?
    /// Seconds on a steady clock, for wheel gestures; tests set their own.
    package var wheelClock: () -> Double = {
        let elapsed = ContinuousClock.now - _wheelClockOrigin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Scroll views with momentum or fading indicators (`advanceScrollAnimations`).
    package var animatingScrollNodes: [ViewNode & _Scrollable] = []

    /// Set when geometry changed without a state update (scrolling, `scrollTo`): the next frame
    /// must lay out again. Cleared by `layout(in:)`.
    public private(set) var layoutRequested = false

    /// Whether the host should produce another frame.
    public var needsFrame: Bool { scheduler.hasPendingWork || layoutRequested || tooltipPending }

    /// Whether the next layout may find different sizes: state updates, image loads and resizes
    /// say so; a scroll only moves content, so the memoised sizes stay valid across its frames.
    private var sizesInvalidated = true

    /// Scroll views whose offset changed since the last layout: when nothing else changed, the
    /// next frame moves their content instead of laying the tree out.
    private var scrolledNodes: [ViewNode & _Scrollable] = []

    /// Why the last `layout(in:)` walked the tree, or "moved"/"repaint" when it did not, with
    /// the pass's `sizeThatFits` calls and memo misses: the host's frame phases carry them, so
    /// a frame that should have moved scrolled content and laid out instead says what made it
    /// (`?perf`, Playwright's frame probes). The site of the last request that invalidated the
    /// memoised sizes is part of the reason.
    public private(set) var lastLayoutReason = ""
    public private(set) var lastLayoutMeasures = 0
    public private(set) var lastLayoutComputes = 0
    package var measureCount = 0
    package var computeCount = 0
    /// With `profileLayout` on, the last pass's recomputations by node description, and the
    /// distinct proposals per node (the host's `layoutProfile()`).
    public var profileLayout = false
    public private(set) var lastComputeHistogram: [String: Int] = [:]
    public private(set) var lastProposalHistogram: [String: Int] = [:]
    package var computeHistogram: [String: Int] = [:]
    package var proposalCounts: [ObjectIdentifier: (String, Int)] = [:]
    /// The proposals the most-recomputed node was computed for, in order (`layoutProfile().worst`).
    package var proposalLog: [ObjectIdentifier: [String]] = [:]
    package var profiledNodes: [ObjectIdentifier: ViewNode] = [:]
    package var shareProbes: [String: Int] = [:]
    public private(set) var lastShareProbes: [String: Int] = [:]
    public private(set) var lastWorstNodeChain: [String] = []
    public private(set) var lastWorstNodeProposals: [String] = []
    private var lastInvalidatingRequest = ""
    private var lastForcingRequest = ""

    package func noteScrolled(_ node: ViewNode & _Scrollable) {
        if !scrolledNodes.contains(where: { $0 === node }) { scrolledNodes.append(node) }
    }

    package func requestLayout(invalidatingSizes: Bool = true, file: StaticString = #fileID, line: UInt = #line) {
        repaintOnly = false
        if invalidatingSizes { sizesInvalidated = true; lastInvalidatingRequest = "\(file):\(line)" }
        guard !layoutRequested else { return }
        layoutRequested = true
        if !scheduler.hasPendingWork { scheduler.onNeedsFlush?() }
    }

    /// Whether the pending frame only repaints (a paint-only animation advanced): every frame
    /// in the tree is still right, so `layout` skips the pass. A layout request clears it.
    private var repaintOnly = false

    /// Whether the next frame must lay the tree out even if only scroll views moved (a
    /// navigation bar collapsed and its screen's frame changes).
    private var layoutForced = false

    /// Counts node creations, updates and removals: what a node derives from its subtree (the
    /// navigation bars from the titles and toolbars in it) stays valid while it is unchanged.
    package var treeVersion: UInt64 = 0
    /// Counts `requestFullLayout` calls (state outside the views changed: a search presented).
    package private(set) var fullLayoutRequests: UInt64 = 0

    /// Whether a placement may be kept (`ViewNode.place`): not in a pass that animates (it sets
    /// tweens from the frames it moves), one asked to place everything, or inside content that
    /// is placed whole (a scroll view's, whose lazy elements follow the viewport).
    package var mayKeepPlacements: Bool {
        keepsPlacements && !placesEverything && layoutAnimation == nil && wholePlacements == 0
    }
    /// Switch for the kept placements, for tests that compare with placing everything.
    package var keepsPlacements = true
    /// Set for a pass after `requestFullLayout`.
    private var placesEverything = false
    private var placesEverythingRequested = false
    /// Nesting of content placed whole (`ScrollNode`).
    package var wholePlacements = 0
    /// Placements kept in the last pass, for tests and the layout reason.
    package var keptPlacements = 0

    /// Asks for a layout pass that keeps the memoised sizes but re-places everything.
    package func requestFullLayout(file: StaticString = #fileID, line: UInt = #line) {
        placesEverythingRequested = true
        fullLayoutRequests &+= 1
        layoutForced = true
        lastForcingRequest = "\(file):\(line)"
        requestLayout(invalidatingSizes: false)
    }

    /// Asks for a frame for a change that moves no view and resizes none (a caret, a focus ring,
    /// a text editor's scroll): the tree is placed again with every memoised size kept, where
    /// `setNeedsDisplay` measures the whole tree again (new-website#216: every keystroke in a
    /// search field measured a whole app, 12,900 views, because the caret moved). The pass still
    /// runs, and the semantics the host reads before it (a field's selection and marked text)
    /// are walked again.
    package func requestRedraw(file: StaticString = #fileID, line: UInt = #line) {
        semanticsCacheLayout = .max
        layoutForced = true
        lastForcingRequest = "\(file):\(line)"
        requestLayout(invalidatingSizes: false, file: file, line: line)
    }

    /// Asks for a frame that paints the tree as it is laid out (a navigation slide advanced).
    package func requestRepaint() {
        let alone = !layoutRequested
        requestLayout(invalidatingSizes: false)
        if alone { repaintOnly = true }
    }

    /// Applies pending updates, then lays the tree out in a window of `size`. As in SwiftUI,
    /// the root view is proposed the full size and centred.
    public func layout(in size: CGSize) {
        updateAnimation = pendingAnimation
        if !pendingAnimationCompletions.isEmpty {
            // The animation of these completions starts now; without one they complete at once.
            for entry in pendingAnimationCompletions { activeAnimationCompletions.append((entry, pendingAnimation, animationClock)) }
            pendingAnimationCompletions.removeAll()
            if pendingAnimation == nil { fireAnimationCompletions(now: animationClock) }
        }
        // Actions queued since the last frame and nothing else (an `onGeometryChange` reporting
        // a scrolled position) run first: one that changes no view leaves the frame a move or a
        // repaint, where running it inside the pass made every scroll step lay the tree out
        // (new-website#216). The updates it does cause are applied here, as the pass would.
        let actionsUpdated = scheduler.hasPendingActionsOnly && scheduler.flush()
        var reason = ""
        if scheduler.hasPendingWork || actionsUpdated { reason = "update" }
        else if size != layoutSize { reason = "resize" }
        else if pendingAnimation != nil { reason = "animation" }
        else if sizesInvalidated { reason = "invalidated by " + lastInvalidatingRequest }
        // An animation beginning lays out (the pass sets the tweens from the frames it moves);
        // one in flight only paints, unless a layout parameter tweens (`advanceAnimations`). A
        // pending update lays out but keeps the memos: the nodes it touches forget their own
        // and their ancestors' as they are applied (`ViewNode.clearNeedsUpdate`).
        let updating = scheduler.hasPendingWork || actionsUpdated
        // An update that also invalidated every memoised size says what did: such a frame
        // measures the whole tree (new-website#216).
        if updating, sizesInvalidated, size == layoutSize, pendingAnimation == nil { reason += ", sizes invalidated by " + lastInvalidatingRequest }
        if size != layoutSize || pendingAnimation != nil { sizesInvalidated = true }
        // A frame that only scrolled moves the scrolled content and keeps every frame else.
        if !updating, !sizesInvalidated, !layoutForced, presentations.isEmpty, scrolledNodes.allSatisfy(\.canMoveContentOnly) {
            let moved = !scrolledNodes.isEmpty
            for node in scrolledNodes { node.moveContent() }
            scrolledNodes.removeAll()
            layoutRequested = false
            updateAnimation = nil
            lastLayoutReason = "moved"; lastLayoutMeasures = 0; lastLayoutComputes = 0
            // Moved content changed positions without a pass: `onGeometryChange` hears of it
            // (its action runs at the start of the next frame).
            if moved { deliverGeometryChanges() }
            return
        }
        // A frame that only repaints keeps every frame and size.
        if repaintOnly, !updating, !sizesInvalidated, presentations.isEmpty, scrolledNodes.isEmpty {
            repaintOnly = false
            layoutRequested = false
            updateAnimation = nil
            lastLayoutReason = "repaint"; lastLayoutMeasures = 0; lastLayoutComputes = 0
            return
        }
        if reason.isEmpty {
            if layoutForced { reason = "forced by " + lastForcingRequest }
            else if !presentations.isEmpty { reason = "presentation" }
            else if !scrolledNodes.isEmpty { reason = "scroll needs layout" }
            else { reason = "requested" }
        }
        measureCount = 0; computeCount = 0
        if profileLayout { computeHistogram.removeAll(); proposalCounts.removeAll(); proposalLog.removeAll(); profiledNodes.removeAll(); shareProbes.removeAll() }
        defer {
            lastLayoutReason = reason + (keptPlacements > 0 ? ", kept \(keptPlacements) placements" : ""); lastLayoutMeasures = measureCount; lastLayoutComputes = computeCount
            if profileLayout {
                lastComputeHistogram = computeHistogram
                var proposals: [String: Int] = [:]
                for (_, entry) in proposalCounts { proposals[entry.0, default: 0] = max(proposals[entry.0, default: 0], entry.1) }
                lastProposalHistogram = proposals
                if let worst = proposalCounts.max(by: { $0.value.1 < $1.value.1 }) {
                    lastWorstNodeProposals = [worst.value.0] + (proposalLog[worst.key] ?? [])
                    var chain: [String] = []
                    var node = profiledNodes[worst.key]
                    while let current = node {
                        let count = proposalCounts[ObjectIdentifier(current)]?.1 ?? 0
                        let distinct = Set(proposalLog[ObjectIdentifier(current)] ?? []).count
                        let sample = Array(Set(proposalLog[ObjectIdentifier(current)] ?? [])).sorted().prefix(8).joined(separator: " ")
                        chain.append("\(current.nodeDescription.prefix(60)) ×\(count) (\(distinct) distinct: \(sample))")
                        node = current.parent
                    }
                    lastWorstNodeChain = chain
                }
                profiledNodes.removeAll()
                lastShareProbes = shareProbes
            }
        }
        repaintOnly = false
        layoutForced = false
        placesEverything = placesEverythingRequested || size != layoutSize
        placesEverythingRequested = false
        keptPlacements = 0
        scrolledNodes.removeAll()
        fullLayoutCount += 1
        inLayoutPass = true
        let invalidatedBefore = sizesInvalidated
        flush()
        if let shallowest = scheduler.lastFlushShallowest, reason.hasPrefix("update") { reason += ", from " + shallowest }
        if sizesInvalidated, !invalidatedBefore { reason += ", sizes invalidated during the update by " + lastInvalidatingRequest }
        applyColorScheme()
        layoutRequested = false
        // The generation keys every node's size memo: a frame that only scrolled keeps it.
        if sizesInvalidated { layoutGeneration += 1 }
        sizesInvalidated = false
        layoutAnimation = pendingAnimation
        repeatingAnimationScopes = pendingAnimation?.repeatCount == 0 ? pendingRepeatingScopes : []
        pendingAnimation = nil
        pendingRepeatingScopes.removeAll()
        isLayingOut = true
        layoutSize = size
        probeFrames.removeAll(keepingCapacity: true)
        root.frame = CGRect(origin: .zero, size: size)
        layoutToolbar(in: size)
        let top = toolbar?.frame.height ?? 0
        let content = CGSize(width: size.width, height: max(0, size.height - top))
        let insets = safeAreaInsets
        let safe = CGRect(x: insets.leading, y: top + insets.top, width: max(0, content.width - insets.leading - insets.trailing),
                          height: max(0, content.height - insets.top - insets.bottom))
        for node in root.layoutChildren {
            if node.extendsIntoSafeArea {
                node.safeAreaOverlap = insets
                node.place(at: CGPoint(x: content.width / 2, y: top + content.height / 2), anchor: .center,
                           proposal: ProposedViewSize(content), by: root)
            } else {
                node.place(at: CGPoint(x: safe.midX, y: safe.midY), anchor: .center, proposal: ProposedViewSize(safe.size), by: root)
            }
        }
        layoutPresentations(in: size)
        // The presented panels' frames as probes, the way the macOS harness records the presented
        // windows (`window.sheet`, `window.alert`, `window.popover`, `window.menu`; a second of a
        // kind numbered): the desktop profile's presentations are separate windows there.
        if !environmentIsIOS {
            var counts: [String: Int] = [:]
            for presentation in presentations {
                let kind: String
                switch presentation.kind {
                case .sheet: kind = presentation.options.fullScreen ? "window" : "sheet"
                case .alert, .dialog: kind = "alert"
                case .popover: kind = "popover"
                case .menu, .submenu: kind = "menu"
                case .window: kind = "window"
                }
                counts[kind, default: 0] += 1
                probeFrames[counts[kind]! == 1 ? "window.\(kind)" : "window.\(kind)\(counts[kind]!)"] = presentation.windowFrame
            }
        }
        isLayingOut = false
        inLayoutPass = false
        layoutAnimation = nil
        updateAnimation = nil
        repeatingAnimationScopes.removeAll()
        deliverPreferences()
        syncNativeViews()
        syncHostedWindows()
    }

    private var environmentIsIOS: Bool { rootEnvironment.platformProfile.isIOS }

    /// Re-reads the observers of geometry alone (`onGeometryChange`) after scrolled content moved.
    package func deliverGeometryChanges() {
        preferenceObservers.removeAll { $0.node == nil || $0.node?.isMounted == false }
        for observer in preferenceObservers where observer.node?.observesGeometry == true {
            observer.node?.evaluatePreference()
        }
    }

    /// Runs every live `onPreferenceChange` action whose value changed in this pass.
    package func deliverPreferences() {
        preferenceObservers.removeAll { $0.node == nil || $0.node?.isMounted == false }
        for observer in preferenceObservers {
            observer.node?.evaluatePreference()
        }
    }
}

/// The parentless node at the top of the tree. Holds the mounted root view's node.
@MainActor
package final class RootNode: ViewNode {
    /// Presenters place sheets, popovers and menus through the root in window coordinates
    /// computed from measured frames; the root never mirrors them.
    override package var mirrorsPlacements: Bool { false }
    package private(set) var child: ViewNode?
    /// Re-applies the mounted view under a new root environment (a colour scheme change).
    package private(set) var reapply: ((EnvironmentValues) -> Void)?

    package init(runtime: Runtime, environment: EnvironmentValues) {
        super.init(parent: nil, runtime: runtime, environment: environment)
    }

    /// The host's safe area is the root view's.
    override package func providedSafeAreaInsets(for child: ViewNode) -> EdgeInsets { runtime.safeAreaInsets }

    /// The area a presentation's content is being placed in (`Runtime.place(_:in:insets:)`):
    /// its bounds in the window and the unsafe depth at each of its edges.
    private var placingArea: (bounds: CGRect, insets: EdgeInsets)?

    /// A presentation's content takes its safe area from the presentation's area (a sheet's
    /// card has no unsafe region above it), the root view from the window.
    override package func assignSafeArea(to child: ViewNode) {
        guard let area = placingArea else { return super.assignSafeArea(to: child) }
        assignSafeArea(to: child, in: area.bounds, own: area.insets)
    }

    /// Places `node` in `bounds` as the root view is placed in the window: a view that extends
    /// into the safe area (a scroll view, a geometry reader) takes the whole area and insets its
    /// content by `insets`; any other view is proposed the safe part and centred in it.
    package func place(_ node: ViewNode, in bounds: CGRect, insets: EdgeInsets) {
        placingArea = (bounds, insets)
        defer { placingArea = nil }
        if node.extendsIntoSafeArea {
            node.safeAreaOverlap = insets
            node.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(bounds.size), by: self)
        } else {
            let safe = CGRect(x: bounds.minX + insets.leading, y: bounds.minY + insets.top,
                              width: max(0, bounds.width - insets.leading - insets.trailing), height: max(0, bounds.height - insets.top - insets.bottom))
            node.place(at: CGPoint(x: safe.midX, y: safe.midY), anchor: .center, proposal: ProposedViewSize(safe.size), by: self)
        }
    }

    fileprivate func mount<V: View>(_ view: V) -> TypedNode<V> {
        if let existing = child as? TypedNode<V> {
            existing.update(view: view, environment: environment)
            reapply = { [weak existing] environment in existing?.update(view: view, environment: environment, force: true) }
            return existing
        }
        child?.unmount()
        let node = V._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        child = node
        reapply = { [weak node] environment in node?.update(view: view, environment: environment, force: true) }
        return node
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
    override package var nodeDescription: String { "Root" }
}

/// Collects invalidated nodes and updates them in depth order so that a parent's update, which
/// already refreshes its subtree, makes the children's own pending updates unnecessary.
@MainActor
package final class UpdateScheduler {
    private var dirty: [ObjectIdentifier: ViewNode] = [:]

    /// Actions to run after the next batch of updates (`onChange`, `initial` actions).
    private var actions: [@MainActor () -> Void] = []

    /// Called the first time work becomes pending after an idle period. Hosts use it to request
    /// an animation frame; headless callers flush explicitly.
    package var onNeedsFlush: (@MainActor @Sendable () -> Void)?

    /// Number of `flush` calls that did work, for tests.
    package private(set) var flushCount = 0

    package var hasPendingWork: Bool { !dirty.isEmpty || !actions.isEmpty }
    /// Whether only actions wait: no node is invalidated.
    package var hasPendingActionsOnly: Bool { dirty.isEmpty && !actions.isEmpty }

    package init() {}

    package func schedule(_ node: ViewNode) {
        let wasIdle = !hasPendingWork
        dirty[ObjectIdentifier(node)] = node
        if wasIdle { onNeedsFlush?() }
    }

    /// Runs `action` once the pending updates have been applied, in the same flush.
    package func enqueue(_ action: @escaping @MainActor () -> Void) {
        let wasIdle = !hasPendingWork
        actions.append(action)
        if wasIdle { onNeedsFlush?() }
    }

    /// The shallowest node the last flush updated, with its depth: a change high in the tree
    /// re-evaluates everything under it (the layout reason names it).
    package private(set) var lastFlushShallowest: String?

    /// Returns whether any node was updated.
    @discardableResult
    package func flush() -> Bool {
        guard hasPendingWork else { return false }
        flushCount += 1
        lastFlushShallowest = nil
        var shallowestDepth = Int.max
        var updated = false
        var passes = 0
        while hasPendingWork {
            passes += 1
            precondition(passes < 1000, "UpdateScheduler: updates keep invalidating nodes; giving up")
            let batch = dirty.values.sorted { $0.depth < $1.depth }
            if let first = batch.first, first.depth < shallowestDepth {
                shallowestDepth = first.depth
                lastFlushShallowest = "\(first.nodeDescription.prefix(80)) at depth \(first.depth) (\(batch.count) nodes)"
            }
            if !batch.isEmpty { updated = true }
            dirty.removeAll(keepingCapacity: true)
            for node in batch {
                node.updateIfNeeded()
            }
            let pending = actions
            actions.removeAll()
            for action in pending { action() }
        }
        return updated
    }
}

/// The start of the wheel clock.
private let _wheelClockOrigin = ContinuousClock.now

/// A trackpad gesture seen as wheel events (`Runtime.wheelGestureEvent`).
package struct WheelGesture {
    package var axis: Axis
    package var nodes: [ViewNode & _Scrollable]
    package var lastTime: Double
    package var lastMagnitude: CGFloat
    /// Speeds along the axis (points per second) of the recent events, newest last.
    package var speeds: [CGFloat] = []
    /// The fastest slice of the gesture so far.
    package var peakSpeed: CGFloat = 0
    /// Whether the speed held or rose from one slice to the next at least once (a swipe's start).
    package var speededUp = false
    /// The finger's speed when the tail began (the largest of the speeds just before it).
    package var liftSpeed: CGFloat = 0
    /// How far the gesture moved along its axis, signed.
    package var displacement: CGFloat = 0
    /// Set once the speeds fall like the OS's momentum.
    package var inMomentum = false
    /// The first scroll view the gesture moved.
    package var mover: (ViewNode & _Scrollable)?
    /// Set once the mover settled: the rest of the gesture is its momentum.
    package var settled = false

    /// The last few events' sizes, newest last (a new push is judged against them).
    package var recentMagnitudes: [CGFloat] = []
    /// The events of the current 16 ms slice of event time: their summed size and start.
    package var sliceStart: Double?
    package var sliceSum: CGFloat = 0

    /// Whether an event of `delta` at `now` still belongs to this gesture. Read from a real
    /// trackpad's events in Safari (new-website#216): a tail never turns back, and a new swipe
    /// often starts within a tenth of a second of the last one, or the other way.
    package func continues(with delta: CGSize, magnitude: CGFloat, at now: Double) -> Bool {
        let gap = now - lastTime
        // A tail's events come 8 to 17 ms apart and only thin out to 33, 66 and 100 ms at its
        // very end, 1 pt each; a new swipe often starts about 100 ms after that. A pause of
        // 60 ms starts a gesture: a straggler at a tail's end becomes a 1 pt gesture that
        // settles back on its page.
        if gap >= 0.06 { return false }
        let along = axis == .horizontal ? delta.width : delta.height
        // A gesture never turns back along its axis, nor turns a right angle.
        if along != 0, displacement != 0, (along > 0) != (displacement > 0) { return false }
        if along == 0, (axis == .horizontal ? delta.height : delta.width) != 0 { return false }
        if inMomentum || settled {
            // A clear new push: larger than three times the last few events (the tail comes
            // in uneven pairs, 8, 19, 12, 18 pt, so the largest of them is the measure).
            let recent = recentMagnitudes.max() ?? lastMagnitude
            if magnitude > max(4, 3 * recent) { return false }
        }
        return true
    }

    package mutating func record(_ delta: CGSize, magnitude: CGFloat, at now: Double) {
        let along = axis == .horizontal ? delta.width : delta.height
        displacement += along
        recentMagnitudes.append(magnitude)
        if recentMagnitudes.count > 3 { recentMagnitudes.removeFirst() }
        lastTime = now
        lastMagnitude = magnitude
        // Speeds are taken over 16 ms slices of the events' own time: events come in uneven
        // pairs and in whole points, which made every event-to-event ratio noise.
        let start = sliceStart ?? now
        sliceStart = start
        sliceSum += abs(along)
        guard now - start >= 0.016 else { return }
        speeds.append(sliceSum / CGFloat(now - start))
        sliceStart = now
        sliceSum = 0
        if speeds.count > 8 { speeds.removeFirst(speeds.count - 8) }
        if speeds.count >= 2, speeds[speeds.count - 1] >= speeds[speeds.count - 2] * 0.98 { speededUp = true }
        peakSpeed = max(peakSpeed, speeds.last ?? 0)
        guard !inMomentum, speeds.count >= 5 else { return }
        // The finger has lifted once the speed has not risen for four slices running and has
        // fallen to three quarters of the swipe's peak. A trackpad's deltas are whole points
        // (10, 10, 9, 8, 8, 8, 7…), so the speed stays flat for a slice or two inside a tail
        // and a "falls every slice" rule missed real tails: the card crept along them for a
        // second (new-website#216). iOS settles a paging view as the finger lifts.
        let recentSpeeds = Array(speeds.suffix(5))
        let notRising = zip(recentSpeeds.dropFirst(), recentSpeeds).allSatisfy { new, old in new <= old * 1.02 }
        if notRising, let current = recentSpeeds.last, current <= peakSpeed * 0.75 {
            inMomentum = true
            // A swipe's speed holds or rises for a slice before it falls; a piece of tail cut off
            // by a pause falls from its first slice, and must not flick the page on.
            liftSpeed = speededUp ? (recentSpeeds.first ?? 0) : 0
        }
    }
}
