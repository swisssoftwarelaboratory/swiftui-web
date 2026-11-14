// sw-ios-sheet-nav (decision 0021, Scrumdinger's add screen): a NavigationStack inside an iOS
// sheet has a bar of its own — inline and untitled for `navigationTitle("")` — carrying the
// stack's toolbar items as pills that dismiss when tapped; the presenting stack keeps its own
// title and items; on iOS toolbar items never go to a window bar. Pixels: ios/sheet/nav,
// ios/sheet/nav-titled (NativePixelTests).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSSheetNavigationTests {
    @Observable final class Model {
        var sheet = false
        var added = 0
        var dismissed = 0
    }

    /// Widths proportional to the point size (the pixel fixtures measure the real text).
    final class ProportionalTextEngine: TextEngine {
        func layout(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
            let string = runs.map(\.string).joined()
            let size = runs.first?.font.size ?? 17
            let w = CGFloat(string.count) * size * 0.55
            let height = size * 1.3, baseline = size
            let line = TextLayout.Line(range: string.startIndex..<string.endIndex, width: w, baseline: baseline, fragments: [TextLayout.Fragment(text: string, run: 0, x: 0, width: w)])
            return TextLayout(size: CGSize(width: w, height: height), firstBaseline: baseline, lastBaseline: baseline, lines: [line])
        }
        func metrics(for font: ResolvedFont) -> FontMetrics { FontMetrics(lineHeight: font.size * 1.3, spacingBelow: 0, spacingAbove: 0, textToText: 0) }
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.paintsWindowChrome = true   // the browser host paints chrome; iOS must not get a window bar
        runtime.textEngine = ProportionalTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 375, height: 667))
        return runtime
    }

    /// Lays out and lets a sheet finish sliding in or out (iOS sheets slide on the navigation spring).
    private func relayout(_ r: Runtime) {
        r.layout(in: CGSize(width: 375, height: 667))
        r.advanceAnimations(elapsed: 1)
        r.layout(in: CGSize(width: 375, height: 667))
    }
    private func texts(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).compactMap { c in c.hasPrefix("drawText(\"") ? String(c.dropFirst(10).prefix { $0 != "\"" }) : nil }
    }
    private func press(_ r: Runtime, _ p: CGPoint) { r.pointerDown(at: p); r.pointerUp(at: p) }

    struct AddScreen: View {
        let model: Model
        let title: String
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            NavigationStack {
                Form { Text("Title")._probe("field") }
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Dismiss") { model.dismissed += 1; dismiss() }._probe("dismiss") }
                        ToolbarItem(placement: .confirmationAction) { Button("Add") { model.added += 1; dismiss() }._probe("add") }
                    }
            }
        }
    }

    struct Presenter: View {
        let model: Model
        var title = ""
        var body: some View {
            NavigationStack {
                List { Text("Row")._probe("row") }
                    .navigationTitle("Scrums")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Show sheet") { model.sheet = true }._probe("show") } }
            }
            .sheet(isPresented: Binding(get: { model.sheet }, set: { model.sheet = $0 })) { AddScreen(model: model, title: title) }
        }
    }

    @Test func itemsSitInTheNavigationBarNotAWindowBar() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        // No window toolbar on iOS: the stack starts at the window's top and its large title
        // bar holds the pill (ios/sheet/nav: 36 pt, 14 down, 20 in from the trailing edge).
        #expect(r.toolbarFrame == nil)
        let show = r.probeFrames["show"]!
        #expect(show.minY == 14 && show.height == 36 && abs(show.maxX - 355) < 0.01, "\(show)")
        #expect(r.probeFrames["row"]!.minY > 116.5)
        #expect(texts(r).contains("Scrums") && texts(r).contains("Show sheet"))
    }

    @Test func aStackInASheetHasItsOwnUntitledBar() {
        let model = Model()
        let r = runtime(Presenter(model: model))
        let show = r.probeFrames["show"]!
        press(r, CGPoint(x: show.midX, y: show.midY))
        relayout(r)
        #expect(model.sheet && r.hasPresentations)
        let painted = texts(r)
        // The sheet's bar: Dismiss leads, Add trails, no title drawn; the presenting bar keeps
        // "Scrums" (a sheet's title never replaces it) and its own item.
        #expect(painted.contains("Dismiss") && painted.contains("Add") && painted.contains("Scrums") && painted.contains("Show sheet"))
        #expect(r.navigationTitle == "Scrums")
        let dismiss = r.probeFrames["dismiss"]!, add = r.probeFrames["add"]!, field = r.probeFrames["field"]!
        // The card starts 21 down (iOS 27); pills 36 pt tall, 14 + 5.5 below the card's top
        // (ios/sheet/nav), 20 in from either edge.
        #expect(abs(dismiss.minY - (21 + 14 + 5.5)) < 0.01 && dismiss.height == 36 && abs(dismiss.minX - 20) < 0.01, "\(dismiss)")
        #expect(abs(add.maxX - 355) < 0.01 && abs(add.minY - dismiss.minY) < 0.01, "\(add)")
        // The form lays out under an inline bar (64 + 5.5) with its 35 pt top inset: the first
        // row at 104.5 from the card's top (the golden), its text 17 lower.
        #expect(abs(field.minY - (21 + 104.5 + 17)) < 0.1, "\(field)")
        // Tapping Add runs the action and dismisses through the sheet's environment.
        press(r, CGPoint(x: add.midX, y: add.midY))
        #expect(model.added == 1 && !model.sheet)
        relayout(r)
        #expect(!r.hasPresentations && !texts(r).contains("Add"))
        // Again, with Dismiss.
        model.sheet = true
        relayout(r)
        let dismiss2 = r.probeFrames["dismiss"]!
        press(r, CGPoint(x: dismiss2.midX, y: dismiss2.midY))
        #expect(model.dismissed == 1 && !model.sheet)
    }

    @Test func aTitledSheetStackShowsItsLargeTitleUnderThePills() {
        let model = Model()
        let r = runtime(Presenter(model: model, title: "New Scrum"))
        model.sheet = true
        relayout(r)
        let painted = texts(r)
        #expect(painted.contains("New Scrum") && painted.contains("Scrums"))
        #expect(r.navigationTitle == "Scrums")
        // Under the large title (116.5 + 5.5) the form keeps no top inset: the first row at
        // 122 from the card's top (the golden).
        let field = r.probeFrames["field"]!
        #expect(abs(field.minY - (21 + 122 + 17)) < 0.1, "\(field)")
    }
}
#endif
