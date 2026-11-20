// The drawn iPhone around an app (new-website#651, moves decided in #628): the side button darkens
// the screen onto its lock screen and wakes it, a drag up unlocks to what was open, a drag up from
// the app's bottom edge sends it into its icon (a short slow one springs back), a tap on the icon
// opens it, a drag down from the top brings the pull-down, a banner drops in and goes, a tap in the
// bottom edge still reaches the app, and the app hears each change through its scene phase.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct DrawnPhoneTests {
    @Observable final class Model {
        var taps = 0
        var phases: [ScenePhase] = []
    }

    struct Probe: View {
        let model: Model
        @Environment(\.scenePhase) private var phase
        var body: some View {
            VStack(spacing: 0) {
                Color.gray.frame(maxWidth: .infinity, maxHeight: .infinity)
                Button { model.taps += 1 } label: {
                    Text("Tab")
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .ignoresSafeArea()
            .onChange(of: phase) { _, new in model.phases.append(new) }
        }
    }

    private let size = CGSize(width: 393, height: 852)

    private func phone(_ model: Model) -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.drawsPhone = true
        runtime.mount(Probe(model: model))
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        _ = r.render(scale: 2)
    }

    private func settle(_ r: Runtime, seconds: Double = 1.5) {
        for _ in 0..<Int(seconds * 60) { frame(r) }
    }

    private var clock = 10.0

    /// A mouse press-and-drag (the finger on the iPhone look) in steps of one display frame.
    private mutating func drag(_ r: Runtime, from a: CGPoint, to b: CGPoint, duration: Double, hold: Double = 0) {
        r.pointerDown(at: a, type: .mouse, time: clock)
        let steps = max(1, Int((duration * 60).rounded()))
        for i in 1...steps {
            clock += duration / Double(steps)
            let f = CGFloat(i) / CGFloat(steps)
            r.pointerMoved(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), time: clock)
            frame(r)
        }
        if hold > 0 {
            let still = Int(hold * 60)
            for _ in 0..<still { clock += 1.0 / 60; frame(r) }
        }
        r.pointerUp(at: b, time: clock)
        clock += 0.01
    }

    private mutating func tap(_ r: Runtime, _ p: CGPoint) {
        r.pointerDown(at: p, type: .mouse, time: clock)
        clock += 0.08
        r.pointerUp(at: p, time: clock)
        clock += 0.01
        frame(r)
    }

    private func state(_ r: Runtime) -> [String: String] {
        Dictionary(uniqueKeysWithValues: r.phoneDebug("").split(separator: "\n").map {
            let parts = $0.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }

    @Test mutating func sideButtonLocksAndUnlockingReturnsToTheApp() {
        let model = Model()
        let r = phone(model)
        #expect(state(r)["mode"] == "app")
        #expect(r.scenePhase == .active)
        r.phoneSideButtonPressed()
        // Dark almost at once: past half within 0.1 s.
        for _ in 0..<6 { frame(r) }
        #expect(Double(state(r)["dark"]!)! > 500)
        settle(r)
        #expect(state(r)["mode"] == "off")
        #expect(state(r)["cover"] == "0")
        #expect(r.scenePhase == .background)
        // Pressed again, it wakes on the lock screen, still background.
        r.phoneSideButtonPressed()
        settle(r)
        #expect(state(r)["mode"] == "locked")
        #expect(state(r)["dark"] == "0")
        // A short drag up falls back; a long one lifts the lock screen off to the app.
        drag(r, from: CGPoint(x: 196, y: 820), to: CGPoint(x: 196, y: 790), duration: 0.3, hold: 0.2)
        settle(r)
        #expect(state(r)["mode"] == "locked")
        #expect(state(r)["cover"] == "0")
        drag(r, from: CGPoint(x: 196, y: 820), to: CGPoint(x: 196, y: 500), duration: 0.2)
        settle(r)
        #expect(state(r)["mode"] == "app")
        #expect(state(r)["cover"] == "-8520")
        #expect(r.scenePhase == .active)
        #expect(model.phases.contains(.background))
        #expect(model.phases.last == .active)
    }

    @Test mutating func leavingTheAppSendsItIntoItsIconAndATapBringsItBack() {
        let model = Model()
        let r = phone(model)
        // Slowly, a little: springs back to full screen.
        drag(r, from: CGPoint(x: 196, y: 845), to: CGPoint(x: 196, y: 800), duration: 0.4, hold: 0.2)
        settle(r)
        #expect(state(r)["mode"] == "app")
        #expect(state(r)["card"] == "0,0,3930,8520")
        // Mid-drag the app is a smaller card under the finger, and inactive.
        r.pointerDown(at: CGPoint(x: 196, y: 845), type: .mouse, time: clock)
        for i in 1...12 {
            clock += 1.0 / 60
            r.pointerMoved(to: CGPoint(x: 196, y: 845 - CGFloat(i) * 25), time: clock)
            frame(r)
        }
        #expect(r.scenePhase == .inactive)
        let card = state(r)["card"]!.split(separator: ",").map { Double($0)! / 10 }
        #expect(card[2] < 393 * 0.8)
        #expect(abs(card[1] + card[3] - 545) < 2)
        r.pointerUp(at: CGPoint(x: 196, y: 545), time: clock)
        settle(r)
        #expect(state(r)["mode"] == "home")
        #expect(state(r)["cardShown"] == "false")
        #expect(r.scenePhase == .background)
        // A tap on its icon grows it back.
        tap(r, CGPoint(x: 57, y: 102))
        settle(r)
        #expect(state(r)["mode"] == "app")
        #expect(state(r)["card"] == "0,0,3930,8520")
        #expect(r.scenePhase == .active)
    }

    @Test mutating func pullDownFromTheTopAndBackUp() {
        let model = Model()
        let r = phone(model)
        drag(r, from: CGPoint(x: 300, y: 20), to: CGPoint(x: 300, y: 500), duration: 0.25)
        settle(r)
        #expect(state(r)["mode"] == "pullDown")
        #expect(state(r)["cover"] == "0")
        #expect(r.scenePhase == .inactive)
        drag(r, from: CGPoint(x: 196, y: 820), to: CGPoint(x: 196, y: 300), duration: 0.2)
        settle(r)
        #expect(state(r)["mode"] == "app")
        #expect(r.scenePhase == .active)
        // A short slow pull goes back up.
        drag(r, from: CGPoint(x: 300, y: 20), to: CGPoint(x: 300, y: 120), duration: 0.4, hold: 0.2)
        settle(r)
        #expect(state(r)["mode"] == "app")
        #expect(state(r)["cover"] == "-8520")
        // Let go still at half way, it goes back up (as in the iOS 27 simulator).
        drag(r, from: CGPoint(x: 300, y: 20), to: CGPoint(x: 300, y: 426), duration: 0.5, hold: 0.3)
        settle(r)
        #expect(state(r)["mode"] == "app")
    }

    @Test mutating func unlockingNeedsAlmostHalfWayOrAFlick() {
        let model = Model()
        let r = phone(model)
        r.phoneSideButtonPressed()
        settle(r)
        r.phoneSideButtonPressed()
        settle(r)
        // Still at 35 %: falls back (iOS fell back at 39 %).
        drag(r, from: CGPoint(x: 196, y: 830), to: CGPoint(x: 196, y: 830 - 298), duration: 0.5, hold: 0.3)
        settle(r)
        #expect(state(r)["mode"] == "locked")
        // Still at 50 %: opens.
        drag(r, from: CGPoint(x: 196, y: 830), to: CGPoint(x: 196, y: 830 - 426), duration: 0.6, hold: 0.3)
        settle(r)
        #expect(state(r)["mode"] == "app")
    }

    @Test mutating func aTapInTheBottomEdgeStillReachesTheApp() {
        let model = Model()
        let r = phone(model)
        tap(r, CGPoint(x: 196, y: 840))
        #expect(model.taps == 1)
        tap(r, CGPoint(x: 196, y: 800))
        #expect(model.taps == 2)
        #expect(state(r)["mode"] == "app")
    }

    @Test func bannerDropsInAndGoesByItself() {
        let model = Model()
        let r = phone(model)
        _ = r.phoneDebug("banner")
        settle(r, seconds: 1)
        #expect(state(r)["bannerShown"] == "true")
        #expect(state(r)["banner"] == "0")
        #expect(r.scenePhase == .active)
        settle(r, seconds: 6)
        #expect(state(r)["bannerShown"] == "false")
        #expect(Double(state(r)["banner"]!)! < -1600)
    }
}
#endif
