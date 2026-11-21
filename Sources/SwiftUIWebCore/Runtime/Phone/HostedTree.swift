#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

// A view tree the drawn iPhone shows outside the app's own window, live (new-website#643 for a
// Live Activity on the lock screen, #638 for widgets on the home screen): a runtime of its own,
// as a `UIHostingController`'s view has, measuring with the app's text engine and reading its
// asset catalog, laid out at a width (or a fixed size), painted where the phone puts it, and
// taking taps. Its state changes and live texts (a rest counting down) ask for a frame through
// `onNeedsRepaint`, so the phone paints again only then.

/// A live view tree hosted by the drawn iPhone.
@MainActor
public final class _HostedTree {
    package let runtime: Runtime
    /// The size it was last laid out in.
    public private(set) var size: CGSize = .zero
    /// Called when the tree changed and must be painted again (a state change, a live text).
    public var onNeedsRepaint: (@MainActor () -> Void)?
    private var fixedSize: CGSize?
    private var width: CGFloat = 0
    private var laidOut = false

    /// A tree for `view`, measured and drawn as the app's own runtime `host` does.
    public init(_ view: AnyView, host: Runtime) {
        var environment = EnvironmentValues()
        environment.platformProfile = host.rootEnvironment.platformProfile
        environment.colorScheme = host.rootEnvironment.colorScheme
        environment.locale = host.rootEnvironment.locale
        environment.dynamicTypeSize = host.rootEnvironment.dynamicTypeSize
        environment.displayScale = host.rootEnvironment.displayScale
        runtime = Runtime(environment: environment)
        runtime.paintsWindowBackground = false
        runtime.textEngine = host.textEngine
        runtime.assetCatalog = host.assetCatalog
        runtime.imageRasterizer = host.imageRasterizer
        runtime.hostPlatformProfile = host.hostPlatformProfile
        runtime.mount(view)
        runtime.onNeedsFrame = { [weak self] in self?.onNeedsRepaint?() }
    }

    /// Shows another view in the tree (the activity's new content), keeping its state.
    public func update(_ view: AnyView) {
        runtime.mount(view)
        onNeedsRepaint?()
    }

    /// The tree takes this size whatever its content asks for (a widget's family).
    public func setFixedSize(_ size: CGSize) {
        guard fixedSize != size else { return }
        fixedSize = size
        laidOut = false
    }

    /// Lays out at `width`, as tall as the content asks (a Live Activity), or in the fixed size.
    /// Returns the size.
    @discardableResult
    public func layout(width: CGFloat) -> CGSize {
        if !laidOut || width != self.width || runtime.needsFrame {
            self.width = width
            let target: CGSize
            if let fixedSize {
                target = fixedSize
            } else {
                runtime.flushForMeasurement()
                let fitting = runtime.root.layoutChildren.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
                target = CGSize(width: width, height: fitting.height.isFinite ? max(0, fitting.height) : 0)
            }
            runtime.layout(in: target)
            size = target
            laidOut = true
        }
        return size
    }

    /// The tree's drawing, its origin at `origin` in the list it goes into.
    public func paint(into list: inout DisplayList, at origin: CGPoint, scale: CGFloat) {
        let content = runtime.render(scale: scale)
        list.append(.save)
        list.append(.concat(CGAffineTransform(translationX: origin.x, y: origin.y)))
        list.commands.append(contentsOf: content.commands)
        list.append(.restore)
    }

    /// Moves animations and scroll momentum on; returns whether anything still moves.
    public func advance(elapsed: Double) -> Bool {
        runtime.advanceFrame(elapsed: elapsed)
    }

    /// Whether the tree is waiting for a frame (a state change or a live text to show).
    public var needsFrame: Bool { runtime.needsFrame }

    // MARK: The finger, in the tree's own points

    /// A press: returns whether it landed on something that takes presses (a button).
    @discardableResult
    public func pointerDown(at point: CGPoint, type: PointerType, time: Double) -> Bool {
        runtime.pointerDown(at: point, type: type, time: time)
        return runtime.pressedNode != nil || runtime.isPanning
    }

    public func pointerMoved(to point: CGPoint, time: Double) {
        runtime.pointerMoved(to: point, time: time)
    }

    public func pointerUp(at point: CGPoint, time: Double) {
        runtime.pointerUp(at: point, time: time)
    }

    /// The press left: whatever it pressed lets go without acting.
    public func pointerCancelled(time: Double) {
        runtime.pointerUp(at: CGPoint(x: -10_000, y: -10_000), time: time)
    }
}

extension Runtime {
    /// Whether a press is moving a scroll view.
    package var isPanning: Bool { pan?.active == true }
}
