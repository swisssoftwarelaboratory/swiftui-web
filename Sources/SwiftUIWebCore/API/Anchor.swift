/// Anchors: a geometry value (a rectangle, a point) captured in one view and read back in
/// another's coordinates through `GeometryProxy`'s subscript (`g[proxy.plotAreaFrame]`). The
/// anchor holds its value in the root view's coordinates; the subscript moves it into the
/// reader's.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An opaque value derived from a view's geometry, resolved in another view's coordinate
/// space by `GeometryProxy`.
public struct Anchor<Value> {
    /// The value in the root view's coordinates.
    package let rootValue: Value
    /// The value moved by an offset.
    package let translate: @Sendable (Value, CGSize) -> Value

    package init(rootValue: Value, translate: @escaping @Sendable (Value, CGSize) -> Value) {
        self.rootValue = rootValue
        self.translate = translate
    }

    /// The value in coordinates whose origin is at `origin` (in the root's).
    package func value(relativeTo origin: CGPoint) -> Value {
        translate(rootValue, CGSize(width: -origin.x, height: -origin.y))
    }
}

extension Anchor where Value == CGRect {
    /// An anchor for a rectangle in the root view's coordinates.
    package init(rootRect: CGRect) {
        self.init(rootValue: rootRect) { rect, offset in rect.offsetBy(dx: offset.width, dy: offset.height) }
    }
}

extension Anchor where Value == CGPoint {
    /// An anchor for a point in the root view's coordinates.
    package init(rootPoint: CGPoint) {
        self.init(rootValue: rootPoint) { point, offset in CGPoint(x: point.x + offset.width, y: point.y + offset.height) }
    }
}

extension Anchor: @unchecked Sendable where Value: Sendable {}

extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Anchor, rhs: Anchor) -> Bool { lhs.rootValue == rhs.rootValue }
}

extension Anchor: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(rootValue) }
}

extension GeometryProxy {
    /// The anchor's value in this container's coordinate space.
    @MainActor public subscript<T>(anchor: Anchor<T>) -> T {
        node.proxyReadPosition()
        return anchor.value(relativeTo: node.frameInRoot.origin)
    }
}

// MARK: - Sources

extension Anchor {
    /// A type-erased geometry value that produces an anchored value: what `anchorPreference`
    /// captures from the view it modifies.
    public struct Source {
        /// The anchor for a view whose frame in the root's coordinates is the argument.
        package let make: @Sendable (CGRect) -> Anchor<Value>

        package init(make: @escaping @Sendable (CGRect) -> Anchor<Value>) { self.make = make }
    }
}

extension Anchor.Source: @unchecked Sendable {}

extension Anchor.Source where Value == CGRect {
    /// The view's bounds.
    public static var bounds: Anchor<CGRect>.Source { Anchor<CGRect>.Source { frame in Anchor(rootRect: frame) } }

    /// A rectangle in the view's own coordinates.
    public static func rect(_ r: CGRect) -> Anchor<CGRect>.Source {
        Anchor<CGRect>.Source { frame in Anchor(rootRect: r.offsetBy(dx: frame.minX, dy: frame.minY)) }
    }
}

extension Anchor.Source where Value == CGPoint {
    /// A point in the view's own coordinates.
    public static func point(_ p: CGPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source { frame in Anchor(rootPoint: CGPoint(x: frame.minX + p.x, y: frame.minY + p.y)) }
    }

    /// A point at a unit position in the view's bounds.
    public static func unitPoint(_ p: UnitPoint) -> Anchor<CGPoint>.Source {
        Anchor<CGPoint>.Source { frame in
            Anchor(rootPoint: CGPoint(x: frame.minX + frame.width * p.x, y: frame.minY + frame.height * p.y))
        }
    }

    public static var topLeading: Anchor<CGPoint>.Source { unitPoint(.topLeading) }
    public static var top: Anchor<CGPoint>.Source { unitPoint(.top) }
    public static var topTrailing: Anchor<CGPoint>.Source { unitPoint(.topTrailing) }
    public static var leading: Anchor<CGPoint>.Source { unitPoint(.leading) }
    public static var center: Anchor<CGPoint>.Source { unitPoint(.center) }
    public static var trailing: Anchor<CGPoint>.Source { unitPoint(.trailing) }
    public static var bottomLeading: Anchor<CGPoint>.Source { unitPoint(.bottomLeading) }
    public static var bottom: Anchor<CGPoint>.Source { unitPoint(.bottom) }
    public static var bottomTrailing: Anchor<CGPoint>.Source { unitPoint(.bottomTrailing) }
}
