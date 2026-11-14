// The seam between a host (a canvas in a page, an AppKit window, a headless driver) and what it
// shows (a SwiftUI runtime, a UIKit window scene; decision 0014). The host owns the frame
// loop, the pixels and the platform's input and accessibility; the scene owns layout, painting
// into a display list, and what the input means.

#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

/// What a host drives: installs its services, asks for frames, forwards input, and mirrors the
/// semantics tree into the platform's accessibility and text-input facilities.
@MainActor
public protocol HostedScene: AnyObject {
    // MARK: What the host installs

    /// Measures and breaks text. Installed before the first layout.
    var textEngine: any TextEngine { get set }
    /// The app's asset catalogs (images and colours by name).
    var assetCatalog: AssetCatalog { get set }
    /// The host's image fetcher for URLs (`_ImageLoading`).
    var imageLoader: (any _ImageLoading)? { get set }
    /// Rasterises a display list of `size` points at `scale` into PNG data (a platform image's
    /// `pngData()`); nil where the host cannot.
    var imageRasterizer: ImageRasterizer? { get set }
    /// The system appearance, now and whenever it changes.
    var hostColorScheme: ColorScheme { get set }
    /// The system's reduce-motion preference, set by hosts.
    var hostReducesMotion: Bool { get set }
    /// The system's increase-contrast preference (`prefers-contrast: more`, AppKit's
    /// `accessibilityDisplayShouldIncreaseContrast`), set by hosts (sw-dark).
    var hostIncreasesContrast: Bool { get set }
    /// The user's text size as a content size category short name ("XS" … "AXXXXL"), nil when
    /// the host has none (sw-dynamic-type: iOS Safari exposes it through `-apple-system-body`).
    var hostDynamicTypeSize: String? { get set }
    /// The host's pixels per point, for values rounded to the display (`@ScaledMetric`).
    var hostDisplayScale: CGFloat { get set }
    /// The device's safe area in points (top, leading, bottom, trailing): a phone's status bar
    /// and home indicator, which the root view is laid out inside unless it extends into it.
    /// Set by hosts that know it (a page in a phone's browser, a drawn phone around the app).
    var hostSafeAreaInsets: [CGFloat] { get set }
    /// Whether the page is visible, and whether its window has focus (the scene phase).
    var hostIsVisible: Bool { get set }
    var hostIsFocused: Bool { get set }
    /// The host's URL changed (a launch with a fragment, `hashchange`, `popstate`).
    func handleOpenURL(_ url: String)
    /// Writes text to the system clipboard, when the host may.
    var clipboardWriter: ((String) -> Void)? { get set }
    /// The host's share sheet (Web Share, `NSSharingServicePicker`), file chooser (a file input,
    /// `NSOpenPanel`) and file saver (a download, `NSSavePanel`), when it has them
    /// (uk-system-sheets: `UIActivityViewController`, `UIDocumentPickerViewController`).
    var shareHandler: ((HostShareRequest) -> Void)? { get set }
    var fileOpenHandler: ((HostFileOpenRequest, _ completion: @escaping @MainActor ([HostFile]) -> Void) -> Void)? { get set }
    var fileSaveHandler: ((HostFile) -> Void)? { get set }
    /// Called when the scene needs a frame without the host having asked for one (a state
    /// change, a layout request); the host coalesces calls into its next frame.
    var onNeedsFrame: (@MainActor () -> Void)? { get set }

    // MARK: Frames

    /// Whether the scene has pending work that needs another frame.
    var needsFrame: Bool { get }
    /// Whether animations are in flight (frames keep coming while true).
    var isAnimating: Bool { get }
    /// Why the last `layout(in:)` walked the tree (or "moved"/"repaint" when it did not), with
    /// the pass's measurements and memo misses, for the host's frame statistics; a scene that
    /// does not know says nothing.
    var lastLayoutReason: String { get }
    /// Every scroll view's frame in the window and content offset, [x, y, w, h, offsetX, offsetY]
    /// (debugging: a gesture's motion read frame by frame).
    var debugScrollViews: [[Double]] { get }
    var lastLayoutMeasures: Int { get }
    var lastLayoutComputes: Int { get }
    /// Layout profiling (`layoutProfile()` on the debug bridge): on, the last pass's
    /// recomputations by node kind and the most proposals any node of a kind was computed for.
    var profileLayout: Bool { get set }
    var lastComputeHistogram: [String: Int] { get }
    var lastProposalHistogram: [String: Int] { get }
    var lastWorstNodeProposals: [String] { get }
    var lastWorstNodeChain: [String] { get }
    var lastShareProbes: [String: Int] { get }
    /// Advances the scene's clocks by `elapsed` seconds before a frame; returns whether an
    /// animation is still running.
    func advanceFrame(elapsed: Double) -> Bool
    /// The frame is on screen `lateness` seconds after its `advanceFrame`: animations the frame
    /// began start from now, as Core Animation begins them when their commit is shown, so a
    /// slow frame doesn't make them jump ahead on the next one.
    func commitAnimations(lateness: Double)
    /// Lays the scene out into `size` (points).
    func layout(in size: CGSize)
    /// Paints the laid-out scene into a display list at `scale` pixels per point.
    func render(scale: CGFloat) -> DisplayList
    /// An image the loader was asked for has arrived (or failed).
    func imageLoadDidFinish()
    /// The title the window or document should show, if the scene sets one.
    var windowTitle: String? { get }
    /// Frames recorded by probes during the most recent layout (test bridges).
    var probeFrames: [String: CGRect] { get }

