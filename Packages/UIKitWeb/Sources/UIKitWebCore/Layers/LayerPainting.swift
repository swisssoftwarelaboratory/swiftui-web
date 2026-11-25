// Painting the layer tree into the display list (decision 0014: UIKit views are painted
// leaves of the same display list SwiftUI views use). A layer paints its background, border and
// shadow, its view's content, then its sublayers in order; opacity and shadows are groups;
// `masksToBounds` clips. Frame edges are rounded to the pixel grid like SwiftUIWeb's.

extension CALayer {
    /// Paints this layer and its sublayers. `context.origin` is the absolute position of the
    /// superlayer's bounds origin; the layer's own transform, if any, is concatenated.
    func paint(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        // The presented geometry and looks: the running animations' values, else the model's.
        let animating = !animatingGroups.isEmpty
        let position = animating ? presented(.position, model: .point(self.position)).point : self.position
        let bounds = animating ? presented(.bounds, model: .rect(self.bounds)).rect : self.bounds
        let opacity = animating ? Float(presented(.opacity, model: .scalar(Double(self.opacity))).scalar) : self.opacity
        let affine = animating ? presented(.transform, model: .transform(self.transform.affine)).transform : self.transform.affine
        let cornerRadius = animating ? CGFloat(presented(.cornerRadius, model: .scalar(Double(self.cornerRadius))).scalar) : self.cornerRadius
        let borderWidth = animating ? CGFloat(presented(.borderWidth, model: .scalar(Double(self.borderWidth))).scalar) : self.borderWidth
        let shadowOpacity = animating ? Float(presented(.shadowOpacity, model: .scalar(Double(self.shadowOpacity))).scalar) : self.shadowOpacity
        let background: RGBA? = animating ? presented(.backgroundColor, model: .color(backgroundColor.flatMap { RGBA(cgColor: $0) })).color : backgroundColor.flatMap { RGBA(cgColor: $0) }
        let border: RGBA? = animating ? presented(.borderColor, model: .color(borderColor.flatMap { RGBA(cgColor: $0) })).color : borderColor.flatMap { RGBA(cgColor: $0) }
        isCommitted = true
        guard !isHidden, opacity > 0 else { return }
        displayIfNeeded()
        let effective = view?.effectiveStyle(style) ?? style
        // The layer's origin in the superlayer's space, without the transform.
        let origin = CGPoint(x: position.x - bounds.width * anchorPoint.x, y: position.y - bounds.height * anchorPoint.y)
        var child = context.child(at: CGRect(origin: origin, size: bounds.size))
        let transformed = !affine.isIdentity
        if transformed {
            list.append(.save)
            let anchor = CGPoint(x: context.origin.x + position.x, y: context.origin.y + position.y)
            let t = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                .concatenating(affine)
                .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
            list.append(.concat(t))
        }
        let rect = child.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        var groups = 0
        if opacity < 1 {
            list.append(.beginGroup(opacity: Double(opacity)))
            groups += 1
        }
        if let mask {
            // The mask's alpha (its own fill and shape) clips everything the layer paints.
            list.append(.beginMask(bounds: rect))
            var maskContext = child
            maskContext.origin = CGPoint(x: child.origin.x - bounds.minX, y: child.origin.y - bounds.minY)
            mask.paint(into: &list, context: maskContext, style: effective)
            list.append(.beginMasked)
            groups += 1
        }
        if shadowOpacity > 0, let shadowColor, let color = RGBA(cgColor: shadowColor) {
            let shadow = color.multiplyingAlpha(by: Double(shadowOpacity))
            if let shadowPath {
                // The shadow path casts the shadow on its own, in the layer's background colour
                // (nothing without one), under what the layer paints.
                if let fill = background, fill.alpha > 0 {
                    list.append(.beginShadow(shadow, radius: shadowRadius, offset: CGSize(width: shadowOffset.width, height: shadowOffset.height)))
                    list.append(.fillPath(shadowPath.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)), fill))
                    list.append(.endGroup)
                }
            } else {
                list.append(.beginShadow(shadow, radius: shadowRadius, offset: CGSize(width: shadowOffset.width, height: shadowOffset.height)))
                groups += 1
            }
        }
        // CoreAnimation does not clamp a corner radius past half a side: the arcs cross and the
        // nonzero fill makes a lens (uikit/view/looks `overRadius`); the painter's rounded rects
        // clamp, so those corners take an explicit path.
        // A drawing that blends or clears composites against the view's own background and
        // earlier drawing, as in a layer's backing store: the view's painting goes in a group.
        if let view, view.drawingRecorded(scale: context.scale).usesBlending {
            list.append(.beginGroup(opacity: 1))
            groups += 1
        }
        let overRadius = cornerRadius > min(rect.width, rect.height) / 2 && maskedCorners == .all && cornerCurve == .circular
        let radius = cornerRadius > 0 && maskedCorners == .all && !overRadius ? min(cornerRadius, min(rect.width, rect.height) / 2) : 0
        let popoverShape = popoverArrow.map { Self.popoverPath(rect, arrow: $0, pointsDown: popoverArrowPointsDown, cardHeight: popoverCardHeight, radius: cornerRadius) }
        if let color = background, color.alpha > 0 {
            if let popoverShape {
                list.append(.fillPath(popoverShape, color))
            } else if overRadius {
                list.append(.fillPath(Self.unclampedCornerPath(rect, radius: cornerRadius), color))
            } else if cornerRadius > 0, maskedCorners != .all {
                list.append(.fillPath(Self.cornerPath(rect, radius: cornerRadius, corners: maskedCorners, curve: cornerCurve), color))
            } else if radius > 0 {
                if cornerCurve == .continuous {
                    list.append(.fillPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), color))
                } else {
                    list.append(.fillRRect(rect, cornerRadius: radius, color))
                }
            } else {
                list.append(.fillRect(rect, color))
            }
        }
        if masksToBounds {
            list.append(.save)
            if let popoverShape {
                list.append(.clipPath(popoverShape))
            } else if overRadius {
                list.append(.clipPath(Self.unclampedCornerPath(rect, radius: cornerRadius)))
            } else if cornerRadius > 0, maskedCorners != .all {
                list.append(.clipPath(Self.cornerPath(rect, radius: cornerRadius, corners: maskedCorners, curve: cornerCurve)))
            } else if radius > 0 {
                list.append(cornerCurve == .continuous ? .clipPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous)) : .clipRRect(rect, cornerRadius: radius))
            } else {
                list.append(.clipRect(rect))
            }
        }
        // The content is scrolled by the bounds origin.
        child.origin = CGPoint(x: child.origin.x - bounds.minX, y: child.origin.y - bounds.minY)
        if let shape = self as? CAShapeLayer {
            shape.paintShape(into: &list, context: child)
        } else if let gradient = self as? CAGradientLayer {
            gradient.paintGradient(into: &list, context: child)
        } else if let text = self as? CATextLayer {
            text.paintText(into: &list, context: child)
        }
        #if !canImport(CoreGraphics) || os(WASI)
        let paintedContents = paintContents(into: &list, in: rect)
        #else
        let paintedContents = false
        #endif
        if !paintedContents { view?.drawContent(into: &list, context: child, style: effective) }
        // A layer whose picture the browser draws (a player's video, a Metal layer's drawable).
        if let surface = _surface { list.append(.drawSurface(surface.id, rect: rect, fit: surface.fit)) }
        for layer in (sublayers ?? []).sorted(by: { $0.zPosition < $1.zPosition }) {
            layer.paint(into: &list, context: child, style: effective)
        }
        if masksToBounds { list.append(.restore) }
        if borderWidth > 0, let color = border, color.alpha > 0 {
            // The border is drawn inside the bounds, centred on a line half the width in.
            let inset = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
            let path: Path
            if cornerRadius > 0, maskedCorners != .all {
                path = Self.cornerPath(inset, radius: max(0, cornerRadius - borderWidth / 2), corners: maskedCorners, curve: cornerCurve)
            } else if radius > 0 {
                path = Path(roundedRect: inset, cornerRadius: max(0, radius - borderWidth / 2), style: cornerCurve == .continuous ? .continuous : .circular)
            } else {
                path = Path(inset)
            }
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: borderWidth), color))
        }
        for _ in 0..<groups { list.append(.endGroup) }
        if transformed { list.append(.restore) }
    }

    /// CoreAnimation's rounded rectangle with a radius past half a side: the quarter arcs are
    /// laid out as if they fit, the straight edges run backwards, and the nonzero fill of the
    /// crossing path is a lens.
    static func unclampedCornerPath(_ rect: CGRect, radius r: CGFloat) -> Path {
        let k: CGFloat = 0.5522847498 * r
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control1: CGPoint(x: rect.maxX - r + k, y: rect.minY), control2: CGPoint(x: rect.maxX, y: rect.minY + r - k))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control1: CGPoint(x: rect.maxX, y: rect.maxY - r + k), control2: CGPoint(x: rect.maxX - r + k, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control1: CGPoint(x: rect.minX + r - k, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.maxY - r + k))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.minY + r - k), control2: CGPoint(x: rect.minX + r - k, y: rect.minY))
        path.closeSubpath()
        return path
    }

    /// A rectangle with only some corners rounded.
    static func cornerPath(_ rect: CGRect, radius: CGFloat, corners: CACornerMask, curve: CALayerCornerCurve) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let radii = RectangleCornerRadii(
            topLeading: corners.contains(.layerMinXMinYCorner) ? r : 0,
            bottomLeading: corners.contains(.layerMinXMaxYCorner) ? r : 0,
            bottomTrailing: corners.contains(.layerMaxXMaxYCorner) ? r : 0,
            topTrailing: corners.contains(.layerMaxXMinYCorner) ? r : 0)
        return Path(roundedRect: rect, cornerRadii: radii, style: curve == .continuous ? .continuous : .circular)
    }
}

