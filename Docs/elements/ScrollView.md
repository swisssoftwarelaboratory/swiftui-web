# ScrollView, ScrollViewReader, scroll modifiers, onChange

Apple docs: [ScrollView](https://developer.apple.com/documentation/swiftui/scrollview),
[ScrollViewReader](https://developer.apple.com/documentation/swiftui/scrollviewreader),
[ScrollViewProxy](https://developer.apple.com/documentation/swiftui/scrollviewproxy),
[scrollIndicators](https://developer.apple.com/documentation/swiftui/view/scrollindicators(_:axes:)),
[scrollDisabled](https://developer.apple.com/documentation/swiftui/view/scrolldisabled(_:)),
[scrollBounceBehavior](https://developer.apple.com/documentation/swiftui/view/scrollbouncebehavior(_:axes:)),
[scrollClipDisabled](https://developer.apple.com/documentation/swiftui/view/scrollclipdisabled(_:)),
[defaultScrollAnchor](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:)),
[onChange](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)-4psgg).

## API surface

| API | Notes |
|---|---|
| `ScrollView(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, content:)`, `axes`, `showsIndicators`, `content` | implemented |
| `ScrollViewReader { proxy in … }`, `ScrollViewProxy.scrollTo(_:anchor:)` | implemented; targets are `View.id(_:)` descendants of the scroll views under the reader, resolved at the next layout; never animated |
| `View.scrollIndicators(_:axes:)`, `ScrollIndicatorVisibility` (`automatic`, `visible`, `hidden`, `never`), environment `horizontal/verticalScrollIndicatorVisibility` | implemented: `hidden`/`never` suppress the overlay indicator; `visible` behaves like `automatic` (overlay only while scrolling) |
| `View.scrollDisabled(_:)`, environment `isScrollEnabled` | implemented (wheel, pan and momentum ignore the view; `scrollTo` still works) |
| `View.scrollBounceBehavior(_:axes:)`, `ScrollBounceBehavior` | stored in the environment, no effect: there is no rubber band yet |
| `View.scrollClipDisabled(_:)` | implemented |
| `View.defaultScrollAnchor(_:)`, `View.defaultScrollAnchor(_:for:)`, `ScrollAnchorRole` (`initialOffset`, `sizeChanges`, `alignment`) | implemented: `alignment` places content shorter than the viewport by the anchor; `sizeChanges` keeps content sitting at the anchor there as the content grows (`scroll/anchor-roles`) |
| `View.onChange(of:initial:_:)` (two-argument and zero-argument actions), deprecated `onChange(of:perform:)` | implemented: actions run after the update pass that changed the value, from the scheduler's action queue |
| `View.scrollPosition(id:anchor:)`, `View.scrollPosition(_:anchor:)`, `ScrollPosition` (`init(edge:)`, `init(point:)`, `init(x:y:)`, `init(id:anchor:)`, `viewID`, `edge`, `point`, `isPositionedByUser`, `scrollTo(id:anchor:)`, `scrollTo(edge:)`, `scrollTo(point:)`, `scrollTo(x:y:)`) | implemented: the binding's changes scroll (an identity with the smallest change without an anchor, an edge, a point); the identity of the view positioned at the anchor (without one, the target showing the most) is written back as the user scrolls; the initial value and programmatic scrolls leave the binding alone (`scroll/position`, `ios/scroll/position`) |
| `View.scrollTargetLayout(isEnabled:)` | implemented: the outermost layout container below the modifier; `ForEach` elements and `id(_:)` views give the targets' identities |
| `View.scrollTargetBehavior(_:)`, `ScrollTargetBehavior` (`updateTarget(_:context:)`), `ScrollTarget`, `ScrollTargetBehaviorContext` (`originalTarget`, `velocity`, `contentSize`, `containerSize`, `axes`, environment by dynamic member), `.paging`, `.viewAligned`, `.viewAligned(limitBehavior:)`, `.viewAligned(anchor:)`, `ViewAlignedScrollTargetBehavior.LimitBehavior` (`automatic`, `always`, `alwaysByFew`, `alwaysByOne`, `never`) | implemented: when a pan ends (or a wheel goes quiet for 0.15 s) the behaviour receives the projected rest position and the content eases to its target over 0.35 s; paging moves at most one container length from where the gesture began; view-aligned picks the nearest target (`automatic` limits a compact width to one view, `alwaysByFew` to three) |
| `View.contentMargins(_:_:for:)` (edges + insets, edges + length, length), `ContentMarginPlacement` (`automatic`, `scrollContent`, `scrollIndicators`) | implemented: content margins inset the content and widen the scroll view across its axis like safe-area insets (`scroll/margins`); indicator margins shorten the scroller's track |
| `View.onScrollGeometryChange(for:of:action:)`, `ScrollGeometry` (`contentOffset`, `contentSize`, `contentInsets`, `containerSize`, `visibleRect`, `bounds`) | implemented: published after every layout and scrolled frame; the action runs once with the value of an empty geometry when the scroll view appears, then on changes (`scroll/geometry`) |
| `View.onScrollPhaseChange(_:)` (two- and three-argument actions), `ScrollPhase` (`idle`, `tracking`, `interacting`, `decelerating`, `animating`, `isScrolling`), `ScrollPhaseChangeContext` (`geometry`, `velocity`) | implemented: `idle` once at appearance, `tracking` on touch, `interacting` while the finger or wheel moves the content, `decelerating` for momentum and a behaviour settling; programmatic scrolls change no phase |
| `View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)` | implemented (the indicators show and fade as after a scroll) |
| `View.scrollDismissesKeyboard(_:)`, `ScrollDismissesKeyboardMode` (`automatic`, `immediately`, `interactively`, `never`), environment `scrollDismissesKeyboardMode` | implemented on iOS: a pan in a scroll view drops keyboard focus unless the mode is `never` (`interactively` behaves as `immediately`) |
| `ScrollViewReader` inside `List` | implemented (2026-09-19, Docs/elements/List.md) |
| `scrollContentBackground` | implemented for `List` (Docs/elements/List.md); no effect on `ScrollView` |

## Runtime

`ScrollNode` (`Runtime/ScrollNodes.swift`) wraps the builder content in an implicit
`VStack` (the goldens show that arrangement for every axis set) and places it at
`-contentOffset`. Along a scroll axis the node proposes nothing to the content and takes the
proposal itself; across it the proposal passes through and the node is exactly as large as its
content. The offset is clamped to `[0, content − viewport]` at every layout, so content that
shrinks pulls the offset back. `scrollTo` records a target; the next layout places the content,
reads the target's fresh frame, computes the offset and places the content again when it moved.

Input is entirely in Swift (decision 0002). `Runtime.scrollWheel(by:at:)` walks the scroll views
on the hit path innermost first and lets each consume what it can along its axes; the remainder
chains outward. Desktop wheel deltas already carry the OS momentum, so none is added. A touch
pointer becomes a pan after `panSlop` (10 pt); a pan cancels the pending press and follows the
finger, and lifting hands the finger's velocity over its last 50 ms (`VelocityTracker`) to the
innermost scroll view, which decelerates at UIScrollView's normal rate (× 0.998 per millisecond,
`DecayModel`, exact for any frame time) and stops at the edges ([Physics](Physics.md)). The host
(`CanvasHost`) normalises `deltaMode` (lines × 16, pages × viewport), consumes the wheel event so
the page does not scroll, and calls `advanceScrollAnimations` once per frame for momentum and
the indicator fade. A scroll frame moves the content without a layout pass when nothing in the
content reads its position (`ScrollNode.canMoveContentOnly`; a geometry reader in a background
or overlay layer, such as a fixture probe, counts since 2026-09-18), else it lays out again
(see the frame-time measurement below). Since 2026-11-12 a geometry reader counts only once its
content asked where it is (`frame(in:)` in a space other than `.local`, `bounds(of:)`, an anchor):
a reader of its size alone is moved with the rest. `onGeometryChange` observers are re-read after
a move, and the actions they queue run at the start of the next frame, which stays a move when
they change no view (an app reporting its views' screen positions to a tour, new-website#216).

Paging and swipes were measured against iOS 27 in the simulator, frame by frame (new-website#216):
a touch pan follows from where the finger left the 10 pt slop; at the lift a paging view turns one
page its way at 380 pt/s or more, otherwise to the nearer page, and settles on a critically
damped spring (ω 17/s) started at the finger's speed (capped at 1.7 ω d₀ toward the target).
A trackpad arrives as wheel events with no phases: a gesture keeps to its axis and its scroll
views, ends on a 60 ms pause, a reversal or a clear new push, and moves a paging view at most a
page from where it began; the finger counts as lifted when the speed, taken over 16 ms slices of
the events' own times, stops rising and falls to three quarters of its peak, and the rest of the
gesture is swallowed. `WheelGestureTests` replays a minute of real trackpad swipes and the
simulator's drag table. Not matched yet: iOS's rubber band at a scroll view's ends.

A control that tracks drags declares the axes it keeps (`_Interactive.dragAxes`; a slider's
track claims `.horizontal`). When the finger crosses the slop on such a control, the movement's
dominant axis decides: along a claimed axis the press keeps the touch and the pan is dropped
(the slider follows the finger from then on, even when it wanders vertically); across it the
pan takes over as for any other view. A finger that rested on the control for
`touchHoldInterval` (0.15 s) before moving keeps the touch whichever way it goes, as
UIScrollView's delayed content touches let a UISlider do (2026-09-05).

Overlay scrollers are painted by the node while `indicatorOpacity > 0`: a knob on the trailing
edge whose length is the viewport's share of the content, held 0.6 s after the last scroll and
faded over 0.25 s. The goldens never show one (macOS renders overlay scrollers only while
scrolling; `scroll/flash` with `scrollIndicatorsFlash(onAppear:)` captured none either), so the
knob was measured by drawing an `NSScroller` of the overlay style with `drawKnob()` into a 2×
bitmap (2026-09-19): a 7 pt core of black at 50 % inside a 1 pt white rim at 15 %, the core
2 pt from the trailing edge and 4 pt from the ends of the track, its length the viewport's
share of the track. The hold, the fade and the minimum knob length stay approximate.

Scroll targets and behaviours (`API/ScrollTargets.swift`, `Runtime/ScrollTargetNodes.swift`):
`scrollPosition`, `onScrollGeometryChange` and `onScrollPhaseChange` become transparent nodes
the scroll view finds by walking its ancestors up to the enclosing scroll view; the target
layout is found below it and its targets (the items of the outermost layout container, with
the identities of `ForEach` elements and `id(_:)` views) are refreshed in content coordinates at
every layout. A behaviour runs when a pan ends or a wheel goes quiet: the projected rest position
(the momentum's geometric sum) becomes the original target, the behaviour's answer is eased to
over `scrollTargetSettleSeconds`. Geometry is published after every layout and every scrolled
frame; actions queued during a layout run in the next frame, as `FixtureRunner` also does.

## Measured behaviours (macOS 26.2, SwiftUI 7.2.5, hosted-window goldens 2026-09-02)

| Behaviour | Value | Fixture |
|---|---|---|
| Size along a scroll axis | the proposal: 200 tall in a 300 × 200 window (vertical), 300 wide (horizontal), 300 × 200 for both axes | `scroll/vertical`, `scroll/horizontal`, `scroll/both` |
| Size across the scroll axis | **exactly the content's size**, never the proposal: 120 for 120 pt rows (centred at x 90 by the window), 100 inside a 250 × 150 frame (x 100), **400** for 400 pt content in a 300 pt proposal (x −50, overflowing the window), 274 for a wrapped paragraph, 152 for padded rows, 40 tall for a horizontal row of 40 pt cells | `scroll/narrow-content`, `scroll/wide-content`, `scroll/text`, `scroll/padding`, `scroll/horizontal` |
| Proposal to the content | across: the scroll view's proposal (the paragraph wraps at 300 → 274 × 32); along: nothing (ideal length: 552, 808, 400) | `scroll/text`, `scroll/vertical-overflow`, `scroll/horizontal`, `scroll/both` |
| Content placement | top-leading at offset 0; content shorter than the viewport is not centred (3 rows at y 0 in a 200 pt viewport) | `scroll/vertical`, `scroll/horizontal` |
| Several views in the builder | an implicit `VStack` with default spacing and centre alignment for **both** vertical and horizontal scroll views: `Text` / 60 × 30 `Color` / `Text` stack at y 0, 24.15, 58.89 (default-font text-to-colour spacing 8.15 and 4.74), texts centred over the 60 pt colour (x 18.75); the horizontal scroll view is 74.89 tall | `scroll/children` |
| In a stack | flexible like `Color`: `VStack(spacing: 0) { Text; ScrollView; Text }` in 200 pt gives 16 / 168 / 16 | `scroll/in-stack` |
| Padding inside | part of the content size (152 × 432 for 120 × 400 rows) | `scroll/padding` |
| `defaultScrollAnchor(.bottom)` | initial offset = content − viewport (content at y −200 for 400 in 200) | `scroll/anchor-bottom` |
| `scrollTo` without an anchor | the smallest offset change that shows the whole target: a row below the fold ends up bottom-aligned (row 15 at y 180, offset 120); a row above the top ends up at y 0 | `scroll/scroll-to` (`row15`, `row0`) |
| `scrollTo` with an anchor | the target's anchor point meets the viewport's: `.top` puts row 3 at y 0 (offset 60); `.center` puts row 10 (200–220) at y 90 (offset 110) | `scroll/scroll-to` (`row3-top`, `row10-center`) |
| `showsIndicators: false`, `scrollIndicators(.hidden)`, `scrollDisabled(true)` | no effect on layout (80 × 200 either way) | `scroll/modifiers` |
| Indicators at rest | none painted in any golden, including right after a programmatic scroll (overlay scroller style) | every scroll fixture's `image@2x.png` |

## Scrolling frame time (Chromium, `Playwright/scroll-probe.mjs`, 2026-09-02)

Every scrolled frame runs a full layout pass and repaints everything, measured by the host's
own clock (`__swiftuiwebDebug.frameMillis()`) while 40 px wheel ticks arrive once per frame:

| Content | Build | Layout + paint per frame |
|---|---|---|
| `scroll/long`, 500 rows | release (`-Osize`) | median 8.3 ms, p90 8.7 ms, max 10.3 ms |
| `scroll/long`, 500 rows | debug | median 23.8 ms, p90 24.9 ms |
| `scroll/vertical-overflow`, 20 rows | debug | median 3.5 ms, p90 5.0 ms |

About 15 µs per row in release, so a few hundred simple rows stay inside a 60 Hz frame and a
few thousand do not; that is the trigger for an offset-only repaint path and content layer
caching (open below). The probe also checks that a real wheel event is consumed by the canvas
(the page does not scroll), that the offset clamps at 0 and that the indicator has faded 1.2 s
after the last tick. Note that headless Chromium delivers `mouse.wheel(0, 40)` as `deltaY: 20`
at device scale factor 2.

### Landing page frame budget (Chromium, `Playwright/landing-perf.mjs` and `landing-mobile.mjs`, 2026-09-05)

`__swiftuiwebDebug.framePhases()` splits a frame into layout, display list (`render`), paint
(encode + Canvas2D), the semantics walk and the overlay DOM writes. The landing page (94 ops,
307 overlay elements at 1280 × 900; 57 ops in the iPhone 14 emulation) scrolled by wheel or
touch, release build, mean per frame:

| Step | Before | After |
|---|---|---|
| Overlay DOM writes (307 elements) | ~3 ms: `style.left`/`top` per element through the bridge | 1.4 ms: one `overlayFrames` typed-array call for the elements that moved; text-input styles only when they change |
| Semantics walk | ~3 ms every frame | 0.5 ms: a frame that only moved scrolled content reuses the last walk with the frames refreshed (`Runtime.semanticsTree`, valid while no state update is pending) |
| Whole frame, desktop | 9–13 ms | 8.0 ms (layout 0, render 2.5, paint 3.7) |
| Whole frame, iPhone 14 emulation, finger drag | 6–7 ms | 4 ms |

The painter also keeps its group offscreen canvases between frames (`reset()` instead of a new
`OffscreenCanvas` per shadow or opacity group). What remains is the display list walk and the
Canvas2D text (`fillText`), so the next steps are per-node display-list fragments and a text
glyph cache. iPhone Safari runs `requestAnimationFrame` at 60 Hz on ProMotion phones unless the
visitor turns off "Prefer Page Rendering Updates near 60fps" in Safari's feature flags (iOS 18+);
the page cannot ask for 120 Hz, it can only keep a frame under 8 ms so it is smooth when allowed.

## Scroll position, targets and geometry (macOS 26.6.2, SwiftUI 7.6.1, goldens 2026-09-19; iOS 26 simulator twins)

Values a golden cannot show as pixels are encoded in 1 pt tall probes `value + 100` wide.

| Behaviour | Value | Fixture |
|---|---|---|
| `scrollPosition(id:)` initial value | no scroll: row 0 stays at y 0 with the binding at 10 (macOS and iPhone; a lazy stack parks the rows it prepared at y 428+, below the viewport) | `scroll/position`, `scroll/position-center`, `ios/scroll/position` |
| Setting the binding | the smallest offset change: row 20 ends up bottom-aligned (y 199 of 219; y 626 of 666 on iPhone) | `scroll/position/row20`, `ios/scroll/position/row20` |
| `ScrollViewReader.scrollTo` with a position binding | scrolls, the binding keeps its value (20) | `scroll/position/proxy5`, `proxy-center` |
| `contentMargins(20, for: .scrollContent)` | content at y 20 and the scroll view 160 wide for 120 pt rows (the margins add across the axis); `.horizontal, 12` gives 144; `.top, 30` (automatic) insets the content; `for: .scrollIndicators` changes nothing | `scroll/margins` |
| `ScrollGeometry` at rest with a 20 pt top margin | `contentOffset` (0, −20), `contentInsets.top` 20, `containerSize` 120 × 130 for a 150 pt viewport, `bounds` (0, −20, 120, 130), `visibleRect` (0, −20, 120, 150), `contentSize` 120 × 400 | `scroll/geometry`, `ios/scroll/geometry` |
| `ScrollGeometry` after `scrollTo(10, anchor: .top)` | `contentOffset.y` 180 (row 10 sits under the margin), `visibleRect.minY` 180 | `scroll/geometry/row10` |
| `onScrollGeometryChange` calls | 2 at rest (an initial call, then the laid-out geometry), 3 after the programmatic scroll | `scroll/geometry` |
| `onScrollPhaseChange` calls | 1 at rest, none for the programmatic scroll | `scroll/geometry` |
| `defaultScrollAnchor(.bottom, for: .alignment)` | 3 rows in 200 pt sit at y 140–200; `.center` at 70 | `scroll/anchor-roles` |
| `defaultScrollAnchor(.bottom, for: .sizeChanges)` | content at the top stays put as 5 rows are added; content at the bottom (`defaultScrollAnchor(.bottom)`) stays at the bottom (offset 200 → 300) | `scroll/anchor-roles/grow` |
| `scrollIndicatorsFlash(onAppear: true)` | nothing in the capture: the flash had faded | `scroll/flash` |

## Fidelity

Tier A: all 22 fixtures exact (the `scroll/scroll-to`, `scroll/position` and `scroll/geometry`
steps included). Tier C ≤ 0.8 % (`scroll/position` steps). Tier B: Chromium within tolerance
(`scroll/flash` frames only: ours paints the knob at rest), WebKit 17/17 (≤ 0.2 %), Firefox 17/17
(worst 1.09 % on `scroll/text`, the usual glyph-hinting class) as of 2026-09-02 for the older
fixtures.

## Open

- Rubber band / bounce and `scrollBounceBehavior`; keyboard scrolling (arrows, page, home/end);
  hover-expanding legacy scroller; the indicator's hold and fade times and its minimum length.
- Animated `scrollTo` (`withAnimation` around a position write); the `animating` phase is never
  reported; `contentMargins` on `List`; the positioned identity written back during a scroll is
  the target showing the most (SwiftUI's exact rule is unmeasured: the goldens cannot scroll
  by hand).
- Which scroll view a nested `scrollTo` should pick (structural order today, outermost first).
- Lazy stacks; an offset-only repaint path, damage rects and content layer caching once a
  measurement shows the full layout pass per scrolled frame is the bottleneck.
