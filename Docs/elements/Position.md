# position, safeAreaInset, safeAreaPadding, ignoresSafeArea

Apple docs: [position(x:y:)](https://developer.apple.com/documentation/swiftui/view/position(x:y:)),
[position(_:)](https://developer.apple.com/documentation/swiftui/view/position(_:)),
[safeAreaInset(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareainset(edge:alignment:spacing:content:)-6gwby),
[safeAreaPadding(_:)](https://developer.apple.com/documentation/swiftui/view/safeareapadding(_:)-2qzs2),
[ignoresSafeArea(_:edges:)](https://developer.apple.com/documentation/swiftui/view/ignoressafearea(_:edges:)).

## API surface

| API | Notes |
|---|---|
| `position(x:y:)`, `position(_:)` | implemented |
| `safeAreaInset(edge:alignment:spacing:content:)` for vertical and horizontal edges | implemented (`HorizontalEdge` added) |
| `safeAreaPadding(_:)` (insets, edges + length, length) | implemented |
| `ignoresSafeArea(_:edges:)`, `edgesIgnoringSafeArea(_:)` | implemented (`SafeAreaRegions` added; the keyboard region does not exist in a browser) |
| `GeometryProxy.safeAreaInsets` | implemented: the overlap plus the extension (below) |

## Behaviour

`position` is `PositionNode`, a unary layout modifier: the modified view takes the proposed size
(the child's size where a dimension is unproposed) and places its child's centre at the point in
its own coordinate space. It reports `paintsOutsideFrame`, so a child moved out of the frame is
not culled by a scroll view.

A browser window has no safe area, but the safe-area modifiers create one for their content,
and a host may give the root one (`Runtime.safeAreaInsets`: a `UIHostingController` under a
navigation bar; the iOS profile's `NavigationStack` gives its screen its bar as one). The safe
area travels down by geometry, set on each node by its placer in `place(at:)` (2026-09-12,
measured on the simulator in `ios/representable/safearea-rule`, `safearea-color`):

- a node's `safeAreaOverlap` is how much of its frame lies in the unsafe region on each edge, and
  its `safeAreaExtension` how far beyond an edge that *touches* the safe boundary the unsafe
  region reaches; an edge inside the safe area gets neither (a colour padded 10 pt below a bar
  stays put; one touching the bar extends under it through a `frame(width:)` or a padding on
  the other edges);
- `SafeAreaNode` (`safeAreaInset` with an inset view, `safeAreaPadding` with fixed lengths) adds
  its insets: a plain child is measured and placed in the bounds minus the insets (with nothing
  proposed the insets add to the child's size); a child that *extends into the safe area*
  (`ViewNode.extendsIntoSafeArea`: scroll views, forwarded through wrappers that do not change
  their child's size) keeps the full bounds and its overlap is the insets. `ScrollNode` takes
  the overlap as content insets: the content starts at the top/leading inset, the scrollable
  range grows by the insets, the frame is unchanged; nested safe-area modifiers accumulate;
- `IgnoresSafeAreaNode` keeps the safe frame its parent gives it (a background or probe outside
  the modifier sees that frame) and proposes its content that frame grown by the extension on
  the ignored edges, placed in the grown rect and centred when smaller; the content gets no safe
  area on those edges (a scroll view ignoring it does not inset), while the geometry stays in
  `platformSafeAreaOverlap` for a hosted UIKit view (Representable.md). A content no larger
  than the safe frame moves into the extension on the side it reaches (a bottom bar ignoring
  the bottom edge sits on the home indicator), centred in the grown rect when it reaches both;
- `background(_:ignoresSafeAreaEdges:)` and `overlay(_:ignoresSafeAreaEdges:)` with a style
  wrap the fill in `ignoresSafeArea` on those edges (all by default), so a screen's ground
  colour reaches under the status bar and the home indicator;
- a scroll view's clip reaches through its extension: content scrolls on under the status bar
  and the home indicator, nothing moves at rest;
- `GeometryProxy.safeAreaInsets` is the reader's overlap plus its extension: a reader filling
  an iPhone's safe area reports the status bar's and the home indicator's depths.

### The device's safe area (sw-ios-safe-area, 2026-11-13)

The page hands the app a phone's safe area (`HostedScene.hostSafeAreaInsets`: the container's
`data-safe-area`, `?safeArea=59,0,34,0`, or else the browser's own `env(safe-area-inset-*)`).
The root view is laid out inside it unless it extends into it. Presentations take it too
(`Runtime.place(_:in:insets:)`, the root's rule in an area of the window): a full-screen
cover's content is laid out in the window's safe area; an iOS sheet's card starts at
`sheetTopInset` or the safe top, whichever is lower (59 on an iPhone 16 with iOS 27), has no
unsafe region above it, and keeps its content clear of the home indicator below. Measured
against Paulo's app on the iPhone 16 simulator (iOS 27), 105 screens side by side.

The inset view is proposed the cross length and nothing along its edge's axis, placed at the edge
aligned by `alignment`, and paints (and is hit tested) over the content. Its length plus the
spacing (`spacing`, default 8) is the inset.

## Measured (macOS 26.2, `position/*`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| `position` size | the full proposal: a 200 × 90 ZStack cell, the remaining 244 pt of an HStack row, the remaining 40 pt of a VStack column | `inZStack`, `inHStack`, `inVStack` |
| `position` child | centred at the point within that frame (pixels) | `position/basic` |
| `safeAreaInset(edge: .bottom)` on a VStack in a 100 × 200 box | the stack is laid out 162 pt tall: 200 − 30 (bar) − 8 (default spacing); the bar sits at the bottom | `plainContent`, `plainBar` |
| the same on a ScrollView | the scroll view stays 100 × 200 and its content (240 pt) starts at the top | `scroll`, `scrollContent` |
| `ignoresSafeArea()` under a top inset with `spacing: 0` | the content keeps 100 × 200 under the bar | `ignoringContent`, `ignoringBar` |
| `safeAreaPadding(.vertical, 20)` on a ScrollView | frame unchanged, content 20 pt lower | `paddedScroll`, `paddedScrollContent` |

## Verification (2026-09-04)

Tier A: 3 fixtures exact. Tier C: all three 0.00 %. Tier B: Chromium and WebKit 3/3 with exact
frames; Firefox 2/3 (`position/basic` carries the known 0.25 pt shift of "Above"). `PositionTests`
cover the proposal-sized frame and centring, insets on every edge with alignment and spacing, the
scroll view's content inset and scrollable range under nested insets, `safeAreaPadding`'s three
spellings, `ignoresSafeArea` (and the older spelling), the geometric rule through frames,
padding and stacks, the host's safe area, and unproposed sizes (2026-09-12: the earlier
assumption that a frame stops the safe area was refuted by `ios/representable/safearea-rule`).

## Corners (sw-safe-area, macOS 26.6, 2026-10-11)

| Property | Value | Probe |
|---|---|---|
| `GeometryReader` under `safeAreaInset(edge: .bottom)` (30 pt bar) in a 100 × 200 box | the reader fills the 200 (it extends into the safe area like a scroll view) and `proxy.safeAreaInsets.bottom` is 38 (bar + spacing); its content starts at the safe region's origin | `inside`, `insideBar` |
| the same reader with `ignoresSafeArea()` | fills the 200, reports 0 | `ignoring`, `ignoringBar` |
| a leading inset of 20 under an ignoring reader | reports 0 (the ignored edge has no safe area) | `leading`, `topBar` |
| `safeAreaInset(edge: .bottom, spacing: 2)` on a `ForEach` of two texts (6 pt bar) in a VStack | every element gets a bar of its own: the stack is 48 tall (2 × (16 + 6 + 2)), the rows 24 apart, two bars painted | `stack`, `apple`, `banana` |
| `Color.ignoresSafeArea()` under 10 pt insets on all four edges, in a 100 × 100 frame | the ignoring node keeps the safe frame (64 × 64 at the centre); its colour extends under every bar (pixels) | `edges`, `blue` |
| a vertical scroll view under a bottom inset of 38 | the indicator track stops at the inset: 200 − 8 − 38 = 154, the knob 154 × 200 / 638 (to the half point) | `SafeAreaTests` |
| the keyboard region | none: a browser has no keyboard safe area (the page's viewport shrinks instead) | — |

The reader's node (`GeometryReaderNode.extendsIntoSafeArea`) keeps the full bounds under a
safe-area modifier and proposes its content the bounds less the overlap, placed at the safe
origin; `GeometryProxy.safeAreaInsets` reads the node's overlap. `SafeAreaInsetNode` makes one
inset view per target as the targets are placed (a list modifier applies to every element) and
paints each over its element (`paintedChildren(of:)` on the proxies); dropped targets drop their
views. `ScrollNode`'s indicator margins add the overlap.

Tier A exact, Tier C `position/safe-area-geometry` 0.00 %, `position/safe-area-elements` within
tolerance (text), Tier B Chromium 5/5 with exact frames.