extension CAShapeLayer {
    /// Fills and strokes the path in the layer's coordinates (absolute through the context).
    func paintShape(into list: inout DisplayList, context: PaintContext) {
        guard var path else { return }
        if strokeStart > 0 || strokeEnd < 1 { path = path.trimmedPath(from: strokeStart, to: strokeEnd) }
        let shift = CGAffineTransform(translationX: context.origin.x, y: context.origin.y)
        let absolute = path.applying(shift)
        if let fillColor, let color = RGBA(cgColor: fillColor), color.alpha > 0 {
            list.append(.fillPath(absolute, color, eoFill: fillRule == .evenOdd))
        }
        if let strokeColor, let color = RGBA(cgColor: strokeColor), color.alpha > 0, lineWidth > 0 {
            list.append(.strokePath(absolute, style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, miterLimit: miterLimit,
                                                                 dash: lineDashPattern ?? [], dashPhase: lineDashPhase), color))
        }
    }
}

extension CALayer {
    /// A popover's card with its arrow: the rounded card over `cardHeight` (at the top when the
    /// arrow points down, else under the arrow) and the arrow's triangle, one path.
    static func popoverPath(_ rect: CGRect, arrow: CGRect, pointsDown: Bool, cardHeight: CGFloat, radius: CGFloat) -> Path {
        let card = CGRect(x: rect.minX, y: pointsDown ? rect.minY : rect.minY + (rect.height - cardHeight), width: rect.width, height: cardHeight)
        var path = Path(roundedRect: card, cornerRadius: min(radius, min(card.width, card.height) / 2), style: .continuous)
        let a = CGRect(x: rect.minX + arrow.minX, y: rect.minY + arrow.minY, width: arrow.width, height: arrow.height)
        if pointsDown {
            path.move(to: CGPoint(x: a.minX, y: a.minY - 1))
            path.addLine(to: CGPoint(x: a.midX, y: a.maxY))
            path.addLine(to: CGPoint(x: a.maxX, y: a.minY - 1))
        } else {
            path.move(to: CGPoint(x: a.minX, y: a.maxY + 1))
            path.addLine(to: CGPoint(x: a.midX, y: a.minY))
            path.addLine(to: CGPoint(x: a.maxX, y: a.maxY + 1))
        }
        path.closeSubpath()
        return path
    }
}
