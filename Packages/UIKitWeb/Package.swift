// swift-tools-version: 6.2
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

// UIKitWeb: an open-source UIKit reimplementation that runs unmodified UIKit source in the
// browser (WebAssembly + Canvas) and natively, on the WebGraphics substrate it shares with
// SwiftUIWeb (decision 0014). It works on its own: a UIKit app depends on this package alone.
//
// Module layout:
//   UIKit          thin re-export so apps can `import UIKit` unchanged; `UIApplicationDelegate.main()`
//   UIKitSubmodules  the clang module map that gives `import UIKit.UIImage` its submodules (wasm)
//   UIKitWebCore   the view and layer trees, responders and touches, controls, view controllers,
//                  the window, screen and application, and the scene the substrate hosts drive
//   UIKitFixtureKit, UIKitFixtures   the fidelity loop's fixture API and fixtures (tests only)
let package = Package(
    name: "UIKitWeb",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UIKit", targets: ["UIKit"]),
        .library(name: "UIKitWebCore", targets: ["UIKitWebCore"]),
        // The fidelity loop's pieces, for the fixture gallery (Examples/Gallery).
        .library(name: "UIKitFixtureKit", targets: ["UIKitFixtureKit"]),
        .library(name: "UIKitFixtures", targets: ["UIKitFixtures"]),
    ],
    dependencies: [
        .package(path: "../WebGraphics"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .target(
            name: "UIKit",
            dependencies: [
                "UIKitWebCore",
                .product(name: "WebFoundation", package: "WebGraphics"),
                .product(name: "WebGraphicsCanvas", package: "WebGraphics"),
                .product(name: "WebGraphicsNative", package: "WebGraphics"),
                // Apple's UIKit brings ImageIO's image sources with it (Nuke and Kingfisher read
                // `CGImageSource` with only `import UIKit`).
                .product(name: "WebImageIO", package: "WebGraphics", condition: .when(platforms: [.wasi])),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit", condition: .when(platforms: [.wasi])),
                // `import UIKit.UIImage` and the other per-header submodules resolve through this
                // clang module of the same name (wasm only: elsewhere the API is reached as `UIKit`).
                .target(name: "UIKitSubmodules", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: framework
        ),
        .target(name: "UIKitSubmodules"),
        .target(
            name: "UIKitWebCore",
            dependencies: [.product(name: "WebFoundation", package: "WebGraphics"), .product(name: "WebGraphics", package: "WebGraphics")],
            swiftSettings: framework
        ),
        // The fidelity loop (decision 0014): the UIKit fixture API, the fixtures themselves (a symlink
        // to Fixtures/UIKit at the repository root, shared with the Catalyst harness), and the tests
        // that hold UIKitWeb's layout to the goldens Apple's UIKit produced.
        .target(
            name: "UIKitFixtureKit",
            dependencies: ["UIKit"],
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .target(
            name: "UIKitFixtures",
            dependencies: ["UIKit", "UIKitFixtureKit"],
            path: "Fixtures",
            swiftSettings: [.treatAllWarnings(as: .error)]
        ),
        .testTarget(
            name: "UIKitWebTests",
            dependencies: ["UIKit", "UIKitFixtureKit", "UIKitFixtures",
                           .product(name: "WebFoundation", package: "WebGraphics"),
                           .product(name: "WebGraphicsHeadless", package: "WebGraphics"),
                           .product(name: "WebGraphicsNative", package: "WebGraphics")],
            // Testing declares a UIKit overlay that only ships on Apple platforms.
            swiftSettings: [.treatAllWarnings(as: .error), .unsafeFlags(["-disable-cross-import-overlays"], .when(platforms: [.wasi, .linux]))]
        ),
    ],
    swiftLanguageModes: [.v6]
)
