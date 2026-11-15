/// State carried through one painting pass.
public struct PaintContext {
    /// Absolute origin (points) of the node being painted, unrounded.
    public var origin: CGPoint
    /// Pixels per point; frame edges are rounded to this grid.
    public let scale: CGFloat
    /// Absolute area a clipping scroll view can show, plus a margin: nodes whose frames lie
    /// outside it are not painted (`ViewNode.paintChildren`).
    public var visibleRect: CGRect?
    /// The exact area a clipping scroll view shows (`visibleRect` without its margin): host
    /// elements are shown through it.
    public var clipRect: CGRect?
    /// Effects the ancestors applied that SwiftUI distributes to every element (opacity, shadow,
    /// colour filters, blend modes): each painted leaf wraps its own drawing in these groups,
    /// outermost first, unless a compositing group collects the subtree into one.
    public var effects: [PendingEffect] = []
    /// A colour that replaces every text's (a list's selected row in a focused list paints
    /// its text white); nil for the texts' own.
    public var foregroundOverride: RGBA?
    /// Inside a scroll view's stored segment (new-website#286), the innermost cull block's
    /// absolute bounds (the segment's window at first): smaller children are wrapped in cull
    /// blocks so the painter can skip the ones the viewport misses when it paints the segment
    /// again. `nil` outside segments.
    public var cullBlock: CGRect?

    /// Below this side (points) a cull block's children get no blocks of their own: a row's
    /// parts leave the viewport with the row.
    public static let cullBlockMinimum: CGFloat = 64

    public init(origin: CGPoint, scale: CGFloat) {
        self.origin = origin
        self.scale = scale
    }

    /// Rounds a value to the pixel grid.
    public func round(_ value: CGFloat) -> CGFloat {
        (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    /// The absolute, pixel-aligned rectangle for a frame relative to this context.
    public func absoluteRect(_ frame: CGRect) -> CGRect {
        let minX = round(origin.x + frame.minX), minY = round(origin.y + frame.minY)
        let maxX = round(origin.x + frame.maxX), maxY = round(origin.y + frame.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The context for a child placed at `frame` within this node.
    public func child(at frame: CGRect) -> PaintContext {
        var child = PaintContext(origin: CGPoint(x: origin.x + frame.minX, y: origin.y + frame.minY), scale: scale)
        child.visibleRect = visibleRect
        child.clipRect = clipRect
        child.effects = effects
        child.foregroundOverride = foregroundOverride
        child.cullBlock = cullBlock
        return child
    }

    /// Wraps a leaf's or a group's drawing in the pending effects: the group commands opened
    /// over `bounds` before `body` runs and closed after it. Nothing is emitted when `body`
    /// draws nothing.
    public func withEffects(_ bounds: CGRect, into list: inout DisplayList, _ body: (inout DisplayList) -> Void) {
        guard !effects.isEmpty else {
            body(&list)
            return
        }
        // The body paints first so the groups can cover what it paints outside `bounds` (a
        // stroke wider than its frame is filtered whole, as SwiftUI filters a view's rendering).
        let mark = list.commands.count
        body(&list)
        guard list.commands.count > mark else { return }
        let painted = list.paintedExtent(from: mark)
        let box = painted.isNull ? bounds : bounds.union(painted)
        let inner = Array(list.commands[mark...])
        list.commands.removeSubrange(mark...)
        for effect in effects { list.append(effect.begin(bounds: box)) }
        list.commands += inner
        for _ in effects { list.append(.endGroup) }
    }
}

/// One distributed effect (see `PaintContext.effects`).
public enum PendingEffect: Equatable, Sendable {
    case opacity(Double)
    case shadow(RGBA, radius: CGFloat, offset: CGSize)
    case filter(DisplayFilter)
    case blend(BlendMode)

    /// The command that opens this effect's group over `bounds` (closed by `endGroup`).
    public func begin(bounds: CGRect) -> DisplayCommand {
        switch self {
        case .opacity(let opacity): return .beginGroup(opacity: opacity)
        case .shadow(let color, let radius, let offset): return .beginShadow(color, radius: radius, offset: offset)
        case .filter(let filter): return .beginFilter(filter, bounds: bounds)
        case .blend(let mode): return .beginBlend(mode, bounds: bounds)
        }
    }
}
