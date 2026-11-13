// Phase 1 step 5: layout engine unit tests (independent of goldens).
import Testing
import SwiftUI

/// A fixed-size child.
private struct Box: View, Equatable {
    var w: CGFloat
    var h: CGFloat
    var body: some View { Color.red.frame(width: w, height: h) }
}

private struct WidthKey: LayoutValueKey { static let defaultValue = 0.0 }

/// A custom layout: places children on a diagonal, reports the `WidthKey` sum as its width.
private struct Diagonal: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let extra = subviews.reduce(0.0) { $0 + $1[WidthKey.self] }
        return CGSize(width: sizes.reduce(0) { $0 + $1.width } + extra, height: sizes.reduce(0) { $0 + $1.height })
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var point = bounds.origin
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(at: point, proposal: .unspecified)
            point.x += size.width
            point.y += size.height
        }
    }
}

@Suite @MainActor struct LayoutTests {
    private func frames(_ runtime: Runtime) -> [String: CGRect] { runtime.probeFrames }

    @Test func proposedViewSizeBasics() {
        #expect(ProposedViewSize.unspecified.replacingUnspecifiedDimensions() == CGSize(width: 10, height: 10))
        #expect(ProposedViewSize(width: 5, height: nil).replacingUnspecifiedDimensions(by: CGSize(width: 1, height: 2)) == CGSize(width: 5, height: 2))
        #expect(ProposedViewSize(CGSize(width: 3, height: 4)) == ProposedViewSize(width: 3, height: 4))
    }

    @Test func rootCentersContent() {
        let runtime = Runtime()
        runtime.mount(Box(w: 50, h: 30)._probe("box"))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(frames(runtime)["box"] == CGRect(x: 75, y: 35, width: 50, height: 30))
    }

