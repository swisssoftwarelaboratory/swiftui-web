// contentTransition: a Text whose content changes under an animation crossfades from the old
// text to the new one; numericText also rolls the texts vertically.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ContentTransitionTests {
    @Observable final class Model: @unchecked Sendable {
        var count = 1
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        let font = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for digit in ["1", "2"] {
            entries[RecordedTextEngine.key(font: font, width: nil, string: digit)] = .init(width: 8, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }
    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }

    struct Counter: View {
        let model: Model
        let transition: ContentTransition
        var body: some View {
            Text("\(model.count)").contentTransition(transition)._probe("text")
        }
    }

    @Test func opacityCrossfades() {
        let model = Model()
        let r = runtime(Counter(model: model, transition: .opacity))
        withAnimation(.linear(duration: 1)) { model.count = 2 }
        relayout(r)
        #expect(r.isAnimating)
        r.advanceAnimations(elapsed: 0.25)
        let mid = commands(r)
        // Both texts are drawn, each in an opacity group: the old at 0.75, the new at 0.25.
        #expect(mid.contains { $0.hasPrefix("drawText(\"1\"") } && mid.contains { $0.hasPrefix("drawText(\"2\"") })
        #expect(mid.contains("beginGroup(opacity: 0.75)") && mid.contains("beginGroup(opacity: 0.25)"))
        r.advanceAnimations(elapsed: 0.75)
        let end = commands(r)
        #expect(!end.contains { $0.hasPrefix("drawText(\"1\"") } && end.contains { $0.hasPrefix("drawText(\"2\"") })
        #expect(!end.contains { $0.hasPrefix("beginGroup") })
        #expect(!r.isAnimating)
    }

    @Test func numericTextRolls() {
        let model = Model()
        let r = runtime(Counter(model: model, transition: .numericText()))
        let before = commands(r).first { $0.hasPrefix("drawText(\"1\"") }!
        withAnimation(.linear(duration: 1)) { model.count = 2 }
        relayout(r)
        r.advanceAnimations(elapsed: 0.5)
        let mid = commands(r)
        let old = mid.first { $0.hasPrefix("drawText(\"1\"") }!
        let new = mid.first { $0.hasPrefix("drawText(\"2\"") }!
        func y(_ command: String) -> Double {
            // "drawText(\"1\" system 13 w400 at 156,105 #…)": the y after the comma.
            let at = command.range(of: " at ")!
            let rest = command[at.upperBound...]
            let comma = rest.firstIndex(of: ",")!
            let space = rest[comma...].firstIndex(of: " ")!
            return Double(rest[rest.index(after: comma)..<space])!
        }
        // Counting up: the old text has moved up, the new one is still below its resting place.
        #expect(y(old) < y(before) && y(new) > y(before))
    }

    struct ValueCounter: View {
        let model: Model
        var body: some View {
            Text("\(model.count)").contentTransition(.numericText(value: Double(model.count)))._probe("text")
        }
    }

    /// `numericText(value:)` rolls by how the value changed: down when it drops, as Apple's.
    @Test func numericTextValueRollsByDirection() {
        let model = Model()
        model.count = 2
        let r = runtime(ValueCounter(model: model))
        let before = commands(r).first { $0.hasPrefix("drawText(\"2\"") }!
        withAnimation(.linear(duration: 1)) { model.count = 1 }
        relayout(r)
        r.advanceAnimations(elapsed: 0.5)
        let mid = commands(r)
        let old = mid.first { $0.hasPrefix("drawText(\"2\"") }!
        let new = mid.first { $0.hasPrefix("drawText(\"1\"") }!
        func y(_ command: String) -> Double {
            let rest = command[command.range(of: " at ")!.upperBound...]
            let comma = rest.firstIndex(of: ",")!
            return Double(rest[rest.index(after: comma)..<rest[comma...].firstIndex(of: " ")!])!
        }
        // Counting down: the old text has moved down, the new one comes from above.
        #expect(y(old) > y(before) && y(new) < y(before))
    }

    @Test func identityAndUnanimatedChangesSnap() {
        let model = Model()
        let r = runtime(Counter(model: model, transition: .identity))
        withAnimation(.linear(duration: 1)) { model.count = 2 }
        relayout(r)
        #expect(!r.isAnimating)
        let plain = Model()
        let p = runtime(Counter(model: plain, transition: .opacity))
        plain.count = 2
        relayout(p)
        #expect(!p.isAnimating && commands(p).contains { $0.hasPrefix("drawText(\"2\"") })
    }
}
#endif
