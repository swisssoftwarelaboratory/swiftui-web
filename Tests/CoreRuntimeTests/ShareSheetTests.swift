// The drawn iPhone's share sheet (new-website#668): on iOS a share link opens iOS 27's sheet
// growing out of its button; an async exporter's bytes are awaited; Copy reaches the clipboard,
// Save Image the drawn phone's photos, a person closes it as if sent; View More grows it into
// the full sheet; a press beside it closes it.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite(.serialized) @MainActor struct ShareSheetTests {
    /// A 2 x 2 PNG.
    nonisolated static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 2, 0, 0, 0, 2, 8, 6, 0, 0, 0, 0x72, 0xB6, 0x0D, 0x24, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    static let size = CGSize(width: 393, height: 852)

    /// An item that renders its image only when shared, as an app's medal does.
    struct Rendered: Transferable {
        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .png) { _ in
                try await Task.sleep(nanoseconds: 1_000_000)
                return ShareSheetTests.png
            }
        }
    }

    private func app<V: View>(_ view: V) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.mount(VStack { Spacer(); HStack { view; Spacer() } }.padding(16))
        runtime.layout(in: Self.size)
        return runtime
    }

    private func tap(_ runtime: Runtime, _ point: CGPoint) {
        runtime.pointerDown(at: point)
        runtime.pointerUp(at: point)
        runtime.layout(in: Self.size)
    }

    private func tap(_ runtime: Runtime, label: String) {
        guard let node = runtime.semanticsTree().first(where: { $0.label == label }) else {
            Issue.record("no \(label) in \(runtime.semanticsTree().map(\.label))")
            return
        }
        tap(runtime, CGPoint(x: node.frame.midX, y: node.frame.midY))
    }

    private func labels(_ runtime: Runtime) -> [String] { runtime.semanticsTree().map(\.label) }

    /// Lets the sheet's task ask the app for its bytes.
    private func settle(_ runtime: Runtime) async {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            await Task.yield()
            runtime.layout(in: Self.size)
        }
    }

    @Test func opensTheSheetWithPeopleAppsAndActions() async {
        var hostShared = false
        ShareAction.systemHandler = { _ in hostShared = true }
        defer { ShareAction.systemHandler = nil }
        let runtime = app(ShareLink(item: Rendered(), preview: SharePreview("10 workouts")) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        #expect(!hostShared)
        let shown = labels(runtime)
        for label in ["10 workouts", "Anna", "Marco", "Lea", "Nils", "Tide", "Ledger", "More", "Copy", "Save Image", "View More"] {
            #expect(shown.contains(label), "\(label) missing from \(shown)")
        }
        let presentation = runtime.presentations.last
        #expect(presentation?.options.share == .compact)
        // The compact card floats over the bottom of the window, inset from its sides.
        if let panel = presentation?.panel {
            #expect(panel.minX == ShareSheetMetrics.sideInset && abs(panel.maxY - (Self.size.height - ShareSheetMetrics.bottomInset)) < 0.5)
        }
        // It grows out of the pressed button.
        #expect(presentation?.pops == true && presentation?.slides == false)
    }

    @Test func copyPutsTheRenderedImageOnTheClipboard() async {
        var copied: [(Int, String)] = []
        ShareAction._copyImage = { bytes, type in copied.append((bytes.count, type)) }
        defer { ShareAction._copyImage = nil }
        let runtime = app(ShareLink(item: Rendered(), preview: SharePreview("10 workouts")) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        tap(runtime, label: "Copy")
        #expect(runtime.presentations.isEmpty)
        await settle(runtime)
        #expect(copied.count == 1 && copied.first?.0 == Self.png.count && copied.first?.1 == "image/png")
        #expect(runtime.presentations.isEmpty)
    }

    @Test func copyPutsALinkOnTheClipboardAsText() {
        var copied: [String] = []
        ShareAction._copyText = { copied.append($0) }
        defer { ShareAction._copyText = nil }
        let runtime = app(ShareLink(item: URL(string: "https://example.com/a")!) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        #expect(!labels(runtime).contains("Save Image"))
        tap(runtime, label: "Copy")
        #expect(copied == ["https://example.com/a"])
    }

    @Test func saveImagePutsItFirstInThePhotos() async {
        let before = _PhotoLibrary.shared.photos.count
        let runtime = app(ShareLink(item: Rendered(), preview: SharePreview("10 workouts")) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        tap(runtime, label: "Save Image")
        await settle(runtime)
        #expect(_PhotoLibrary.shared.photos.count == before + 1)
        #expect(_PhotoLibrary.shared.photos.first?.pixelWidth == 2)
        #expect(runtime.presentations.isEmpty)
    }

    @Test func aPersonClosesItAsIfSent() {
        let runtime = app(ShareLink(item: URL(string: "https://example.com/a")!) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")

        tap(runtime, label: "Marco")
        #expect(runtime.presentations.isEmpty)
    }

    @Test func viewMoreGrowsItIntoTheFullSheet() {
        let runtime = app(ShareLink(item: Rendered(), preview: SharePreview("10 workouts")) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        let compact = runtime.presentations.last!.panel
        tap(runtime, label: "View More")
        runtime.layout(in: Self.size)
        let sheet = runtime.presentations.last!
        #expect(sheet.options.share == .expanded)
        #expect(sheet.panel.minY < compact.minY && sheet.panel.width == Self.size.width)
        let shown = labels(runtime)
        for label in ["Print", "Save to Files", "Edit Actions", "View Less", "Close"] { #expect(shown.contains(label), "\(label)") }
        tap(runtime, label: "View Less")
        #expect(runtime.presentations.last?.options.share == .compact)
    }

    @Test func aPressBesideItClosesIt() {
        let runtime = app(ShareLink(item: URL(string: "https://example.com/a")!) { Text("Share").frame(width: 60, height: 44) })
        tap(runtime, label: "Share")
        #expect(!runtime.presentations.isEmpty)
        tap(runtime, CGPoint(x: 196, y: 80))
        #expect(runtime.presentations.isEmpty)
    }
}
#endif
