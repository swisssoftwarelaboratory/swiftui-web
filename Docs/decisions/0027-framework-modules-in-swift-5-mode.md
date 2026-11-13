# 0027 — Framework modules in Swift 5 mode, as Apple builds its own

Date: 2026-11-13
Status: **accepted**. Every framework module of the root package, UIKitWeb, Shadows and
`Packages/ObjectiveC` builds with the `framework` settings at the top of its manifest. WebGraphics
(WebFoundation, WebCombine, the substrate) stays in Swift 6 mode. Tests, fixtures, macros and
host tools stay in Swift 6 mode, as an app's own code is.

## The requirement

An app should get the warnings Xcode gives it, no more and no fewer: an app that treats warnings
as errors must build here as it builds in Xcode. A real iOS 26 app's package, built by Xcode 27.2
(Swift 6.4.2) for the simulator, gives 8 warnings. The same unchanged files built here gave 78.

70 of the extra ones were "converting non-Sendable function value to '@MainActor @Sendable () ->
Void' may introduce data races" (and "passing non-Sendable parameter"), nearly all at
`Button(action: action)`, where `action` is a stored `() -> Void`. Our `Button` is declared as
Apple's is (`@preconcurrency nonisolated init(action: @escaping @MainActor () -> Void, …)`). The
difference is the module's language mode: Apple builds SwiftUI, SwiftUICore, UIKit, Foundation and
Charts with `-language-mode 5` (their `.swiftinterface` files say so; SwiftUI turns on only
`InferSendableFromCaptures`). In Swift 6 mode, `GlobalActorIsolatedTypesUsability` (SE-0434) makes
every `@MainActor` function type `Sendable` by itself, so the parameter's type becomes
`@MainActor @Sendable () -> Void`, and an app passing a non-`Sendable` closure is warned. A
two-module test shows that this one feature decides it: the same declaration warns at the call
site when its module is in Swift 6 mode, and stays quiet in Swift 5 mode, also with every other
Swift 6 feature turned on. Swift 6 mode cannot turn the feature off
(`-disable-upcoming-feature` answers "already enabled as of Swift version 6").

## What was chosen

- **Swift 5 language mode with the other 14 Swift 6 features on** (`ConciseMagicFile` …
  `NonfrozenEnumExhaustivity`, `StrictConcurrency` among them, as `swiftc -print-supported-features`
  lists them for 6), and warnings as errors. The framework code is checked as strictly as before
  except for the one rule apps see; `DynamicActorIsolation` stays on, so runtime isolation checks
  are unchanged.
- **Where the fork's own code leaned on the rule**, it says so in place, without changing a
  declaration an app sees:
  - host plumbing that crosses into WebGraphics (still Swift 6) or is called from tests spells
    `@MainActor @Sendable` out: `onNeedsFrame`, the file and document panels' completions, the
    audio, speech, notification and location host hooks, a custom detent's stored resolver;
  - a main-actor closure handed on to code that runs it later on the main actor is copied into a
    `nonisolated(unsafe) let` first (paste commands, `onKeyPress`, `onReceive`, a window group's
    content, UIKit's launch, the microphone and speech sessions);
  - `EnvironmentalModifier`'s default `_makeNode` is `@MainActor`, as its requirement is, and its
    `resolve(in:)` is `nonisolated`, as Apple's is.
- **WebGraphics stays in Swift 6 mode.** WebCombine's plumbing hands `@MainActor` closures through
  `@Sendable` ones in about 40 places, and its operators' main-actor closures are our own design
  (Apple's Combine operators take plain closures), so Swift 5 mode there changes nothing an app
  sees from Apple's API. The two places it meets the Swift 5 modules (`HostedScene`'s
  `onNeedsFrame` and file panel) are spelled `@Sendable` on the Swift 5 side.

## Declarations that differed from Apple's

The same comparison found declarations whose difference from Apple's showed as a warning:

| Warning | Fix |
|---|---|
| `nonisolated(unsafe)` unnecessary for `AVCaptureSession` | not `Sendable`, as on iOS |
| result of `getRed(_:green:blue:alpha:)` unused | `@discardableResult` (an Objective-C `BOOL` method) |
| result of `await UIApplication.open(_:options:)` unused | `@discardableResult` (an imported async method) |
| missing: `AVAsset.duration` deprecated | `@available(*, deprecated, message:)` with Apple's message |
| missing: `Bundle.appStoreReceiptURL` deprecated | the same |
| missing: `@Entry` storing a closure | the macro warns as Apple's does: at a function type (through attributes, parentheses, `?`, `!`, `Optional<>`), else at a closure default |
| missing: main-actor call in `alignmentGuide`'s closure | its closure is `@Sendable` and the method `@preconcurrency`, as Apple's |

A deprecation reads "'duration' is deprecated: Use load(.duration) instead" here, where Xcode
says "was deprecated in iOS 16.0": an `@available(iOS, …)` attribute does nothing in a wasm build,
so the fork marks Apple's deprecations with `*` (as it already did). Same line, same message.

## How it was checked

The app's package built with Xcode for the simulator and here, warnings compared line by line:
the same 8 at the same lines. Every fork module and test target built with warnings as errors
switched off for one run, to list everything at once, on macOS and wasm.

## Left as it is

The build system's own notes about the app's package are not compiler warnings and Xcode has no
counterpart for them: "no rule to process file" for an `.xcassets`, `.xcstrings` and `.metal`
file on wasm32 (the fork's plugins and loaders handle those), and clang's "argument unused during
compilation: '-rdynamic'" when linking an executable.
