// A plain button on iOS (new-website#264): the press shows at once, the release fades back on the
// default spring, and what the action changed in the label fades in with it (a tab bar's new
// highlight takes about half a second in the simulator). On the Mac both are instant.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct PlainButtonReleaseTests {
    @Observable final class Model { var selected = false }

    struct Host: View {
        let model: Model
        var body: some View {
            Button { model.selected = true } label: {
                Color.clear.frame(width: 100, height: 50)
                    .background { if model.selected { Capsule().fill(Color.red) } }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The group opacity the red highlight is drawn under (1 when none), nil when it isn't drawn.
    private func highlight(_ r: Runtime) -> Double? {
        var stack: [Double] = [1]
        for command in r.render(scale: 1).commands.map(\.description) {
            if command.hasPrefix("beginGroup") {
                let value = command.split(separator: "opacity: ").last.flatMap { Double($0.prefix { "0123456789.e-".contains($0) }) } ?? 1
                stack.append(stack.last! * value)
            } else if command == "endGroup" {
                stack.removeLast()
            } else if command.contains("#FF383C") {
                return stack.last!
            }
        }
        return nil
    }

    private func run(_ profile: PlatformProfile) -> (pressed: Double?, early: Double?, later: Double?, end: Double?) {
        let model = Model()
        var environment = EnvironmentValues()
        environment.platformProfile = profile
        let r = Runtime(environment: environment)
        let size = CGSize(width: 393, height: 852)
        r.mount(Host(model: model))
        r.layout(in: size)
        r.pointerDown(at: CGPoint(x: 196, y: 426), type: .touch, time: 1)
        r.layout(in: size)
        r.pointerUp(at: CGPoint(x: 196, y: 426), time: 1.1)
        r.layout(in: size)
        let pressed = highlight(r)
        r.advanceAnimations(elapsed: 0.05); r.layout(in: size)
        let early = highlight(r)
        r.advanceAnimations(elapsed: 0.15); r.layout(in: size)
        let later = highlight(r)
        r.advanceAnimations(elapsed: 2); r.layout(in: size)
        return (pressed, early, later, highlight(r))
    }

    @Test func onIOSTheReleaseFadesIn() {
        let (_, early, later, end) = run(.iOS)
        #expect(model(early) < model(later), "\(String(describing: early)) \(String(describing: later))")
        #expect(model(later) < 1)
        #expect(end == 1)
    }

    @Test func onTheMacItIsInstant() {
        let (_, early, _, end) = run(.macOS)
        #expect(early == 1 && end == 1, "\(String(describing: early))")
    }

    private func model(_ value: Double?) -> Double { value ?? 0 }
}
#endif
