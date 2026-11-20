# iOS platform profile

The runtime reproduces the macOS look by default. `PlatformProfile.iOS`, selected through the
`platformProfile` environment (fixtures marked `.platform(.iOS)`, the landing page's phone
frame), switches text styles, control geometry and colours to the iOS look. Goldens come from
an iPhone SE simulator on iOS 26 (decision 0015, `scripts/gen-goldens-sim.sh ios`; the Mac
Catalyst route of decision 0013 remains as a comparison tool); the metrics live in
`PlatformMetricsIOS.swift` and `SystemFontMetricsTableIOS.swift`.

## What switches

| Piece | macOS | iOS |
|---|---|---|
| Default text font | 13 pt system font | `.body` (17 pt, 24.5 pt line, baseline 18.5) |
| Text styles | HIG macOS table | HIG iOS table: largeTitle 34 (48.5 line), title 28 (41), title2 22 (32), title3 20 (28), headline 17 semibold, subheadline 15 (21), body 17, callout 16 (24), footnote 13 (18.5), caption 12 (17.5), caption2 11 (16) |
| Bold trait | per style (`text/bold-trait`) | bold for largeTitle, title and title2; semibold for every other style, headline included (`ios/text/bold-trait`: the widths of the w600 faces) |
| Default padding, stack spacing | 16, 8 | 16, 8 (text-to-text 2 for body, 8 sideways); controls keep the plain 8 and let a text's own distances win: 14.81 from a body text down to a control, 8.43 from a control up to a text; a borderless button takes its label's distance above and the plain 8 below; a toggle or stepper row spaces like a control, not like its label (`ios/layout/controls`) |
| Button (automatic) | bordered | borderless: body label in the accent colour, red for a destructive role |
| Button sizes and states | bezel sizes | `controlSize`: mini and small are 31 pt capsules of a subheadline label 10 in, large and extra large 54.5 pt capsules of a body label 20 in; a destructive prominent button is a red capsule with a white label; a disabled prominent one wears the bordered fill with its label at 17 %, a disabled plain one its label at 50 % (`ios/button/looks`) |
| Bordered / prominent button | 24 pt rounded rect, 13 pt label | 38.5 pt capsule: body label, 12 pt sideways and 7 pt vertical padding; fill black 41/255 (prominent: the accent, white label) |
| Toggle (automatic) | checkbox | a row filling the proposed width: label leading, the iOS 26 switch (66 × 30: a green (52, 199, 89) or (118, 118, 124) 16 % capsule filling its frame, a 38 × 25 white pill knob 2.5 in, 0.5 from the on end) trailing, text baselines at the row's top; hidden label = the switch alone; disabled: the track at half strength, the knob and the label as they are; in a list row the toggle is its label's 24.5 pt line and the switch overflows it |
| Slider | 16 pt row, label before the track | 31 pt row filling the width, no label outside a form, accent fill; disabled: accent at 50 % |
| Stepper | 20 × 26 arrows after the label | a row filling the width: label leading, a 94 × 32 control trailing (93 × 28 capsule, black 11/255, a 1 pt divider at 75/255, − and + of 13 pt / 2 pt strokes at 218/255); text baselines at the row's top; − left decrements |
| TextField | 24 pt bezel | 34 pt rounded border (0.5 pt black 20 % inside, 4 pt corners, text 7.5 in, baseline 23.5 down), 26 pt plain with the text at the top, empty or not; automatic = plain; placeholder (189, 189, 190); secure bullets 7 pt at a 10.5 pitch |
| Picker (menu) | pop-up button with the label | the selected value in the accent colour with two chevrons, no box or label: 40.5 tall, 13.5 in each side, chevrons 9 wide 4 after the text |
| Picker (segmented) | equal segments of the widest option + 21 | fills the proposed width, 31 tall, capsule black 31/255; the selected segment a white capsule inset 7 × 2; titles 13 pt medium (selected semibold), 7 pt down |
| Disabled labels | 30 % | buttons 24 % (52 over 215); a toggle's or stepper's label is not dimmed |
| Divider | 1 pt | 0.5 pt, a hairline (`ios/layout/basics`) |
| Plain text field, empty | — | 26 pt, like one with text (`ios/dark/controls` `emptyField`) |
| List (automatic) | inset rows on white | inset grouped: a (235, 236, 236) ground, each section a white card 16 in with 26 pt continuous corners; rows max(56, content + 30) with content 16 in and centred, 1 pt separators from the content's leading edge to the card's inner edge, none under a card's last row; 35 above a first card without a header and between a card and the next header-less card (`ios/representable/form`); headers in body medium, secondary, 27.5 below the previous card (10 at the top) and 10 above their card; navigation link rows fill the row and end in a 7 × 12 chevron at 30 % |
| SF Symbols | the metrics table's sizes | the same table by point size, weight and scale (`ios/symbol/basic`: star 22 × 20 at body, 36 × 34 at title); iOS's 28 and 34 pt styles are extrapolated from the macOS sizes, within 1.5 pt, so `ios/symbol/` and `ios/label/` are checked within 3 pt |
| Label | icon + 8 + title; in a list a 16 pt slot, 6 to the title | icon + 8 + title outside lists (`ios/label/basic`); in a list row the icon at the large image scale (star 28 × 27), centred in a 24 pt slot it may overflow, 16 to the title, the accent tint (`ios/label/list`; the row grows to the icon's 27) |
| Menu button | a pull-down button | its label in the body font and the accent colour, nothing else: no fill, no chevron (`menuIndicator` has nothing to hide); black at 67/255 when disabled; it lines up with text on the baseline (`ios/menu/basic`); the menu itself opens as the runtime's presentation |
| Section footer | 12 pt text | footnote in the secondary colour, 8 below its card in a 21 pt slot (UIKit's label height around the 18.5 pt line, so the footer probes are ignored while the rows around them are checked), the next card 23.5 below the slot (`ios/list/footer`); a header that follows a footer sits 16 below the slot (`ios/list/footer-header`) |
| ProgressView (linear) | a 20 pt row with an 8 pt pill | a 4 pt accent pill on a (120, 120, 125) 20 % track, no indeterminate segment; a label sits 4 above it in the primary colour (`ios/progress/basic`) |
| ProgressView (circular) | a 32 pt ring or spinner | always the 20 pt spinner, a value included: eight spokes from 38 % to 12 % black, the darkest pointing left; a label below it in the secondary colour |
| List (plain) | 8 pt margins | white, rows 56 with content 16 in, separators 16 in; headers 32 below the previous row, 10 above the next |
| Form | columns | an inset grouped list; a menu picker row keeps its label and puts the value and chevron, in the secondary colour, at the trailing edge; sliders lose their label; text fields are plain; a toggle, stepper or menu picker row is its label's 24.5 pt line and the control overflows it (rows stay 56) |
| NavigationStack | content-sized; no bar (the window's title) | fills its proposal (`ios/nav/sizing`: 320 × 267.5 above a text in a 300 pt column); each screen under its own bar: 117 pt with the large title (34 pt bold, 20 in, its line 65.5 down) or 64 pt inline (headline, centred), none for an untitled root or a pushed screen with neither title nor back button (`ios/nav/push-noback` fills the stack); a large title takes the list's 35 pt top inset, an inline one does not; `.automatic` on a pushed screen inherits the previous screen's large title (`ios/nav/push`: 117 over the detail) |
| Large title on scroll | — | the title scrolls up with the screen's content, clipped under the 64 pt inline zone; once the content has scrolled its full 53 pt the bar is the inline one, the content frame grows by 53 and its offset shrinks by 53 so what is on screen stays put (`ios/nav/scroll`: a 40 pt scroll leaves the bar large, a far one collapses it); back at the top it expands again (UIKit leaves a programmatic scroll to the top collapsed; a drag expands it) |
| Search field | the window toolbar | iOS 26 puts a navigation stack's `searchable` in a 46 pt capsule at the bottom of the screen (28 in, the content 76 shorter); presented, the bar hides, the field moves down beside a 48 pt cancel circle, suggestions replace the content and an active scope bar takes a 44 pt band at the top (`ios/search/*`, Docs/elements/Toolbar.md "iOS") |
| DatePicker (wheel) | the field | `.wheel`: a 320 × 216 picker of three columns on a cylinder, the selected row on a 30 pt band, 23 pt labels shrinking and fading away from it (`ios/datepicker/wheel`, Docs/elements/DatePicker.md "iOS wheel") |
| Back button | none | a pushed screen's bar (unless `navigationBarBackButtonHidden`): a 44 pt circle at (10, 10) filled (246, 246, 246) at 66 % (white behind it reads 249.5, the grey ground 243), a chevron 8 × 16 between its tips of a 3 pt round stroke, its centre 1.5 left and 0.5 below the circle's, in the accent colour; the large title keeps its place below it; pressing pops |
| Push, pop | instant | a 0.35 s ease-in-out slide: the pushed screen arrives from the trailing edge over the old one, which travels 30 % of the width the other way under a black dimming that reaches 10 %; the bars cross-fade; a pop reverses it and keeps the popped screen mounted until it is out. Inferred from iOS, not measurable from goldens |

## Measured (iPhone SE simulator, iOS 26.0, `ios/*` fixtures, 2026-09-10)

Every row above comes from `Fixtures/Goldens/ios/<fixture>/frames.json` and pixels sampled from
`image@2x.png`, all 36 `ios/` fixtures regenerated on the simulator with `scripts/gen-goldens-sim.sh ios`
(decision 0015). Tier A holds every one exact; the only allowances are the symbol table's
extrapolation (`ios/symbol/`, `ios/label/` within 3 pt), UIKit's footer slot (21 around a 19 pt
footnote line: the footer probes are ignored) and its header label ("Header" measures 37 for
SwiftUI's 36). Tier B and C compare pixels within the base 3 % everywhere (dark fixtures over the
black window the iPhone draws).

What the iPhone changed against the Catalyst goldens of 2026-09-05: text 2 to 4 % narrower and
the text styles' own metrics (body's baseline at 18.5, callout's line 23.5, footnote's 19); the
0.5 pt divider; the 66 × 30 iOS 26 switch; list rows whose toggle, stepper and menu picker are
their label's line; a borderless button spacing plainly below; navigation bars of 116.5 (large)
and 64 (inline) with the title 16 in; a scrolled large title fading under the bar's glass with the
content showing through; opaque screens; a plain list painting black only behind its rows in the
dark appearance; the palette below.

The first nine fixtures had been exact on Catalyst too; the list-backed ones were within 3 pt
there because Catalyst's UIKit cells measured text 1.5 to 2.5 pt narrower than SwiftUI's. That
allowance is gone: the iPhone's cells and text agree.

## Colours and the dark appearance

`ios/color/system` and `ios/dark/system-colors` on the iPhone: the tints match macOS 26's except
in the dark appearance, where grey is (142, 142, 147), indigo (107, 93, 255) and the accent
(0, 145, 255) (`PlatformProfile.iOSLightColors`, `iOSDarkColors` in `Display/ColorTable.swift`).
Labels are opaque black or white; the secondary label is (60, 60, 67) at 60 % (dark:
(235, 235, 245)), the tertiary and quaternary the secondary at half and 0.3 (30 % and 18 %),
which is how `.tertiary` and `.quaternary` resolve on iOS as fills and foreground styles. The
backgrounds: a white window with the (242, 242, 247) grouped ground and white cards in the
light appearance; in the dark one a black window, black text fields, a plain list black behind
its rows only, and the grouped values, a black ground with (28, 28, 30) cards. A navigation
screen is opaque: the list's ground, else the window's colour (`ios/nav/push-noback`,
`ios/dark/nav`). Measured in `ios/dark/controls`: the bordered button's fill (118, 121, 128) at
32 % (the light one (118, 118, 124) at 16 %), the slider's unfilled track and the stepper's pill
at the light alphas in white, the placeholder white at 25 %, the selected segment (191, 191, 204)
at 47 % over a (117, 117, 130) 24 % fill.

## Scroll content under the bar (iPhone SE simulator, iOS 26, `ios/nav/list-scroll`, `ios/nav/ignores`, 2026-10-04)

| Behaviour | Value | Fixture |
|---|---|---|
| `ScrollView` ignoring the top safe area | its probe frame is the safe one (116.5 down, 283.5 tall; 64 and 336 once collapsed) while its content starts at the window's top (row 0 at y 0) and `scrollTo(8, anchor: .top)` lands row 8 at y 0: the collapse grows nothing and shifts no offset | `ios/nav/ignores` |
| `List` under the large title | rows 56 apart from 132.25 (the list 116.5 down with its 15.75 inset); `scrollTo(1, anchor: .top)` collapses the bar (56 ≥ 53) and UIKit re-anchors the row: row 1 at 73.25, 9.25 under the inline bar; `scrollTo(8)` lands row 8 at 79.75, 15.75 under it (the plain scroll view's row 8 lands 52.5 under it). Ours collapses the bar and keeps the content put, so the rows sit elsewhere after a programmatic scroll; the rows in view are compared only before the steps | `ios/nav/list-scroll` |

## The navigation bar's glass (iOS 26)

At rest the bar is transparent over the screen's ground (`ios/nav/basic`, `ios/nav/inline`).
Once content has scrolled under it (`ios/nav/scroll` `row1`, `row8`) a tint of the ink at 37/255
sits at the window's top and eases out over 80 pt (218 at the top, 231 at 40 pt, 246 at 60, 253
at 80 over white), full after a quarter of the collapse; the large title travels with the content
and fades over the collapse instead of being clipped, and the scroll view keeps painting up to the
window's top (`_navigationBarOverhang`), so the rows show through the glass.

## Presentations, the tab bar, date pills and selection (iPhone SE simulator, iOS 26.0, 2026-09-18)

Window-captured fixtures (`Fixture.capturesWindow`: the golden is the whole 375 × 667 window,
a step presents first) `ios/sheet/basic`, `ios/sheet/medium`, `ios/representable/sheet`,
`ios/alert/basic`, `ios/dialog/basic`, `ios/tabs/basic` and `ios/tabs/second`, plus
`ios/datepicker/compact` and `ios/list/selection`; the presenting screens are white so the
glass materials blur an app's ground. Tier A holds every probe exact; Tier C is within 1.5 %
(the date picker 2.5 %): the materials are painted as their colour over the dimmed white and
the shadows as rings (`PlatformMetricsIOS.swift`).

- **Sheet** (`ios/sheet/basic`, regenerated on iOS 27 on 2026-10-12 with the whole `ios/sheet/`
  family: the harness built with Xcode 27's SDK no longer loads on the iOS 26 runtime): the
  window dims 20 % black; the card is white, the window's width, from 21 to the bottom (31 on
  iOS 26) with 39 pt top corners, its content centred in it and clipped to the card
  (`sheetsFillWindow`, `sheetTopInset`, `sheetCornerRadius`). With `presentationDetents([.medium])`
  (`ios/sheet/medium`) the card floats: 351/667 of the window tall, 6 in from the sides and the
  bottom, every corner 39, the regular material ((239) over the dimmed white); with
  `presentationDragIndicator(.visible)` a 36 × 5 grabber 5 below the top at black 25 %. A
  representable in a sheet lays out like any leaf (`ios/representable/sheet`).
- **A navigation stack in a sheet** (`ios/sheet/nav`, `ios/sheet/nav-titled`, iOS 27,
  sw-ios-sheet-nav, 2026-10-12): the stack has a bar of its own, 5.5 lower than at the window's
  top (`sheetNavigationBarTopInset`: the first form row at 104.5 from the card's top under an
  inline bar, 122 under the large title; 99 and 116.5 at the window's top). `navigationTitle("")`
  is an inline bar drawing no title; the presenting stack keeps its own title and items
  (`NavigationTitleNode` leaves `Runtime.navigationTitle` alone inside a presentation).
- **Navigation bar items** (`ios/sheet/nav`, iOS 27): on iOS a `toolbar`'s items belong to the
  bar of the nearest `NavigationStack` (`NavigationStackNode.registerToolbar`; the window gets
  no toolbar on iOS, `Runtime.showsToolbar`) as 36 pt glass pills 14 below the bar's top and
  20 in from the window's sides, `cancellationAction` leading, the others trailing, the label
  in the body size with 12 pt of pill either side, semibold for `confirmationAction`
  (`_IOSBarItemsView`, `_IOSBarButtonStyle`, hosted and hit tested like the search chrome; the
  glass is approximate: a half-white fill, a faint rim and a soft shadow). A bar with items
  and no title exists at the inline height.
- **Alert** (iOS 27, `ios/alert/basic` and `ios/alert/stacked` regenerated on the iOS 27
  simulator, 2026-10-11; iOS 26's 299 pt card with an accent-filled cancel button is gone): a
  320 pt glass card (237) centred with 34 pt corners over the 20 % dim; a 17 pt bold title
  and a 15 pt secondary message leading-aligned 31.5 in, the title 25 from the top, the message
  10.5 below it (a wrapped title's lines 5 further apart — one sample); 21 below the message the
  48 pt capsule buttons (black 12 %, the (206) over 237): two share a row 16 apart, 20 from the
  sides; one, or three and more, stack 8 apart 16 from the sides with the cancel button last;
  16 from the bottom. The cancel label is semibold, the destructive one (216, 63, 56), the rest
  the primary colour, all 17 pt. Tier C 1.2 % / 2.4 %.
- **Confirmation dialog** (iOS 27, `ios/dialog/basic` regenerated 2026-10-11): a 241 pt white
  panel with 32.5 pt corners centred on its source (kept 16 inside the window), no arrow, no
  dim, a soft shadow; the same 17 pt bold title and 15 pt secondary message 31.5 in (25 from the
  top, 10.5 apart), the actions 21 below stacked as 208 pt 48 pt capsules 8 apart (black 12 %),
  16 from the bottom; the cancel button is not shown (a tap outside dismisses). Tier C 1.7 %.
- **Full-screen cover** (`ios/sheet/fullscreen`, 2026-10-11): `fullScreenCover` fills the
  window with its content over the system background — no card, no inset, no dim. Tier C 0.75 %.
- **Multiple selection in edit mode** (`ios/list/multiselect`, 2026-10-11): every row's content
  moves 40 in for a 22 pt circle 17 from the card's edge: a 1.5 pt (197, 197, 199) ring, or
  the (59, 134, 247) disc with a white check when selected; a selected row fills with
  (209, 209, 214) inside the card. Tier A exact, Tier C 0.75 %.
- **Tab bar** (`ios/tabs/basic`, `ios/tabs/second`): a floating capsule (251, 252, 252),
  270 wide (52.5 in from each side), 58 tall, 23 above the window's bottom, a soft shadow
  below; the content is centred in the window less 83 at the bottom. The tabs share the
  capsule less 6 at each end; the selected tab sits on a 93.5 × 53.5 pill 2 below the capsule's
  top at black 8.6 %, whatever its label; a 24 pt symbol 7.5 below the pill's top and a 10 pt
  medium label on the baseline 44 below it, the accent for the selected tab, the primary colour
  otherwise. A programmatic selection change leaves the pill raised as glass for seconds, so
  `ios/tabs/second` starts on the second tab instead of stepping there.
- **Compact date picker in a form** (`ios/datepicker/compact`): the row spans its width with
  the label leading; each value sits in a pill at the trailing edge ("Mar 15, 2025", "11:09 AM"
  in 17 pt, 13.5 of padding each side, 8 pt corners, black 6.3 %), the pills 5 apart; a date
  alone is 38.5 tall, a picker with a time 40, and the row is that plus 30. Disabled, the pills
  go and the texts stay black. The fixture's hour has two digits: iOS 26 sizes the time pill for
  the wider of its own time and the current one.
- **List selection** (`ios/list/selection`): the selected row fills its 56 pt row across the
  card with (209, 209, 214), the separators beside it hidden; a row outside a `ForEach` is
  identified by its `tag`.

## Open on the simulator

The materials' blur is approximated by their colour and the shadows by rings. Not measured:
a sheet offering both detents and dragging between them, the tab pill's selection animation,
a tap on a date pill (iOS opens a calendar popover), a dialog whose source sits at the window's
edge (the panel is clamped 16 inside). The blur inside the navigation bar's glass is
approximated by the tint alone. Dark-appearance switch and slider tracks are painted with the
light alphas in white. The iOS 26 sheets, tab bars, date pills and the single selection keep
their iOS 26 goldens; alerts, dialogs, the cover and the edit-mode selection come from iOS 27.

## The Catalyst route (decision 0013), kept for comparison

`scripts/gen-goldens-ios.sh` still renders the same fixtures in a UIKit window on Mac Catalyst
(iPad idiom). Its text measures 2 to 4 % wider than the iPhone's, its `UIFont` metrics differ
(`Docs/elements/UIKit/UIFont.md`), it draws the Mac switch and slider knob, a Mac window's greys
in the dark appearance with premultiplied PNGs, and the compact date picker, tab bars and sheets
as an iPad would. Nothing from it is committed; `meta.json`'s `host` names the producer.

## The drawn keyboard (iOS 27 simulator, iPhone 16, new-website#648, 2026-11-20)

On the iPhone look in a browser on a computer (no coarse pointer; `?keyboard=none` leaves it
out), a focused text field or editor brings up the iOS 27 keyboard drawn by the runtime
(`Runtime/Keyboard/`). A phone's browser keeps its own.

- **Look:** 328 pt tall (UIKit's end frame y 524), top corners 34, suggestions band 53, four rows
  of 42 pt keys at 53.33, 107.33, 161.33 and 215.33. Full rows start at 7 (11 keys 28.33 wide
  35 apart, 10 keys 32 wide 38.67 apart), shorter rows centred; shift 7 / 43.33, delete
  342.67 / 43.67, bottom row 123 7 / 41.33, emoji 55 / 41.67, space 103.33 / 186.33, return
  296.33 / 90. Colours sampled from the simulator: panel #E2E3E8 / #202020, keys white / #444,
  held key #DFDFDF / #676767, the bubble (52 × 64, 4 above the key) white / #505050. Our own
  drawn icons; the return key follows `submitLabel` (Send an arrow up on blue).
- **Layouts:** from the app's language (`Bundle.main.preferredLocalizations`, or the host's
  `softwareKeyboardLanguage`): German is Swiss German QWERTZ with Ü Ö Ä, French Swiss French
  (QWERTZ, one accent key after L whose mark follows the letter before the caret: ´ after e,
  ` after a, ^ after u o i, ’ after a consonant, put on the letter when it takes it), anything
  else US English. 123 and #+= pages; an emoji page in the viewer's emoji font.
- **Finger:** a press dims the key and shows its bubble, which follows the finger across keys;
  lifting types the key, off the keys nothing. Holding a letter with accents (0.45 s) opens
  the accent row; holding delete repeats (after 0.5 s, every 0.1 s). Capitals at a sentence's
  start (or as `textInputAutocapitalization` asks), shift toggles, a double tap locks, a double
  space types ". ", space goes back to the letters.
- **The viewer's keyboard:** types through the input element as before; the drawn key it
  matches is held with its bubble while the real key is down (a character on another page
  brings that page up).
- **Motion and layout:** slides on UIKit's keyboard spring (`SpringModel.navigation`, critical at
  ω ≈ 18). The keyboard is the safe area's keyboard region: regions combine as the deeper one,
  a reader reports the depth from the screen's edge, and `ignoresSafeArea` drops only the
  regions it names (`.container` keeps the keyboard: a reader there reports 328 with the frame
  ending at the keyboard's top; `.keyboard` is as if it never came up). Layout takes the final
  values at once and the frames move on the keyboard's spring. UIKit's notifications follow
  (end frame, 0.3833 s, curve 7). Tests: `KeyboardSafeAreaTests`, `SystemKeyboardTests`.
- **Not yet:** guesses in the suggestions band (it shows the typed word only), dictation (the
  mic does nothing), number pads (a numeric `keyboardType` opens the 123 page), sheets avoiding
  the keyboard.
