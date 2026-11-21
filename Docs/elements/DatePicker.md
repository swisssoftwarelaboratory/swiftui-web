# DatePicker

Apple docs: [DatePicker](https://developer.apple.com/documentation/swiftui/datepicker),
[DatePickerComponents](https://developer.apple.com/documentation/swiftui/datepickercomponents),
[DatePickerStyle](https://developer.apple.com/documentation/swiftui/datepickerstyle),
[datePickerStyle(_:)](https://developer.apple.com/documentation/swiftui/view/datepickerstyle(_:)),
[EnvironmentValues.timeZone](https://developer.apple.com/documentation/swiftui/environmentvalues/timezone).

## API surface

| API | Notes |
|---|---|
| `DatePicker(selection:displayedComponents:label:)`, `DatePicker(_ title, selection:displayedComponents:)` (key and string) | implemented |
| `in:` ranges (`ClosedRange`, `PartialRangeFrom`, `PartialRangeThrough`) on every form | implemented: stepping and the calendar clamp into the range; the calendar dims the days outside it (black 66/255, `datepicker/looks`) and ignores presses on them (2026-10-04) |
| `DatePickerComponents` (`.date`, `.hourAndMinute`) | implemented |
| `DatePickerStyle`: `.automatic`, `.compact`, `.stepperField` (all the field with a stepper on macOS), `.field`, `.graphical`, `.wheel` (iOS; the field on macOS); `datePickerStyle(_:)` | implemented; custom styles (`makeBody`) are not (the protocol exposes only the platform kind) |
| `.compact` on macOS | implemented (2026-10-04): a press on the field opens the graphical picker in a popover under it (approximate: popovers are not capturable) |
| `.graphical` with both components | implemented: the calendar and the clock side by side, 18 apart (`datepicker/looks` `both`: 275.5 wide) |
| `EnvironmentValues.timeZone`, `EnvironmentValues.calendar` | implemented; dates are drawn in the environment's time zone through the Gregorian calendar |
| `EnvironmentValues.locale` | implemented (2026-10-04): the field's order, padding, 24-hour clock and joiner follow the locale's language and region ("Locales" below); month and weekday names stay English; other calendars are not drawn |
| Typing | implemented: digits type into the selected component (two for the month, day, hour and minute, four for the year; the selection moves on when the component is full or cannot take another digit), Delete takes a digit back, A and P set the period |
| Dragging the clock's hands | implemented: a press beyond the hour hand's reach takes the minute hand (to the nearest minute), nearer the centre the hour hand (to the nearest hour, the period kept) |
| `labelsHidden()`, `disabled` | implemented |

## Behaviour

The field (`DateFieldNode`) draws the shown components in fixed slots: two tabular 8 pt
digits for the month, day, hour and minute, four for the year, 17 pt for AM/PM, joined by
"/" (4), ", " (8), ":" (4) and a space (4); numbers are right-aligned in their slots and the
period starts a point before its slot. The stepper styles put a 72 pt bezel (for a date) a
point in, then a 9.5 pt gap and a 12.5 × 20 mini stepper with the standalone stepper's fill,
divider and chevron colours; the field style has no stepper and a 3 pt inset each side, and is
21 tall instead of 22. The bezel is the text field's: white with a 1 pt border of black 12/255
drawn outside. A press on a component selects it (highlighted in the accent colour while the
field is focused), a press on the stepper's halves and the Up/Down keys step the selected
component (the first when none is selected), Left/Right move the selection; `_Adjustable`
for assistive technology. The calendar (`CalendarNode`) is 138.5 × 148: the month and year in
13 pt bold, previous/today/next controls, the weekday row in 10 pt bold grey and six weeks of
18.5 × 18 cells with 11 pt day numbers right-aligned 2 pt from the cell's trailing edge, the
neighbouring months' days in grey and the selected day on a 16 pt rounded highlight; pressing a
day selects it (keeping the time), the arrows page the shown month, the dot returns to today.
The clock (`ClockNode`) is a 119 pt square holding a 120 pt dial: a 6 pt bezel ring with a
light-blue-to-grey vertical gradient over a faint inner shadow, 13 pt numerals at radius
48.5, the period in 13 pt medium grey under the centre, black hands; display only.

## Measured (macOS 26.2, `datepicker/basic`, `datepicker/styles`, `datepicker/graphical`, `datepicker/clock`, `datepicker/steps`, 2026-09-04)

| Property | Value | Probe |
|---|---|---|
| Row | label (body) + 8 + control; the date control 95 × 22 ("Date" 28.5 → 131.5), date and time 160 (203 with "When"), time 80 (118 with "Time"); the field style 78 × 21 and 143 × 21 | `date`, `dateTime`, `time`, `hidden`, `field`, `fieldBoth` |
| Slots | "3" right-aligned in a 16 pt month slot starting 2 in, "/" 4, day 16, "/" 4, year 32; ", " 8; hour 16, ":" 4, minute 16, space 4, period 17 (the "PM" glyphs start a point before it) | glyph columns of `hidden`, `dateTime`, `time` |
| Bezel | the stepper styles: outer 72 wide (date), 137 (date and time), 57 (time), from x + 1; the field style: content + 6 from x; 1 pt border of black 12/255 outside a white fill with 5 pt corners | pixels |
| Stepper | 12.5 × 20 at the trailing edge, centred vertically; fill black 20/255, divider 43/255 at the middle, chevrons 137/255 (3 in, rise 3, feet 6.5 and 13.5 from the top) | pixels of `hidden` |
| Text | 13 pt, centred in the 22 pt row (baseline 16); a point down in the 21 pt field style | pixels of `hidden`, `field` |
| Disabled | text at about 30 % (approximate), the bezel unchanged | `disabled` |
| Compact | identical to the stepper field on macOS 26 | `compact`, `compactTime` |
| In a row | the 22 pt field is centred with a 24 pt button (y + 1) and a text | `row`, `rowPicker` |
| Model changes | the field re-lays out its text; a longer date keeps the width (fixed slots) | `datepicker/steps` |
| Calendar | 138.5 × 148 after "Calendar" + 8 (241 × 188 with the padding); box 137.5 wide with a faint 1 pt border and 3 pt corners; header centre 10 down, 3 in, 13 pt bold; controls 5.5 × 7 triangles and a 7 pt dot 8 apart, 6 from the trailing edge, secondary; weekdays centre 30 down in 10 pt bold at black 66/255; day rows centred 47 + 18k down, cells 18.5 wide from 4 in, numbers 11 pt right-aligned 2 from the cell's end; the selection a 16 pt highlight of black 35/255 across the cell | pixels of `graphical` |
| Clock | 119 × 119 after "Clock" + 8; dial centre (60.25, 61.5), radius 60; ring 54…60 from (209, 231, 237) at the top to (118, 118, 118) at the bottom; inner shadow (185) at the top fading out; face (252, 253, 254); numerals 13 pt at radius 48.5; "PM" 13 pt medium at 170 grey 17.5 under the centre; hands to 52 (minute) and about 36 (hour), cap radius 4.5 | pixels of `clock` |

## Locales (`datepicker/locales` on macOS 26.6, out of the golden set, 2026-10-04)

| Locale | Field |
|---|---|
| en_US (default) | 3/15/2025, 3:09 PM |
| en_GB, fr_FR (and other `d/M/y` languages) | 15/03/2025, 15:09 |
| de_DE (and da, nb, fi, cs, pl, ru, tr) | 15. 3.2025, 15:09 (the month slot right-aligned, so "15.  3.2025") |
| ja_JP (and zh, ko, hu, lt) | 2025/ 3/15 15:09 (joined by a space) |
| nl | 15-03-2025, 15:09 |

macOS 26.6 drew those fields 24 tall and 137.5 wide (the 26.2 goldens: 22 and 160), so the
fixture stays out of the golden set; `DatePickerEditingTests` hold the formats.

## iOS wheel (iOS 27, iPhone 16, new-website#665, 2026-11-21)

A 320 × 216 picker: the selected row on a 32 pt band 9 in from both sides ((115, 115, 128) at
8 %, 12 pt corners), its 23 pt labels full size and in the label colour. Outside the band the
rows are 0.873 as wide and, turned away on a cylinder 31, 58.5 and 76.5 from the centre,
0.827 / 0.636 / 0.38 as tall at 35 / 33 / 19 % black, each column's rows shrinking towards
their own pivot; a row crossing the band's edge is split between the two looks, as on iOS.
The columns follow the locale (`WheelDateNode.columns`, measured from the simulator with a
probe app): en_US "5 | 30 | AM" and "October | 13 | 2026"; en_GB and de_CH 24-hour "05 | 30";
dates day first ("13 | October | 2026", German "13. | Oktober | 2026", French months);
date and time together "Tue 13 Oct | 05 | 30" (en_US "Tue Oct 13 | 5 | 30 | AM"), today as
"Today". Hours, minutes, months and days go round; a 12-hour column turns the period over
between 11 and 12. A finger turns a column as UIPickerView does: it follows the drag, coasts
from the finger's speed with friction tuned to stop on a row (or springs onto the nearest,
critical ω 18), and the binding changes when the column comes to rest; a press on a row above
or below turns it into the band. iOS 27's golden harness draws the wheels blank, so
`ios/datepicker/wheel` stays the iOS 26 capture; the iOS 27 comparison was made against
simulator screenshots of the same pickers.

## Verification (2026-09-04; 2026-10-04 for the looks)

Tier A: all 5 fixtures exact, `datepicker/steps` steps included. Tier B, frames exact in
Chromium, WebKit and Firefox; pixels `basic` ≤ 1.29 %, `styles` ≤ 1.29 %, `graphical` ≤ 1.76 %,
`clock` ≤ 1.67 %, `steps` ≤ 0.95 % (glyph-level differences of the browsers' fallback digits,
the calendar's sub-pixel text snapping, the clock's bezel and hands). Tier C: 1.18 / 1.07 /
1.72 / 1.63 / ≤ 0.82 %. `DatePickerTests` cover the slot and stepper geometry, the displayed
components, stepping and selection by press and keys, range clamping and the period, the
calendar's grid, paging and day selection, and the clock's commands. `datepicker/looks` (the
range calendar and both graphical components): Tier A exact, Tier B 4.0 % and Tier C 4.1 %
(approximate: 26.6 greys the neighbouring months lighter); `ios/datepicker/wheel`: Tier A
exact, Tier B 3.7 % and Tier C 3.7 % (approximate). `DatePickerEditingTests` cover typing,
the compact popover, the dimmed days, the clock's hands, the wheel and the locales.

## iOS compact (iOS 27, `ios/datepicker/compact` regenerated 2026-11-21, new-website#665)

The compact picker is iOS's pills (`datePills`): the label leading and one capsule per value at
the trailing edge, in a form row or anywhere else, 34.5 tall for a date alone and 36 with a
time; texts in the locale's way ("Mar 15, 2025" and "11:09\u{202F}AM" in en_US, "13 Oct 2026"
and "05:30" in en_GB, "13.10.2026" in German). A press on the time pill opens iOS 27's frosted
panel (232 × 204, 26 pt corners) with the time wheel in it, and the pill's text turns to the
tint while it is open; a press outside closes it. Placement (re-measured with pills at ten
heights, new-website#674): a pill whose centre is in the window's upper half gets its panel
below, the panel's top 6 below the pill's centre (over the pill's lower part); lower down above,
its bottom 6 above the centre; the panel's trailing edge 41 left of the pill's, 16 kept from the
window's sides. A pill an app lays an
almost invisible picker over (Paulo's "Started 06:40") opens it the same way: a background's
or overlay's views now take presses and reach accessibility, as in SwiftUI.

## iOS calendar (iOS 27, iPhone 16 and SE, `ios/datepicker/graphical`, `ios/datepicker/panels`, new-website#674, 2026-11-21)

The date pill opens iOS 27's own calendar in a 320 × 332 panel, and `.graphical` on iOS is the
same calendar in the app's layout (`IOSCalendarNode`, `_IOSCalendar`). Measured with the probe
app `ios-in-browser/swipe-harness/picker-probe-674`:

- Header centred 34.7 below the top: the month and year in 17 pt semibold (20 in from the
  panel's side, 12 in `.graphical`), a tinted chevron 8 after it; the previous and next month
  chevrons (10 × 17.4) centred 68.3 and 22.7 from the trailing edge in the panel (59 and 15.7 in
  `.graphical`), in the label colour in the panel and in the tint in `.graphical`.
- Weekday names in 13 pt semibold grey ("MON", German "MO"), centred 77.4 below the top. The
  weeks start on Monday: iOS takes the first day from the phone's calendar, not from an app's
  locale (en_US in the simulator still starts on Monday), and the drawn iPhone is Swiss.
- Only the month's own days, in 20 pt, from 86.4 below the top. The weeks share one band (228 in
  the panel, 0.709 of the width in `.graphical`), so a five-week month has taller rows; the
  panel's columns are 10.3 in from its sides, `.graphical`'s fill its width.
- The selection is a filled circle as wide as the shorter of a cell's sides: black with white
  semibold text (white with black in the dark), the tint when it is today; today otherwise in
  the tint on the tint at 12 %. Picking a day keeps the panel open, as on iOS.
- The title opens a month and a year wheel (291 tall, 39.4 below the panel's top, 54 in
  `.graphical`), the title turning to the tint with its chevron pointing down; the wheel moves
  the shown month only.
- `.graphical` with the time adds a 38 pt "Time" row with the time pill under the calendar.
- The panels come and go as a UIKit popover (the confirmation dialog's springs, fitted to the
  panel's frames: in omega 18.8, zeta 0.80; out 17.9, 0.85): from a fifth of their size about the
  pill's centre line and the panel's edge nearest the pill, fading in, the height unrolling from
  that edge; back the same way. The panel is (32, 32, 32) in the dark.

## macOS 27 (regenerated 2026-10-11 under decision 0019)

The compact and stepper-field styles are 20 tall (26.2: 22; the `.field` style stays 21), the
text line 1 down (digits' bottoms at 15), the mini stepper half a point above the field's top
with its up chevron's feet at 5.5 and the divider at 9.5 (`dateCompactHeight`,
`dateCompactTextTop`, `dateStepperOffset`, `dateStepperDividerTop`). The dark looks are in
Docs/elements/DarkMode.md (`dark/chrome`). Tier A exact, Tier C `basic` 2.5 %.

## Not yet covered

Calendars other than the Gregorian; month names beyond English, German, French and Italian;
the calendar's sideways slide between months (it changes at once) and paging it with a swipe;
the frosted blur behind the panel; the wheels' slight sideways perspective; the exact hand widths and the
stepper's corner radius (approximate); typing on iOS.
