// An app's own sheet (new-website#264): a view inserted and removed under `withAnimation` with
// `.transition(.move(edge: .bottom))`, an `.id` and a drag offset, as apps draw their own sheets.
// On iOS the removed view slides off from where it stands; it must not vanish in one frame.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct MoveTransitionTests {
    @Observable final class Model {
        var sheet: Int? = nil
        var drag: CGFloat = 0
    }

    struct Host: View {
        let model: Model
        var body: some View {
            ZStack(alignment: .bottom) {
                Color.white
                if let sheet = model.sheet {
                    Group {
                        Color.red.frame(height: 300)
                    }
                    .padding(.bottom, 8)
                    .offset(y: max(0, model.drag))
                    .gesture(DragGesture().onChanged { model.drag = $0.translation.height })
                    .transition(.move(edge: .bottom))
                    .id(sheet)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    private let size = CGSize(width: 393, height: 852)

    /// Where the red card is drawn: its rect's top plus the translation it is drawn under.
    private func redTop(_ r: Runtime) -> Double? {
        var shift = 0.0
        for command in r.render(scale: 1).commands.map(\.description) {
            if command.hasPrefix("concat(") {
                let parts = command.dropFirst(7).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 6 { shift += parts[5] }
            } else if command == "restore" {
                shift = 0
            } else if command.hasPrefix("fillRect("), command.contains("#FF383C") {
                let parts = command.dropFirst(9).split(separator: ",").prefix(2).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                return parts.count == 2 ? parts[1] + shift : nil
            }
        }
        return nil
    }

    @Test func aRemovedSheetSlidesOffFromWhereTheDragLeftIt() {
        let model = Model()
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(Host(model: model))
        r.layout(in: size)
        withAnimation(.smooth(duration: 0.38)) { model.sheet = 1 }
        r.layout(in: size)
        r.advanceAnimations(elapsed: 2); r.layout(in: size)
        let rest = redTop(r)
        #expect(abs((rest ?? 0) - 544) < 0.01, "\(r.render(scale: 1).commands.map(\.description))")
        // The finger dragged it 150 down, then lifted: the app dismisses and springs `drag` back.
        model.drag = 150
        r.layout(in: size)
        #expect(abs((redTop(r) ?? 0) - 694) < 0.01, "\(r.render(scale: 1).commands.map(\.description))")
        withAnimation(.smooth(duration: 0.3)) { model.sheet = nil }
        withAnimation(.smooth) { model.drag = 0 }
        r.layout(in: size)
        r.advanceAnimations(elapsed: 0.016); r.layout(in: size)
        let early = redTop(r)
        #expect(early != nil, "the sheet vanished at once")
        r.advanceAnimations(elapsed: 0.1); r.layout(in: size)
        let later = redTop(r)
        #expect((later ?? 0) > (early ?? .infinity), "\(String(describing: early)) \(String(describing: later))")
        r.advanceAnimations(elapsed: 2); r.layout(in: size)
        #expect(redTop(r) == nil)
    }
}
#endif
