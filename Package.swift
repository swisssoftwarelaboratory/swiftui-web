// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

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

// SwiftUIWeb: an open-source SwiftUI reimplementation that runs unmodified SwiftUI
// source in the browser (WebAssembly + Canvas) and, later, natively.
//
// Module layout (see Docs/ARCHITECTURE.md):
//   SwiftUI              thin re-export so apps can `import SwiftUI` unchanged
//   SwiftUIWebCore       API + runtime + layout + text + display list
//   SwiftUIWebHeadless   headless renderer over the substrate's recorded text metrics
//   SwiftUIWebCanvas     the runtime in the substrate's wasm canvas host
//   SwiftUIWebNative     the runtime in the substrate's AppKit host
//   SwiftUIWebTestSupport fixture registry, golden codecs, comparators
//   SwiftUIWebUIKit      UIViewRepresentable / UIViewControllerRepresentable over UIKitWeb (decision 0014)
//   Packages/WebGraphics the graphics substrate shared with UIKitWeb (decision 0014)
//   Packages/UIKitWeb    the UIKit reimplementation SwiftUI depends on, as Apple's does on iOS

let package = Package(
    name: "SwiftUIWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .library(name: "Charts", targets: ["Charts"]),
        .library(name: "MapKit", targets: ["MapKit"]),
        .library(name: "AVFoundation", targets: ["AVFoundation"]),
        .library(name: "AVKit", targets: ["AVKit"]),
        .library(name: "Speech", targets: ["Speech"]),
        .library(name: "SwiftData", targets: ["SwiftData"]),
        // Core Data (the shadow `CoreData` module in Packages/Shadows re-exports it on wasm), and
        // the build plugin that turns an app's `.xcdatamodeld` into Swift.
        .library(name: "WebCoreData", targets: ["WebCoreData"]),
        .plugin(name: "CoreDataModel", targets: ["CoreDataModel"]),
        // The build plugin that writes an app's asset symbols (`ImageResource.logo`,
        // `ColorResource.accent`) from its `.xcassets`, as Xcode does.
        .plugin(name: "AssetSymbols", targets: ["AssetSymbols"]),
        .library(name: "UserNotifications", targets: ["UserNotifications"]),
        .library(name: "CryptoKit", targets: ["CryptoKit"]),
        .library(name: "CoreHaptics", targets: ["CoreHaptics"]),
        .library(name: "WebCoreImage", targets: ["WebCoreImage"]),
        .library(name: "WidgetKit", targets: ["WidgetKit"]),
        .library(name: "ActivityKit", targets: ["ActivityKit"]),
        .library(name: "AlarmKit", targets: ["AlarmKit"]),
        .library(name: "EventKit", targets: ["EventKit"]),
        .library(name: "AudioToolbox", targets: ["AudioToolbox"]),
        .library(name: "StoreKit", targets: ["StoreKit"]),
        .library(name: "AppIntents", targets: ["AppIntents"]),
        .library(name: "WebKit", targets: ["WebKit"]),
        .library(name: "SwiftUIWebCanvas", targets: ["SwiftUIWebCanvas"]),
        .library(name: "SwiftUIWebNative", targets: ["SwiftUIWebNative"]),
        .library(name: "SwiftUIWebHeadless", targets: ["SwiftUIWebHeadless"]),
        .library(name: "FixtureKit", targets: ["FixtureKit"]),
        .library(name: "SwiftUIWebFixtures", targets: ["SwiftUIWebFixtures"]),
    ],
    // Opt-in parts of the `SwiftUI` module (decision 0024). An app enables one on its dependency,
    // `.package(name: "SwiftUIWeb", path: ..., traits: ["CoreData"])`; Tools/Traits/traits.py
    // says which an app needs. Off by default, so Counter's bundle stays as it is (decision 0006).
    traits: [
        .trait(name: "CoreData", description: "`import SwiftUI` re-exports WebCoreData on wasm (`@FetchRequest`, `FetchedResults`), as Apple's SwiftUI declares them."),
        .trait(name: "FoundationFormats", description: "`import SwiftUI` re-exports WebFoundationFormats on wasm (`DateComponentsFormatter`, `ByteCountFormatter`, list and duration formatting), as Apple's SwiftUI re-exports Foundation."),
        .trait(name: "DecimalFormatting", description: "Charts plots `Decimal` values on wasm (`.value(\"Price\", price)` with a `Decimal` price)."),
    ],
    dependencies: [
        // The graphics substrate shared with UIKitWeb (decision 0014), and UIKitWeb itself: the
        // `SwiftUI` module re-exports `UIKit` the way Apple's does on iOS.
        .package(path: "Packages/WebGraphics"),
        .package(path: "Packages/UIKitWeb"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
        // Only for the `#Preview` macro plugin (expands to nothing); SwiftPM uses prebuilt libraries.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "601.0.1"),
    ],
    targets: [
        .target(
            name: "SwiftUI",
            dependencies: [
                "SwiftUIWebCore",
                "SwiftUIWebMacros",
                "SwiftUIWebUIKit",
                .product(name: "UIKit", package: "UIKitWeb"),
                .product(name: "WebFoundation", package: "WebGraphics"),
                .product(name: "WebCombine", package: "WebGraphics"),
                .target(name: "SwiftUIWebCanvas", condition: .when(platforms: [.wasi])),
                .target(name: "SwiftUIWebNative", condition: .when(platforms: [.macOS])),
                .target(name: "WebCoreData", condition: .when(platforms: [.wasi], traits: ["CoreData"])),
                .product(name: "WebFoundationFormats", package: "WebGraphics", condition: .when(platforms: [.wasi], traits: ["FoundationFormats"])),
            ],
            swiftSettings: framework
        ),
        // Swift Charts over the display list (sw-frameworks, decision 0018): `import Charts`.
        .target(
            name: "Charts",
            dependencies: ["SwiftUI"],
            swiftSettings: framework
        ),
        // Map, VideoPlayer and WebView (sw-frameworks): painted tiles, host elements over the canvas.
        .target(name: "CoreLocationHost", swiftSettings: framework),
        .target(name: "CoreLocation", dependencies: ["CoreLocationHost", .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "MapKit", dependencies: ["SwiftUI", "CoreLocation"], swiftSettings: framework),
        // The player and capture layers subclass UIKitWeb's CALayer; AudioToolbox carries the
        // CoreAudioTypes a render block names, which Apple's AVFoundation re-exports.
        .target(name: "AVFoundation", dependencies: ["AudioToolbox", .product(name: "UIKitWebCore", package: "UIKitWeb"), .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "AVKit", dependencies: ["SwiftUI", "AVFoundation"], swiftSettings: framework),
        .target(name: "SwiftData", dependencies: ["SwiftUIWebCore", "SwiftDataMacros", .product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebCombine", package: "WebGraphics")], swiftSettings: framework),
        // The `@Model`, `#Predicate` and `@ModelActor` macros (host-compiled, as `#Preview`'s plugin).
        .macro(
            name: "SwiftDataMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // Core Data over SwiftData's host storage: NSManagedObject, contexts, stores, NSPredicate,
        // NSSortDescriptor, `@FetchRequest`. Its own module, so nothing here reaches the bundles
        // of apps that do not import CoreData (the size gate, decision 0006).
        .target(
            name: "WebCoreData",
            dependencies: ["SwiftUIWebCore", "SwiftData", .product(name: "WebFoundation", package: "WebGraphics"),
                           .product(name: "WebFoundationFormats", package: "WebGraphics"), .product(name: "WebCombine", package: "WebGraphics")],
            swiftSettings: framework
        ),
        // The CoreDataModel plugin's tool: `.xcdatamodeld` to Swift (host only).
        .executableTarget(name: "CoreDataModelGen", swiftSettings: [.treatAllWarnings(as: .error)]),
        .plugin(name: "CoreDataModel", capability: .buildTool(), dependencies: ["CoreDataModelGen"]),
        // The AssetSymbols plugin's tool: `.xcassets` to `ImageResource` and `ColorResource` symbols (host only).
        .executableTarget(name: "AssetSymbolsGen", swiftSettings: [.treatAllWarnings(as: .error)]),
        .plugin(name: "AssetSymbols", capability: .buildTool(), dependencies: ["AssetSymbolsGen"]),
        .target(name: "UserNotifications", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        // Hashes, HMAC and symmetric keys; haptics on hardware without an engine; the app's calls
        // to its widgets (none on the web). Pure Swift values over WebFoundation.
        .target(name: "CryptoKit", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "CoreHaptics", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        // Core Image's images, filters and contexts as display-list recordings (filters the
        // painters draw), with UIKit's CIColor and UIImage additions. Apps import it as
        // `CoreImage`, the Shadows module that re-exports it on wasm (a root module of that
        // name would shadow Apple's, which AppKit imports, in every macOS build).
        .target(
            name: "WebCoreImage",
            dependencies: [.product(name: "UIKit", package: "UIKitWeb"), .product(name: "WebGraphics", package: "WebGraphics"),
                           .product(name: "WebFoundation", package: "WebGraphics"),
                           .product(name: "WebImageIO", package: "WebGraphics", condition: .when(platforms: [.wasi]))],
            swiftSettings: framework
        ),
        .target(name: "WidgetKit", dependencies: ["SwiftUI", "ActivityKit", .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        // Live Activities and alarms: neither is enabled on the web (no Lock Screen); the types
        // are values, so an app's code for them compiles and its "off" path runs. iOS-only
        // frameworks, so these root modules shadow nothing in a macOS build.
        .target(name: "ActivityKit", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "AlarmKit", dependencies: ["ActivityKit", "AppIntents", "SwiftUI"], swiftSettings: framework),
        .target(name: "EventKit", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "AudioToolbox", dependencies: [.product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "Speech", dependencies: ["AVFoundation", .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        .target(name: "WebKit", dependencies: ["SwiftUI"], swiftSettings: framework),
        // In-app purchases with an empty store (no products load on the web) and its SwiftUI views.
        .target(
            name: "StoreKit",
            dependencies: ["SwiftUI", .product(name: "WebFoundation", package: "WebGraphics"),
                           .product(name: "WebDecimalFormats", package: "WebGraphics", condition: .when(platforms: [.wasi]))],
            swiftSettings: framework
        ),
        // Intents, entities and App Shortcuts. Nothing runs them from Siri or Shortcuts on the web;
        // Button(intent:) and Toggle(isOn:intent:) run them.
        .target(name: "AppIntents", dependencies: ["SwiftUI", .product(name: "WebFoundation", package: "WebGraphics")], swiftSettings: framework),
        // The representables (decision 0014, Phase 2): UIKit views hosted as SwiftUI leaves.
        .target(
            name: "SwiftUIWebUIKit",
            dependencies: ["SwiftUIWebCore", .product(name: "UIKitWebCore", package: "UIKitWeb"), .product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: framework
        ),
        // Compiler plugin: `#Preview` expands to nothing, so preview blocks in app sources compile.
        .macro(
            name: "SwiftUIWebMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebCore",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebCombine", package: "WebGraphics"), .product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "SwiftUIWebHeadless",
            dependencies: ["SwiftUIWebCore", .product(name: "WebGraphicsHeadless", package: "WebGraphics")],
            swiftSettings: framework
        ),
        .target(
            name: "SwiftUIWebTestSupport",
            dependencies: ["SwiftUIWebCore", "SwiftUIWebHeadless"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The native macOS host: the runtime in the substrate's AppKit host (decisions 0012, 0014).
        // Its sources are `#if canImport(AppKit)`, so the target is empty elsewhere.
        .target(
            name: "SwiftUIWebNative",
            dependencies: ["SwiftUIWebCore", .product(name: "WebGraphicsNative", package: "WebGraphics")],
            swiftSettings: framework
        ),
        // The browser host: the runtime in the substrate's canvas host (decisions 0007, 0014).
        .target(
            name: "SwiftUIWebCanvas",
            dependencies: [
                "SwiftUIWebCore",
                // The audio, speech, notification and data stand-ins' host hooks (decisions
                // 0021, 0022): Web Audio, the microphone, the on-device recogniser fed the app's
                // buffers, the Notification API, geolocation, localStorage for SwiftData's stores.
                "AVFoundation", "Speech", "UserNotifications", "CoreLocationHost", "SwiftData",
                // The on-screen keyboard's frame from the visual viewport into UIKitScene (KeyboardHost.swift).
                .product(name: "UIKitWebCore", package: "UIKitWeb"),
                .product(name: "WebGraphicsCanvas", package: "WebGraphics"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: framework
        ),
        // FixtureKit is the SwiftUIWeb twin of Harness/Sources/FixtureKit; SwiftUIWebFixtures compiles
        // the fixture sources shared with Harness/ (which builds them against Apple's SwiftUI).
        .target(
            name: "FixtureKit",
            dependencies: ["SwiftUI"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "SwiftUIWebFixtures",
            dependencies: ["SwiftUI", "FixtureKit", "Charts", "MapKit", "AVKit", "WebKit"],
            path: "Fixtures/Sources",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        // The Linux and wasm Testing modules declare a `_Testing_UIKit` cross-import overlay that
        // does not exist on those platforms; with `import SwiftUI` re-exporting UIKitWeb's `UIKit`, the tests would try
        // to load it. Disable overlay lookup for those test builds.
        .testTarget(
            name: "CoreRuntimeTests",
            dependencies: ["SwiftUI", "Charts", "MapKit", "CoreLocation", "AVKit", "Speech", "SwiftData", "UserNotifications", "WebKit", "StoreKit", "AppIntents", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures", .product(name: "WebFoundation", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        // Core Data against a model the plugin generates (Tests/CoreDataTests/Library.xcdatamodeld).
        .testTarget(
            name: "CoreDataTests",
            dependencies: ["SwiftUI", "WebCoreData", "SwiftData", "SwiftUIWebTestSupport", .product(name: "WebFoundation", package: "WebGraphics")],
            exclude: ["Library.xcdatamodeld"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))],
            plugins: ["CoreDataModel"]
        ),
        // The symbols the AssetSymbols plugin writes for Tests/AssetSymbolsTests/Media.xcassets, with
        // the framework extensions its `AssetSymbolExtensions` file asks for.
        .testTarget(
            name: "AssetSymbolsTests",
            dependencies: ["SwiftUI", .product(name: "WebFoundation", package: "WebGraphics")],
            exclude: ["Media.xcassets", "AssetSymbolExtensions"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))],
            plugins: ["AssetSymbols"]
        ),
        // The small frameworks against known answers (FIPS 180, RFC 1321, RFC 4231 vectors).
        .testTarget(
            name: "FrameworkTests",
            dependencies: ["CryptoKit", "CoreHaptics", "WebCoreImage", "WidgetKit", "EventKit", "AudioToolbox", .product(name: "WebGraphics", package: "WebGraphics"), .product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebFoundationFormats", package: "WebGraphics"), .product(name: "WebDecimalFormats", package: "WebGraphics")],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        .testTarget(
            name: "LayoutFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebHeadless", "SwiftUIWebTestSupport", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        // Tier C: the native painter against Apple's goldens (macOS only; empty elsewhere).
        .testTarget(
            name: "NativeFidelityTests",
            dependencies: ["SwiftUI", "SwiftUIWebNative", "SwiftUIWebHeadless", "FixtureKit", "SwiftUIWebFixtures"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
        .testTarget(
            name: "BrowserTests",
            dependencies: ["SwiftUI", "SwiftUIWebCanvas", "SwiftUIWebTestSupport"],
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