    // MARK: Input, in points from the top left

    func pointerDown(at point: CGPoint, type: PointerType, time: Double)
    func pointerMoved(to point: CGPoint, time: Double)
    func pointerLeft()
    func pointerUp(at point: CGPoint, time: Double)
    /// A secondary (right) button press: context menus.
    func secondaryPointerDown(at point: CGPoint)
    /// A wheel or trackpad scroll by `delta` points (positive moves content up and left).
    func scrollWheel(by delta: CGSize, at point: CGPoint)
    /// The same, with the event's time in seconds (the host's clock): a scene that reads a
    /// trackpad gesture out of its wheel events measures their gaps with it.
    func scrollWheel(by delta: CGSize, at point: CGPoint, time: Double)
    /// A pinch from a trackpad or two touches: `scale` and `rotation` (radians, clockwise) are
    /// cumulative since `began`; `point` is the pinch's centre.
    func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: Double, at point: CGPoint, time: Double)
    /// A key press; returns whether the scene consumed it.
    func keyDown(_ event: KeyEvent) -> Bool
    /// A key release (`onKeyPress` up phases); returns whether the scene consumed it.
    func keyUp(_ event: KeyEvent) -> Bool
    /// The modifier keys held as a pointer event arrives (Shift and Command clicks in lists).
    func pointerModifiersChanged(_ modifiers: EventModifiers)
    /// The CSS cursor name the pointer should show, or nil for the default.
    var pointerCursor: String? { get }

    // MARK: Semantics and text input

    /// The accessibility tree after the most recent layout.
    func semanticsTree() -> [SemanticsNode]
    func activate(semanticsIdentifier: Int)
    func adjust(semanticsIdentifier: Int, increment: Bool)
    func setValue(semanticsIdentifier: Int, value: Double)
    /// A custom action of an element (`SemanticsNode.customActions`) performed by assistive technology.
    func performAccessibilityAction(semanticsIdentifier: Int, name: String)
    /// What the scene asks of the host's assistive layer since the last frame (announcements,
    /// focus moves posted by the app); the host takes them after syncing its overlay.
    func takeAccessibilityEvents() -> [AccessibilityEvent]
    /// Keyboard focus moved to an element (`keyboard` tells whether a focus ring should show).
    func focus(semanticsIdentifier: Int?, keyboard: Bool)
    func blur(semanticsIdentifier: Int)
    /// The element with keyboard focus, and the text field with it (which sets both).
    var focusedIdentifier: Int? { get }
    var focusedTextFieldIdentifier: Int? { get }
    /// The host's input element for a text field changed, submitted, or changed focus.
    func textField(_ semanticsIdentifier: Int, didChange text: String)
    func textFieldDidSubmit(_ semanticsIdentifier: Int)
    func textField(_ semanticsIdentifier: Int, focused: Bool)
    /// The element's caret or selection moved (UTF-16 offsets); scenes painting their own
    /// caret (`TextInputInfo.paintsCaret`) follow it.
    func textField(_ semanticsIdentifier: Int, selectionStart start: Int, end: Int)
    /// The host's input method is composing: `range` (UTF-16 offsets in the field's text) is
    /// the marked text, underlined until it commits; nil when nothing is marked.
    func textField(_ semanticsIdentifier: Int, markedRange range: Range<Int>?)
    /// The element's content scrolled (a multi-line editor's textarea), in points.
    func textField(_ semanticsIdentifier: Int, scrolledTo offset: CGFloat)
    /// A bundled font the host loaded is now available: text measured before it lays out again.
    func fontsDidLoad()
    /// The scene laid out a symbol outside the built-in layout table: hosts that can load the
    /// full table do so once and hand it over parsed (`SystemSymbolMetricsTable.parse`).
    var onNeedsSymbolMetrics: (() -> Void)? { get set }
    func symbolMetricsDidLoad(_ table: [String: [Double]])
    /// A colour well was pressed: hosts with a system colour chooser (the browser's
    /// `<input type="color">`, `NSColorPanel`) install a handler that shows it and return true;
    /// the scene shows its own preset panel otherwise (sw-colorpicker).
    var colorPanelHandler: ((ColorPanelRequest) -> Bool)? { get set }
    /// The host's chooser picked a colour for the well (continuously while it is open).
    func colorPanel(_ identifier: Int, didPick color: RGBA)
    /// The host's chooser closed, or moved to another well.
    func colorPanelDidClose(_ identifier: Int)

    // Drags across the app boundary (sw-dragdrop-os). The scene's own drags stay pointer-driven;
    // a host that can hand them to the system (the browser's `DataTransfer`, AppKit's dragging
    // session) asks for the items once the scene lifted a payload and reports the outcome.
    /// Whether a drag can start from a press at `point` (the browser host marks its canvas
    /// draggable for that press alone, so other gestures never become system drags).
    func hasDragSource(at point: CGPoint) -> Bool
    /// The items of the drag the scene has in flight, for the host's system drag (empty: none).
    func externalDragItems() -> [ExternalDragItem]
    /// A press on a drag source: the host's system drag is starting from it, so the scene lifts
    /// the payload now (the browser fires `dragstart` before the scene's own threshold) and
    /// returns the items; empty when nothing under the press can be dragged.
    func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem]
    /// A system drag (the scene's own, or one from outside carrying `types`) is over `point`:
    /// returns whether a destination accepts it.
    func externalDragUpdated(types: [String], at point: CGPoint) -> Bool
    /// The system drag left the scene.
    func externalDragExited()
    /// The system drag dropped `items` at `point`: returns whether a destination took them.
    func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool
    /// The host's system session for the scene's drag ended; `dropped` when another app took it.
    func externalDragEnded(dropped: Bool)
    /// The image the system drag shows: the lifted preview as a display list in its own space,
    /// its size, and where the pointer holds it.
    func externalDragPreview() -> ExternalDragPreview?

    // MARK: Host elements (sw-frameworks)

    /// Platform elements the host places over the painted content after a render: a video
    /// player, a web view. The scene paints a stand-in underneath for hosts without them.
    func hostElements() -> [HostElement]
}

