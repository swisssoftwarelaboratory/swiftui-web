# Gestures: DragGesture, LongPressGesture, TapGesture, composition, @GestureState

Apple docs: [Gesture](https://developer.apple.com/documentation/swiftui/gesture),
[DragGesture](https://developer.apple.com/documentation/swiftui/draggesture),
[LongPressGesture](https://developer.apple.com/documentation/swiftui/longpressgesture),
[TapGesture](https://developer.apple.com/documentation/swiftui/tapgesture),
[gesture(_:including:)](https://developer.apple.com/documentation/swiftui/view/gesture(_:including:)),
[GestureState](https://developer.apple.com/documentation/swiftui/gesturestate).

## API surface

| API | Notes |
|---|---|
| `Gesture` protocol (`Value`, `Body`), custom gestures with a `body` | implemented |
| `TapGesture(count:)` | implemented: taps within 0.35 s and 10 pt of each other |
| `LongPressGesture(minimumDuration:maximumDistance:)` | implemented: reports `true` on press, ends (recognises) once the duration passes on the animation clock, fails on movement or an early release |
| `DragGesture(minimumDistance:coordinateSpace:)`, `DragGesture.Value` (`time`, `location`, `startLocation`, `translation`, `velocity`, `predictedEndLocation`, `predictedEndTranslation`) | implemented: `.local` and `.global` spaces (a named space reports local points); velocity over the finger's last 50 ms (`VelocityTracker`, as a scroll view reads it; zero once it rested 0.1 s before lifting); the prediction is a quarter second of velocity |
| `MagnifyGesture`, `RotateGesture`, `MagnificationGesture`, `RotationGesture` | implemented (2026-10-04): pinches from trackpads and two touches through `Runtime.pinch`; `minimumScaleDelta`/`minimumAngleDelta` before activation, velocities from the last two events, `startAnchor`/`startLocation` in the view's space |
| `onChanged`, `onEnded`, `map`, `updating(_:body:)` with `@GestureState` | implemented; the `updating` body's transaction applies to the state change and the `reset` closure's transaction to the reset (2026-10-04) |
| `sequenced(before:)`, `simultaneously(with:)`, `exclusively(before:)` and their value types | implemented (`_SequenceValue`, `_SimultaneousValue`, `_ExclusiveValue`) |
| `gesture(_:including:)`, `highPriorityGesture`, `simultaneousGesture` | implemented; `GestureMask` honoured (`.subviews` leaves presses to the subviews, `.gesture` keeps them from the subviews, `.none` takes and drops them); `simultaneousGesture` runs alongside the subview's control or gesture (2026-10-04) |
| `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)` | implemented |
| `onTapGesture(count:)` | implemented: the modifier's node counts taps like `TapGesture(count:)` |
| Pinches on iOS competing with scroll views, the focused window for pinches | missing (a two-finger touch always pinches; a scroll view under it does not zoom) |

## Behaviour

`GestureNode` is the `_Interactive` node for the modified content: a press that hit-tests to it
(the deepest interactive node under the pointer, so subviews' controls win unless the gesture is
`highPriorityGesture`, which sets `capturesHitTesting`) feeds `pressBegan(at:)`,
`pressMoved(to:)` and `pressEnded(inside:at:)` to the gesture's recogniser as `GestureEvent`s in
the node's space, with the host's event time and the animation clock. The node exposes its
children rather than itself (role `group`, `exposesChildren`). A press in flight keeps its
recogniser through re-renders, so handlers that captured `@State` keep working.

`_GestureRecognizer<Value>` is a class with a phase (`possible`, `active`, `ended`, `failed`) and
handler lists; `emitChanged` and `emitEnded` run the `onChanged`/`onEnded` handlers, and `reset`
handlers restore `@GestureState` when a gesture ends or fails. `TapRecognizer` counts releases
inside the frame; `DragRecognizer` becomes active at `minimumDistance` and reports every move;
`LongPressRecognizer` needs frames (`wantsFrames`): the node subscribes to `Runtime.subscribeFrames`
while it waits, and `tick(clock:)` recognises once `minimumDuration` has passed on the animation
clock, which hosts advance by real elapsed time. `MapRecognizer` wraps another; the sequence,
simultaneous and exclusive recognisers own two and forward events (a sequence switches to its
second once the first ended; exclusive picks the first recogniser to become active and cancels
the other; a long press's initial "pressing" report is not activation).

`Runtime.lastPointerTime` keeps the host's event time for tap intervals and drag velocity.

## Verification (2026-09-04)

`gesture/basic` (resting state): Tier A exact, Tier C 0.00 %, Tier B exact frames in three
browsers. `Playwright/gesture-probe.mjs` drags the box (the label shows the translation and the
drag ends), holds the orange box (pressing, then a long press after the duration), double-clicks
the green box, and holds the purple box (`@GestureState` set while held, reset on release).
`GestureTests` cover drag translation, the minimum distance, local and global points, velocity;
long presses on the clock, cancellation by movement and by an early release; tap counts and
intervals; `@GestureState`; sequenced, simultaneous and exclusive combinations; and priority
against an inner button.

## Pinches, simultaneity and transactions (2026-10-04)

The canvas host delivers pinches to `HostedScene.pinch(_:scale:rotation:at:time:)` from three
sources: a `wheel` event with the control key (Chromium and Firefox send trackpad pinches so;
the scale compounds by e^(−deltaY/100) and the pinch ends 200 ms after its last event), Safari's
`gesturestart`/`gesturechange`/`gestureend` (its `scale` and `rotation` in degrees), and two
touches (the press under the first touch is cancelled, the distance and angle between the
touches give the scale and rotation, and the touch that remains after one lifts is ignored
until it lifts). `Runtime.pinch` fixes the targets when the pinch begins: the deepest gesture
node under the centre whose recogniser takes pinches, plus the `simultaneousGesture` nodes
above it; each gets `PinchEvent`s in its space with its bounds (for `startAnchor`).
`MagnifyRecognizer` and `RotateRecognizer` activate at the minimum deltas and report the
cumulative scale or angle with a velocity from the last two events; the older gestures map
them to `CGFloat` and `Angle`. Composite recognisers forward pinches as they do presses.

`simultaneousGesture` is now true simultaneity: when a subview's control or gesture takes the
press, the runtime walks the pressed node's ancestors and feeds every `simultaneousGesture`
node the same press (`inside` judged by that node's own frame), cancelling them with the press
when a pan or drag takes it. `GestureMask` is honoured as in the table. `@GestureState` applies
the `updating` body's transaction to its change and the `reset` closure's transaction to the
reset, so both can animate.

`gesture/pinch`: the resting state (Tier A exact, Tier C 0.00 %, Tier B within tolerance).
`Playwright/gesture-probe.mjs` now also pinches it with synthetic control-wheel events, Safari
style gesture events and two CDP touches. `PinchGestureTests` cover the thresholds, velocities,
anchors, cancellation, the older gestures, the deepest target, simultaneous ancestors sharing
pinches and presses with an inner button, the four masks and the transactions.

## Not yet covered

Touch drags competing with scroll views (a touch pan belongs to the scroll view), pinches
zooming scroll views, trackpad pinches in Firefox verified by hand (the control-wheel route is
exercised with synthetic events).
