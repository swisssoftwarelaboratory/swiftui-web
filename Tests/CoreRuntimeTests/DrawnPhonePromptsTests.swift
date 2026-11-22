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

    // MARK: Sign in with Apple (new-website#707)

    @Test mutating func appleIDsSheetAsksThenFaceIDThenAnswers() async {
        let r = phone()
        let heard = Heard<_PhonePrompts.Answer>()
        _PhonePrompts.show(.appleID(.init(returning: false, asksName: true, asksEmail: true)), fallback: .cancelled) { heard.hear($0) }
        await turns(r)
        settle(r)
        let names = textNodes(r).map(\.0)
        for word in ["Sign in with Apple", "Name", "Share My Email", "Hide My Email", "mara.keller@icloud.com", "Continue"] {
            #expect(names.contains(word), "missing \(word)")
        }
        #expect(names.contains { $0.hasPrefix("Create an account for") })
        // Floating at its content's height, in from the sides.
        let panel = r.presentations.first!.panel
        #expect(panel.minX == 6 && panel.maxY == 852 - 6 && panel.height < 600)
        tap(r, text: "Continue")
        // Face ID over the sheet, then the answer.
        #expect(r.drawnPhone!.needsTime && heard.value == nil && r.hasPresentations)
        settle(r, seconds: 2)
        guard case let .appleID(name, hide)? = heard.value else { Issue.record("answer \(String(describing: heard.value))"); return }
        #expect(name == "Mara Keller" && hide)
        #expect(!r.hasPresentations)
    }

    @Test mutating func aReturningSignInOnlyAsksToContinue() async {
        let r = phone()
        let heard = Heard<_PhonePrompts.Answer>()
        _PhonePrompts.show(.appleID(.init(returning: true, asksName: true, asksEmail: true)), fallback: .cancelled) { heard.hear($0) }
        await turns(r)
        settle(r)
        let names = textNodes(r).map(\.0)
        #expect(!names.contains("Share My Email") && !names.contains("Name"))
        #expect(names.contains { $0.hasPrefix("Do you want to sign in to") })
        // Only its buttons close it.
        #expect(r.dismissTopmostPresentation())
        #expect(r.hasPresentations && heard.value == nil)
    }

    // MARK: The photo library (new-website#708)

    private func status<T: Sendable>(_ ask: (@escaping @MainActor @Sendable (T) -> Void) -> Void) -> Heard<T> {
        let heard = Heard<T>()
        ask { heard.hear($0) }
        return heard
    }

    @Test mutating func photoLibrarysAskShowsTheStripsWordsAndKeepsFullAccess() async {
        let r = phone()
        _PhonePrompts.forgetAnswers()
        #expect(_PhotoAccess.readWrite == .notDetermined && _PhotoAccess.addOnly == .notDetermined)
        let heard = status(_PhotoAccess.requestReadWrite)
        await turns(r)
        settle(r, seconds: 0.5)
        let names = textNodes(r).map(\.0)
        #expect(names.first == "Allow \u{201C}App\u{201D} to access your photo library?")
        #expect(names.contains("0 Photos") && names.contains(_PhotoAccess.metadataLine))
        #expect(Array(names.suffix(3)) == ["Select Photos", "Allow Full Access", "Don\u{2019}t Allow"])
        // Three buttons stack, top to bottom in iOS's order.
        let frames = textNodes(r).suffix(3).map(\.1.midY)
        #expect(frames == frames.sorted() && Set(frames).count == 3)
        // Only a button answers it.
        #expect(r.dismissTopmostPresentation())
        #expect(r.hasPresentations && heard.value == nil)
        tap(r, text: "Allow Full Access")
        settle(r, seconds: 0.5)
        await turns(r)
        #expect(heard.value == .authorized && !r.hasPresentations)
        // Full access allows adding too, and nothing asks again.
        #expect(_PhotoAccess.readWrite == .authorized && _PhotoAccess.addOnly == .authorized)
        let again = status(_PhotoAccess.requestAddOnly)
        await turns(r)
        #expect(again.value == .authorized && !r.hasPresentations)
        _PhonePrompts.forgetAnswers()
    }

    @Test mutating func addingIsAskedOnItsOwnAndChangesTheFullAsk() async {
        let r = phone()
        _PhonePrompts.forgetAnswers()
        let add = status(_PhotoAccess.requestAddOnly)
        await turns(r)
        settle(r, seconds: 0.5)
        #expect(textNodes(r).map(\.0) == ["Allow \u{201C}App\u{201D} to add photos and videos to your photo library?", "Don\u{2019}t Allow", "Allow"])
        tap(r, text: "Allow")
        settle(r, seconds: 0.5)
        await turns(r)
        #expect(add.value == .authorized && _PhotoAccess.readWrite == .notDetermined)
        // Once adding is allowed, the full ask says "full access" and its last button keeps adding only.
        let full = status(_PhotoAccess.requestReadWrite)
        await turns(r)
        settle(r, seconds: 0.5)
        let names = textNodes(r).map(\.0)
        #expect(names.first == "Allow \u{201C}App\u{201D} full access to your photo library?")
        #expect(names.last == "Keep Add Only")
        tap(r, text: "Keep Add Only")
        settle(r, seconds: 0.5)
        await turns(r)
        #expect(full.value == .denied && _PhotoAccess.addOnly == .authorized)
        _PhonePrompts.forgetAnswers()
    }

    @Test mutating func addingIsStillAskedAfterFullAccessWasRefused() async {
        let r = phone()
        _PhonePrompts.forgetAnswers()
        let full = status(_PhotoAccess.requestReadWrite)
        await turns(r)
        settle(r, seconds: 0.5)
        tap(r, text: "Don\u{2019}t Allow")
        settle(r, seconds: 0.5)
        await turns(r)
        #expect(full.value == .denied && _PhotoAccess.addOnly == .notDetermined)
        _ = status(_PhotoAccess.requestAddOnly)
        await turns(r)
        settle(r, seconds: 0.5)
        #expect(textNodes(r).first?.0 == "Allow \u{201C}App\u{201D} to add photos and videos to your photo library?")
        _PhonePrompts.forgetAnswers()
    }

    @Test mutating func selectPhotosOpensThePhotoSheetAndLimits() async {
        let r = phone()
        _PhonePrompts.forgetAnswers()
        let full = status(_PhotoAccess.requestReadWrite)
        await turns(r)
        settle(r, seconds: 0.5)
        tap(r, text: "Select Photos")
        settle(r, seconds: 0.5)
        await turns(r)
        settle(r)
        // The photo sheet is up; the app hears nothing until it closes.
        #expect(r.hasPresentations && full.value == nil)
        #expect(r.presentations.last?.kind == .sheet)
        #expect(r.dismissTopmostPresentation())
        settle(r)
        await turns(r)
        #expect(full.value == .limited && _PhotoAccess.selected.isEmpty && !r.hasPresentations)
        // The app can open it again while limited; a full library never shows it.
        let more = status(_PhotoAccess.choosePhotos)
        await turns(r)
        settle(r)
        #expect(r.hasPresentations && more.value == nil)
        #expect(r.dismissTopmostPresentation())
        settle(r)
        await turns(r)
        #expect(more.value == [] && !r.hasPresentations)
        _PhonePrompts.forgetAnswers()
        _PhonePrompts.setAnswer("photos", "full")
        let none = status(_PhotoAccess.choosePhotos)
        await turns(r)
        settle(r)
        #expect(none.value == [] && !r.hasPresentations)
        _PhonePrompts.forgetAnswers()
    }

    @Test func appleAccountIdsAreStable() {
        let user = _PhonePrompts.AppleAccount.userID
        #expect(user == _PhonePrompts.AppleAccount.userID)
        let parts = user.split(separator: ".")
        #expect(parts.count == 3 && parts[0].count == 6 && parts[1].count == 32 && parts[2].count == 4)
        #expect(_PhonePrompts.AppleAccount.relayEmail.hasSuffix("@privaterelay.appleid.com"))
    }
}
}
#endif