    @Test func hstackLeastFlexibleFirst() {
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) {
            Color.red._probe("a")
            Box(w: 50, h: 10)._probe("b")
            Color.green._probe("c")
        })
        runtime.layout(in: CGSize(width: 300, height: 100))
        let f = frames(runtime)
        #expect(f["a"] == CGRect(x: 0, y: 0, width: 125, height: 100))
        #expect(f["b"] == CGRect(x: 125, y: 45, width: 50, height: 10))
        #expect(f["c"] == CGRect(x: 175, y: 0, width: 125, height: 100))
    }

    @Test func hstackSpacingAndAlignment() {
        let runtime = Runtime()
        runtime.mount(HStack(alignment: .top, spacing: 4) {
            Box(w: 20, h: 60)._probe("a")
            Box(w: 20, h: 30)._probe("b")
        }._probe("stack"))
        runtime.layout(in: CGSize(width: 300, height: 200))
        let f = frames(runtime)
        #expect(f["stack"] == CGRect(x: 128, y: 70, width: 44, height: 60))
        #expect(f["a"] == CGRect(x: 128, y: 70, width: 20, height: 60))
        #expect(f["b"] == CGRect(x: 152, y: 70, width: 20, height: 30))
    }

    @Test func layoutPriorityGroups() {
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) {
            Color.red._probe("low")
            Color.blue.layoutPriority(1)._probe("high")
        })
        runtime.layout(in: CGSize(width: 300, height: 10))
        let f = frames(runtime)
        // The high-priority child is sized first and takes everything; the other keeps its minimum (0).
        #expect(f["high"]?.width == 300)
        #expect(f["low"]?.width == 0)
    }

    @Test func spacerAndDividerFollowStackOrientation() {
        let runtime = Runtime()
        runtime.mount(VStack(spacing: 0) {
            HStack(spacing: 0) {
                Box(w: 50, h: 20)._probe("a")
                Spacer()._probe("hspacer")
                Divider()._probe("vdivider")
                Box(w: 50, h: 20)._probe("b")
            }
            Divider()._probe("hdivider")
            Spacer(minLength: 5)._probe("vspacer")
        })
        runtime.layout(in: CGSize(width: 300, height: 100))
        let f = frames(runtime)
        // Orientation: spacers are flat across the axis, dividers are one point thick along it.
        #expect(f["hspacer"]?.height == 0)
        #expect(f["hspacer"]?.width == 199)
        #expect(f["vdivider"]?.width == 1)
        #expect(f["hdivider"]?.size == CGSize(width: 300, height: 1))
        #expect(f["vspacer"]?.width == 0)
        #expect(f["a"]?.minX == 0)
        #expect(f["b"]?.maxX == 300)
    }

    @Test func frameAndPadding() {
        let runtime = Runtime()
        runtime.mount(
            Box(w: 40, h: 40)._probe("inner")
                .frame(width: 120, height: 80, alignment: .topLeading)._probe("frame")
                .padding(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))._probe("padded"))
        runtime.layout(in: CGSize(width: 200, height: 200))
        let f = frames(runtime)
        #expect(f["padded"] == CGRect(x: 37, y: 58, width: 126, height: 84))
        #expect(f["frame"] == CGRect(x: 39, y: 59, width: 120, height: 80))
        #expect(f["inner"] == CGRect(x: 39, y: 59, width: 40, height: 40))
    }

    @Test func flexibleFrames() {
        let runtime = Runtime()
        runtime.mount(VStack(spacing: 0) {
            Box(w: 40, h: 20).frame(minWidth: 100)._probe("min")
            Box(w: 40, h: 20).frame(maxWidth: 200)._probe("max")
            Box(w: 40, h: 20).frame(minWidth: 50, maxWidth: .infinity)._probe("fill")
            Box(w: 40, h: 20).frame(idealWidth: 150).fixedSize()._probe("ideal")
            Color.red.frame(maxWidth: 120, maxHeight: 20)._probe("clamp")
        })
        runtime.layout(in: CGSize(width: 300, height: 300))
        let f = frames(runtime)
        #expect(f["min"]?.width == 100)
        #expect(f["max"]?.width == 200)
        #expect(f["fill"]?.width == 300)
        #expect(f["ideal"]?.width == 150)
        #expect(f["clamp"]?.size == CGSize(width: 120, height: 20))
    }

    /// The height a flexible frame round a 100 × 212 box takes when offered `proposed`.
    private func flexHeight(_ proposed: CGFloat, _ frame: (Box) -> some View) -> CGFloat? {
        let runtime = Runtime()
        runtime.mount(frame(Box(w: 100, h: 212))._probe("f").frame(width: 300, height: proposed))
        runtime.layout(in: CGSize(width: 300, height: 2000))
        return frames(runtime)["f"]?.height
    }

    /// Each answer is SwiftUI's, measured with `NSHostingController.sizeThatFits` on macOS 26:
    /// the child's length, at least the proposal up to a maximum, at most the proposal down to a minimum.
    @Test func flexibleFrameNeverSqueezesAChildBelowItsLength() {
        #expect(flexHeight(50) { $0.frame(maxHeight: .infinity) } == 212)
        #expect(flexHeight(50) { $0.frame(maxHeight: 150) } == 150)
        #expect(flexHeight(1000) { $0.frame(maxHeight: 400) } == 400)
        #expect(flexHeight(50) { $0.frame(minHeight: 100) } == 100)
        #expect(flexHeight(50) { $0.frame(minHeight: 300) } == 300)
        #expect(flexHeight(500) { $0.frame(minHeight: 100) } == 212)
        #expect(flexHeight(50) { $0.frame(minHeight: 100, maxHeight: .infinity) } == 100)
        #expect(flexHeight(50) { $0.frame(minHeight: 250, maxHeight: 400) } == 250)
    }

    /// Paulo's day-one Weight history: two `maxHeight: .infinity` cards in a stack inside a
    /// stack in a scroll view. The outer stack places the inner one at its ideal length; the
    /// inner one shares that out, and must not give the chart's card less than its chart.
    @Test func stretchyCardsInAScrollViewKeepTheirContent() {
        let runtime = Runtime()
        runtime.mount(ScrollView {
            VStack(spacing: 0) {
                Box(w: 300, h: 40)
                VStack(spacing: 16) {
                    VStack(spacing: 14) { Box(w: 100, h: 60); Box(w: 100, h: 212) }
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)._probe("chart")
                    VStack(spacing: 4) { Box(w: 100, h: 30); Box(w: 100, h: 90) }
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)._probe("entries")
                }
            }
        })
        runtime.layout(in: CGSize(width: 393, height: 852))
        let f = frames(runtime)
        #expect(f["chart"]?.height == 334)
        #expect(f["entries"]?.height == 172)
        #expect(f["entries"]?.minY == (f["chart"]?.maxY ?? 0) + 16)
    }

    @Test func fixedSizeUsesIdeal() {
        let runtime = Runtime()
        runtime.mount(Color.red.fixedSize()._probe("c"))
        runtime.layout(in: CGSize(width: 200, height: 200))
        #expect(frames(runtime)["c"] == CGRect(x: 95, y: 95, width: 10, height: 10))
    }

    @Test func zstackAlignsOnGuides() {
        let runtime = Runtime()
        runtime.mount(ZStack(alignment: .bottomTrailing) {
            Box(w: 100, h: 100)._probe("a")
            Box(w: 30, h: 30)._probe("b")
        }._probe("stack"))
        runtime.layout(in: CGSize(width: 200, height: 200))
        let f = frames(runtime)
        #expect(f["stack"] == CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(f["b"] == CGRect(x: 120, y: 120, width: 30, height: 30))
    }

    @Test func alignmentGuidesInStacks() {
        let runtime = Runtime()
        runtime.mount(VStack(alignment: .leading, spacing: 0) {
            Box(w: 100, h: 20).alignmentGuide(.leading) { $0[.trailing] }._probe("a")
            Box(w: 50, h: 20)._probe("b")
        }._probe("stack"))
        runtime.layout(in: CGSize(width: 300, height: 100))
        let f = frames(runtime)
        // a's leading guide is at its trailing edge, so a sits 100 to the left of b.
        #expect(f["stack"] == CGRect(x: 75, y: 30, width: 150, height: 40))
        #expect(f["a"] == CGRect(x: 75, y: 30, width: 100, height: 20))
        #expect(f["b"] == CGRect(x: 175, y: 50, width: 50, height: 20))
    }

    @Test func modifiersDistributeOverLists() {
        let runtime = Runtime()
        runtime.mount(HStack(spacing: 0) {
            Group {
                Color.red._probe("a")
                Color.blue._probe("b")
            }
            .frame(width: 50, height: 50)
            Color.green._probe("c")
        })
        runtime.layout(in: CGSize(width: 300, height: 100))
        let f = frames(runtime)
        #expect(f["a"] == CGRect(x: 0, y: 25, width: 50, height: 50))
        #expect(f["b"] == CGRect(x: 50, y: 25, width: 50, height: 50))
        #expect(f["c"] == CGRect(x: 100, y: 0, width: 200, height: 100))
    }

    @Test func customLayoutAndLayoutValues() {
        let runtime = Runtime()
        runtime.mount(Diagonal {
            Box(w: 10, h: 10)._probe("a")
            Box(w: 20, h: 20).layoutValue(key: WidthKey.self, value: 5)._probe("b")
        }._probe("layout"))
        runtime.layout(in: CGSize(width: 100, height: 100))
        let f = frames(runtime)
        #expect(f["layout"] == CGRect(x: 32.5, y: 35, width: 35, height: 30))
        #expect(f["a"] == CGRect(x: 32.5, y: 35, width: 10, height: 10))
        #expect(f["b"] == CGRect(x: 42.5, y: 45, width: 20, height: 20))
    }

    @Test func layoutUpdatesAfterStateChange() throws {
        struct Toggler: View {
            @State var wide = false
            var body: some View { Box(w: wide ? 80 : 40, h: 10)._probe("box") }
        }
        let runtime = Runtime()
        let node = try #require(runtime.mount(Toggler()) as? CompositeNode<Toggler>)
        runtime.layout(in: CGSize(width: 100, height: 100))
        #expect(frames(runtime)["box"]?.width == 40)
        node.view.wide = true
        runtime.layout(in: CGSize(width: 100, height: 100))   // flushes, then lays out
        #expect(frames(runtime)["box"]?.width == 80)
    }
}
