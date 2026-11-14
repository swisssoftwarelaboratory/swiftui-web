# Animation, withAnimation, transitions

Apple docs: [Animation](https://developer.apple.com/documentation/swiftui/animation),
[withAnimation(_:_:)](https://developer.apple.com/documentation/swiftui/withanimation(_:_:)),
[animation(_:value:)](https://developer.apple.com/documentation/swiftui/view/animation(_:value:)),
[transaction(_:)](https://developer.apple.com/documentation/swiftui/view/transaction(_:)-1r5uc),
[AnyTransition](https://developer.apple.com/documentation/swiftui/anytransition),
[transition(_:)](https://developer.apple.com/documentation/swiftui/view/transition(_:)-1hq0g).

## API surface

| API | Notes |
|---|---|
| `Animation`: `.default`, `linear`, `easeIn`, `easeOut`, `easeInOut` (with and without `duration:`), `timingCurve` | implemented (cubic Bézier solved by bisection) |
| `spring(response:dampingFraction:blendDuration:)`, `interactiveSpring`, `interpolatingSpring(mass:stiffness:damping:initialVelocity:)`, `spring(duration:bounce:)`, `smooth`, `snappy`, `bouncy` | implemented as damped springs; `initialVelocity` starts the step response moving (2026-10-04); `blendDuration` is accepted (a retargeted animation already starts from the value presented at that moment, at the velocity it had, which is the blend's effect); a spring's duration is its settling time; all run on `SpringModel` ([Physics](Physics.md)) |
| `delay`, `speed`, `repeatCount(_:autoreverses:)`, `repeatForever(autoreverses:)` | implemented |
| `withAnimation(_:_:)`, `Transaction.animation`, `withTransaction` | implemented |
| `withAnimation(_:completionCriteria:_:completion:)`, `Transaction.addAnimationCompletion(criteria:_:)`, `AnimationCompletionCriteria` | implemented (2026-10-04): the runtime of the first node invalidated under the transaction claims the completion and runs it when its animation's duration has passed (`logicallyComplete`) or it has ended entirely (`removed`: never for `repeatForever`); without an animation it runs at the next layout, and when nothing was invalidated on the next turn |
| `accessibilityReduceMotion` (`accessibilityReduceTransparency`, `accessibilityDifferentiateWithoutColor`, `accessibilityInvertColors`) | the first follows the host's `prefers-reduced-motion` (`Runtime.hostReducesMotion`); the others are always false (2026-10-04) |
| Ghosts in `List`, `Picker` and grouped `Form` | implemented: containers that paint their own children paint their exiting ghosts too |
| `contentTransition` on symbol images (`.symbolEffect`, `.opacity`, `.interpolate`) | implemented: a symbol replaced under an animation crossfades from the old glyph |
| `animation(_:value:)`, `animation(_:)` (deprecated), `transaction(_:)` | implemented as scopes that take precedence over the transaction for their subtree (`.animation(nil, value:)` switches animation off there) |
| What animates | every layout node's frame (position and size), `opacity(_:)`, `Color` fills, transitions; not yet: `foregroundColor`, shape fills and strokes, `rotationEffect`/`scaleEffect` (no transforms), text content, `Animatable` custom data, `animatableData` of shapes, `matchedGeometryEffect`, `phaseAnimator`, `keyframeAnimator` |
| `AnyTransition`: `.identity`, `.opacity`, `.move(edge:)`, `.slide`, `.offset`, `.combined(with:)`, `.asymmetric(insertion:removal:)`, `.animation(_:)` | implemented; `.scale` fades for now; `transition(_:)` on the removed or inserted view (or a modifier chain inside it); the default transition is a fade |
| `Transaction.disablesAnimations`, `isContinuous` | honoured (`disablesAnimations` drops the transaction's animation) |

## Behaviour

`ViewNode.invalidate` records `Transaction._current.animation` on the runtime; `Runtime.layout`
makes it the update animation for the flush (transitions, opacity and colour changes look it up
through `effectiveUpdateAnimation`, scopes first) and the layout animation for the placement
pass. `place` compares the new frame with the old target: a change under an animation starts a
`Tween` from the currently presented frame (so retargeting mid-flight is smooth; a spring also
carries the velocity the replaced tween had, per value, see [Physics](Physics.md)), a change
without one clears any tween. Painting uses `presentedFrame` everywhere (the tween's frame plus a
transition's offset) and `absoluteBounds` the presented size; `OpacityNode` and `ColorNode` tween
their values. Structural nodes (`_ConditionalContent`, `Optional`, `ForEach`) call `noteInserted`
and `retire`: a new subtree's layout nodes start their transition from the removed look, a
removed subtree stays in the parent's `exitingChildren` and its layout nodes are painted as
ghosts (at their last frames, offset and faded by the transition) by the nearest layout ancestor's
base `paint`, then unmounted when the transition ends. `Runtime.advanceAnimations(elapsed:)`
moves the clock, drops finished tweens and requests a repaint while anything runs (and once
more when the last ends). The canvas host calls it every frame alongside the scroll animations
and keeps scheduling frames while `isAnimating`; `__swiftuiwebDebug.animating()` lets Tier B
wait for the settled state after a step.

A view with a body that conforms to `Animatable`, and an `AnimatableModifier` (or any modifier
with a body that conforms to `Animatable`), gets a node of its own,
`AnimatableBodyNode` or `AnimatableModifierBodyNode` (Runtime/AnimatableBodies.swift), chosen by
`_makeNode` defaults constrained to `Animatable`, so the composite and modifier nodes every other
type uses carry nothing for it. When its animatable data changes under an animation, the node
subscribes to frames and evaluates the body each frame with the data interpolated from the value
on screen to the new one; a change without an animation jumps, and the subscription ends with
the tween. A custom `Shape` is such a view, so its data (a trimmed arc's progress, a corner
radius) interpolates the same way. Geometry effects keep their own node, and a representable
that conforms to `Animatable` is hosted as before.

## Measured (macOS 26.2, `animation/frame`, `animation/transition`, `animation/implicit`, 2026-09-03)

| Property | Value | Probe |
|---|---|---|
| Frames during an animation | `GeometryReader` reports the target frames at once (the box is 200 × 60 right after `withAnimation`), so Tier A compares end states | `box`, `below` |
| Harness and `withAnimation` | the golden window disables transactions' animations (`.transaction { $0.animation = nil }`): pixels are end states | steps `expand`, `collapse`, `hide`, `show` |
| `animation(_:value:)` and the harness | the modifier's animation overrides the outer transaction: with a real duration Apple's pixels were mid-flight (the green box 20 pt short after 1 capture), so the fixture uses a zero-length animation; ours settles at the target | `moved`, pixels |
| Removal | the removed view leaves the layout at once (the stack is 40 tall while the ghost slides out) | `stack` after `hide` |
| Browser motion | the red box's painted width grows 100 → 111 → 128 → … → 200 over 0.3 s and `animating()` turns false | `Playwright/animation-probe.mjs` |

## Verification (2026-09-03)

Tier A: 3 fixtures exact with all 6 steps. Tier B 9/9 renders in Chromium (≤ 0.29 %) and WebKit
(≤ 0.94 %), Firefox 6/9 with every failure the 0.5 pt narrower "Above" (the known hinting class);
each step is compared after the animation settles. `AnimationTests` cover curves, springs
(overshoot for `.bouncy`, settling), delay/speed/repeat, frame tweens and snapping, scoped
implicit animation, opacity and colour tweens, insertion and removal transitions with ghosts.
wasm js tests pass.

## Not yet covered

Animating shape and text colours, `Animatable`/`animatableData` interpolation for shapes,
`blendDuration` as a real blend, animating `ScrollView` offsets through `withAnimation`,
`contentTransition(.interpolate)` as a true interpolation (a crossfade here).
