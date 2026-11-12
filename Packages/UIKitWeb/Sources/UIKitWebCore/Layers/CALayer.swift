// CALayer (Docs/elements/UIKit/CALayer.md): the retained visual tree. Every view owns a layer;
// the scene paints the layer tree into the display list. Geometry is CoreAnimation's: `bounds`,
// `position` and `anchorPoint` define `frame`; the transform applies about the anchor.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A 3D transform, kept to its affine part (the painter is 2D).
public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat = 1, m12: CGFloat = 0, m13: CGFloat = 0, m14: CGFloat = 0
    public var m21: CGFloat = 0, m22: CGFloat = 1, m23: CGFloat = 0, m24: CGFloat = 0
    public var m31: CGFloat = 0, m32: CGFloat = 0, m33: CGFloat = 1, m34: CGFloat = 0
    public var m41: CGFloat = 0, m42: CGFloat = 0, m43: CGFloat = 0, m44: CGFloat = 1

    public init() {}

    public init(affine: CGAffineTransform) {
        m11 = affine.a; m12 = affine.b; m21 = affine.c; m22 = affine.d; m41 = affine.tx; m42 = affine.ty
    }

    /// The affine part.
    public var affine: CGAffineTransform { CGAffineTransform(a: m11, b: m12, c: m21, d: m22, tx: m41, ty: m42) }
    public var isIdentity: Bool { self == CATransform3D() }
}

public let CATransform3DIdentity = CATransform3D()
public func CATransform3DMakeAffineTransform(_ m: CGAffineTransform) -> CATransform3D { CATransform3D(affine: m) }
public func CATransform3DGetAffineTransform(_ t: CATransform3D) -> CGAffineTransform { t.affine }
public func CATransform3DIsIdentity(_ t: CATransform3D) -> Bool { t.isIdentity }
public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D { CATransform3D(affine: CGAffineTransform(translationX: tx, y: ty)) }
public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D { CATransform3D(affine: CGAffineTransform(scaleX: sx, y: sy)) }
public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D { CATransform3D(affine: CGAffineTransform(rotationAngle: z >= 0 ? angle : -angle)) }

/// Which corners a layer's `cornerRadius` rounds.
public struct CACornerMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let layerMinXMinYCorner = CACornerMask(rawValue: 1)
    public static let layerMaxXMinYCorner = CACornerMask(rawValue: 2)
    public static let layerMinXMaxYCorner = CACornerMask(rawValue: 4)
    public static let layerMaxXMaxYCorner = CACornerMask(rawValue: 8)
    public static let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
}

/// The corner curve of a rounded layer.
public struct CALayerCornerCurve: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

/// An object that manages image-based content and allows you to perform animations on that
/// content.
@preconcurrency @MainActor
open class CALayer {
    // MARK: Geometry

    /// The layer's own coordinate rectangle: its size, and the origin its content is scrolled to.
    open var bounds = CGRect.zero {
        didSet {
            if bounds != oldValue {
                UIViewAnimationContext.record(self, .bounds, from: .rect(oldValue), to: .rect(bounds))
                boundsDidChange(from: oldValue)
            }
        }
    }
    /// Where the anchor point sits in the superlayer's coordinates.
    open var position = CGPoint.zero {
        didSet {
            if position != oldValue {
                UIViewAnimationContext.record(self, .position, from: .point(oldValue), to: .point(position))
                setNeedsDisplay()
            }
        }
    }
    /// The animation groups with a running animation of one of this layer's properties.
    var animatingGroups: [UIViewAnimationGroup] = []
    /// The point of `bounds`, in unit coordinates, that `position` places and transforms pivot on.
    open var anchorPoint = CGPoint(x: 0.5, y: 0.5) {
        didSet { if anchorPoint != oldValue { setNeedsDisplay() } }
    }
    open var zPosition: CGFloat = 0
    open var transform = CATransform3DIdentity {
        didSet {
            if transform != oldValue {
                UIViewAnimationContext.record(self, .transform, from: .transform(oldValue.affine), to: .transform(transform.affine))
                setNeedsDisplay()
            }
        }
    }

