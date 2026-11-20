# Dark appearance: colorScheme, preferredColorScheme, system colours and control inks

Apple docs: [ColorScheme](https://developer.apple.com/documentation/swiftui/colorscheme),
[colorScheme](https://developer.apple.com/documentation/swiftui/environmentvalues/colorscheme),
[preferredColorScheme(_:)](https://developer.apple.com/documentation/swiftui/view/preferredcolorscheme(_:)).

## API surface

| API | Notes |
|---|---|
| `ColorScheme`, `EnvironmentValues.colorScheme`, `.environment(\.colorScheme, …)` | implemented: system colours, label colours, control inks, list and field backgrounds and asset variants follow the environment |
| `preferredColorScheme(_:)` | implemented: applies to the whole window (the root environment), `nil` returns to the system appearance; inside a sheet, popover or other presentation it applies to that presentation alone (its panel and content; `PresentationNode.preferredColorScheme`, 2026-10-11) |
| The system appearance | the browser host follows `prefers-color-scheme` (and its changes); the native host follows the window's effective appearance |
| `UIUserInterfaceStyle` in the app's Info.plist (or Xcode's `INFOPLIST_KEY_UIUserInterfaceStyle`) | implemented 2026-11-20 (new-website#663): Light or Dark holds the browser host's scheme there whatever `prefers-color-scheme` says, as iOS holds an app to it whatever the device's setting, so the drawn keyboard, alerts and system sheets stay light in a light-only app; Automatic or none follows the system; a window's `overrideUserInterfaceStyle` and `preferredColorScheme` still win over it. The build reads the key from the app's Xcode target (`scripts/info_plist.py`, into the asset manifest's `info`); the native host does not read it |
| `UIWindow.overrideUserInterfaceStyle` on the scene's windows (`UIApplication.shared.connectedScenes`) | implemented (2026-10-29, Ember): a SwiftUI app's launch registers one key window with the UIKit scene; its override is the runtime's `interfaceStyleOverride`, between the tree's `preferredColorScheme` and the host's scheme, and an open presentation follows the root's scheme at once (`InterfaceStyleOverrideTests`) |
| `colorSchemeContrast`, `ColorSchemeContrast` | implemented 2026-10-11: `.increased` when the host reports it (`prefers-contrast: more` in the browser, `accessibilityDisplayShouldIncreaseContrast` natively, `Runtime.hostIncreasesContrast`); nothing built in changes its look for it (AppKit's focus and accent colours read the same under the high-contrast appearances) |

## Behaviour

`PlatformProfile.resolve(_:scheme:)` has a table per appearance (`ColorTable.swift`); `Color`
resolves through `environment.colorScheme`. Controls draw their fills, tracks, separators and
marks with `environment._ink(alpha)` (the `controlInk` system colour: black in light, white in
dark, at the same alphas, which is what Apple's inactive-window greys measure to); text fields,
lists, tables and date pickers fill with `controlBackground`; switch and slider knobs with `knob`;
presentations with `windowBackground`.

`Runtime.hostColorScheme` is the system appearance a host reports (seeded from the initial
environment, so fixtures and tests choose theirs); `preferredColorScheme` records the tree's
preference on the runtime; `applyColorScheme` (in `layout`) moves the root environment to the
effective scheme and re-applies the root view (`RootNode.reapply`), so every node resolves its
colours again. `Runtime.paintsWindowBackground` (hosts set it) makes `render` start with the
window background; goldens are transparent, so fixtures leave it off.

The harness gives a fixture with `.colorScheme(.dark)` a `darkAqua` window (AppKit-backed
controls follow the window, not the environment) and the fixture catalog's dark variants
(`FixtureAssets.appearance`).

## Measured (macOS 26.2, `dark/*`, 2026-09-04)

| Colour | Light | Dark | Fixture |
|---|---|---|---|
| red, orange, yellow, green | 255 56 60 · 255 141 40 · 255 204 0 · 52 199 89 | 255 66 69 · 255 146 48 · 255 214 0 · 48 209 88 | `dark/system-colors` |
| mint, teal, cyan, blue | 0 200 179 · 0 195 208 · 0 192 232 · 0 136 255 | 0 218 195 · 0 210 224 · 60 211 254 · 0 145 255 | |
| indigo, purple, pink, brown, gray | 97 85 245 · 203 48 224 · 255 45 85 · 172 127 94 · 142 142 147 | 109 124 255 · 219 52 242 · 255 55 95 · 183 138 102 · 152 152 157 | |
| primary, secondary | black 216/255, black 127/255 | white 216/255, white 140/255 | `dark/text` |
| tertiary, quaternary (`fill(.tertiary)`) | — | white 63/255, white 25/255 (drawn as primary × 0.35 and × 0.25, within a channel's tolerance) | `dark/system-colors` |
| accentColor | 0 136 255 | 0 122 255 (not the dark blue) | |
| link | 0 104 218 | 65 156 255 | `dark/text` |
| window / control background | white (`NSColor.windowBackgroundColor` on 26.2) | 30 30 30 | `dark/list`, `dark/controls` text fields |
| control inks | black at 19–50/255 (buttons 19, checkbox 25/36, switch 25/36, pop-up 20, segmented 20/50, stepper 20, slider 25/58, progress 15, group box 8) | white at the same alphas | `dark/controls` |
| progress fill | black 85/255 | opaque 170 170 170 | |
| switch and slider knobs | white | white 222/255 | |
| text field border | black 23/255 | 128 128 128 at 22/255 | |
| placeholder, disabled field text | secondary, tertiary | secondary, tertiary (154 and 86 over the 30 fill) | |

## Measured (macOS 27.0.1, `dark/chrome`, 2026-10-11)

| Chrome | Light | Dark | Notes |
|---|---|---|---|
| Gauge track (linear capacity) | black 18/255 | white 26/255 | the fill the dark green (48, 209, 88) |
| Gauge ring (accessory circular) | black 216/255 | white 216/255 (the primary) | it was painted black in every scheme before |
| Date picker field (compact) | white bezel under a black 12/255 edge | (22, 22, 22) at 217/255 under a (35, 35, 35) at 219/255 edge; text (224) | 20 tall on macOS 27 (26.2: 22), the text 1 down, the stepper half a point above the field, its up chevron's feet at 5.5 and the divider at 9.5 |
| Calendar box | no fill, a 5/255 edge | white 13/255 fill, a 20/255 edge | |
| Calendar weekday names and other months' days | black 66/255 | white 146/255 | the days the primary (white 216/255) |
| Selected day | black 35/255 | (70, 70, 70) opaque | |
| Colour well frame | black 25/255 | white 25/255 | the swatch's red (255, 66, 69) |
| Grouped form | white ground (the window colour), cards black 8/255 (247), separators black 20/255 | ground (30, 30, 30), cards white 8/255 (37), separators white 10/255 (47) | the form's scroll view paints the ground unless `scrollContentBackground(.hidden)` |
| Focus ring | (0, 103, 244) at 0.498 | (26, 169, 255) at 0.498 | `NSColor.keyboardFocusIndicatorColor` in Aqua and Dark Aqua (read; the same under the high-contrast appearances) |

## Verification (2026-09-04; `dark/chrome` 2026-10-11)

Tier A: 6 fixtures exact. Tier C: `dark/system-colors` and `dark/text` 0.00 %, `dark/list`
0.02 %, `dark/controls` 0.33 %, `dark/chrome` 0.63 %; Tier B within 0.7 %. `DarkModeTests` cover
the tables, the ink swap, field and text colours, `preferredColorScheme` on and off, a host
scheme change re-resolving a mounted tree, the painted window background, a sheet's own scheme
and the contrast value.

## Not yet covered

Sidebar backgrounds, popover and menu panels in dark, the clock face in dark (inks, unmeasured),
the gallery page chrome, a look for increased contrast.