/// An element a host shows over the canvas at a view's frame (`VideoPlayer`, `WebView`).
public struct HostElement: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A video: its source, whether it should be playing, muted or looping, with controls.
        case video(url: String, playing: Bool, muted: Bool, loops: Bool, controls: Bool, rate: Double)
        /// A web page by URL or inline HTML.
        case web(url: String?, html: String?)

        public var isVideo: Bool { if case .video = self { return true } else { return false } }
    }
    public var identifier: Int
    public var kind: Kind
    public var isVideo: Bool { kind.isVideo }
    /// The element's frame in root coordinates.
    public var frame: CGRect
    /// The part of the frame the host may show (a scroll view's clip).
    public var visibleFrame: CGRect
    public init(identifier: Int, kind: Kind, frame: CGRect, visibleFrame: CGRect) {
        self.identifier = identifier
        self.kind = kind
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// What a scene asks the host to share: links and texts, a subject, a message, and data as files.
public struct HostShareRequest: Sendable {
    public var items: [String]
    public var subject: String?
    public var message: String?
    public var files: [HostFile]
    public init(items: [String], subject: String? = nil, message: String? = nil, files: [HostFile] = []) {
        self.items = items
        self.subject = subject
        self.message = message
        self.files = files
    }
}

/// A file the host hands over or takes: its bytes, a name, its type (a MIME type) and, where
/// the host has one, a location.
public struct HostFile: Sendable {
    public var data: Data
    public var name: String
    public var mimeType: String
    public var url: URL?
    public init(data: Data, name: String, mimeType: String = "application/octet-stream", url: URL? = nil) {
        self.data = data
        self.name = name
        self.mimeType = mimeType
        self.url = url
    }
}

/// What a scene asks the host's file chooser for: the extensions it accepts (empty: any),
/// whether several files may be chosen, and whether images only (a photo library on hosts
/// that have one).
public struct HostFileOpenRequest: Sendable {
    public var extensions: [String]
    public var allowsMultiple: Bool
    public var imagesOnly: Bool
    public init(extensions: [String] = [], allowsMultiple: Bool = false, imagesOnly: Bool = false) {
        self.extensions = extensions
        self.allowsMultiple = allowsMultiple
        self.imagesOnly = imagesOnly
    }
}

/// A drag preview for the host's system drag.
public struct ExternalDragPreview {
    public let list: DisplayList
    public let size: CGSize
    public let grab: CGPoint
    public init(list: DisplayList, size: CGSize, grab: CGPoint) {
        self.list = list
        self.size = size
        self.grab = grab
    }
}

/// An item of a drag crossing the app boundary: its type (a MIME type such as `text/plain`
/// or `text/uri-list`, or a uniform type identifier), its text, its bytes and a file's name.
public struct ExternalDragItem: Equatable, Sendable {
    public var type: String
    public var text: String?
    public var data: Data?
    public var fileName: String?

    public init(type: String, text: String? = nil, data: Data? = nil, fileName: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.fileName = fileName
    }
}

/// What a scene asks a host's colour chooser to show: the well's semantics identifier (the
/// callbacks name it), its current colour, whether opacity may change, and the well's frame in
/// the scene (points) for a chooser that anchors itself.
public struct ColorPanelRequest: Equatable, Sendable {
    public let identifier: Int
    public let color: RGBA
    public let supportsOpacity: Bool
    public let anchor: CGRect

    public init(identifier: Int, color: RGBA, supportsOpacity: Bool, anchor: CGRect) {
        self.identifier = identifier
        self.color = color
        self.supportsOpacity = supportsOpacity
        self.anchor = anchor
    }
}

extension HostedScene {
    public func commitAnimations(lateness: Double) {}
    public func scrollWheel(by delta: CGSize, at point: CGPoint, time: Double) { scrollWheel(by: delta, at: point) }
    public func hostElements() -> [HostElement] { [] }
    public func colorPanel(_ identifier: Int, didPick color: RGBA) {}
    public func colorPanelDidClose(_ identifier: Int) {}
    public func textField(_ semanticsIdentifier: Int, selectionStart start: Int, end: Int) {}
    public func textField(_ semanticsIdentifier: Int, markedRange range: Range<Int>?) {}
    public func textField(_ semanticsIdentifier: Int, scrolledTo offset: CGFloat) {}
    public func fontsDidLoad() {}
    public func symbolMetricsDidLoad(_ table: [String: [Double]]) {}
    public func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: Double, at point: CGPoint, time: Double) {}
    public func keyUp(_ event: KeyEvent) -> Bool { false }
    public func pointerModifiersChanged(_ modifiers: EventModifiers) {}
    public func performAccessibilityAction(semanticsIdentifier: Int, name: String) {}
    public func takeAccessibilityEvents() -> [AccessibilityEvent] { [] }
    public func hasDragSource(at point: CGPoint) -> Bool { false }
    public func externalDragItems() -> [ExternalDragItem] { [] }
    public func beginExternalDrag(at point: CGPoint) -> [ExternalDragItem] { [] }
    public func externalDragUpdated(types: [String], at point: CGPoint) -> Bool { false }
    public func externalDragExited() {}
    public func externalDrop(items: [ExternalDragItem], at point: CGPoint) -> Bool { false }
    public func externalDragEnded(dropped: Bool) {}
    public func externalDragPreview() -> ExternalDragPreview? { nil }
}

