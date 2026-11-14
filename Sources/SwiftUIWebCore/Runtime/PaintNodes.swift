// Nodes that draw: colours, shapes, text, and the modifiers that layer, fade or clip.

/// Node for a shape view (`_ShapeView`, `FillShapeView`, `StrokeShapeView`, …): the view sizes
/// and paints itself.
@MainActor
package final class ShapeNode<V: _ShapePainting>: LeafNode<V> {
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        view._shapeSizeThatFits(proposal)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        _withContainerShape(for: self) { view._paintShape(in: absoluteBounds(context), environment: environment, scale: context.scale, into: &list) }
    }
}

/// Background / overlay: a second subtree laid out against the content's size. When the content
/// is a list, every element gets its own layer instance (`Group { A; B }.background(...)` draws
/// two backgrounds), created when the element is first placed and dropped when it goes away.
@MainActor
package final class LayeredNode<Content: View, Modifier: ViewModifier, Layer: View>: UnaryLayoutModifierNode<Content, Modifier> {
    private struct Slot {
        weak var target: ViewNode?
        let layer: TypedNode<Layer>
    }

    package enum Mode { case background, overlay, mask }

    private var slots: [ObjectIdentifier: Slot] = [:]
    private let layerPath: KeyPath<ModifiedContent<Content, Modifier>, Layer>
    private let alignmentPath: KeyPath<ModifiedContent<Content, Modifier>, Alignment>
    private let mode: Mode

    package init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>,
                 layer: KeyPath<ModifiedContent<Content, Modifier>, Layer>,
                 alignment: KeyPath<ModifiedContent<Content, Modifier>, Alignment>, mode: Mode) {
        layerPath = layer
        alignmentPath = alignment
        self.mode = mode
        super.init(context)
        for target in targets { _ = self.layer(for: target) }
    }

    package convenience init(_ context: _NodeContext<ModifiedContent<Content, Modifier>>,
                             layer: KeyPath<ModifiedContent<Content, Modifier>, Layer>,
                             alignment: KeyPath<ModifiedContent<Content, Modifier>, Alignment>, isOverlay: Bool) {
        self.init(context, layer: layer, alignment: alignment, mode: isOverlay ? .overlay : .background)
    }

    /// The layer subtree for one element, in target order.
    package var layers: [TypedNode<Layer>] { targets.compactMap { slots[ObjectIdentifier($0)]?.layer } }

    /// For tests: the single layer of a non-list content.
    package var layer: TypedNode<Layer>! { layers.first }

    /// The environment the layer sees: a mask draws with an opaque black foreground (the
    /// label colour's 85 % alpha would otherwise fade the masked content).
    private var layerEnvironment: EnvironmentValues {
        guard mode == .mask else { return environment }
        var masked = environment
        masked.foregroundColor = .black
        masked.foregroundGradient = nil
        return masked
    }

    private func layer(for target: ViewNode) -> TypedNode<Layer> {
        let key = ObjectIdentifier(target)
        if let slot = slots[key], slot.target === target { return slot.layer }
        let node = Layer._makeNode(_NodeContext(view: view[keyPath: layerPath], parent: self, environment: layerEnvironment))
        slots[key] = Slot(target: target, layer: node)
        return node
    }

    override package func update(view: ModifiedContent<Content, Modifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        let live = Set(targets.map(ObjectIdentifier.init))
        for (key, slot) in slots where !live.contains(key) || slot.target == nil {
            slot.layer.unmount()
            slots[key] = nil
        }
        let layerEnvironment = layerEnvironment
        for target in targets {
            layer(for: target).update(view: view[keyPath: layerPath], environment: layerEnvironment, force: force)
        }
    }

    override package func unmount() {
        for slot in slots.values { slot.layer.unmount() }
        slots.removeAll()
        super.unmount()
    }

    override package func placeTarget(_ target: ViewNode, in bounds: CGRect, proposal: ProposedViewSize, by placer: ViewNode) {
        super.placeTarget(target, in: bounds, proposal: proposal, by: placer)
        // The layer is proposed the content's size and aligned within it.
        let alignment = view[keyPath: alignmentPath]
        let container = ViewDimensions(size: bounds.size)
        let layerProposal = ProposedViewSize(bounds.size)
        for node in layer(for: target).layoutChildren {
            let dims = node.dimensions(in: layerProposal)
            let origin = CGPoint(x: bounds.minX + container[alignment.horizontal] - dims[alignment.horizontal],
                                 y: bounds.minY + container[alignment.vertical] - dims[alignment.vertical])
            node.place(at: origin, anchor: .topLeading, proposal: layerProposal, by: placer)
        }
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let layerNodes = layer(for: target).layoutChildren
        switch mode {
        case .background:
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
            super.paintTarget(target, in: node, into: &list, context: context)
        case .overlay:
            super.paintTarget(target, in: node, into: &list, context: context)
            for layerNode in layerNodes { layerNode.paint(into: &list, context: context.child(at: layerNode.presentedFrame)) }
        case .mask:
            // The mask draws free of the distributed effects (they act on the masked result);
            // the content keeps them.
            var maskContext = context
            maskContext.effects = []
            list.append(.beginMask(bounds: context.absoluteRect(target.presentedFrame)))
            for layerNode in layerNodes { layerNode.paint(into: &list, context: maskContext.child(at: layerNode.presentedFrame)) }
            list.append(.beginMasked)
            super.paintTarget(target, in: node, into: &list, context: context)
            list.append(.endGroup)
        }
    }

    override package var structuralChildren: [ViewNode] { [child] + layers }
    override package var nodeDescription: String {
        switch mode {
        case .background: return "Background"
        case .overlay: return "Overlay"
        case .mask: return "Mask"
        }
    }
}

