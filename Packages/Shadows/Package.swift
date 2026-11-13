// swift-tools-version: 6.2
// Modules named after Apple's, for wasm only (decision 0021): `Combine` re-exports WebCombine
// and `Foundation` re-exports WebFoundation (decision 0017) with the names Apple's Foundation
// re-exports, so an app file's `import Foundation` or `import Combine` means what it does on
// iOS. An app's Package.swift adds them next to the SwiftUI product:
//     .package(name: "Shadows", path: "<SwiftUIWeb>/Packages/Shadows"),
//     .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
//     .product(name: "Combine", package: "Shadows", condition: .when(platforms: [.wasi])),
// `os` and `OSLog` (`Logger` over the console), `CoreGraphics` (the geometry and image types),
// `ImageIO` (image sources over WebImageIO, and destinations), `CoreImage` (SwiftUIWeb's WebCoreImage),
// `MobileCoreServices` (the `kUTType` names and tag functions), `SystemConfiguration` (network
// reachability over the browser's online state), `Network` (`NWPathMonitor` over the same state),
// `LocalAuthentication` (an `LAContext` that
// reports no biometry, as on a device without it), `FoundationNetworking` (the URLSession names,
// where Linux's Foundation keeps them), `FoundationXML` (XMLParser, likewise) and
// `UniformTypeIdentifiers` (`UTType`), `CommonCrypto` (the C digest and HMAC functions over
// SwiftUIWeb's CryptoKit) are here for the same reason as the rest, and so is
// `CoreData` (WebCoreData; the app's models go through SwiftUIWeb's CoreDataModel plugin). With
// `CoreGraphics` importable on wasm, SwiftUIWeb's own sources test for Apple's with
// `canImport(CoreGraphics) && !os(WASI)`.
// `Dispatch` (WebFoundation's queues, for packages that import it by name), `CoreFoundation`
// (WebFoundation's CF names, which `Security` re-exports as Apple's does),
// `Security` (the keychain item functions over a host store, which `Foundation` re-exports as
// Apple's does) and `SafariServices`
// (`SFSafariViewController` over `WKWebView`) live here for the same reason (decision 0021, the
// Ember app): a root-package module named `Security` would shadow Apple's for every macOS
// build, the testing library's included. Their sources are `#if os(WASI)` too.
// A module named `Foundation` must never be built on macOS or Linux (it would shadow the
// system module for every target compiled after it; the sources are `#if os(WASI)`), and must
// stay out of SwiftUIWeb's own test builds: SwiftPM's wasm test discovery imports XCTest, whose
// binary module wants the SDK's Foundation.
import PackageDescription

// Framework modules build the way Apple builds its own (decision 0027): in Swift 5 language
// mode, so an app built in Swift 6 mode gets from them the warnings Xcode gives it from Apple's
// (in Swift 6 mode a `@MainActor` closure parameter becomes `@Sendable`, and every app's
// `Button(action: action)` warns). Every other check Swift 6 mode makes at compile time is turned
// on, and warnings are errors, so the fork's own code stays as strictly checked as before. Not
// `DynamicActorIsolation`: in Swift 5 mode it traps in every main-actor closure called off the
// main actor, where Swift 6 mode checks none of them, and Apple's frameworks don't turn it on.
let framework: [SwiftSetting] = [.swiftLanguageMode(.v5), .treatAllWarnings(as: .error)] + [
    "ConciseMagicFile", "ForwardTrailingClosures", "StrictConcurrency", "BareSlashRegexLiterals",
    "DeprecateApplicationMain", "ImportObjcForwardDeclarations", "DisableOutwardActorInference",
    "IsolatedDefaultValues", "GlobalConcurrency", "InferSendableFromCaptures", "ImplicitOpenExistentials",
    "RegionBasedIsolation", "NonfrozenEnumExhaustivity",
].map { .enableUpcomingFeature($0) }

