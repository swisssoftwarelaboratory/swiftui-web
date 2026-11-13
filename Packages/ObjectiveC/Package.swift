// swift-tools-version: 6.2
// A module named `ObjectiveC` for wasm builds without the Objective-C runtime (decision 0026).
//
// The compiler gives `NSObject` one privilege by the name of its module: a `Sendable` class may
// inherit from it only when it is declared in a module named `ObjectiveC` or `Foundation`. iOS
// code writes `final class Delegate: NSObject, Sendable` for notification and location delegates,
// so the stand-in `NSObject` (and the `Selector` its message methods take) lives here and
// WebFoundation re-exports it, as Apple's Foundation re-exports the real module.
//
// Its own package, below WebGraphics, for two reasons: WebFoundation needs it, and a module named
// `ObjectiveC` must never be built for macOS, where it would shadow Apple's for every target
// compiled after it (WebFoundation depends on it on wasm only, so a native build never builds
// it; the source is `#if os(WASI)` as well). With the Objective-C runtime SDK the real module is
// the SDK's, and WebGraphics leaves this package out (`SWIFTUIWEB_WASM_SDK`, decision 0023).
import PackageDescription

let package = Package(
    name: "ObjectiveCStandIn",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ObjectiveC", targets: ["ObjectiveC"]),
    ],
    targets: [
        .target(name: "ObjectiveC", swiftSettings: [.treatAllWarnings(as: .error)]),
    ]
)
