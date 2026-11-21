// The drawn phone's photo library and the photos picker's sheet (Docs/elements/PhotosPicker.md,
// new-website#667): saved photos go first, a picked photo's bytes come back as `Data`, one tap
// picks when one photo is asked for, several are marked in order and handed over by the check.
import Foundation
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PhotosPickerTests {
    /// A 2 x 2 PNG.
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 2, 0, 0, 0, 2, 8, 6, 0, 0, 0, 0x72, 0xB6, 0x0D, 0x24, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])

    private func library(_ count: Int) -> _PhotoLibrary {
        _PhotoLibrary(listed: (1...count).map { _PhotoLibrary.Photo(id: "p\($0)", url: "photos/p\($0).jpg", pixelWidth: 1000, pixelHeight: 750) })
    }

    private func sheet(_ view: _PhotosPickerSheet) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 393, height: 793))
        return runtime
    }

    private func tap(_ runtime: Runtime, _ frame: CGRect) {
        runtime.pointerDown(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.pointerUp(at: CGPoint(x: frame.midX, y: frame.midY))
        runtime.layout(in: CGSize(width: 393, height: 793))
    }

    private func photos(_ runtime: Runtime) -> [CGRect] {
        runtime.semanticsTree().filter { $0.label == "Photo" }.map(\.frame)
    }

    @Test func savedPhotosComeFirstAndKeepTheirBytes() async {
        let library = library(3)
        #expect(library.photos.map(\.id) == ["p1", "p2", "p3"])
        let first = library.save(Self.png)
        let second = library.save(Self.png)
        #expect(library.photos.map(\.id) == [second!.id, first!.id, "p1", "p2", "p3"])
        #expect(second!.url.hasPrefix("data:image/png;base64,") && second!.pixelWidth == 2)
        #expect(await library.data(for: second!) == Self.png)
        #expect(library.save(Data("not an image".utf8)) == nil)
    }

    @Test func pickedBytesComeBackAsData() {
        #expect(_PhotoLibrary.imported(Self.png, as: Data.self) == Self.png)
    }

    @Test func gridIsThreeAcrossEdgeToEdge() {
        let runtime = sheet(_PhotosPickerSheet(limit: 1, library: library(6), pick: { _ in }, cancel: {}))
        let cells = photos(runtime)
        #expect(cells.count == 6)
        // Three square cells across the full 393 pt, 5/3 pt apart, as on iOS 27.
        #expect(abs(cells[0].minX) < 0.01 && abs(cells[2].maxX - 393) < 0.01)
        #expect(abs(cells[0].width - (393 - 10.0 / 3) / 3) < 0.01 && abs(cells[0].height - cells[0].width) < 0.01)
        #expect(abs(cells[3].minY - cells[0].maxY - 5.0 / 3) < 0.01)
    }

    @Test func oneTapPicksWhenOnePhotoIsAsked() {
        var picked: [String] = []
        let runtime = sheet(_PhotosPickerSheet(limit: 1, library: library(6), pick: { picked = $0 }, cancel: {}))
        tap(runtime, photos(runtime)[4])
        #expect(picked == ["p5"])
    }

    @Test func severalAreMarkedInOrderAndTheCheckHandsThemOver() {
        var picked: [String] = []
        let runtime = sheet(_PhotosPickerSheet(limit: 2, library: library(6), pick: { picked = $0 }, cancel: {}))
        let cells = photos(runtime)
        tap(runtime, cells[3])
        tap(runtime, cells[0])
        tap(runtime, cells[5])   // past the limit: not marked
        #expect(picked.isEmpty)
        let add = runtime.semanticsTree().first { $0.label == "Add" }!
        tap(runtime, add.frame)
        #expect(picked == ["p4", "p1"])
    }

    /// The first screen of photos is asked of the page's image loader as soon as the list is
    /// read, newest first, so the grid is full while the sheet slides up.
    @Test func theFirstScreenIsPrefetched() {
        final class Recorder: _ImageLoading {
            var asked: [String] = []
            func state(for url: String) -> _ImageLoadState { asked.append(url); return .loading }
        }
        let recorder = Recorder()
        let runtime = Runtime()
        runtime.imageLoader = recorder
        library(30).prefetchFirstScreen()
        #expect(recorder.asked == (1...24).map { "photos/p\($0).jpg" })
        runtime.imageLoader = nil
    }

    @Test func theXCancels() {
        var cancelled = false
        let runtime = sheet(_PhotosPickerSheet(limit: 1, library: library(3), pick: { _ in }, cancel: { cancelled = true }))
        tap(runtime, runtime.semanticsTree().first { $0.label == "Cancel" }!.frame)
        #expect(cancelled)
    }
}
#endif
