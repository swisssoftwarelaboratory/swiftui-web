// A frame in which content only scrolled paints the scroll view's stored content again, moved,
// instead of building it again (new-website#286): the stored segment covers more than the
// viewport, shows what painting afresh would show, and is painted afresh once anything else
// changed, the content moved past what was stored, or a scroll view inside it moved.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import WebGraphics

#if !os(WASI)

@Observable private final class Rows { var first = "Row 0" }

/// A long list whose first row reads `rows`.
private struct List: View {
    let rows: Rows
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(rows.first).frame(height: 40)
                ForEach(1..<200, id: \.self) { i in Text("Row \(i)").frame(height: 40) }
            }
        }
    }
}

@MainActor
@Suite struct ScrollSegmentTests {
    private let size = CGSize(width: 200, height: 400)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func list(_ rows: Rows = Rows()) -> some View { List(rows: rows) }

    private func defines(_ list: DisplayList) -> [Int] {
        list.commands.compactMap { if case .beginSegment(let id, _) = $0 { return id }; return nil }
    }

    private func reuses(_ list: DisplayList) -> [Int] {
        list.commands.compactMap { if case .reuseSegment(let id, _, _, _) = $0 { return id }; return nil }
    }

    /// The texts a list draws inside the window, with their baselines (what lies outside it
    /// the painter skips, by the cull blocks).
    private func shownTexts(_ commands: [DisplayCommand]) -> [String] {
        commands.compactMap { command in
            guard case .drawText(let text, _, let origin, _) = command, origin.y > 0, origin.y < size.height,
                  origin.x > 0, origin.x < size.width else { return nil }
            return "\(text) at \(origin.x),\(origin.y)"
        }.sorted()
    }

    /// One frame as a canvas host paints it, keeping the sources for reading it back.
    private func frame(_ r: Runtime, _ sources: inout SegmentSources) -> DisplayList {
        r.layout(in: size)
        let list = r.renderKeepingSegments(scale: 2)
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        sources.store(list, defining: encoded.segments, reusing: encoded.reusedSegments)
        return list
    }

    @Test func aFrameThatOnlyScrolledPaintsTheStoredContentAgain() {
        let r = runtime(list())
        var sources = SegmentSources()
        let first = frame(r, &sources)
        #expect(defines(first).count == 1)
        r.scrollWheel(by: CGSize(width: 0, height: 30), at: CGPoint(x: 100, y: 200))
        let moved = frame(r, &sources)
        #expect(r.lastLayoutReason == "moved")
        #expect(defines(moved).isEmpty)
        #expect(reuses(moved) == defines(first))
        #expect(moved.commands.count < first.commands.count / 4, "\(moved.commands.count) against \(first.commands.count)")
        // What it shows is what painting afresh shows.
        #expect(shownTexts(sources.resolved(moved.commands)) == shownTexts(r.render(scale: 2).commands))
        #expect(shownTexts(sources.resolved(moved.commands)).contains { $0.hasPrefix("Row 1 ") })
    }

    @Test func aMoveOfPartOfAPixelPaintsWithinHalfAPixelOfAFreshPaint() {
        let r = runtime(list())
        var sources = SegmentSources()
        _ = frame(r, &sources)
        r.scrollWheel(by: CGSize(width: 0, height: 30.3), at: CGPoint(x: 100, y: 200))
        let moved = frame(r, &sources)
        #expect(!reuses(moved).isEmpty)
        func baselines(_ commands: [DisplayCommand]) -> [String: CGFloat] {
            var out: [String: CGFloat] = [:]
            for case .drawText(let text, _, let origin, _) in commands where origin.y > 0 && origin.y < size.height { out[text] = origin.y }
            return out
        }
        let reused = baselines(sources.resolved(moved.commands)), fresh = baselines(r.render(scale: 2).commands)
        #expect(Set(reused.keys) == Set(fresh.keys))
        for (text, y) in fresh { #expect(abs((reused[text] ?? .infinity) - y) <= 0.5, "\(text)") }
    }

    @Test func aChangedViewPaintsTheContentAfresh() {
        let rows = Rows()
        let r = runtime(list(rows))
        var sources = SegmentSources()
        _ = frame(r, &sources)
        rows.first = "Changed"
        r.scrollWheel(by: CGSize(width: 0, height: -10), at: CGPoint(x: 100, y: 200))
        let next = frame(r, &sources)
        #expect(reuses(next).isEmpty)
        #expect(defines(next).count == 1)
        #expect(shownTexts(next.commands).contains { $0.hasPrefix("Changed ") })
    }

    @Test func scrollingPastTheStoredContentPaintsItAfresh() {
        let r = runtime(list())
        var sources = SegmentSources()
        _ = frame(r, &sources)
        var reused = 0, recorded = 0
        // 40 frames of 50 pt: 2,000 pt, five viewports.
        for _ in 0..<40 {
            r.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 100, y: 200))
            let list = frame(r, &sources)
            reused += reuses(list).count
            recorded += defines(list).count
            #expect(shownTexts(sources.resolved(list.commands)) == shownTexts(r.render(scale: 2).commands))
        }
        #expect(recorded >= 2, "the content left the stored window")
        #expect(reused > recorded * 4, "\(reused) reused, \(recorded) recorded")
    }

    @Test func anInnerScrollViewMovingPaintsTheOuterContentAfresh() {
        let r = runtime(ScrollView {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) { ForEach(0..<10, id: \.self) { i in Text("Page \(i)").frame(width: 200, height: 100) } }
                }
                .frame(height: 100)
                ForEach(0..<50, id: \.self) { i in Text("Row \(i)").frame(height: 40) }
            }
        })
        var sources = SegmentSources()
        let first = frame(r, &sources)
        #expect(defines(first).count == 2)
        r.scrollWheel(by: CGSize(width: 60, height: 0), at: CGPoint(x: 100, y: 50))
        let sideways = frame(r, &sources)
        #expect(defines(sideways).count == 1, "the outer content shows the pager moved: \(defines(sideways))")
        #expect(shownTexts(sources.resolved(sideways.commands)) == shownTexts(r.render(scale: 2).commands))
        r.scrollWheel(by: CGSize(width: 0, height: 40), at: CGPoint(x: 100, y: 300))
        let down = frame(r, &sources)
        #expect(defines(down).isEmpty)
        #expect(reuses(down).count == 1)
        #expect(shownTexts(sources.resolved(down.commands)) == shownTexts(r.render(scale: 2).commands))
    }

    @Test func aRenderWithoutSegmentsPaintsEverything() {
        let r = runtime(list())
        let plain = r.render(scale: 2)
        #expect(defines(plain).isEmpty && reuses(plain).isEmpty)
        #expect(!plain.commands.contains { if case .beginCullBlock = $0 { return true }; return false })
    }

    @Test func aCullBlockSaysWhereItsCommandsEnd() {
        var list = DisplayList()
        list.append(.beginCullBlock(CGRect(x: 0, y: 0, width: 10, height: 10)))
        list.append(.fillRect(CGRect(x: 0, y: 0, width: 10, height: 10), RGBA(red: 1, green: 0, blue: 0, alpha: 1)))
        list.append(.endCullBlock)
        list.append(.save)
        let ops = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont).ops
        #expect(ops[0] == DisplayOp.beginCullBlock.rawValue)
        #expect(ops[Int(ops[5])] == DisplayOp.save.rawValue)
    }
}

#endif
