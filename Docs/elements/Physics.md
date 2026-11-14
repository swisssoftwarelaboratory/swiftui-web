# Physics: one system for every motion

Not an Apple API: the runtime's own model of how iOS moves things, in
`Sources/SwiftUIWebCore/Runtime/Physics.swift`. Every animated or touch-driven motion should run
on it instead of keeping its own timing. Sources and numbers: new-website#261 (how iOS moves
things) and new-website#262 (every motion of a real app filmed in the simulator and in the
browser).

## The two kinds of motion

iOS has two. Content coasting after a flick slows by the same share every millisecond and never
overshoots. Everything else (bounce back, paging, push and pop, sheets, the keyboard, every
SwiftUI animation) is a spring that starts at the speed the finger or the previous motion had.

| Piece | What it is |
|---|---|
| `SpringModel` | A unit-mass damped spring, ω and ζ. Built from SwiftUI's parameters as SwiftUI maps them: `response`/`dampingFraction` (ω = 2π / response), `duration`/`bounce` (ζ = 1 − bounce, or 1 / (1 + bounce) below zero), mass/stiffness/damping (with Core Animation's `allowsOverdamping`). `state(displacement:velocity:at:)` is the exact solution in every damping regime; `settlingTime` bounds it. `Animation`'s springs, `Spring` (including `value`/`velocity(target:initialVelocity:time:)`) and the paging settle all evaluate through it. |
| `SpringModel.navigation` | UIKit's push, pop and keyboard spring: mass 3, stiffness 1000, damping 500, not overdamped, so a critical spring at ω 18.26 /s. It also matches a system sheet sliding up in the simulator (rms 2 pt). |
| `SpringModel.rubberBandReturn` | Stretched content springing back after the finger lifts: critical, ω 12.7 /s, fitted to the simulator (rms 1.6 pt). |
| `DecayModel` | Friction per millisecond (`.normal` 0.998, `.fast` 0.99): `v(t) = v₀ · rate^(1000t)`. Exact state, rest offset, Apple's projection `(v / 1000) · rate / (1 − rate)` for scroll targets, the time to slow to a floor and the time to cover a distance. |
| `RubberBand` | `(1 − 1 / (x · 0.55 / d + 1)) · d` for a pull of x past the end of a view d long, and its inverse (where a finger landing on stretched content picks it up). |
| `VelocityTracker` | The finger's speed over its last 50 ms (UIKit's reading, steady on uneven frames, new-website#216); zero once it rested 0.1 s before lifting. Scroll pans and `DragGesture` share it. |
| `Motion` | One value on one axis, held by a finger, carried by a spring, or coasting and bouncing off its bounds on an edge spring. Every change of plan starts from the current position and velocity; `step(_:)` is exact for any frame time, so a coast or spring lands in the same place at 30, 60 or 120 frames a second, and a coast reaching a bound hands over to the edge spring inside the same step. |

## Interruption

A `Tween` whose animation is a single spring carries a velocity per value: when a change
replaces a tween in flight (frames, opacity, colours, effects), the new one starts at the old
one's presented value *and velocity*, so a retargeted spring carries on without a kink (WWDC
2023, "Animate with springs"). Other curves start from the presented value at rest, as before.

## Frame time

Every piece is a closed-form solution stepped by the real time between frames, so a slow
frame lands the motion where it should be rather than further behind. Animations begun in a
frame start when that frame is on screen: the host reports how late the paint was
(`HostedScene.commitAnimations(lateness:)`, called by the canvas and native hosts before the
next `advanceFrame`) and the runtime moves those animations' start to it, as Core Animation
begins an animation at its commit. Without it a chat opening under `.smooth(duration: 0.35)`
was 68 % open in its first frame after a slow update (new-website#262). Headless tests that don't
call it keep the old timing.

## What runs on it

- **Push and pop** (`NavigationStackNode`): the slide is `Animation(spring: .navigation)`, UIKit's
  critical spring, instead of a 0.35 s ease-in-out that arrived at 0.14 s where iOS eases on to
  about 0.3 s. It starts when its first frame is shown (`_StartsOnScreen`).
- **iOS sheets and covers** (`PresentationNode.slide`, a `Motion`): a sheet presented once its
  presenter is on screen rises from just below the window on the navigation spring (within
  4.5 pt rms of the simulator's Lights out sheet; most of that in its first fast frames); the dim
  follows how far it is in. A finger on a sheet drags it down: the scroll views under the finger
  scroll first and hand the sheet what is past their top, a finger going back up raises it first.
  At the lift it closes when where it would coast (`DecayModel.projectedOffset`) is past half
  its height, else springs back at the finger's speed. Dismissed (by a drag, `dismiss`, its
  binding), it slides off from where it stands and stays painted, never hit, in
  `Runtime.leavingPresentations` until it is gone. Covers slide but are not dragged; nor is a
  sheet with `interactiveDismissDisabled`. A sheet there from the first frame doesn't slide.

## Not on it yet

Still on their own timing, in new-website#264's order: the rubber band and bounce at a scroll
view's ends (the pieces are here, the scroll view doesn't use them yet), the tab highlight, and
the keyboard.

## Tests

`SheetMotionTests`: a sheet rising against the simulator's curve, frame by frame on the spring;
one there from the first frame not sliding; a long drag closing it and its slide off; a flick
closing and a short slow drag springing back; a scroll view in a sheet scrolling and handing
the sheet what is past its top; a cover not dragged away; a dismissed sheet sliding off while
presses go behind it. `IOSNavigationTests`: the push at 0.175 s on the spring.


`PhysicsTests`: SwiftUI's parameter mapping; the exact solution's velocity is its slope in each
regime; `.snappy` against the simulator's toggle (rms under 0.2 pt with no fitted shape, only
the start time); the navigation spring against a system sheet; the rubber band's 93.08 pt for
190 pt on an 852 pt list and the spring back; decay 0.998 against a coast (0.997 and 0.999 fit
four times worse); a spring and a bouncing coast reaching the same state at 30, 60, 120 frames
a second and a ragged mix; a retargeted `Motion` and `Tween` keeping their velocity; the
finger's speed on uneven frames and after a rest; and a slow first frame not eating into an
animation.
