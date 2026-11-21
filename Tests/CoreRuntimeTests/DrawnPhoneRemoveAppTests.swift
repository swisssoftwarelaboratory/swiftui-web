// Remove App on the drawn iPhone's home screen (new-website#709): holding the app's icon opens
// iOS's menu with Remove App, which asks as iOS does (Delete App, then Delete), the icon shrinks
// away, and the app starts again as a fresh install: its answers forgotten, on the home screen,
// not running until it is opened, its name marked new. A short tap still opens the app; the
// made-up apps take no hold; a press beside the menu closes it.
import SwiftUI
import SwiftUIWebCore
import Testing
import WebFoundation

#if !os(WASI)
extension NotificationCentreSuites {
@Suite(.serialized) @MainActor struct DrawnPhoneRemoveAppTests {
    private let size = CGSize(width: 393, height: 852)
    private var clock = 10.0

    init() {}

    private func phone() -> Runtime {
        _DrawnPhoneSystem.widgetSource = nil
        _DrawnPhoneSystem.reinstall = nil
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.textEngine = MonospaceTextEngine()
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.drawsPhone = true
        runtime.mount(Color.gray.ignoresSafeArea())
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    @discardableResult
    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) -> DisplayList {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        return r.render(scale: 2)
    }

    private func settle(_ r: Runtime, seconds: Double = 1.5) {
        for _ in 0..<Int(seconds * 60) { frame(r) }
    }

