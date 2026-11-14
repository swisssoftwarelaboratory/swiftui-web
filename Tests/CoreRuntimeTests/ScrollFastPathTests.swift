// Scroll frames that only moved content: the size memo survives (no layout generation), the
// scrolled content is moved rather than laid out, and content that reads its own geometry
// (a GeometryReader asking where it is) still gets a full layout so its readings follow the scroll.
import Testing
import SwiftUI
import SwiftUIWebCore

@Observable
private final class Readings {
    var minY: [CGFloat] = []
}

private struct ReadingRows: View {
    let readings: Readings
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<20, id: \.self) { _ in Color.blue.frame(width: 100, height: 20) }
                GeometryReader { proxy in
                    Color.red.onChange(of: proxy.frame(in: .global).minY, initial: true) { _, y in readings.minY.append(y) }
                }
                .frame(width: 100, height: 20)
            }
        }
    }
}

@Suite @MainActor struct ScrollFastPathTests {
    private func rows(_ count: Int) -> some View {
        VStack(spacing: 0) { ForEach(0..<count, id: \.self) { _ in Color.blue.frame(width: 100, height: 20) } }
    }

    @Test func scrollFramesMoveContentWithoutLayingOut() {
        let runtime = Runtime()
        runtime.mount(ScrollView { rows(20) })
        runtime.layout(in: CGSize(width: 100, height: 100))
        let generation = runtime.layoutGeneration
        // The scroll view's content node (the scroll node paints exactly its content).
        let content = runtime.root.layoutChildren.first!.paintedChildren.first!
        let before = content.frameInRoot
        runtime.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 50, y: 50))
        #expect(runtime.needsFrame)
        runtime.layout(in: CGSize(width: 100, height: 100))
        // Moved by the delta; no new layout generation, so every memoised size is still valid.
        #expect(content.frameInRoot.minY == before.minY - 50)
        #expect(runtime.layoutGeneration == generation)
        // A state change afterwards lays out fully again.
        runtime.layout(in: CGSize(width: 120, height: 100))
        #expect(runtime.layoutGeneration == generation + 1)
    }

    /// A geometry reader that reads its position in a background layer (a probe) forbids the
    /// fast path as one in the content does: the gallery's probe frames follow a wheel over
    /// ios/representable/wheel. (A reader of its size alone does not: LayoutOnlyWhatChangedTests.)
    @Test func geometryReadersInLayersForceLayout() {
        let runtime = Runtime()
        runtime.mount(ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    Color.red.frame(height: 60).background(GeometryReader { proxy in
                        let _ = proxy.frame(in: .global)
                        Color.clear
                    })
                }
            }
        })
        runtime.layout(in: CGSize(width: 200, height: 100))
        let layouts = runtime.fullLayoutCount
        runtime.scrollWheel(by: CGSize(width: 0, height: 60), at: CGPoint(x: 100, y: 50))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.fullLayoutCount == layouts + 1)
    }

    @Test func geometryReadersStillFollowScrolls() {
        let readings = Readings()
        let runtime = Runtime()
        runtime.mount(ReadingRows(readings: readings))
        runtime.layout(in: CGSize(width: 100, height: 100))
        let layouts = runtime.fullLayoutCount
        runtime.scrollWheel(by: CGSize(width: 0, height: 50), at: CGPoint(x: 50, y: 50))
        runtime.layout(in: CGSize(width: 100, height: 100))
        runtime.layout(in: CGSize(width: 100, height: 100))
        // The reader's global frame moved up by the scroll, which took a full layout (the
        // memoised sizes stay: the reader's content is rebuilt from its new frame when placed).
        #expect(readings.minY.first == 400 && readings.minY.last == 350)
        #expect(runtime.fullLayoutCount > layouts)
    }
}