let package = Package(
    name: "Shadows",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Foundation", targets: ["Foundation"]),
        .library(name: "Combine", targets: ["Combine"]),
        .library(name: "Security", targets: ["Security"]),
        .library(name: "SafariServices", targets: ["SafariServices"]),
        .library(name: "os", targets: ["os"]),
        .library(name: "OSLog", targets: ["OSLog"]),
        .library(name: "CoreGraphics", targets: ["CoreGraphics"]),
        .library(name: "ImageIO", targets: ["ImageIO"]),
        .library(name: "CoreImage", targets: ["CoreImage"]),
        .library(name: "MobileCoreServices", targets: ["MobileCoreServices"]),
        .library(name: "SystemConfiguration", targets: ["SystemConfiguration"]),
        .library(name: "Network", targets: ["Network"]),
        .library(name: "LocalAuthentication", targets: ["LocalAuthentication"]),
        .library(name: "FoundationNetworking", targets: ["FoundationNetworking"]),
        .library(name: "FoundationXML", targets: ["FoundationXML"]),
        .library(name: "UniformTypeIdentifiers", targets: ["UniformTypeIdentifiers"]),
        .library(name: "CoreData", targets: ["CoreData"]),
        .library(name: "Dispatch", targets: ["Dispatch"]),
        .library(name: "CoreFoundation", targets: ["CoreFoundation"]),
        .library(name: "CommonCrypto", targets: ["CommonCrypto"]),
        .library(name: "simd", targets: ["simd"]),
        .library(name: "Metal", targets: ["Metal"]),
        .library(name: "QuartzCore", targets: ["QuartzCore"]),
        .library(name: "CoreAudio", targets: ["CoreAudio"]),
        .library(name: "HealthKit", targets: ["HealthKit"]),
        .library(name: "PhotosUI", targets: ["PhotosUI"]),
    ],
    // `CoreData` (decision 0024): `import Foundation` re-exports WebCoreData too, as Apple's
    // declares `NSPredicate`, `NSSortDescriptor` and `NSExpression`. Enable it with SwiftUIWeb's.
    // `DecimalFormatting`: `import Foundation` re-exports WebDecimalFormats (`Decimal.FormatStyle`),
    // for an app that names Decimal (Tools/Traits/traits.py).
    traits: [
        .trait(name: "CoreData", description: "`import Foundation` re-exports WebCoreData (`NSPredicate`, `NSSortDescriptor`)."),
        .trait(name: "DecimalFormatting", description: "`import Foundation` re-exports WebDecimalFormats (`Decimal.formatted`, `Decimal.FormatStyle`)."),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
        .package(name: "SwiftUIWeb", path: "../.."),
        .package(path: "../UIKitWeb"),
    ],
    targets: [
        .target(
            name: "Foundation",
            dependencies: [
                .product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebFoundationFormats", package: "WebGraphics"), "Combine", "CoreGraphics",
                "Security", .product(name: "WebGraphics", package: "WebGraphics"),
                .product(name: "WebCoreData", package: "SwiftUIWeb", condition: .when(traits: ["CoreData"])),
                .product(name: "WebDecimalFormats", package: "WebGraphics", condition: .when(traits: ["DecimalFormatting"])),
            ],
            swiftSettings: framework
        ),
        .target(
            name: "Combine",
            dependencies: [.product(name: "WebCombine", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "Dispatch",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "CoreFoundation",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "Security",
            dependencies: ["CoreFoundation", .product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "SafariServices",
            dependencies: [.product(name: "SwiftUI", package: "SwiftUIWeb"), .product(name: "WebKit", package: "SwiftUIWeb")],
            swiftSettings: framework
        ),
        .target(
            name: "os",
            // `import os.log` and the other submodules resolve through this clang module of the same
            // name (wasm only: on Apple platforms the SDK's own `os` is the one in scope).
            dependencies: [.target(name: "OSSubmodules", condition: .when(platforms: [.wasi]))],
            swiftSettings: framework
        ),
        .target(name: "OSSubmodules"),
        .target(
            name: "OSLog",
            dependencies: ["os"],
            swiftSettings: framework
        ),
        .target(
            name: "CoreGraphics",
            dependencies: [.product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "ImageIO",
            dependencies: ["CoreGraphics", .product(name: "WebImageIO", package: "WebGraphics"),
                           .product(name: "WebFoundationFormats", package: "WebGraphics"), .product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "CoreImage",
            dependencies: ["CoreGraphics", .product(name: "WebCoreImage", package: "SwiftUIWeb")],
            swiftSettings: framework
        ),
        .target(
            name: "SystemConfiguration",
            // `import SystemConfiguration.CaptiveNetwork` resolves through this clang module of the
            // same name (wasm only, as `os`'s submodules do).
            dependencies: ["CoreFoundation", .product(name: "WebFoundation", package: "WebGraphics"),
                           .target(name: "SCSubmodules", condition: .when(platforms: [.wasi]))],
            swiftSettings: framework
        ),
        .target(name: "SCSubmodules"),
        .target(
            name: "FoundationNetworking",
            dependencies: ["Foundation", .product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "FoundationXML",
            dependencies: ["Foundation", .product(name: "WebFoundationFormats", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "CommonCrypto",
            dependencies: [.product(name: "CryptoKit", package: "SwiftUIWeb")],
            swiftSettings: framework
        ),
        .target(
            name: "Network",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "LocalAuthentication",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "MobileCoreServices",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "UniformTypeIdentifiers",
            dependencies: [.product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "CoreData",
            dependencies: [.product(name: "WebCoreData", package: "SwiftUIWeb")],
            swiftSettings: framework
        ),
        // Graphics and device frameworks a page has no hardware for (no GPU device, no Health
        // store, no photo library): `simd`'s functions over the standard library's vectors,
        // `Metal` with no device, `QuartzCore` (UIKitWeb's layers, and a Metal layer with no
        // drawable), `CoreAudio` (AudioToolbox's CoreAudioTypes), `HealthKit` with no store,
        // `PhotosUI` with an inert picker. Apps take the paths they have for missing hardware.
        .target(name: "simd", swiftSettings: framework),
        .target(name: "Metal", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(
            name: "QuartzCore",
            dependencies: ["Metal", .product(name: "UIKitWebCore", package: "UIKitWeb")],
            swiftSettings: framework
        ),
        .target(name: "CoreAudio", dependencies: [.product(name: "AudioToolbox", package: "SwiftUIWeb")], swiftSettings: framework),
        .target(name: "HealthKit", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "PhotosUI", dependencies: [.product(name: "SwiftUI", package: "SwiftUIWeb")], swiftSettings: framework),
    ]
)
