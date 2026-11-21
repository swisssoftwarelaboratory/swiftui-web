# Browser runner

```sh
cd Playwright && npm install && npm run install-browsers
node run-page.mjs http://127.0.0.1:8765/index.html --pattern '\[spike05\]' --wait-for measureText --shot spike05.png
```

Serve a built bundle first (`scripts/build-wasm.sh <pkg>` then `scripts/serve.sh <pkg> 8765`).

- `tier-b.mjs`: Tier B fidelity (probe frames via the debug bridge, screenshots against the
  goldens, behaviour steps); run through `scripts/tier-b.sh [--browser chromium|webkit|firefox]`.
- `counter.mjs`: the Counter example end to end.
- `interactions.mjs <gallery url>`: the interaction suite CI runs on every push: each gallery
  probe that drives the runtime as a user does (focus, typing, keys, menus, sheets, gestures,
  hover, scrolling, selection, drag and drop, accessibility, pickers), one process each, with a
  `report.json`; `--only focus,menu` runs a few.
- `landing-controls-probe.mjs <landing url>`: the Controls demo by keyboard (issue 54): Space turns
  Notifications off, on, off and on, and Name disables and re-enables with it. CI runs it in
  `scripts/frame-budget.sh`.
- `landing-perf.mjs`, `landing-mobile.mjs`, `landing-load.mjs`: the landing page's frame phases
  under wheel scrolling (with a CPU profile), an iPhone-sized finger drag (`--webkit` runs it in
  WebKit; the drag is the host's scripted one, `__swiftuiwebDebug.drag`), and the loading screen
  across browsers. Serve the release build first (`scripts/build-wasm.sh Examples/Landing`, then
  `python3 -m http.server 8771 --directory Examples/Landing`; pick a port nothing else holds —
  a forgotten server keeps serving an old bundle).
- `device-perf.mjs <url> --udid <udid>`: the same drag on a real iPhone through `safaridriver -p
  4444` (Settings › Apps › Safari › Advanced › Remote Automation on the phone; serve the site on
  the LAN with `--bind 0.0.0.0`). Prints the frame split (`layout`, `render`, `encode`, `paint`,
  `semantics`, `overlay`), the rAF gaps and the canvas facts. Any page with `?perf` in its URL
  also shows the frame-time HUD with a "drive" button for the same drag by hand, and records
  `performance.mark` phases for Safari's timeline.
- `scroll-probe.mjs`: interactive scrolling in the gallery (`--fixture scroll/long`): a real wheel
  event, 60 in-page wheel ticks with the host's layout + paint time per frame
  (`__swiftuiwebDebug.frameMillis()`), clamping at the top, the indicator fade, and eight single real ticks from rest that must each move
  the content (each logs the browser's scroll box, which takes real vertical wheels). Measurements
  are recorded in `Docs/elements/ScrollView.md`; use a release build for numbers.
- `uikit-accessibility-probe.mjs <gallery url>`: `uikit/accessibility/basic` — the overlay's roles, states and custom-action buttons, a posted announcement in the live region, and Chromium's accessible tree (uk-accessibility).
- `foundation-probe.mjs <counter url>`: WebFoundation through the browser's `Intl` (pf-web-foundation-gaps): the page in New York with a German language, `__swiftuiwebDebug.foundation(time)` reports the tz name, the summer and winter offsets and abbreviations, the locale, the known zones, Europe/Berlin on request and a formatted date.
