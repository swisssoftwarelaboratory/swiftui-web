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

    /// The app's own pattern in full: a dim and the sheet, dismissed from the drag's end.
    struct AppSheet: View {
        let model: Model
        var body: some View {
            ZStack(alignment: .bottom) {
                Color.white
                if model.sheet != nil {
                    Color.black.opacity(0.3).ignoresSafeArea().transition(.opacity)
                }
                if let sheet = model.sheet {
                    Group { Color.red.frame(height: 300) }
                        .padding(.bottom, 8)
                        .offset(y: max(0, model.drag))
                        .gesture(DragGesture()
                            .onChanged { model.drag = $0.translation.height }
                            .onEnded { value in
                                if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                                    withAnimation(.smooth(duration: 0.3)) { model.sheet = nil }
                                }
                                withAnimation(.smooth) { model.drag = 0 }
                            })
                        .transition(.move(edge: .bottom))
                        .id(sheet)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }


    /// The app's real layering: the sheet host is a stack of its own with nothing behind the
    /// sheet, inside a bottom-aligned stack over the screen. Once the sheet and dim are removed
    /// the host shrinks to a point at the bottom centre; the leaving sheet and dim must stay
    /// where they were, not drift right and down with it (new-website#264).
    struct ShellHost: View {
        let model: Model
        var body: some View {
            ZStack(alignment: .bottom) {
                Color.white
                ShellSheetHost(model: model)
            }
        }
    }
    struct ShellSheetHost: View {
        let model: Model
        var body: some View {
            ZStack(alignment: .bottom) {
                if model.sheet != nil {
                    Color.black.opacity(0.3).ignoresSafeArea().transition(.opacity)
                }
                if let sheet = model.sheet {
                    Group { Color.red.frame(height: 300) }
                        .padding(.bottom, 8)
                        .offset(y: max(0, model.drag))
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

    @Test func aSheetDismissedByItsOwnDragSlidesOff() {
        let model = Model()
        model.sheet = 1
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(AppSheet(model: model))
        r.layout(in: size)
        func frame() { _ = r.advanceFrame(elapsed: 1.0 / 60); r.layout(in: size); _ = r.render(scale: 3) }
        frame()
        var t = 1.0
        r.pointerDown(at: CGPoint(x: 196, y: 650), type: .touch, time: t)
        for i in 1...20 {
            t += 1.0 / 60
            r.pointerMoved(to: CGPoint(x: 196, y: 650 + Double(i) * 10), time: t)
            frame()
        }
        #expect(abs((redTop(r) ?? 0) - 744) < 1, "\(String(describing: redTop(r)))")
        r.pointerUp(at: CGPoint(x: 196, y: 850), time: t)
        #expect(model.sheet == nil)
        var tops: [Double?] = []
        for _ in 0..<90 { frame(); tops.append(redTop(r)) }
        // It leaves the screen before it goes: its last drawn top is at the bottom edge.
        let lastDrawn = tops.compactMap { $0 }.last ?? 0
        #expect(lastDrawn > 840, "\(tops)")
        #expect(tops.prefix(6).allSatisfy { $0 != nil }, "\(tops)")
        #expect((tops[3] ?? 0) > 744, "\(tops)")
    }

    /// The red card's left edge and top, and the dim's origin, from the drawing list.
    private func origins(_ r: Runtime) -> (red: CGPoint?, dim: CGPoint?) {
        var shift = CGPoint.zero, red: CGPoint?, dim: CGPoint?
        for command in r.render(scale: 1).commands.map(\.description) {
            if command.hasPrefix("concat(") {
                let parts = command.dropFirst(7).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 6 { shift.x += parts[4]; shift.y += parts[5] }
            } else if command == "restore" {
                shift = .zero
            } else if command.hasPrefix("fillRect(") {
                let parts = command.dropFirst(9).split(separator: ",").prefix(2).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2 else { continue }
                let p = CGPoint(x: parts[0] + shift.x, y: parts[1] + shift.y)
                if command.contains("#FF383C") { red = p } else if command.contains("#000000") { dim = p }
            }
        }
        return (red, dim)
    }

    @Test func aSheetLeavingAnEmptyHostStaysInPlace() {
        let model = Model()
        model.sheet = 1
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(ShellHost(model: model))
        r.layout(in: size)
        let start = origins(r)
        #expect(start.red?.x == 0 && start.dim == CGPoint(x: 0, y: 0), "\(start)")
        withAnimation(.smooth(duration: 0.3)) { model.sheet = nil }
        r.layout(in: size)
        var seen: [(red: CGPoint?, dim: CGPoint?)] = []
        for _ in 0..<12 { r.advanceAnimations(elapsed: 1.0 / 60); r.layout(in: size); seen.append(origins(r)) }
        // Still on screen mid-slide, and straight below where it was: no sideways drift.
        #expect(seen[5].red != nil, "\(seen)")
        for frame in seen {
            if let red = frame.red { #expect(abs(red.x) < 0.01, "\(seen)") }
            if let dim = frame.dim { #expect(abs(dim.x) < 0.01 && abs(dim.y) < 0.01, "\(seen)") }
        }
        #expect((seen[5].red?.y ?? 0) > (start.red?.y ?? .infinity), "\(seen)")
    }

    @Test func aSheetEnteringAnEmptyHostFadesItsDimInPlace() {
        let model = Model()
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let r = Runtime(environment: environment)
        r.mount(ShellHost(model: model))
        r.layout(in: size)
        withAnimation(.smooth(duration: 0.3)) { model.sheet = 1 }
        r.layout(in: size)
        var seen: [(red: CGPoint?, dim: CGPoint?)] = []
        for _ in 0..<12 { r.advanceAnimations(elapsed: 1.0 / 60); r.layout(in: size); seen.append(origins(r)) }
        // The dim fades in where it stands; the sheet rises straight up from below.
        #expect(seen.contains { $0.dim != nil }, "\(seen)")
        for frame in seen {
            if let dim = frame.dim { #expect(abs(dim.x) < 0.01 && abs(dim.y) < 0.01, "\(seen)") }
            if let red = frame.red { #expect(abs(red.x) < 0.01, "\(seen)") }
        }
    }
}
#endif