    /// The layer's frame in its superlayer's coordinates, from the bounds, position and anchor
    /// (with the transform applied, as CoreAnimation does).
    open var frame: CGRect {
        get {
            let untransformed = CGRect(x: position.x - bounds.width * anchorPoint.x, y: position.y - bounds.height * anchorPoint.y,
                                       width: bounds.width, height: bounds.height)
            if transform.isIdentity { return untransformed }
            return untransformed.applying(transformAboutAnchor)
        }
        set {
            // Setting the frame with a transform in place is undefined in CoreAnimation; the
            // untransformed frame is set.
            bounds.size = newValue.size
            position = CGPoint(x: newValue.minX + newValue.width * anchorPoint.x, y: newValue.minY + newValue.height * anchorPoint.y)
        }
    }

    /// The affine transform applied about the anchor, in superlayer coordinates.
    var transformAboutAnchor: CGAffineTransform {
        let anchor = CGPoint(x: position.x, y: position.y)
        return CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(transform.affine)
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    }

    public func affineTransform() -> CGAffineTransform { transform.affine }
    public func setAffineTransform(_ m: CGAffineTransform) { transform = CATransform3D(affine: m) }

    func boundsDidChange(from old: CGRect) {
        setNeedsDisplay()
        if old.size != bounds.size { setNeedsLayout() }
    }

    // MARK: Appearance