@MainActor
package final class OpacityNode<Content: View>: UnaryLayoutModifierNode<Content, _OpacityEffect> {
    override package func update(view: ModifiedContent<Content, _OpacityEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedOpacity
        let changed = modifier.opacity != view.modifier.opacity
        super.update(view: view, environment: environment, force: force)
        if changed {
            if let animation = runtime.effectiveUpdateAnimation(for: self) {
                let presentation = self.presentation ?? NodePresentation()
                presentation.opacity = Tween(from: [old], to: [view.modifier.opacity], animation: animation, start: runtime.animationClock, continuing: presentation.opacity)
                self.presentation = presentation
                runtime.register(animating: self)
            } else {
                presentation?.opacity = nil
            }
        }
    }

    /// The opacity to paint with: the tween's value while animating.
    package var presentedOpacity: Double {
        presentation?.opacity?.value(at: runtime.animationClock).first ?? modifier.opacity
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let opacity = presentedOpacity
        guard opacity > 0 else { return }
        if opacity >= 1 {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        var context = context
        context.effects.append(.opacity(opacity))
        super.paintTarget(target, in: node, into: &list, context: context)
    }
}

/// `shadow`: every element of the target paints into a group whose composite casts the shadow
/// (the painters blur the group's alpha), as SwiftUI does without a compositing group. Layout is
/// untouched and the shadow reaches outside the frame.
@MainActor
package final class ShadowNode<Content: View>: UnaryLayoutModifierNode<Content, _ShadowEffect> {
    override package var paintsOutsideFrame: Bool { true }

    private func values(_ modifier: _ShadowEffect, in environment: EnvironmentValues) -> [Double] {
        let c = modifier.color.resolve(in: environment)
        return [c.red, c.green, c.blue, c.alpha, max(0, modifier.radius), modifier.offset.width, modifier.offset.height]
    }

    override package func update(view: ModifiedContent<Content, _ShadowEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedValues
        let new = values(view.modifier, in: environment)
        super.update(view: view, environment: environment, force: force)
        _tweenEffect(from: old, to: new)
    }

    /// The shadow's colour, radius and offset: the tween's values while animating.
    private var presentedValues: [Double] {
        presentation?.effect?.value(at: runtime.animationClock) ?? values(modifier, in: environment)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let v = presentedValues
        let color = RGBA(red: v[0], green: v[1], blue: v[2], alpha: v[3])
        guard color.alpha > 0 else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        var context = context
        context.effects.append(.shadow(color, radius: v[4], offset: CGSize(width: v[5], height: v[6])))
        super.paintTarget(target, in: node, into: &list, context: context)
    }
}

extension ViewNode {
    /// Starts (or drops) a tween of an effect's values on a change under an animation
    /// (`presentation.effect`, the slot layouts use for their animatable data).
    package func _tweenEffect(from old: [Double], to new: [Double]) {
        guard old.count == new.count, old != new else {
            if old.count != new.count { presentation?.effect = nil }
            return
        }
        if let animation = runtime.effectiveUpdateAnimation(for: self) {
            let presentation = self.presentation ?? NodePresentation()
            presentation.effect = Tween(from: old, to: new, animation: animation, start: runtime.animationClock, continuing: presentation.effect)
            self.presentation = presentation
            runtime.register(animating: self)
        } else {
            presentation?.effect = nil
        }
    }
}

/// Colour effects: the target paints into a group the painters filter with the modifier's
/// matrix over the target's frame before compositing it.
@MainActor
package final class ColorMatrixNode<Content: View>: UnaryLayoutModifierNode<Content, _ColorMatrixEffect> {
    override package func update(view: ModifiedContent<Content, _ColorMatrixEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedValues
        let sameKind = modifier.sameKind(as: view.modifier)
        super.update(view: view, environment: environment, force: force)
        if sameKind {
            _tweenEffect(from: old, to: view.modifier.values(in: environment))
        } else {
            presentation?.effect = nil
        }
    }

    private var presentedValues: [Double] {
        presentation?.effect?.value(at: runtime.animationClock) ?? modifier.values(in: environment)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let matrix = _ColorMatrixEffect.matrix(kind: modifier.kind, values: presentedValues)
        guard matrix != .identity else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        var context = context
        context.effects.append(.filter(.colorMatrix(matrix)))
        super.paintTarget(target, in: node, into: &list, context: context)
    }
}

/// `blur`: the target paints into a group the painters blur; a soft blur spreads outside the
/// frame, an opaque one keeps the edges.
@MainActor
package final class BlurNode<Content: View>: UnaryLayoutModifierNode<Content, _BlurEffect> {
    override package var paintsOutsideFrame: Bool { !modifier.isOpaque }

    override package func update(view: ModifiedContent<Content, _BlurEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedRadius
        super.update(view: view, environment: environment, force: force)
        _tweenEffect(from: [old], to: [view.modifier.radius])
    }

    private var presentedRadius: CGFloat {
        presentation?.effect?.value(at: runtime.animationClock).first ?? modifier.radius
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let radius = presentedRadius
        guard radius > 0 else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        var context = context
        context.effects.append(.filter(.blur(radius: radius, opaque: modifier.isOpaque)))
        super.paintTarget(target, in: node, into: &list, context: context)
    }
}

/// `blendMode`: the target paints into a group composited with the mode.
@MainActor
package final class BlendModeNode<Content: View>: UnaryLayoutModifierNode<Content, _BlendModeEffect> {
    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        guard modifier.blendMode != .normal else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        var context = context
        context.effects.append(.blend(modifier.blendMode))
        super.paintTarget(target, in: node, into: &list, context: context)
    }
}

