// Geometry effect nodes: identity for layout; painting wraps the target in save/concat/restore
// with the effect's transform about its anchor (in absolute coordinates). Parameters tween
// under an animation like opacity does.

@MainActor
package protocol _EffectParameters: AnyObject {
    /// The effect's animatable parameters as a vector.
    var effectParameters: [Double] { get }
}

extension ViewNode {
    /// Records a tween from the previous effect parameters when they change under an animation.
    package func tweenEffect(from old: [Double], to new: [Double]) {
        guard old != new else { return }
        if let animation = runtime.effectiveUpdateAnimation(for: self) {
            let presentation = self.presentation ?? NodePresentation()
            presentation.effect = Tween(from: old, to: new, animation: animation, start: runtime.animationClock, continuing: presentation.effect)
            self.presentation = presentation
            runtime.register(animating: self)
        } else {
            presentation?.effect = nil
        }
    }

    /// The parameters to paint with: the tween's while animating, else the current ones.
    package func presentedEffect(_ current: [Double]) -> [Double] {
        presentation?.effect?.value(at: runtime.animationClock) ?? current
    }

    /// Paints `body` inside a transform about the node's frame.
    package func paintTransformed(_ transform: CGAffineTransform, into list: inout DisplayList, body: (inout DisplayList) -> Void) {
        if transform == .identity { body(&list); return }
        list.append(.save)
        list.append(.concat(transform))
        body(&list)
        list.append(.restore)
    }
}

/// A transform of `local` (about the node's origin) applied around `anchor` in absolute space.
private func aboutAnchor(_ local: CGAffineTransform, origin: CGPoint, size: CGSize, anchor: UnitPoint) -> CGAffineTransform {
    let p = CGPoint(x: origin.x + size.width * anchor.x, y: origin.y + size.height * anchor.y)
    return CGAffineTransform(translationX: -p.x, y: -p.y).concatenating(local).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
}

