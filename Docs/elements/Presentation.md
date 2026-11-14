# sheet, popover, alert, dismiss (the presentation layer)

Apple docs: [sheet(isPresented:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)),
[popover(isPresented:attachmentAnchor:arrowEdge:content:)](https://developer.apple.com/documentation/swiftui/view/popover(ispresented:attachmentanchor:arrowedge:content:)),
[alert(_:isPresented:actions:message:)](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:actions:message:)-8dvt3),
[DismissAction](https://developer.apple.com/documentation/swiftui/dismissaction).

## API surface

| API | Notes |
|---|---|
| `sheet(isPresented:onDismiss:content:)`, `sheet(item:onDismiss:content:)` | implemented (modal, dimmed backdrop) |
| `popover(isPresented:attachmentAnchor:arrowEdge:content:)`, `popover(item:…)` | implemented: anchored to the view's bounds, a rect in them (`.rect(.rect(_:))`) or a point of them (`.point(UnitPoint)`, 2026-09-18); a press outside dismisses |
| `alert(_:isPresented:actions:message:)` (Text, key and string titles, with and without a message) | implemented (buttons dismiss after their action) |
| `confirmationDialog(_:isPresented:titleVisibility:actions:message:)` | implemented: an alert-style panel on macOS; on iOS a glass popover above its source, its actions stacked as capsules and the cancel button left out (`Docs/elements/iOS.md`, `ios/dialog/basic`) |
| `@Environment(\.dismiss)`, `DismissAction` | implemented: dismisses the presentation the view is in, else pops the enclosing `NavigationStack` |
| Pop-up `Picker` menu | implemented (`Docs/elements/Picker.md`): a menu below the button with the selected row checked |
| `fullScreenCover`, `Menu`, `contextMenu`, `fileImporter`, `presentationMode`, keyboard dismissal (Escape) | implemented 2026-09-04 (`Docs/elements/Keyboard.md`) |
| `interactiveDismissDisabled(_:)` | implemented 2026-09-18: a press outside the presentation and Escape are consumed without dismissing; programmatic dismissal still works (`PresentationTests`) |
| `presentationDetents` (`medium`, `large`; `fraction`, `height` and the selection form accepted), `presentationDragIndicator` | implemented 2026-09-18 for the iOS sheet (`ios/sheet/medium`): the medium detent's floating card and the grabber; no effect on macOS |

## Behaviour

`PresentationNode`s are owned by the runtime (`Runtime.presentations`), parented to the root
but outside its layout children. `Runtime.layout` lays them out after the main tree at the
window's size (`layoutPresentations`), `render` paints them last (`paintPresentations`) and
`interactiveNode(at:)` consults them first (`presentationHit`): a hit inside the topmost panel
wins, a press inside a panel but on nothing is consumed, a press outside a modal panel is
consumed, and a press outside a popover or menu dismisses it and is consumed. The modifiers'
bodies read their binding (`_PresentationModifier` → `_PresentationSync`), so observation
presents and dismisses through `PresentationSyncNode`; dismissing from inside (the `dismiss`
action, an alert button, a menu row, a press outside) removes the node at once and resets the
binding. Content is mounted with the presenter's environment plus `dismiss`; `_dismissesOnActivation`
makes an alert's buttons dismiss after running. `Runtime.dismissTopmostPresentation()` is for hosts.

## Motion on iOS (new-website#264)

A sheet or cover presented after its presenter is on screen slides up from below the window on
UIKit's navigation spring, its dim following; a finger drags a sheet down (scroll views inside
it first take what they can), and it closes past half its height or on a flick, else springs
back; dismissed, it slides off and is painted from `Runtime.leavingPresentations` until it is
gone, while presses already go behind it. A sheet's scroll views take touches and the wheel
(`scrollableNodes` looks in the topmost presentation; nothing under a modal one scrolls). How
it works: `Docs/elements/Physics.md`. Tests: `SheetMotionTests`.

## Geometry (macOS 27 window geometry measured 2026-10-12; the panels' chrome by eye)

iOS is measured: the sheet, its medium detent, the alert and the dialog on the simulator are
in `Docs/elements/iOS.md` (`ios/sheet/`, `ios/alert/`, `ios/dialog/`; the golden captures the
whole window). On macOS (sw-mac-presentation-looks) `Fixture.capturesWindow` puts the harness
window on screen so the presentations open as the separate windows they are; the harness
records each presented window's frame relative to the content as a probe (`window.sheet`,
`window.alert`, `window.popover`, `window.menu`; `Runtime` publishes the same names from its
presentations, `PresentationNode.windowFrame`) and composites the windows' content views into
the capture (`presentation/mac-sheet`, `mac-alert`, `mac-popover`: Tier A exact, Tier B/C
≤ 1.4 %). The panels' own chrome — glass, shadow, corners — is the window server's and would
need screen recording to capture, so it stays by eye.

| Kind | Panel |
|---|---|
| Sheet | a window exactly the content's size in whole points (the content pads itself; 209 × 115 for a 16 pt-padded three-line sheet), limited to the window minus 20 pt margins (a taller content is proposed the limit, so a `ScrollView` inside scrolls), centred in the window as AppKit rounds (x up at a half, y measured from the bottom); the window behind is **not** dimmed; 10 pt corners, 1 pt border at 15 %, a 2 pt shadow ring at 12 % (by eye) |
| Popover | a window of the content plus a 13 pt margin all round (the arrow and shadow live in it), its edge on the anchor's: `arrowEdge: .top` (the default) is the arrow on the anchor's top edge, so the popover sits **above** the anchor, `.bottom` below, `.leading`/`.trailing` beside; centred on the anchor at whole points, kept 13 inside the window (162 × 101 for a 16 pt-padded two-line popover above a button) |
| Alert | a 260 pt window centred (260 × 127 for a title, a message and two buttons); the 13 pt bold title centred 20.5 from the top, the 13 pt message (primary, not secondary) 13 below, 17.5 below it 28 pt capsule buttons sharing the width 8 apart and 16 from the sides — the cancel role first on grey (229), the destructive role on pink (255, 220, 220) with red text — 16 from the bottom; not dimmed |
| Menu | rows 22 pt tall (a 22 pt check column, the 13 pt title, 16 pt trailing), at least the pop-up's width, 4 pt above and below, 2 pt under the button (above it when it would overflow); 6 pt corners |

## Verification (2026-09-03)

`presentation/basic` (buttons presenting each kind, a pop-up picker) is exact in Tier A and Tier B
for the base state. `PresentationTests` cover the sheet (geometry, modal blocking, `dismiss`,
`onDismiss`), the popover (anchor, dismissal outside), the alert (buttons dismiss) and the picker
menu (opens, a row selects and closes). `Playwright/presentation-probe.mjs` presents and dismisses
every kind in headless Chromium through the accessibility overlay. wasm js tests pass.

## Not yet covered

The real macOS looks (sheet slide-in and shadow, popover material, alert icon and button
layout), sizes for wide content (no scrolling inside sheets), `Menu`/`contextMenu`, keyboard
dismissal, focus moving into the presentation, detents beyond medium and large. The macOS
window geometry is measured (above); the panels' chrome (the sheet's glass and shadow, the
popover's material and arrow shape, the alert's capsule fills) stays by eye, as does the menu
window (no fixture presents one). Several presentations from one view work
(`oneViewPresentsASheetAndAnAlert`).