/// What a scene asks of the host's assistive layer: a string to announce in a live region, or
/// assistive focus moved to an element (`UIAccessibility.post`).
public enum AccessibilityEvent: Equatable, Sendable {
    case announce(String)
    case focus(Int)
    /// The layout changed; the host re-reads its overlay (it does so every frame).
    case layoutChanged
    /// A new screen: the host announces nothing itself but moves focus when asked.
    case screenChanged
}

/// The phase of a continuous gesture a host delivers (pinches and rotations).
public enum ContinuousGesturePhase: Sendable {
    case began, changed, ended, cancelled
}

/// Turns a display list in a space of `size` points into PNG data at `scale` pixels per point.
public typealias ImageRasterizer = @MainActor (_ list: DisplayList, _ size: CGSize, _ scale: CGFloat) -> Data?

extension HostedScene {
    /// Scenes without Dynamic Type ignore the setting.
    public var hostDynamicTypeSize: String? {
        get { nil }
        set {}
    }
    public var hostDisplayScale: CGFloat {
        get { 2 }
        set {}
    }
    /// Scenes without a device safe area ignore it.
    public var hostSafeAreaInsets: [CGFloat] {
        get { [0, 0, 0, 0] }
        set {}
    }
}

extension HostedScene {
    public var lastLayoutReason: String { "" }
    public var debugScrollViews: [[Double]] { [] }
    public var lastLayoutMeasures: Int { 0 }
    public var lastLayoutComputes: Int { 0 }
    public var profileLayout: Bool { get { false } set {} }
    public var lastComputeHistogram: [String: Int] { [:] }
    public var lastProposalHistogram: [String: Int] { [:] }
    public var lastWorstNodeProposals: [String] { [] }
    public var lastWorstNodeChain: [String] { [] }
    public var lastShareProbes: [String: Int] { [:] }
}