    private func turns(_ r: Runtime) async {
        for _ in 0..<20 { await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
        settle(r, seconds: 0.6)
    }

    private func debug(_ r: Runtime, _ key: String) -> String {
        r.phoneDebug("").split(separator: "\n").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
    }

    private mutating func goHome(_ r: Runtime) {
        r.pointerDown(at: CGPoint(x: 196, y: 845), type: .mouse, time: clock)
        for step in 1...10 {
            clock += 0.016
            r.pointerMoved(to: CGPoint(x: 196, y: 845 - Double(step) * 40), time: clock)
        }
        clock += 0.016
        r.pointerUp(at: CGPoint(x: 196, y: 445), time: clock)
        settle(r)
    }

    private var icon: CGPoint { CGPoint(x: 27 + 30, y: 72 + 30) }

    /// A press held at `point` for `seconds`, frames running, then lifted.
    private mutating func hold(_ r: Runtime, at point: CGPoint, seconds: Double = 0.7) {
        r.pointerDown(at: point, type: .mouse, time: clock)
        for _ in 0..<Int(seconds * 60) { clock += 1.0 / 60; frame(r) }
        r.pointerUp(at: point, time: clock)
        clock += 0.01
        frame(r)
    }

    private mutating func tap(_ r: Runtime, _ p: CGPoint) {
        r.pointerDown(at: p, type: .mouse, time: clock)
        clock += 0.08
        r.pointerUp(at: p, time: clock)
        clock += 0.01
        frame(r)
    }

    /// The words on the phone's own tree over the home screen, with where they stand.
    private func menuTexts(_ r: Runtime) -> [(String, CGRect)] {
        guard let tree = r.drawnPhone?.iconMenu else { return [] }
        return tree.runtime.presentations.flatMap { presentation in
            presentation.descendants(where: { $0 is TextNode }).compactMap { node -> (String, CGRect)? in
                guard let text = node as? TextNode else { return nil }
                var frame = text.frameInRoot
                var current: ViewNode? = text
                while frame.width == 0, let up = current?.parent { frame = up.frameInRoot; current = up }
                return (text.view.resolvedString, frame)
            }
        }
    }

    private mutating func tap(_ r: Runtime, text: String) {
        guard let rect = menuTexts(r).first(where: { $0.0 == text })?.1 else { Issue.record("no \(text) in \(menuTexts(r).map(\.0))"); return }
        tap(r, CGPoint(x: rect.midX, y: rect.midY))
    }

    @Test mutating func holdingTheIconOpensRemoveAppAndATapStillOpensTheApp() async {
        let r = phone()
        goHome(r)
        #expect(debug(r, "mode") == "home")
        // A short tap opens the app, as before.
        tap(r, icon)
        settle(r)
        #expect(debug(r, "mode") == "app")
        goHome(r)
        hold(r, at: icon)
        #expect(debug(r, "iconMenu") == "menu")
        #expect(menuTexts(r).map(\.0) == ["Edit Home Screen", "Remove App"])
        // Lifting the finger left the menu open and the app closed.
        settle(r)
        #expect(debug(r, "mode") == "home")
        #expect(debug(r, "iconMenu") == "menu")
        // A press beside the menu closes it.
        tap(r, CGPoint(x: 300, y: 600))
        settle(r)
        #expect(debug(r, "iconMenu") == "none")
        #expect(debug(r, "mode") == "home")
    }

    @Test mutating func aMadeUpAppTakesNoHold() async {
        let r = phone()
        goHome(r)
        hold(r, at: CGPoint(x: 120 + 30, y: 72 + 30))
        #expect(debug(r, "iconMenu") == "none")
        #expect(debug(r, "mode") == "home")
    }

    @Test mutating func removeAppAsksTwiceThenReinstalls() async {
        let r = phone()
        _PhonePrompts.setAnswer("notifications", "allowed")
        var reinstalled = 0
        _DrawnPhoneSystem.reinstall = { reinstalled += 1 }
        defer { _DrawnPhoneSystem.reinstall = nil }
        goHome(r)
        hold(r, at: icon)
        tap(r, text: "Remove App")
        await turns(r)
        #expect(debug(r, "iconMenu") == "alert")
        #expect(menuTexts(r).map(\.0).contains("Remove \u{201C}App\u{201D}?"))
        tap(r, text: "Delete App")
        await turns(r)
        #expect(debug(r, "iconMenu") == "alert")
        #expect(menuTexts(r).map(\.0).contains("Deleting this app will also delete its data."))
        tap(r, text: "Delete")
        frame(r)
        #expect(debug(r, "removing") == "true")
        settle(r)
        #expect(reinstalled == 1)
        #expect(debug(r, "removing") == "false")
        #expect(_PhonePrompts.answer("notifications") == nil)
    }

    @Test mutating func cancelKeepsTheApp() async {
        let r = phone()
        var reinstalled = 0
        _DrawnPhoneSystem.reinstall = { reinstalled += 1 }
        defer { _DrawnPhoneSystem.reinstall = nil }
        goHome(r)
        hold(r, at: icon)
        tap(r, text: "Remove App")
        await turns(r)
        tap(r, text: "Delete App")
        await turns(r)
        tap(r, text: "Cancel")
        settle(r)
        #expect(debug(r, "iconMenu") == "none")
        #expect(reinstalled == 0)
        tap(r, icon)
        settle(r)
        #expect(debug(r, "mode") == "app")
    }

    @Test mutating func aFreshInstallWaitsOnTheHomeScreenUntilOpened() async {
        let r = phone()
        var launched = 0
        r.phoneStartsFreshlyInstalled { launched += 1 }
        settle(r)
        #expect(debug(r, "mode") == "home")
        #expect(debug(r, "freshlyInstalled") == "true")
        #expect(launched == 0)
        #expect(r.scenePhase == .background)
        tap(r, icon)
        settle(r)
        #expect(launched == 1)
        #expect(debug(r, "mode") == "app")
        #expect(debug(r, "freshlyInstalled") == "false")
        goHome(r)
        tap(r, icon)
        settle(r)
        #expect(launched == 1)
    }

    @Test func eachAppKeepsItsOwnKeys() {
        _AppSandbox.nativeIdentifier = "com.example.one"
        defer { _AppSandbox.nativeIdentifier = nil }
        #expect(_AppSandbox.prefix == "swiftuiweb.app[com.example.one].")
        #expect(_PhonePrompts.keyPrefix == "swiftuiweb.app[com.example.one].phone.permission.")
        #expect(_AppSandbox.owns("swiftuiweb.app[com.example.one].defaults.standard"))
        #expect(!_AppSandbox.owns("swiftuiweb.app[com.example.one.two].defaults.standard"))
        #expect(!_AppSandbox.owns("swiftuiweb.defaults.standard"))
        _AppSandbox.nativeIdentifier = nil
        // An app without an identifier never touches another app's keys.
        #expect(_AppSandbox.owns("swiftuiweb.defaults.standard"))
        #expect(!_AppSandbox.owns("swiftuiweb.app[com.example.one].defaults.standard"))
        #expect(!_AppSandbox.owns("somethingelse"))
    }
}
}
#endif