@MainActor
package final class OffsetNode<Content: View>: UnaryLayoutModifierNode<Content, _OffsetEffect> {
    override package var paintsOutsideFrame: Bool { true }
    private var current: [Double] { [modifier.offset.width, modifier.offset.height] }

    override package func update(view: ModifiedContent<Content, _OffsetEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    private var presentedOffset: CGSize {
        let v = presentedEffect(current)
        return CGSize(width: v[0], height: v[1])
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let offset = presentedOffset
        paintTransformed(CGAffineTransform(translationX: offset.width, y: offset.height), into: &list) { list in
            super.paintTarget(target, in: node, into: &list, context: context)
        }
    }

    /// Hit testing follows the offset.
    override package var hitTestOffset: CGPoint { CGPoint(x: presentedOffset.width, y: presentedOffset.height) }
}

@MainActor
package final class RotationNode<Content: View>: UnaryLayoutModifierNode<Content, _RotationEffect> {
    private var current: [Double] { [modifier.angle.radians] }

    override package func update(view: ModifiedContent<Content, _RotationEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let radians = presentedEffect(current)[0]
        let transform = aboutAnchor(CGAffineTransform(rotationAngle: CGFloat(radians)), origin: context.origin, size: node.presentedFrame.size, anchor: modifier.anchor)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform {
        aboutAnchor(CGAffineTransform(rotationAngle: CGFloat(presentedEffect(current)[0])), origin: .zero, size: frame.size, anchor: modifier.anchor)
    }
}

@MainActor
package final class ScaleNode<Content: View>: UnaryLayoutModifierNode<Content, _ScaleEffect> {
    private var current: [Double] { [modifier.scale.width, modifier.scale.height] }

    override package func update(view: ModifiedContent<Content, _ScaleEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let v = presentedEffect(current)
        let transform = aboutAnchor(CGAffineTransform(scaleX: CGFloat(v[0]), y: CGFloat(v[1])), origin: context.origin, size: node.presentedFrame.size, anchor: modifier.anchor)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform {
        let v = presentedEffect(current)
        return aboutAnchor(CGAffineTransform(scaleX: CGFloat(v[0]), y: CGFloat(v[1])), origin: .zero, size: frame.size, anchor: modifier.anchor)
    }
}

@MainActor
package final class TransformNode<Content: View>: UnaryLayoutModifierNode<Content, _TransformEffect> {
    override package var paintsOutsideFrame: Bool { true }
    private var current: [Double] { let t = modifier.transform; return [t.a, t.b, t.c, t.d, t.tx, t.ty] }

    override package func update(view: ModifiedContent<Content, _TransformEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let v = presentedEffect(current)
        let local = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
        // Applied in the view's local space: about its origin.
        let transform = aboutAnchor(local, origin: context.origin, size: node.presentedFrame.size, anchor: .topLeading)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform {
        let v = presentedEffect(current)
        return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }
}

/// `rotation3DEffect`: the rotation's affine part about the anchor (Docs/elements/Transform.md).
@MainActor
package final class Rotation3DNode<Content: View>: UnaryLayoutModifierNode<Content, _Rotation3DEffect> {
    override package var paintsOutsideFrame: Bool { true }
    private var current: [Double] { [modifier.angle.radians] }

    override package func update(view: ModifiedContent<Content, _Rotation3DEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    private var local: CGAffineTransform { _Rotation3DEffect.affine(radians: presentedEffect(current)[0], axis: modifier.axis) }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let transform = aboutAnchor(local, origin: context.origin, size: node.presentedFrame.size, anchor: modifier.anchor)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform { aboutAnchor(local, origin: .zero, size: frame.size, anchor: modifier.anchor) }
}

/// `projectionEffect`: the projection's affine part about the view's origin.
@MainActor
package final class ProjectionNode<Content: View>: UnaryLayoutModifierNode<Content, _ProjectionEffect> {
    override package var paintsOutsideFrame: Bool { true }
    private var current: [Double] { let t = modifier.transform.affine; return [t.a, t.b, t.c, t.d, t.tx, t.ty] }

    override package func update(view: ModifiedContent<Content, _ProjectionEffect>, environment: EnvironmentValues, force: Bool) {
        let old = presentedEffect(current)
        super.update(view: view, environment: environment, force: force)
        tweenEffect(from: old, to: current)
    }

    private var local: CGAffineTransform { let v = presentedEffect(current); return CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]) }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let transform = aboutAnchor(local, origin: context.origin, size: node.presentedFrame.size, anchor: .topLeading)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform { local }
}

/// A custom `GeometryEffect`: its projection's affine part at the view's size, about the
/// origin; its animatable data tweens under an animation and the effect is re-evaluated at the
/// tweened value while painting.
@MainActor
package final class GeometryEffectNode<Content: View, Effect: GeometryEffect>: UnaryLayoutModifierNode<Content, _GeometryEffectModifier<Effect>> {
    override package var paintsOutsideFrame: Bool { true }
    /// The animatable data a running tween goes from and to; the `effect` presentation slot
    /// carries the tween's progress (0 to 1).
    private var tweenFrom: Effect.AnimatableData?
    private var tweenTo: Effect.AnimatableData?

    override package func update(view: ModifiedContent<Content, _GeometryEffectModifier<Effect>>, environment: EnvironmentValues, force: Bool) {
        let old = presentedData
        let changed = (old - view.modifier.effect.animatableData).magnitudeSquared > 0
        super.update(view: view, environment: environment, force: force)
        if changed {
            tweenFrom = old
            tweenTo = view.modifier.effect.animatableData
            tweenEffect(from: [0], to: [1])
        }
    }

    /// The animatable data to paint with: interpolated while a tween runs.
    private var presentedData: Effect.AnimatableData {
        guard let tweenFrom, let tweenTo, let progress = presentation?.effect?.value(at: runtime.animationClock).first else { return modifier.effect.animatableData }
        return tweenFrom.interpolated(towards: tweenTo, amount: progress)
    }

    /// The effect at the presented animatable data.
    private var presentedTransform: CGAffineTransform {
        var effect = modifier.effect
        effect.animatableData = presentedData
        return effect.effectValue(size: frame.size).affine
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        let transform = aboutAnchor(presentedTransform, origin: context.origin, size: node.presentedFrame.size, anchor: .topLeading)
        paintTransformed(transform, into: &list) { list in super.paintTarget(target, in: node, into: &list, context: context) }
    }

    override package var hitTestTransform: CGAffineTransform { presentedTransform }
}
