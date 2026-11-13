# SwiftUIWeb

An open-source reimplementation of SwiftUI that runs **unmodified SwiftUI source** in the
browser (WebAssembly + Canvas) and natively on macOS (AppKit) and Linux (GTK4), with 1:1 rendering
and behaviour fidelity measured against the real SwiftUI.

**Landing page: [iamcgn.github.io/swiftui-web](https://iamcgn.github.io/swiftui-web/)**, itself
written in SwiftUI and rendered by SwiftUIWeb (source in [`Examples/Landing`](Examples/Landing)).
The current support matrix is [`Docs/support-matrix.md`](Docs/support-matrix.md); what remains,
by priority, is [`Docs/TODO.md`](Docs/TODO.md) (decision 0016).

```swift
import SwiftUI

@main struct CounterApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 12) {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
        .padding()
    }
}
```

No custom compiler: this package provides a module named `SwiftUI` with Apple's API surface,
a runtime and layout engine written from the documented semantics, and a painter backend.
Every element is verified against goldens rendered by Apple's SwiftUI on macOS.

## Status

Phases 0 to 5 of `Docs/ROADMAP.md` are done: the core views, controls, state, navigation,
presentations, animation, accessibility and the native macOS painter, each verified against
goldens rendered by Apple's SwiftUI. `Docs/support-matrix.md` lists every API with its status,
including what is still missing (the Phase 6 modifier sweep is next). `Docs/decisions/` holds the
measured results behind the design.

## Trademark and licensing notice

SwiftUI, Swift, SF Symbols, macOS, iOS and Apple are trademarks of Apple Inc., registered in the
U.S. and other countries. SwiftUIWeb is an independent open-source project. It is not affiliated
with, sponsored by, endorsed by or otherwise associated with Apple Inc.

SwiftUIWeb is a complete, from-scratch reproduction of SwiftUI's public API surface and its
observable behaviour. It contains no Apple source code, binaries, fonts, symbols or other
proprietary assets. Everything in this repository was written from Apple's public documentation
and published Swift interface files, and from behaviour measured by rendering fixtures with Apple's
own SwiftUI on macOS (the goldens in `Fixtures/Goldens`, which are this project's own output).
The module is named `SwiftUI` solely so that unmodified application source compiles against it;
this nominative use of the name describes interface compatibility and implies no endorsement.
Apple's SwiftUI framework remains subject to Apple's own license terms, and nothing in this
repository grants any rights to it. SF Symbols and the San Francisco fonts are never shipped:
`Image(systemName:)` draws Lucide (ISC) icons as stand-ins and text is set in the viewer's
system fonts.

The code in this repository is licensed under the Apache License 2.0 (`LICENSE`). Third-party
components and the projects whose ideas are borrowed with attribution are listed in `NOTICE`.

## Getting started

```sh
./scripts/bootstrap.sh          # swiftly + Swift 6.4.2 + wasm SDK + binaryen
swift test                      # native runtime + layout tests (fast)
./scripts/build-wasm.sh Examples/Counter   # wasm bundle
./scripts/serve.sh Examples/Counter        # open in a browser
```

### Linux headless tests

Use the pinned Swift 6.4.2 toolchain. The core, headless renderer, UIKitWeb and fixtures build
on Linux. Run `swift test --scratch-path .build/native`, `(cd Packages/UIKitWeb && swift test)`
and `(cd Packages/WebGraphics && swift test)` (the last needs `libcairo2-dev` for the Cairo
painter's tests; `brew install cairo` on macOS). Native Foundation geometry and attributed strings retain their identities; WebGraphics
and WebFoundation supply the missing CoreGraphics and Objective-C-facing value APIs.

`TextField(value:formatter:)` uses Linux's public `NumberFormatter` and `DateFormatter`
parsers. Other Formatter subclasses leave the bound value unchanged when edited; use a
`ParseableFormatStyle` for custom parsing.

For wasm tests, use `swift package --disable-sandbox --swift-sdk swift-6.4.2-RELEASE_wasm js
test` without a scratch-path override. JavaScriptKit's test packager requires the default
`.build` directory, so keep native tests in `.build/native` as above.

## Layout of the repository

| Path | Purpose |
|---|---|
| `Sources/SwiftUI` | Thin `import SwiftUI` module re-exporting the implementation |
| `Packages/Shadows` | `Foundation` and `Combine` modules for wasm (decision 0021): re-exports of `WebFoundation` (with libm, Observation, `UserDefaults`, `Bundle`, `FileManager`, `DispatchQueue`) and `WebCombine`, so an app file's `import Foundation` or `import Combine` means what it does on iOS. An app's `Package.swift` links them (`Examples/Launches`); never built natively and never part of this package's own builds |
| `Packages/WebGraphics` | the graphics substrate shared with UIKitWeb: geometry, paths, display list, text measuring, the hosts (decision 0014); `WebFoundation`, the Foundation every module imports, with the wasm stand-ins for `Data`, `URL`, `Calendar` and friends that keep FoundationEssentials out of the bundle (decision 0017) |
| `Packages/UIKitWeb` | `import UIKit` on the same substrate: views, layers, controls, view controllers, Auto Layout (a Cassowary solver, the visual format language), `draw(_:)` with UIBezierPath, `UIView.animate` and Core Animation, navigation and tab bar controllers, `UITableView`, `UICollectionView` with flow, compositional and list layouts, diffable data sources, alerts and sheets, text views, toolbars and search bars, date and wheel pickers, sliders, segmented controls, steppers, progress and activity indicators, page controls; `Examples/UIKitCounter` and `Examples/UIKitSettings` (a tab bar, a navigation stack, an inset grouped table with controls); goldens from real UIKit on an iPhone simulator (`scripts/gen-goldens-sim.sh uikit`, `Fixtures/UIKit`) |
| `Sources/SwiftUIWebUIKit` | `UIViewRepresentable`, `UIViewControllerRepresentable` and `UIHostingController` over UIKitWeb; `import SwiftUI` re-exports `UIKit` as on iOS (`Docs/elements/Representable.md`) |
| `Sources/SwiftUIWebCore` | API, runtime, layout engine, font resolution |
| `Sources/SwiftUIWebCanvas` | wasm Canvas2D painter, semantics overlay, text input host |
| `Sources/SwiftUIWebHeadless` | Display-list recorder for native tests |
| `Fixtures/` | Fixture views (shared with the harness) and committed goldens |
| `Harness/` | Separate macOS package that renders fixtures with **Apple's** SwiftUI |
| `Docs/` | Architecture, element workflow, decision records, support matrix |

## Documentation

- `Docs/ARCHITECTURE.md`
- `Docs/ELEMENT_WORKFLOW.md`
- `Docs/decisions/`

## License

Apache-2.0. Ideas and small pieces are borrowed with attribution from Tokamak (Apache-2.0),
ElementaryUI (Apache-2.0) and OpenSwiftUI (MIT); see `NOTICE`.

## Running the examples

```sh
. scripts/env.sh                                  # swiftly toolchain + Apple ld shim
swift test                                        # native: runtime, layout and golden-frame tests
scripts/build-wasm.sh Examples/Counter --debug    # wasm bundle for the Counter app
scripts/serve.sh Examples/Counter 8765            # then open http://localhost:8765/
scripts/tier-b.sh --filter layout/                # browser fidelity: gallery + Playwright vs goldens
(cd Tools/Host && /usr/bin/swift run swiftui-host ../../Examples/Counter)   # the bundle in a WKWebView window
(cd Examples/Counter && swift run Counter)          # the same app natively: AppKit window, CoreGraphics painter
```

An app package is `Examples/Counter`'s `Package.swift`: the `SwiftUI` and `SwiftUIWebCanvas`
products of this package. When the app's own files `import Foundation` or `import Combine`
(most do), it adds `Packages/Shadows` and its two products, as `Examples/Launches` does:

```swift
.package(name: "Shadows", path: "../../Packages/Shadows"),
// in the target's dependencies, after the SwiftUI products:
.product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
.product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
```

`Examples/Landing` is the project's landing page written in SwiftUI and rendered by SwiftUIWeb: a
sales page with live controls and the support matrix (generated from `Docs/support.json` by
`scripts/gen-progress.py`). `scripts/build-landing.sh` builds it into `Examples/Landing/dist`
and `scripts/deploy-landing.sh` publishes that to GitHub Pages (the `gh-pages` branch); the
`Landing page` workflow does the same on every push to `main` that changes the page. See
`Examples/Landing/README.md`.

`Examples/Gallery` lists every fixture in a left pane and shows the selected one as code (the
`Fixture(...)` declaration or its whole file, via `scripts/gen-fixture-sources.py`) next to its live
preview, with buttons for its behaviour steps; `index.html?fixture=text/wrapped` opens one directly
and `?filter=ios/representable` narrows the list to a prefix. `scripts/build-landing.sh` publishes
a release build of it next to the landing page at `/gallery/` (the support matrix's rows link to
the fixtures that prove them), behind the same loading screen and a 4 MB brotli gate.
`Examples/Progress` is the progress page at `/progress/`: the counts, the full support matrix
with search and filters (rows link to their gallery fixtures), the todo list from `Docs/todo.json`
(items link to their docs) and what landed recently, all from `scripts/gen-progress.py`.
`scripts/gen-goldens.sh` regenerates goldens with Apple's SwiftUI (macOS only).

`Tools/Host` is the native host of Phase 4: `swiftui-host <package-dir>` serves the package's
`index.html` and built bundle on 127.0.0.1 and opens it in a WKWebView window (macOS 14+, Apple
toolchain). `--screenshot out.png` waits for the app's first frame, writes a snapshot and quits;
`--timeout seconds` quits on its own (both for scripts and CI); `--port`, `--path`, `--width` and
`--height` are optional. `scripts/build-host-app.sh` wraps it as `dist/SwiftUIHost.app`, which
opens `.swiftuiweb` bundles (a built package directory renamed) and bundle folders by double
click or drop, one window each.

`Sources/Charts`, `MapKit`, `AVKit` and `WebKit` are the other Apple frameworks apps import
unchanged (sw-frameworks, `Docs/elements/Charts.md`, `Docs/elements/Frameworks.md`): Swift
Charts painted over the display list and measured against Apple's, a `Map` from OpenStreetMap
tiles, and `VideoPlayer` / `WebView` as host elements the browser shows with a `<video>` or
`<iframe>` over the canvas.

`Packages/LinuxHost` is the Linux window (pf-linux, `Docs/elements/Linux.md`): the display list
painted by Cairo (`WebGraphicsCairo` in `Packages/WebGraphics`) into a GTK4 `GtkDrawingArea`,
input through GTK4's event controllers; `(cd Packages/LinuxHost && swift run gtk-counter)` runs
the Counter app (needs `libgtk-4-dev`, or Homebrew's `gtk4` on macOS). `Packages/WebKitHost`'s
`gtk-host <package-dir>` is Tools/Host for Linux: the bundle served on 127.0.0.1 and shown in a
WebKitGTK view (needs `libwebkitgtk-6.0-dev`; built in CI, not yet run under a display).

`SwiftUIWebNative` (decision 0012) is the true native backend: on macOS `App.main()` opens an
AppKit window whose flipped view paints the display list with CoreGraphics and measures text
with CoreText, so an unmodified `@main` app runs with `swift run`. `SWIFTUIWEB_SCREENSHOT=out.png`
and `SWIFTUIWEB_TIMEOUT=seconds` capture the first frame from a script. Tier C
(`Tests/NativeFidelityTests`, part of `swift test` on macOS) paints every fixture natively and
compares it with Apple's golden pixels.