    open var backgroundColor: CGColor? {
        didSet {
            UIViewAnimationContext.record(self, .backgroundColor, from: .color(oldValue.flatMap { RGBA(cgColor: $0) }), to: .color(backgroundColor.flatMap { RGBA(cgColor: $0) }))
            setNeedsDisplay()
        }
    }
    open var cornerRadius: CGFloat = 0 {
        didSet {
            if cornerRadius != oldValue { UIViewAnimationContext.record(self, .cornerRadius, from: .scalar(Double(oldValue)), to: .scalar(Double(cornerRadius))) }
            setNeedsDisplay()
        }
    }
    open var maskedCorners: CACornerMask = .all { didSet { setNeedsDisplay() } }
    open var cornerCurve: CALayerCornerCurve = .circular { didSet { setNeedsDisplay() } }
    open var borderWidth: CGFloat = 0 {
        didSet {
            if borderWidth != oldValue { UIViewAnimationContext.record(self, .borderWidth, from: .scalar(Double(oldValue)), to: .scalar(Double(borderWidth))) }
            setNeedsDisplay()
        }
    }
    open var borderColor: CGColor? = CGColor(red: 0, green: 0, blue: 0, alpha: 1) {
        didSet {
            UIViewAnimationContext.record(self, .borderColor, from: .color(oldValue.flatMap { RGBA(cgColor: $0) }), to: .color(borderColor.flatMap { RGBA(cgColor: $0) }))
            setNeedsDisplay()
        }
    }
    open var opacity: Float = 1 {
        didSet {
            if opacity != oldValue { UIViewAnimationContext.record(self, .opacity, from: .scalar(Double(oldValue)), to: .scalar(Double(opacity))) }
            setNeedsDisplay()
        }
    }
    open var isHidden = false { didSet { setNeedsDisplay() } }
    open var masksToBounds = false { didSet { setNeedsDisplay() } }
    open var shadowColor: CGColor? = CGColor(red: 0, green: 0, blue: 0, alpha: 1) { didSet { setNeedsDisplay() } }
    open var shadowOpacity: Float = 0 {
        didSet {
            if shadowOpacity != oldValue { UIViewAnimationContext.record(self, .shadowOpacity, from: .scalar(Double(oldValue)), to: .scalar(Double(shadowOpacity))) }
            setNeedsDisplay()
        }
    }
    open var shadowOffset = CGSize(width: 0, height: -3) { didSet { setNeedsDisplay() } }
    open var shadowRadius: CGFloat = 3 { didSet { setNeedsDisplay() } }
    /// The shape that casts the shadow instead of the layer's composite (in the layer's
    /// bounds). Painted as that shape in the layer's background colour under the layer, so a
    /// transparent layer's shadow path casts nothing (open).
    open var shadowPath: Path? { didSet { setNeedsDisplay() } }
    open var contentsScale: CGFloat = 2
    /// Whether the layer promises to be fully opaque (a drawing hint; the painters do not read it).
    open var isOpaque = false
    /// The layer's image (a `CGImage`), drawn in its bounds by `contentsGravity` after its
    /// background and in place of its view's own content (LayerPainting.swift).
    open var contents: Any? { didSet { setNeedsDisplay() } }
    open var contentsGravity: CALayerContentsGravity = .resize { didSet { setNeedsDisplay() } }
    /// The part of the image shown, in unit coordinates (all of it by default).
    open var contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1) { didSet { setNeedsDisplay() } }
    open var contentsCenter = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsFormat: CALayerContentsFormat = .RGBA8Uint
    /// Whether `setNeedsDisplay` asked for `display` before the next paint.
    var needsDisplayCall = false
    open var name: String?
    /// Whether the layer has been painted: a standalone layer's property changes animate
    /// implicitly only once it has a presentation, as in Core Animation (a layer added and
    /// configured in the same transaction shows its values at once).
    var isCommitted = false
    /// A mask layer: its alpha clips this layer's content (its own fill and shape, if any).
    open var mask: CALayer?
    /// A popover's shape (Containers/UIAlertController.swift): the card's rounded rect over
    /// `popoverCardHeight` with the arrow at `popoverArrow` (in the layer's bounds); the
    /// background fills it and `masksToBounds` clips to it.
    package var popoverArrow: CGRect? { didSet { setNeedsDisplay() } }
    var popoverArrowPointsDown = true
    var popoverCardHeight: CGFloat = 0

    // MARK: Tree

    public private(set) var sublayers: [CALayer]?
    public private(set) weak var superlayer: CALayer?
    /// The view this layer draws for, if it is a view's layer.
    weak var view: UIView?
    /// The explicit animations added by key (Layers/CAAnimation.swift).
    var explicitAnimations: [String: (animation: CAAnimation, group: UIViewAnimationGroup)] = [:]

    public required init() {}

    /// A copy of a layer's properties (`init(layer:)` in CoreAnimation).
    public init(layer: Any) {
        if let other = layer as? CALayer {
            bounds = other.bounds; position = other.position; anchorPoint = other.anchorPoint; transform = other.transform
            backgroundColor = other.backgroundColor; cornerRadius = other.cornerRadius; opacity = other.opacity
        }
    }

    open func addSublayer(_ layer: CALayer) {
        layer.removeFromSuperlayer()
        layer.superlayer = self
        sublayers = (sublayers ?? []) + [layer]
        setNeedsDisplay()
    }

    open func insertSublayer(_ layer: CALayer, at index: UInt32) {
        layer.removeFromSuperlayer()
        layer.superlayer = self
        var list = sublayers ?? []
        list.insert(layer, at: min(Int(index), list.count))
        sublayers = list
        setNeedsDisplay()
    }

    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        guard let sibling, let index = sublayers?.firstIndex(where: { $0 === sibling }) else { return addSublayer(layer) }
        insertSublayer(layer, at: UInt32(index))
    }

    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        guard let sibling, let index = sublayers?.firstIndex(where: { $0 === sibling }) else { return addSublayer(layer) }
        insertSublayer(layer, at: UInt32(index + 1))
    }

    open func removeFromSuperlayer() {
        guard let superlayer else { return }
        superlayer.sublayers?.removeAll { $0 === self }
        if superlayer.sublayers?.isEmpty == true { superlayer.sublayers = nil }
        superlayer.setNeedsDisplay()
        self.superlayer = nil
    }

    /// Moves `layer` in the sublayer order (views reorder their subviews through it).
    func move(_ layer: CALayer, to index: Int) {
        guard var list = sublayers, let current = list.firstIndex(where: { $0 === layer }) else { return }
        list.remove(at: current)
        list.insert(layer, at: min(index, list.count))
        sublayers = list
        setNeedsDisplay()
    }

    // MARK: Invalidation

    /// Marks the layer's content as needing to be drawn again (the next frame repaints the tree).
    open func setNeedsDisplay() {
        needsDisplayCall = true
        UIKitScene.shared.setNeedsFrame()
    }

    open func setNeedsDisplay(_ rect: CGRect) { setNeedsDisplay() }

    open func setNeedsLayout() {
        view?.setNeedsLayout()
        UIKitScene.shared.setNeedsFrame()
    }

    open func layoutIfNeeded() { view?.layoutIfNeeded() }
    open func layoutSublayers() {}
    /// Updates the contents: a view's layer asks its view (`display(_:)`), as Core Animation
    /// asks the layer's delegate. Called before the paint after `setNeedsDisplay`.
    open func display() { view?.display(self) }
    open func displayIfNeeded() {
        guard needsDisplayCall else { return }
        needsDisplayCall = false
        display()
        needsDisplayCall = false   // what `display` set does not ask again
    }
    open func needsDisplay() -> Bool { needsDisplayCall }

    // MARK: Geometry queries

    /// Converts a point from `layer`'s coordinate space (nil: the root) to this layer's.
    open func convert(_ point: CGPoint, from layer: CALayer?) -> CGPoint {
        let absolute = layer.map { $0.convertToRoot(point) } ?? point
        return convertFromRoot(absolute)
    }

    open func convert(_ point: CGPoint, to layer: CALayer?) -> CGPoint {
        let absolute = convertToRoot(point)
        return layer.map { $0.convertFromRoot(absolute) } ?? absolute
    }

    /// A rect through a rotation or skew comes back as its bounding box, as Core Animation's does.
    open func convert(_ rect: CGRect, from layer: CALayer?) -> CGRect {
        let toRoot = layer?.transformToRoot ?? .identity
        return rect.applying(toRoot.concatenating(transformToRoot.inverted()))
    }

    open func convert(_ rect: CGRect, to layer: CALayer?) -> CGRect {
        let fromRoot = layer?.transformToRoot.inverted() ?? .identity
        return rect.applying(transformToRoot.concatenating(fromRoot))
    }

    /// The transform from this layer's coordinates to its superlayer's.
    var transformToSuperlayer: CGAffineTransform {
        let origin = CGPoint(x: position.x - bounds.width * anchorPoint.x - bounds.minX, y: position.y - bounds.height * anchorPoint.y - bounds.minY)
        let translate = CGAffineTransform(translationX: origin.x, y: origin.y)
        return transform.isIdentity ? translate : translate.concatenating(transformAboutAnchor)
    }

    /// The transform from this layer's coordinates to the root layer's.
    var transformToRoot: CGAffineTransform {
        var t = transformToSuperlayer
        var ancestor = superlayer
        while let layer = ancestor {
            t = t.concatenating(layer.transformToSuperlayer)
            ancestor = layer.superlayer
        }
        return t
    }

    func convertToRoot(_ point: CGPoint) -> CGPoint { point.applying(transformToRoot) }
    func convertFromRoot(_ point: CGPoint) -> CGPoint { point.applying(transformToRoot.inverted()) }

    open func contains(_ point: CGPoint) -> Bool { bounds.contains(point) }

    /// The deepest sublayer (or this layer) containing `point`, given in the superlayer's space.
    open func hitTest(_ point: CGPoint) -> CALayer? {
        let local = point.applying(transformToSuperlayer.inverted())
        guard !isHidden, opacity > 0, bounds.contains(local) || !masksToBounds else { return nil }
        for layer in (sublayers ?? []).reversed() {
            if let hit = layer.hitTest(local) { return hit }
        }
        return bounds.contains(local) ? self : nil
    }
}

