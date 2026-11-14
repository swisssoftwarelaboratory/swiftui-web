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

## Not on it yet

Which motions still run on their own timing, and their order, is new-website#264: the rubber
band and bounce at a scroll view's ends (the pieces are here, the scroll view doesn't use them
yet), system sheets, push and pop (still an ease-in-out of fixed duration), the app's own sheet
at release, the tab highlight, and the keyboard.

## Tests

`PhysicsTests`: SwiftUI's parameter mapping; the exact solution's velocity is its slope in each
regime; `.snappy` against the simulator's toggle (rms under 0.2 pt with no fitted shape, only
the start time); the navigation spring against a system sheet; the rubber band's 93.08 pt for
190 pt on an 852 pt list and the spring back; decay 0.998 against a coast (0.997 and 0.999 fit
four times worse); a spring and a bouncing coast reaching the same state at 30, 60, 120 frames
a second and a ragged mix; a retargeted `Motion` and `Tween` keeping their velocity; the
finger's speed on uneven frames and after a rest; and a slow first frame not eating into an
animation.
