# 0026 — Swift 6.4.2, and a module named ObjectiveC without the runtime

Date: 2026-11-13
Status: **accepted**. `.swift-version` is 6.4.2; the stock wasm SDK is
`swift-6.4.2-RELEASE_wasm` (sha256 `83baca83553f8c443cda7b84800912e6e709c3acd2e7ebf277794ca5836c0da5`,
93 MB). The Objective-C runtime SDK of decision 0023 stays on Swift 6.3.3.

## The requirement

A real iOS 26 app, built by Xcode in Swift 6 mode, needed two settings in its wasm wrapper that
Xcode never sets:

1. **Swift 5 language mode**, because of `final class Delegate: NSObject, Sendable`. The compiler
   lets a `Sendable` class inherit from `NSObject` only when that class is declared in a module
   named `ObjectiveC` or `Foundation` (`ClassDecl::isNSObject`). WebFoundation's stand-in is
   neither, so Swift 6 mode rejects the line ("class 'Delegate' cannot conform to the 'Sendable'
   protocol"). Tested both ways: the same code compiles when the stand-in lives in a module named
   `ObjectiveC` and fails under any other name.
2. **`-enable-constraint-solver-performance-hacks`**, because Swift 6.3.3 gives up on
   `meshes.flatMap { c in [Float((c >> 16) & 0xFF) / 255, …] }` as too complex even with only the
   standard library imported. Xcode's Swift 6.4.2 checks it, and so does the 6.4.2 wasm toolchain.

## What was chosen

- **Swift 6.4.2** for the whole package. It accepts the expression with no flag, and the package
  needed only two changes for it: `PersistentModel` refines `SendableMetatype`, as Apple's does
  (6.4 rejects `@Query var query: [T]` over a generic model otherwise: "conformance of 'T' to
  protocol 'PersistentModel' may be isolated"), and two `nonisolated(unsafe)` copies of
  `[any PersistentModel.Type]` became unnecessary.
- **`Packages/ObjectiveC`**: a package whose one module is named `ObjectiveC` and holds the
  stand-ins `NSObject`, `NSObjectProtocol` and `Selector` (moved out of WebFoundation, unchanged).
  WebFoundation depends on it on wasm only and re-exports it, as Apple's Foundation re-exports the
  real module, so `import Foundation` still brings `NSObject`. It is its own package below
  WebGraphics because a module named `ObjectiveC` must never be built for macOS, where it would
  shadow Apple's for every target after it; a native build never reaches it.
- **`#if _runtime(_ObjC)`** replaces `#if canImport(ObjectiveC)` in the package's own sources
  (about 50 places). `canImport` is now true on wasm with the stock SDK too, so it no longer
  says "the Objective-C runtime is here"; `_runtime(_ObjC)` does, on every platform: true on
  Apple's, true with the runtime SDK (interop is on), false on Linux and with the stock wasm SDK.
  Every branch keeps the meaning it had.
- **The runtime SDK** (decision 0023) is built for Swift 6.3.3 only, and a Swift SDK works with
  exactly one compiler. `scripts/build-wasm.sh` builds with the toolchain the SDK's name gives
  (`swiftly run … +6.3.3`), and WebGraphics leaves `Packages/ObjectiveC` out when
  `SWIFTUIWEB_WASM_SDK` names a `-objc` SDK, whose real module the stand-in would shadow. CI
  installs 6.3.3 beside 6.4.2 for those steps. A 6.4.2 build of the runtime SDK is not made here:
  it means rebuilding swift-objc-wasm's patched compilers, and nothing the apps need waits on it.

Why not the runtime SDK for everything: it is 659 MB, exists for 6.3.3 only (so it cannot have
the 6.4.2 type checker the second setting needs), and an app that writes no `@objc` gains nothing
from it. Its bundle cost was therefore not measured.

## Swift Build

SwiftPM 6.4 builds with Swift Build (Xcode's engine) by default; the native build system is
deprecated. Products now sit in `.build/<scratch>/debug` and `release` (links into `out/Products`)
instead of `wasm32-unknown-wasip1/<config>`, and a target's processed resources are
`<Package>_<Target>.bundle` instead of `.resources`. `build-wasm.sh` reads both layouts, and the
workflows' size steps read the new one.

## Stale incremental builds

Twice an incremental build after a change in UIKitWeb linked code compiled against the old
UIKitWeb with the new one: the page failed with "function signature mismatch", and a native test
crashed, until a clean build. Small reproductions (methods, stored properties and protocol
requirements added across two and three modules, on 6.3.3) were rebuilt correctly every time, so
the cause was not found. `build-wasm.sh` now notices instead: when any file under `Sources`,
`Packages` or `Plugins` is newer than the bundle's last build (taken when that build started, so
an edit made during a build counts), it removes the bundle's wasm outputs before building. The
host's macros and plugins and the fetched packages are kept; an edit to the app alone stays
incremental. Native `swift test` is not covered.

## Evidence

A real iOS 26 app, unmodified, builds for wasm in Swift 6 mode with no Swift setting in its
wrapper (what remains there is the wasm stack size every app's wrapper sets, and the medal
artwork folder it leaves out). A Chromium walk of its 105 screens on the 6.4.2 build loads every
one without a page error; against a clean 6.3.3 build of the same commit the screens are
pixel-identical except for running animations and timers.

On 6.4.2 (2026-11-13, macOS 26): the root suite passes but for `dateStylesAndFormats`, which
expects "1,234" on a Mac whose region writes "1'234" (the same on 6.3.3); UIKitWeb's 213 tests
pass; WebGraphics' results equal 6.3.3's (`symbolSkeletonsMatchFoundation` and the Amete Alem
calendar differ from this Mac's Foundation on both). `TextEncodingTests` compares ASCII decoding
only where Foundation rejects bytes above 0x7F: 6.4.2's `swiftpm-testing-helper`, the process
swift-testing runs in, is built with the macOS 14 SDK, and Foundation keeps decoding them as
Latin 1 for such programs (a two-line program shows it either way by its SDK stamp). The wasm
suites (`js test`) pass, 401 tests. Counter builds with
`SWIFTUIWEB_WASM_SDK=swift-6.3.3-RELEASE_wasm` through the toolchain switch.
