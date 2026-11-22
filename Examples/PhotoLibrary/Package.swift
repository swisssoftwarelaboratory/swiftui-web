// swift-tools-version: 6.1
// A small app that asks for the photo library the way apps do (new-website#708):
// `PHPhotoLibrary.requestAuthorization(for:)` for full access and for adding only, and
// `presentLimitedLibraryPicker` once limited. Its texts come from `PhotoLibrary.xcodeproj`. Run it in the drawn
// iPhone: `scripts/build-wasm.sh Examples/PhotoLibrary --debug`, serve the folder and open
// `index.html?platform=ios&device=iphone`.
import PackageDescription

let package = Package(
    name: "PhotoLibrary",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../.."),
        .package(name: "Shadows", path: "../../Packages/Shadows"),
        .package(name: "UIKitWeb", path: "../../Packages/UIKitWeb"),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "PhotoLibrary",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
                .product(name: "UIKit", package: "UIKitWeb", condition: .when(platforms: [.wasi])),
                .product(name: "Foundation", package: "Shadows", condition: .when(platforms: [.wasi])),
                .product(name: "Photos", package: "Shadows", condition: .when(platforms: [.wasi])),
            ],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
    ]
)