/// A layer that draws a path.
@preconcurrency @MainActor
open class CAShapeLayer: CALayer {
    /// The path in the layer's coordinates (a WebGraphics `Path`; `UIBezierPath.cgPath` gives one).
    open var path: Path? { didSet { setNeedsDisplay() } }
    open var fillColor: CGColor? = CGColor(red: 0, green: 0, blue: 0, alpha: 1) { didSet { setNeedsDisplay() } }
    open var strokeColor: CGColor? { didSet { setNeedsDisplay() } }
    open var lineWidth: CGFloat = 1 { didSet { setNeedsDisplay() } }
    open var lineCap: CGLineCap = .butt { didSet { setNeedsDisplay() } }
    open var lineJoin: CGLineJoin = .miter { didSet { setNeedsDisplay() } }
    open var lineDashPattern: [CGFloat]? { didSet { setNeedsDisplay() } }
    open var lineDashPhase: CGFloat = 0 { didSet { setNeedsDisplay() } }
    open var miterLimit: CGFloat = 10 { didSet { setNeedsDisplay() } }
    open var strokeStart: CGFloat = 0 { didSet { setNeedsDisplay() } }
    open var strokeEnd: CGFloat = 1 { didSet { setNeedsDisplay() } }
    open var fillRule: CAShapeLayerFillRule = .nonZero { didSet { setNeedsDisplay() } }

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }
}