/// `compositingGroup` / `drawingGroup`: the pending effects open once around the whole target
/// instead of around each of its elements.
@MainActor
package final class CompositingGroupNode<Content: View>: UnaryLayoutModifierNode<Content, _CompositingGroupEffect> {
    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        var inner = context
        inner.effects = []
        context.withEffects(context.absoluteRect(target.presentedFrame), into: &list) { list in
            super.paintTarget(target, in: node, into: &list, context: inner)
        }
    }
}

/// `zIndex`: transparent to layout and painting; the value surfaces as the node's trait.
@MainActor
package final class ZIndexNode<Content: View>: UnaryLayoutModifierNode<Content, _ZIndexEffect> {
    override package func zIndex(of target: ViewNode) -> Double { modifier.value }
}

/// `hidden`: the target keeps its layout but is neither painted, hit tested nor exposed.
@MainActor
package final class HiddenNode<Content: View>: UnaryLayoutModifierNode<Content, _HiddenModifier> {
    override package var hidesTargets: Bool { true }
    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {}
}

@MainActor
package final class ClipNode<Content: View, S: Shape>: UnaryLayoutModifierNode<Content, _ClipEffect<S>> {
    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        list.append(.save)
        list.append(_withContainerShape(for: node) { _clipCommand(modifier.shape, in: context.absoluteRect(CGRect(origin: .zero, size: node.frame.size)), fillStyle: modifier.style, direction: node.environment.layoutDirection) })
        super.paintTarget(target, in: node, into: &list, context: context)
        list.append(.restore)
    }
}
