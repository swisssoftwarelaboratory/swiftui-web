// swift-tools-version: 6.1
// An app with a home screen widget, written as for Xcode (an app target and a widget extension
// target, each with its own @main), for the drawn iPhone's home screen (new-website#638). The
// extension is a library target whose entry point is renamed, so both live in one page; the
// drawn iPhone starts it as iOS starts an extension.
import PackageDescription

let package = Package(
    name: "WidgetCounter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "SwiftUIWeb", path: "../.."),
        // Direct dependency so the PackageToJS command plugin (`swift package js`) is available here.
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.49.0"),
    ],
    targets: [
        .executableTarget(
            name: "WidgetCounter",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "WidgetKit", package: "SwiftUIWeb"),
                .product(name: "SwiftUIWebCanvas", package: "SwiftUIWeb"),
                "WidgetCounterWidgets",
            ],
            // wasm-ld's default 64 KB shadow stack overflows on deep view trees; give the app 4 MB.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
        .target(
            name: "WidgetCounterWidgets",
            dependencies: [
                .product(name: "SwiftUI", package: "SwiftUIWeb"),
                .product(name: "WidgetKit", package: "SwiftUIWeb"),
            ],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-entry-point-function-name", "-Xfrontend", "swiftui_web_widgets_main"])],
            // The launcher only names the entry weakly: the link keeps it.
            linkerSettings: [.unsafeFlags(["-Xlinker", "--undefined=swiftui_web_widgets_main"], .when(platforms: [.wasi]))]
        ),
    ]
)
