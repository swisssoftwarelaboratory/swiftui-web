# Coverage: Apple's API surface and a corpus of real apps

Two measurements that turn "runs any SwiftUI iOS app" from a goal into a ranked list. Both run in
the `Coverage` workflow (`.github/workflows/coverage.yml`), on a push that touches this folder or
by hand; the report is the run's job summary and its `report` artifact (`coverage.md`, and
`coverage.json` with every missing key and every classified error).
A snapshot of the report is kept in `Docs/coverage.md`; refresh it from a run's log or artifact.

## The surface diff

`apple-symbols.sh` extracts symbol graphs from the iOS SDK of the newest Xcode on a macOS runner,
one folder per framework (SwiftUI and SwiftUICore first, then the frameworks this package ships a
module for, then the ones apps import most). The `ours` job builds every product an app links for
wasm with `-emit-symbol-graph`. `surface.py` reduces each side to keys: a declaration's path with
its argument labels, `View.padding(_:_:)`, `Button.init(_:action:)`, `ScrollViewReader`.

What a key does and does not say:

- Overloads that differ only in their types share a key, so a missing generic variant of a
  present name is not counted. The diff measures names and labels.
- Present is not working. A key that compiles and does nothing (an `accepted` row of the support
  matrix) counts as present; the matrix and the goldens say what behaves.
- Underscored names, members synthesized from protocol extensions, and symbols unavailable or
  obsoleted on iOS are left out. Deprecated keys are counted apart, since apps still call them.
- Apple's Foundation, UIKit and AVFoundation are mostly Objective-C. Their percentages are
  context, not targets: the sweep says which parts apps use.

## The compile sweep

`corpus.json` lists 30 open-source iOS apps (chosen from the swiftui tag of
dkhamsing/open-source-ios-apps, plus Apple's two published SwiftUI samples) and two apps of
decision 0021 as controls: they build unmodified in `Apps/`, so they should build here too, and
when they do not, the sweep's heuristics are wrong, not the package.

`sweep.py` turns each clone into targets with no Xcode:

- every local Swift package (read with `swift package dump-package`) becomes one target per
  target, with its local dependencies, language mode, defines and resources;
- every other Swift file outside tests, extensions, widgets and the other platforms' folders is
  the app target, with one `@main`; its language mode is the Xcode project's `SWIFT_VERSION`;
- every third-party package the app pins (its `Package.resolved`, Xcode's or a local package's)
  is cloned at the pinned revision and built from source the same way, as a real build would:
  the targets the app's code reaches, macro targets included (built for the host against
  swift-syntax, with the libraries they use: those link SwiftUIWeb and the shadows of Apple's
  modules only on wasm, so on the host they see Apple's own Foundation and Dispatch). Binary, system-library and plugin targets, C-only targets and whatever needs
  them are left out, and an import of one of those is taken out like a missing framework;
- apps are grouped into batches whose module names do not collide (two apps pinning a package
  at the same revision share it), one generated package per batch, so SwiftUIWeb builds once a
  batch; the batches run in parallel.

To see below the first missing import, the copies (never the clones) have every `import` of a
module wasm does not have turned into `import Foundation` (Apple's frameworks all re-export it)
with the original kept as a comment, line numbers kept. This is a measurement and
nothing more: decision 0021's standard, unmodified sources, stays the bar for an app to count as
running. The report labels the errors that follow from a removed third-party package, Xcode's
generated asset symbols (`Color(.brand)`) and Core Data's generated classes, so they are not read
as SwiftUIWeb gaps.

Known limits: SwiftPM stops at a module whose dependency failed, so a modular app's errors are
those of its lowest broken modules (the report marks the rest blocked); `#if os(iOS)` is false on
wasm, so files with it compile their other branch (the report counts them; the workflow's
`ios` input reads it as true instead, as decision 0025 builds an app); build-tool
plugins (code generators such as swift-openapi-generator's), binary targets and C or
Objective-C targets are not built. A package's errors count toward the first app of its batch
that pins it, and show in the report with the package's name before the file.

## Which SDK

The sweep builds with the Objective-C runtime wasm SDK of decision 0023 (swift-objc-wasm,
macOS arm64 only, so those jobs run on macOS): it is what an app with `@objc`, `#selector` or
NSObject subclasses ships with, and the packages apps pin use all three. A dispatch with
`sdk: stock` builds with the plain wasm SDK on Linux instead. The report names the SDK under
"The corpus"; totals from the two SDKs are not comparable. A dispatch's `show` input (a pattern
of `App Module` names, like `Kingfisher`) prints every error of the modules it matches to the
sweep job's log (`run --show`), for work aimed at one package.

## Running it by hand

On Linux with the wasm SDK (`scripts/bootstrap.sh`):

```sh
python3 Tools/Coverage/sweep.py plan --corpus Tools/Coverage/corpus.json --work /tmp/corpus -o plan.json
python3 Tools/Coverage/sweep.py prepare --plan plan.json --work /tmp/corpus --batch 0 --root "$PWD" -o /tmp/sweep
python3 Tools/Coverage/sweep.py run --plan plan.json --work /tmp/corpus --pkg /tmp/sweep --batch 0 \
  --sdk swift-6.4.2-RELEASE_wasm -o results-0.json
python3 Tools/Coverage/report.py --plan plan.json --sweep results-*.json --md coverage.md --json coverage.json
```

The surface diff needs Xcode for Apple's side (`apple-symbols.sh`, then `surface.py apple`) and a
wasm build with `-emit-symbol-graph` for this package's (the `ours` job).