public struct CAShapeLayerFillRule: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let nonZero = CAShapeLayerFillRule(rawValue: "non-zero")
    public static let evenOdd = CAShapeLayerFillRule(rawValue: "even-odd")
}

// MARK: - Gradient and text layers (uikit/layer/content)

public struct CAGradientLayerType: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let axial = CAGradientLayerType(rawValue: "axial")
    public static let radial = CAGradientLayerType(rawValue: "radial")
    public static let conic = CAGradientLayerType(rawValue: "conic")
}

/// A layer that draws a colour gradient over its bounds: axial between `startPoint` and
/// `endPoint` (unit coordinates), radial as the ellipse centred on the start whose radii reach
/// the end point, conic around the start beginning in the end point's direction.
@preconcurrency @MainActor
open class CAGradientLayer: CALayer {
    open var colors: [CGColor]? { didSet { setNeedsDisplay() } }
    /// The stops' positions (0…1), as doubles: a literal array works on both platforms.
    open var locations: [Double]? { didSet { setNeedsDisplay() } }
    open var startPoint = CGPoint(x: 0.5, y: 0) { didSet { setNeedsDisplay() } }
    open var endPoint = CGPoint(x: 0.5, y: 1) { didSet { setNeedsDisplay() } }
    open var type: CAGradientLayerType = .axial { didSet { setNeedsDisplay() } }

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }

    /// The stops: the colours at their locations, evenly spread without any.
    var stops: [DisplayGradient.Stop] {
        let colors = (self.colors ?? []).compactMap { RGBA(cgColor: $0) }
        guard !colors.isEmpty else { return [] }
        let locations = self.locations
        return colors.enumerated().map { index, color in
            let location = locations?.indices.contains(index) == true ? locations![index] : (colors.count > 1 ? Double(index) / Double(colors.count - 1) : 0)
            return DisplayGradient.Stop(location: location, color: color)
        }
    }

    func paintGradient(into list: inout DisplayList, context: PaintContext) {
        let stops = self.stops
        guard !stops.isEmpty else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let start = CGPoint(x: rect.minX + startPoint.x * rect.width, y: rect.minY + startPoint.y * rect.height)
        let end = CGPoint(x: rect.minX + endPoint.x * rect.width, y: rect.minY + endPoint.y * rect.height)
        switch type {
        case .radial:
            // An ellipse with the end point's offsets as radii: a circle drawn under a scale.
            let rx = max(0.5, abs(end.x - start.x)), ry = max(0.5, abs(end.y - start.y))
            let scaleY = ry / rx
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: 0, y: start.y).scaledBy(x: 1, y: scaleY).translatedBy(x: 0, y: -start.y)))
            let region = Path(CGRect(x: rect.minX, y: start.y + (rect.minY - start.y) / scaleY, width: rect.width, height: rect.height / scaleY))
            list.append(.fillGradient(region, DisplayGradient(kind: .radial(center: start, startRadius: 0, endRadius: rx), stops: stops)))
            list.append(.restore)
        case .conic:
            let angle = Double(_atan2(end.y - start.y, end.x - start.x))
            list.append(.fillGradient(Path(rect), DisplayGradient(kind: .angular(center: start, startAngle: angle), stops: stops)))
        default:
            list.append(.fillGradient(Path(rect), DisplayGradient(kind: .linear(start: start, end: end), stops: stops)))
        }
    }
}

public struct CATextLayerAlignmentMode: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let natural = CATextLayerAlignmentMode(rawValue: "natural")
    public static let left = CATextLayerAlignmentMode(rawValue: "left")
    public static let right = CATextLayerAlignmentMode(rawValue: "right")
    public static let center = CATextLayerAlignmentMode(rawValue: "center")
    public static let justified = CATextLayerAlignmentMode(rawValue: "justified")
}

