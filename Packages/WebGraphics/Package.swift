// swift-tools-version: 6.2
import PackageDescription

// WebGraphics: the graphics substrate SwiftUIWeb and UIKitWeb share (decision 0014): geometry
// (CoreGraphics types on wasm), paths, the display list and its encoder, text measuring and the
// measured font tables, asset catalogs, the value types hosts exchange with a scene (semantics,
// text input, keys), and the hosts themselves over the `HostedScene` protocol. No runtime.
//
// Module layout:
//   WebFoundation        Foundation for the substrate: Foundation itself, or FoundationEssentials
//                        plus the wasm stand-ins for its heaviest value types (decision 0017)
//   WebFoundationFormats list, duration and date-components formatting; `import Foundation` only
//   WebDecimalFormats    `Decimal`'s formatting; `import Foundation` with the DecimalFormatting trait
//   WebGraphics          geometry, display list, paths, text engine protocol, HostedScene
//   WebGraphicsCanvas    wasm-only Canvas2D painter, canvas host, semantics overlay, text input
//   WebGraphicsNative    macOS CoreText engine, CoreGraphics painter, AppKit host
//   WebGraphicsHeadless  recorded text metrics and the asset manifest reader for tests
//   WebGraphicsCairo     the Cairo painter for Linux (and anywhere cairo is installed; pf-linux)
// On wasm WebFoundation re-exports a module named `ObjectiveC` (decision 0026): the Objective-C
// runtime SDK's (decision 0023, `SWIFTUIWEB_WASM_SDK=swift-<version>-RELEASE_wasm-objc`), or
// Packages/ObjectiveC's stand-ins with the stock SDK. Never both: the stand-in would shadow the
// runtime's.
let objcRuntimeSDK = (Context.environment["SWIFTUIWEB_WASM_SDK"] ?? "").hasSuffix("-objc")
let objectiveC: [Target.Dependency] = objcRuntimeSDK ? [] : [
    .product(name: "ObjectiveC", package: "ObjectiveCStandIn", condition: .when(platforms: [.wasi])),
]

let package = Package(
    name: "WebGraphics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WebFoundation", targets: ["WebFoundation"]),
        .library(name: "WebFoundationFormats", targets: ["WebFoundationFormats"]),
        .library(name: "WebDecimalFormats", targets: ["WebDecimalFormats"]),
        .library(name: "WebCombine", targets: ["WebCombine"]),
        .library(name: "WebGraphics", targets: ["WebGraphics"]),
        .library(name: "WebImageIO", targets: ["WebImageIO"]),
        .library(name: "WebGraphicsCanvas", targets: ["WebGraphicsCanvas"]),
        .library(name: "WebGraphicsNative", targets: ["WebGraphicsNative"]),
        .library(name: "WebGraphicsHeadless", targets: ["WebGraphicsHeadless"]),
        .library(name: "WebGraphicsCairo", targets: ["WebGraphicsCairo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ] + (objcRuntimeSDK ? [] : [.package(name: "ObjectiveCStandIn", path: "../ObjectiveC")]),
    targets: [
        .target(
            name: "WebFoundation",
            dependencies: objectiveC,
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Foundation's less used formatting, calendar search and XMLParser on wasm, re-exported by
        // `import Foundation` only (Packages/Shadows), so an app that never uses them does not ship them.
        .target(
            name: "WebFoundationFormats",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // `Decimal.FormatStyle` on wasm. Naming `Decimal` links Foundation's Decimal (3.4 MB), so
        // `import Foundation` re-exports this only for an app that enables Shadows' DecimalFormatting
        // trait, which Tools/Traits/traits.py asks of an app that names Decimal (decision 0024).
        .target(
            name: "WebDecimalFormats",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Combine without Combine (decision 0021): the ObservableObject family, the publishers
        // and operators SwiftUI and `import Combine` on wasm are built on.
        .target(
            name: "WebCombine",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphics",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // ImageIO's image sources on wasm (the `ImageIO` shadow re-exports it, Packages/Shadows):
        // a module of its own, so the shadow brings its names and none of WebGraphics's.
        .target(
            name: "WebImageIO",
            dependencies: ["WebFoundation", "WebGraphics"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphicsCanvas",
            dependencies: [
                "WebFoundation",
                "WebGraphics",
                .product(name: "JavaScriptKit", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Sources are `#if canImport(AppKit)`, so the target is empty elsewhere.
        .target(
            name: "WebGraphicsNative",
            dependencies: ["WebGraphics", "WebGraphicsHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "WebCombineTests",
            dependencies: ["WebCombine", "WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "WebFoundationTests",
            dependencies: ["WebFoundation"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "WebGraphicsHeadless",
            dependencies: ["WebFoundation", "WebGraphics"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Cairo through pkg-config (libcairo2-dev on Debian and Ubuntu, `brew install cairo`);
        // the painter paints the display list into an image surface or any cairo context.
        .systemLibrary(
            name: "CCairo",
            pkgConfig: "cairo",
            providers: [.apt(["libcairo2-dev"]), .brew(["cairo"])]
        ),
        .target(
            name: "WebGraphicsCairo",
            dependencies: ["WebFoundation", "WebGraphics", "CCairo"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "WebGraphicsCairoTests",
            dependencies: ["WebGraphicsCairo", "WebGraphicsHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
