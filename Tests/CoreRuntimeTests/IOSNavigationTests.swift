// The iOS navigation bar over a pushed screen (Docs/elements/iOS.md): the back button that
// pops, the slide of a push and a pop, screens under their own bars, and
// navigationBarBackButtonHidden. Layout against goldens is in GoldenFrameTests (ios/nav/push*).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct IOSNavigationTests {
    private static let body = ResolvedFont(family: "system", size: 17, weight: .regular, italic: false, textStyle: .body, profile: "iOS")
    private static let headline = ResolvedFont(family: "system", size: 17, weight: .semibold, italic: false, textStyle: .headline, profile: "iOS")
    private static let largeTitle = ResolvedFont(family: "system", size: 34, weight: .bold, italic: false, textStyle: .largeTitle, weightOverridden: true, profile: "iOS")

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Root", 37.0), ("Detail", 46.0), ("Pushed", 57.5)] {
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 24.5, firstBaseline: 18, lastBaseline: 18)
        }
        entries[RecordedTextEngine.key(font: Self.headline, width: nil, string: "Detail")] = .init(width: 48, height: 24.5, firstBaseline: 18, lastBaseline: 18)
        entries[RecordedTextEngine.key(font: Self.largeTitle, width: nil, string: "Settings")] = .init(width: 131, height: 48.5, firstBaseline: 35.5, lastBaseline: 35.5)
        entries[RecordedTextEngine.key(font: Self.headline, width: nil, string: "Settings")] = .init(width: 66, height: 24.5, firstBaseline: 18, lastBaseline: 18)
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V, profile: PlatformProfile = .iOS, size: CGSize = CGSize(width: 320, height: 480)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.hostPlatformProfile = profile
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    /// The y of the first text drawn in `font`.
    private func commandY(_ commands: [String], font: String) -> Double? {
        guard let command = commands.first(where: { $0.hasPrefix("drawText(") && $0.contains(font) }),
              let range = command.range(of: " at ") else { return nil }
        let coordinates = command[range.upperBound...].split(separator: " ").first?.split(separator: ",") ?? []
        return coordinates.count == 2 ? Double(coordinates[1]) : nil
    }

    private func texts(_ r: Runtime) -> [String] {
        commands(r).compactMap { command in
            guard command.hasPrefix("drawText(\"") else { return nil }
            return String(command.dropFirst(10).prefix { $0 != "\"" })
        }
    }

    /// A settings root with a large title and a titled detail screen.
    private func stack(_ box: _IOSPathBox, detail: @escaping (Int) -> AnyView) -> some View {
        NavigationStack(path: Binding(get: { box.path }, set: { box.path = $0 })) {
            VStack(spacing: 12) {
                Text("Root")._probe("root")
                NavigationLink("Detail", value: 1)._probe("link")
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Int.self) { number in detail(number) }
        }
        ._probe("nav")
    }

    @Test func aPushedScreenGetsABackButtonThatPops() {
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in AnyView(Text("Pushed")._probe("pushed").navigationTitle("Detail")) })
        #expect(!r.semanticsTree().contains { $0.label == "Back" })
        #expect(texts(r) == ["Root", "Detail", "Settings"])
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480))
        r.advanceAnimations(elapsed: 1)
        // The detail inherits the large title: its content sits under a 116.5 pt bar, centred.
        #expect(r.probeFrames["pushed"] == CGRect(x: 131.25, y: 286, width: 57.5, height: 24.5))
        #expect(texts(r) == ["Pushed", "Detail"])
        let back = r.semanticsTree().first { $0.label == "Back" }
        #expect(back?.role == .button && back?.frame == CGRect(x: 10, y: 10, width: 44, height: 44))
        // The circle, then the accent chevron.
        #expect(commands(r).contains { $0.hasPrefix("fillRRect(10, 10, 44, 44) r=22 #F6F6F6@0.66") })
        #expect(commands(r).contains { $0.hasPrefix("strokePath(3 elements) w=3") && $0.hasSuffix("#0088FF") })
        // Pressing it pops through the binding.
        r.pointerDown(at: CGPoint(x: 32, y: 32)); r.pointerUp(at: CGPoint(x: 32, y: 32))
        #expect(box.path == [])
        r.layout(in: CGSize(width: 320, height: 480))
        r.advanceAnimations(elapsed: 1)
        #expect(texts(r) == ["Root", "Detail", "Settings"])
        #expect(!r.semanticsTree().contains { $0.label == "Back" })
    }

    @Test func aPushSlidesTheNewScreenInOverTheOldOne() {
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in AnyView(Text("Pushed").navigationTitle("Detail")) })
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(r.isAnimating)
        // 0.175 s in, on UIKit's push spring (critical, ω 18.26 /s, 83 % of the way): both
        // screens paint, the old one shifted left under a dimming and the new one arriving from
        // the right.
        r.advanceAnimations(elapsed: 0.175)
        let midway = commands(r)
        #expect(texts(r).contains("Root") && texts(r).contains("Pushed"))
        #expect(midway.contains { $0.hasPrefix("clipRect(0, 0, 320, 480)") })
        let shifts = midway.filter { $0.hasPrefix("concat(") }
        #expect(shifts.count == 2, "\(shifts)")
        let dim = midway.first { $0.hasPrefix("fillRect(0, 0, 320, 480) #000000@") } ?? ""
        let dimAlpha = Double(dim.split(separator: "@").last ?? "") ?? 0
        let progress = 1 - SpringModel.navigation.state(displacement: 1, velocity: 0, at: 0.175).displacement
        #expect(abs(dimAlpha - 0.1 * progress) < 1e-6, "\(dim)")
        // Settled: only the new screen and its bar remain.
        r.advanceAnimations(elapsed: 1)
        #expect(!r.isAnimating)
        #expect(texts(r) == ["Pushed", "Detail"])
        #expect(!commands(r).contains { $0.hasPrefix("concat(") })
        // A pop slides the old screen back out and unmounts it when the slide ends.
        box.path = []
        r.layout(in: CGSize(width: 320, height: 480))
        r.advanceAnimations(elapsed: 0.175)
        #expect(texts(r).contains("Root") && texts(r).contains("Pushed"))
        r.advanceAnimations(elapsed: 1)
        #expect(texts(r) == ["Root", "Detail", "Settings"])
    }

    @Test func screensKeepTheirOwnBars() {
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in
            AnyView(Text("Pushed")._probe("pushed").frame(maxWidth: .infinity, maxHeight: .infinity).navigationTitle("Detail").navigationBarTitleDisplayMode(.inline))
        })
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480))
        r.advanceAnimations(elapsed: 1)
        // An inline bar is 64 pt: the content centres below it (ios/nav/push-inline).
        #expect(r.probeFrames["pushed"] == CGRect(x: 131.25, y: 259.75, width: 57.5, height: 24.5))
        // The root keeps its large bar beneath.
        #expect(abs((r.probeFrames["root"]?.minY ?? 0) - (116.5 + (363.5 - 24.5 - 12 - 24.5) / 2)) < 1e-9)
    }

    @Test func hidingTheBackButtonOnAnUntitledScreenRemovesTheBar() {
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in
            AnyView(Text("Pushed")._probe("pushed").frame(maxWidth: .infinity, maxHeight: .infinity).navigationBarBackButtonHidden())
        })
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480))
        r.advanceAnimations(elapsed: 1)
        #expect(r.probeFrames["pushed"] == CGRect(x: 131.25, y: 227.75, width: 57.5, height: 24.5))
        #expect(!r.semanticsTree().contains { $0.label == "Back" })
        #expect(texts(r) == ["Pushed"])
    }

    @Test func aStackFillsItsProposalOnIOS() {
        let r = runtime(VStack(spacing: 8) { NavigationStack { Text("Root")._probe("small") }._probe("nav"); Text("Root") }, size: CGSize(width: 320, height: 300))
        #expect(r.probeFrames["nav"] == CGRect(x: 0, y: 0, width: 320, height: 267.5))
        #expect(r.probeFrames["small"] == CGRect(x: 141.5, y: 121.5, width: 37, height: 24.5))
    }

    @Test func aNewRootAfterAPopStillPaints() {
        // The gallery mounts fixtures one after another in one runtime (Tier B).
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in AnyView(Text("Pushed").navigationTitle("Detail")) })
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480)); _ = commands(r)
        r.advanceAnimations(elapsed: 1); r.layout(in: CGSize(width: 320, height: 480)); _ = commands(r)
        box.path = []
        r.layout(in: CGSize(width: 320, height: 480)); _ = commands(r)
        r.advanceAnimations(elapsed: 1); r.layout(in: CGSize(width: 320, height: 480)); _ = commands(r)
        #expect(!r.isAnimating)
        r.mount(Text("Pushed"))
        r.advanceAnimations(elapsed: 0.016)
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(texts(r) == ["Pushed"])
    }

    @Test func scrollingCollapsesTheLargeTitle() {
        // ios/nav/scroll: a scroll view of 40 pt rows under a large title.
        let r = runtime(NavigationStack {
            ScrollView {
                VStack(spacing: 0) { ForEach(0..<20, id: \.self) { _ in Text("Root").frame(maxWidth: .infinity).frame(height: 40) } }
            }
            .navigationTitle("Settings")
            ._probe("scroll")
        }, size: CGSize(width: 320, height: 400))
        #expect(r.probeFrames["scroll"] == CGRect(x: 0, y: 116.5, width: 320, height: 283.5))
        let titleY = commandY(commands(r), font: "system 34 w700")!
        // 40 pt: the bar stays large; the title slides up, fading, under the bar's glass (a
        // gradient over the inline zone), and the content shows through it.
        r.scrollWheel(by: CGSize(width: 0, height: 40), at: CGPoint(x: 160, y: 200))
        r.layout(in: CGSize(width: 320, height: 400))
        #expect(r.probeFrames["scroll"] == CGRect(x: 0, y: 116.5, width: 320, height: 283.5))
        let sliding = commands(r)
        #expect(sliding.contains { $0.hasPrefix("fillGradient") })
        #expect(sliding.contains { $0.hasPrefix("drawText(\"Settings\" system 34 w700") && $0.contains("@0.2") })
        #expect(commandY(sliding, font: "system 34 w700") == titleY - 40)
        // Past the title: the inline bar, the content frame grows and its offset is reduced by
        // the difference, so the rows on screen stay where they were.
        r.scrollWheel(by: CGSize(width: 0, height: 100), at: CGPoint(x: 160, y: 200))
        r.layout(in: CGSize(width: 320, height: 400))
        #expect(r.probeFrames["scroll"] == CGRect(x: 0, y: 64, width: 320, height: 336))
        let collapsed = commands(r)
        #expect(collapsed.contains { $0.hasPrefix("drawText(\"Settings\" system 17 w600") })
        #expect(!collapsed.contains { $0.contains("system 34") })
        // Back at the top it expands again.
        r.scrollWheel(by: CGSize(width: 0, height: -200), at: CGPoint(x: 160, y: 200))
        r.layout(in: CGSize(width: 320, height: 400))
        #expect(r.probeFrames["scroll"] == CGRect(x: 0, y: 116.5, width: 320, height: 283.5))
    }

    @Test func macOSPushesStayInstantWithoutABackButton() {
        let box = _IOSPathBox()
        let r = runtime(stack(box) { _ in AnyView(Text("Pushed").navigationTitle("Detail")) }, profile: .macOS)
        box.path = [1]
        r.layout(in: CGSize(width: 320, height: 480))
        #expect(!r.isAnimating)
        #expect(!r.semanticsTree().contains { $0.label == "Back" })
        #expect(!commands(r).contains { $0.hasPrefix("concat(") })
    }
}

@Observable private final class _IOSPathBox: @unchecked Sendable { var path: [Int] = [] }
#endif
