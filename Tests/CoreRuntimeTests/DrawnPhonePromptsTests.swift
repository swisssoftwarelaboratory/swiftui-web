// The drawn iPhone's permission prompts (new-website#666): what the frameworks ask through
// `_PhonePrompts` shows as iOS does it over the app (the iOS 27 alert, Apple Health's access
// sheet, the Face ID badge), one at a time, and the person's press is the answer.
import SwiftUI
import SwiftUIWebCore
import Testing
import WebFoundation

#if !os(WASI)
/// What a prompt's answer closure heard.
@MainActor private final class Heard<T> {
    var value: T?
    var all: [T] = []
    func hear(_ value: T) { self.value = value; all.append(value) }
}

extension NotificationCentreSuites {
@Suite(.serialized) @MainActor struct DrawnPhonePromptsTests {
    private let size = CGSize(width: 393, height: 852)
    private var clock = 10.0

    init() {}

    private func phone() -> Runtime {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let runtime = Runtime(environment: environment)
        runtime.safeAreaInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)
        runtime.drawsPhone = true
        runtime.mount(Color.gray.ignoresSafeArea())
        runtime.layout(in: size)
        _ = runtime.render(scale: 2)
        return runtime
    }

    private func frame(_ r: Runtime, _ dt: Double = 1.0 / 60) {
        _ = r.advanceFrame(elapsed: dt)
        r.layout(in: size)
        _ = r.render(scale: 2)
    }

    private func settle(_ r: Runtime, seconds: Double = 1) {
        for _ in 0..<Int(seconds * 60) { frame(r) }
    }

    private func textNodes(_ r: Runtime) -> [(String, CGRect)] {
        r.presentations.flatMap { presentation in
            presentation.descendants(where: { $0 is TextNode }).compactMap { node -> (String, CGRect)? in
                guard let text = node as? TextNode else { return nil }
                // Headless text has no size here: the nearest container that has one.
                var frame = text.frameInRoot
                var current: ViewNode? = text
                while frame.width == 0, let up = current?.parent { frame = up.frameInRoot; current = up }
                return (text.view.resolvedString, frame)
            }
        }
    }

    private mutating func tap(_ r: Runtime, text: String) {
        guard let rect = textNodes(r).first(where: { $0.0 == text })?.1 else { Issue.record("no \(text)"); return }
        let p = CGPoint(x: rect.midX, y: rect.midY)
        r.pointerDown(at: p, type: .mouse, time: clock)
        clock += 0.08
        r.pointerUp(at: p, time: clock)
        clock += 0.01
        frame(r)
    }

    /// Main-actor work a prompt starts: a few turns of the run loop.
    private func turns(_ r: Runtime) async {
        for _ in 0..<10 { await Task.yield(); try? await Task.sleep(nanoseconds: 1_000_000) }
        frame(r)
    }

    @Test mutating func anAlertAsksAndThePressIsTheAnswer() async {
        let r = phone()
        #expect(_PhonePrompts.isPresent)
        let heard = Heard<_PhonePrompts.Answer>()
        let title = "\u{201C}Counter\u{201D} Would Like to Send You Notifications"
        _PhonePrompts.show(.alert(title: title, message: "Notifications may include alerts, sounds, and icon badges. These can be configured in Settings.",
                                  buttons: ["Don\u{2019}t Allow", "Allow"]), fallback: .button(0)) { heard.hear($0) }
        await turns(r)
        settle(r, seconds: 0.5)
        let texts = textNodes(r)
        #expect(texts.map(\.0) == [title, "Notifications may include alerts, sounds, and icon badges. These can be configured in Settings.", "Don\u{2019}t Allow", "Allow"])
        // A press beside it, or Escape, does not answer it.
        #expect(r.dismissTopmostPresentation())
        #expect(r.hasPresentations && heard.value == nil)
        tap(r, text: "Allow")
        settle(r, seconds: 0.5)
        guard case .button(1)? = heard.value else { Issue.record("answer \(String(describing: heard.value))"); return }
        #expect(!r.hasPresentations)
    }

    @Test mutating func promptsWaitTheirTurn() async {
        let r = phone()
        let heard = Heard<String>()
        _PhonePrompts.show(.alert(title: "First", message: "", buttons: ["No", "Yes"]), fallback: .button(0)) { _ in heard.hear("first") }
        _PhonePrompts.show(.alert(title: "Second", message: "", buttons: ["No", "Yes"]), fallback: .button(0)) { _ in heard.hear("second") }
        await turns(r)
        settle(r, seconds: 0.5)
        #expect(r.presentations.count == 1 && textNodes(r).first?.0 == "First")
        tap(r, text: "No")
        settle(r, seconds: 0.5)
        #expect(heard.all == ["first"] && textNodes(r).first?.0 == "Second")
        tap(r, text: "Yes")
        settle(r, seconds: 0.5)
        #expect(heard.all == ["first", "second"] && !r.hasPresentations)
    }

    @Test mutating func healthsSheetListsTheTypesAndWaitsForASwitch() async {
        let r = phone()
        let heard = Heard<_PhonePrompts.Answer>()
        _PhonePrompts.show(.health(share: [], read: ["Steps", "Sleep"], shareExplanation: "", readExplanation: "Your sleep feeds your Scores."),
                           fallback: .health(allowed: nil)) { heard.hear($0) }
        await turns(r)
        settle(r)
        let names = textNodes(r).map(\.0)
        #expect(names.contains("Health Access") && names.contains("Turn On All") && names.contains("App Explanation: Your sleep feeds your Scores."))
        // Sorted by name, as Health lists them.
        #expect((names.firstIndex(of: "Sleep") ?? 99) < (names.firstIndex(of: "Steps") ?? 0))
        // Allow does nothing until a switch is on.
        tap(r, text: "Allow")
        settle(r, seconds: 0.3)
        #expect(heard.value == nil && r.hasPresentations)
        // (Turn On All and the switches are checked in the browser, where text has its size.)
    }

    @Test mutating func healthsSheetDontAllowRefusesAll() async {
        let r = phone()
        let heard = Heard<_PhonePrompts.Answer>()
        _PhonePrompts.show(.health(share: ["Weight"], read: ["Weight"], shareExplanation: "Weigh-ins are saved.", readExplanation: ""),
                           fallback: .health(allowed: [])) { heard.hear($0) }
        await turns(r)
        settle(r)
        tap(r, text: "Don\u{2019}t Allow")
        settle(r)
        guard case .health(nil)? = heard.value else { Issue.record("answer \(String(describing: heard.value))"); return }
    }

    @Test func faceIDsBadgeShowsThenAnswers() async {
        let r = phone()
        let heard = Heard<Bool>()
        _PhonePrompts.show(.faceID, fallback: .done) { _ in heard.hear(true) }
        await turns(r)
        #expect(r.drawnPhone!.needsTime && heard.value == nil)
        // It holds the screen while it shows.
        #expect(r.drawnPhone!.pointerDown(at: CGPoint(x: 200, y: 400), type: .touch, time: 1))
        settle(r, seconds: 1.6)
        #expect(heard.value == true && !r.drawnPhone!.needsTime)
    }
}
}
#endif