public struct CATextLayerTruncationMode: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let none = CATextLayerTruncationMode(rawValue: "none")
    public static let start = CATextLayerTruncationMode(rawValue: "start")
    public static let end = CATextLayerTruncationMode(rawValue: "end")
    public static let middle = CATextLayerTruncationMode(rawValue: "middle")
}

/// A layer that draws a string from its top edge in Helvetica (Core Animation's default
/// font), wrapped when asked, aligned by `alignmentMode`.
@preconcurrency @MainActor
open class CATextLayer: CALayer {
    open var string: Any? { didSet { setNeedsDisplay() } }
    /// A `UIFont` or a font name; nil draws Helvetica at `fontSize`.
    open var font: Any? { didSet { setNeedsDisplay() } }
    open var fontSize: CGFloat = 36 { didSet { setNeedsDisplay() } }
    open var foregroundColor: CGColor? = CGColor(red: 0, green: 0, blue: 0, alpha: 1) { didSet { setNeedsDisplay() } }
    open var isWrapped = false { didSet { setNeedsDisplay() } }
    open var alignmentMode: CATextLayerAlignmentMode = .natural { didSet { setNeedsDisplay() } }
    open var truncationMode: CATextLayerTruncationMode = .none { didSet { setNeedsDisplay() } }
    open var allowsFontSubpixelQuantization = false

    public required init() { super.init() }
    public override init(layer: Any) { super.init(layer: layer) }

    var text: String {
        if let string = string as? String { return string }
        if let attributed = string as? NSAttributedString { return attributed.string }
        return string.map { "\($0)" } ?? ""
    }

    var resolvedFont: UIFont {
        if let font = font as? UIFont { return font.withSize(fontSize) }
        if let name = font as? String, let named = UIFont(name: name, size: fontSize) { return named }
        return UIFont(name: "Helvetica", size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    func paintText(into list: inout DisplayList, context: PaintContext) {
        let text = self.text
        guard !text.isEmpty, let color = foregroundColor.flatMap({ RGBA(cgColor: $0) }) else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let font = resolvedFont
        let truncation: TextTruncationMode = truncationMode == .start ? .head : truncationMode == .middle ? .middle : .tail
        let options = TextLayoutOptions(lineLimit: isWrapped ? nil : 1, truncationMode: truncation)
        let layout = UIKitScene.shared.textEngine.layout([StyledRun(text, font: font.resolved)], options: options, width: isWrapped ? bounds.width : nil)
        let displayFont = DisplayFont(font.resolved)
        var y = rect.minY + font.ascender
        for line in layout.lines {
            let width = line.inkWidth
            let x: CGFloat
            switch alignmentMode {
            case .center: x = rect.midX - width / 2
            case .right: x = rect.maxX - width
            default: x = rect.minX
            }
            for fragment in line.fragments {
                list.append(.drawText(fragment.text, displayFont, origin: CGPoint(x: x + fragment.x, y: y), color))
            }
            y += font.lineHeight
        }
    }
}

/// Where a layer's contents image sits in its bounds.
public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let top = CALayerContentsGravity(rawValue: "top")
    public static let bottom = CALayerContentsGravity(rawValue: "bottom")
    public static let left = CALayerContentsGravity(rawValue: "left")
    public static let right = CALayerContentsGravity(rawValue: "right")
    public static let topLeft = CALayerContentsGravity(rawValue: "topLeft")
    public static let topRight = CALayerContentsGravity(rawValue: "topRight")
    public static let bottomLeft = CALayerContentsGravity(rawValue: "bottomLeft")
    public static let bottomRight = CALayerContentsGravity(rawValue: "bottomRight")
    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
}

/// The pixel format of a layer's backing store (every layer here is painted, so all alike).
public struct CALayerContentsFormat: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let RGBA8Uint = CALayerContentsFormat(rawValue: "RGBA8")
    public static let RGBA16Float = CALayerContentsFormat(rawValue: "RGBAh")
    public static let gray8Uint = CALayerContentsFormat(rawValue: "Gray8")
}
