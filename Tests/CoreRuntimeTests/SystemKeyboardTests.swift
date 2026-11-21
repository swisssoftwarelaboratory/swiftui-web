// The drawn iPhone keyboard (new-website#648): it slides up on focus and down on blur on UIKit's
// keyboard spring, a press is a finger (lifting types the key under it, dragging moves to
// another key), capitals at a sentence's start, shift and caps lock, double space, the 123 page,
// accents on a long press, delete repeating, and the viewer's own keys holding the drawn ones.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Observable private final class SheetModel { var open = false }

@Suite @MainActor struct SystemKeyboardTests {
    static let screen = CGSize(width: 393, height: 852)

    private func runtime(_ box: KeyboardTextBox, language: String = "de-CH", submitted: KeyboardTextBox? = nil) -> Runtime {
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.drawsSoftwareKeyboard = true
        r.softwareKeyboardLanguage = language
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        r.mount(VStack {
            Spacer()
            TextField("Message", text: binding).submitLabel(.send).onSubmit { submitted?.value += "sent" }
        })
        r.layout(in: Self.screen)
        return r
    }

    private func focus(_ r: Runtime) {
        let field = r.semanticsTree().first { $0.textInput != nil }!
        r.textField(field.identifier, focused: true)
        settle(r)
    }

    private func settle(_ r: Runtime, seconds: Double = 1) {
        var t = 0.0
        while t < seconds { _ = r.advanceFrame(elapsed: 1.0 / 60); r.layout(in: Self.screen); t += 1.0 / 60 }
    }

    /// The window point at a key's centre.
    private func point(of kind: KeyboardKeyKind, in r: Runtime) -> CGPoint {
        let keyboard = r.systemKeyboard
        let key = keyboard.keys.first { $0.kind == kind }!
        return CGPoint(x: keyboard.frame.minX + key.frame.midX, y: keyboard.frame.minY + key.frame.midY)
    }

    private func tap(_ kind: KeyboardKeyKind, _ r: Runtime) {
        let p = point(of: kind, in: r)
        r.pointerDown(at: p, type: .mouse)
        _ = r.advanceFrame(elapsed: 0.05)
        r.pointerUp(at: p)
        _ = r.advanceFrame(elapsed: 0.05)
    }

    private func letter(_ c: String) -> KeyboardKeyKind { .character(c) }

    /// A sheet coming up over a focused field takes its focus and the keyboard goes down;
    /// closing it gives both back, as in the iOS 27 simulator (a focused field, then
    /// `.photosPicker`, new-website#667).
    @Test func aSheetOverTheFieldTakesTheKeyboardAndGivesItBack() {
        let model = SheetModel()
        let box = KeyboardTextBox("")
        let r = Runtime()
        r.hostPlatformProfile = .iOS
        r.drawsSoftwareKeyboard = true
        r.softwareKeyboardLanguage = "en"
        r.mount(VStack {
            Spacer()
            TextField("Message", text: Binding(get: { box.value }, set: { box.value = $0 }))
        }
        .sheet(isPresented: Binding(get: { model.open }, set: { model.open = $0 })) { Text("Photos") })
        r.layout(in: Self.screen)
        focus(r)
        let field = r.focusedTextFieldIdentifier
        #expect(field != nil && r.systemKeyboard.isVisible)
        model.open = true
        settle(r)
        #expect(r.hasPresentations)
        #expect(r.focusedTextFieldIdentifier == nil)
        #expect(!r.systemKeyboard.isVisible && r.keyboardInset == 0)
        model.open = false
        settle(r, seconds: 1.5)
        #expect(!r.hasPresentations)
        #expect(r.focusedTextFieldIdentifier == field)
        #expect(r.systemKeyboard.isVisible && r.keyboardInset == 328)
    }

    @Test func slidesUpOnFocusOnUIKitsSpringAndTheSafeAreaFollows() {
        let box = KeyboardTextBox("")
        let r = runtime(box)
        var frames: [CGRect?] = []
        r.onKeyboardFrameChange = { frames.append($0) }
        #expect(!r.systemKeyboard.isVisible)
        let field = r.semanticsTree().first { $0.textInput != nil }!
        r.textField(field.identifier, focused: true)
        #expect(frames == [CGRect(x: 0, y: 852 - 328, width: 393, height: 328)])
        #expect(r.keyboardInset == 328)
        // Critically damped at ω ≈ 18 /s: about two thirds up after 0.1 s, all the way after 0.6 s.
        _ = r.advanceFrame(elapsed: 0.1)
        let early = r.systemKeyboard.lift.position
        #expect(early > 328 * 0.5 && early < 328 * 0.85)
        settle(r)
        #expect(abs(r.systemKeyboard.frame.minY - (852 - 328)) < 0.01, "\(r.systemKeyboard.frame) \(r.systemKeyboard.lift)")
        // The field moved up above the keyboard.
        let moved = r.semanticsTree().first { $0.textInput != nil }!
        #expect(moved.frame.maxY <= 852 - 328 + 0.5)
        // Blur: it slides down, and the frame goes away.
        r.textField(field.identifier, focused: false)
        #expect(frames.last == .some(nil))
        settle(r)
        #expect(!r.systemKeyboard.isVisible && r.keyboardInset == 0)
    }

    @Test func aTapTypesTheKeyWithCapitalsAtTheSentencesStart() {
        let box = KeyboardTextBox("")
        let r = runtime(box)
        focus(r)
        #expect(r.systemKeyboard.shift == .on)
        tap(letter("h"), r)
        #expect(box.value == "H")
        #expect(r.systemKeyboard.shift == .off)
        tap(letter("a"), r)
        tap(letter("l"), r)
        #expect(box.value == "Hal")
        // Double space: ". " and capitals again.
        tap(.space, r)
        tap(.space, r)
        #expect(box.value == "Hal. ")
        #expect(r.systemKeyboard.shift == .on)
        tap(letter("ü"), r)
        #expect(box.value == "Hal. Ü")
    }

    @Test func shiftTogglesAndADoubleTapLocks() {
        let box = KeyboardTextBox("x")
        let r = runtime(box)
        focus(r)
        #expect(r.systemKeyboard.shift == .off)
        tap(.shift, r)
        #expect(r.systemKeyboard.shift == .on)
        tap(letter("q"), r)
        tap(letter("q"), r)
        #expect(box.value == "xQq")
        tap(.shift, r)
        tap(.shift, r)
        #expect(r.systemKeyboard.shift == .locked)
        tap(letter("w"), r)
        tap(letter("w"), r)
        #expect(box.value == "xQqWW")
    }

    @Test func draggingMovesToAnotherKeyAndOnlyTheLastTypes() {
        let box = KeyboardTextBox("x")
        let r = runtime(box)
        focus(r)
        r.pointerDown(at: point(of: letter("q"), in: r))
        r.pointerMoved(to: point(of: letter("e"), in: r))
        #expect(r.systemKeyboard.finger?.key?.kind == letter("e"))
        r.pointerUp(at: point(of: letter("e"), in: r))
        #expect(box.value == "xe")
        // Dragged off the keys (up into the app): nothing.
        r.pointerDown(at: point(of: letter("r"), in: r))
        r.pointerMoved(to: CGPoint(x: 200, y: 300))
        r.pointerUp(at: CGPoint(x: 200, y: 300))
        #expect(box.value == "xe")
    }

    @Test func holdingALetterOpensItsAccents() {
        let box = KeyboardTextBox("x")
        let r = runtime(box)
        focus(r)
        let a = point(of: letter("a"), in: r)
        r.pointerDown(at: a)
        _ = r.advanceFrame(elapsed: 0.5)
        let accents = try! #require(r.systemKeyboard.finger?.accents)
        #expect(accents.first == "a" && accents.contains("à"))
        // One cell to the right picks the second accent.
        r.pointerMoved(to: CGPoint(x: a.x + KeyboardMetrics.accentCell.width, y: a.y))
        r.pointerUp(at: CGPoint(x: a.x + KeyboardMetrics.accentCell.width, y: a.y))
        #expect(box.value == "x" + accents[1])
    }

    @Test func holdingDeleteRepeats() {
        let box = KeyboardTextBox("abcdefghij")
        let r = runtime(box)
        focus(r)
        let p = point(of: .delete, in: r)
        r.pointerDown(at: p)
        #expect(box.value == "abcdefghi")
        for _ in 0..<60 { _ = r.advanceFrame(elapsed: 1.0 / 60) }   // 1 s: one at 0.5 s, then every 0.1 s
        r.pointerUp(at: p)
        #expect(box.value.count <= 4 && box.value.count >= 2)
    }

    @Test func pagesAndSpaceGoesBackToLetters() {
        let box = KeyboardTextBox("x")
        let r = runtime(box)
        focus(r)
        tap(.page(.numbers), r)
        #expect(r.systemKeyboard.page == .numbers)
        tap(letter("€"), r)
        tap(.page(.symbols), r)
        tap(letter("£"), r)
        tap(.space, r)
        #expect(box.value == "x€£ " && r.systemKeyboard.page == .letters)
    }

    @Test func returnSubmitsTheField() {
        let box = KeyboardTextBox("Hi")
        let submitted = KeyboardTextBox("")
        let r = runtime(box, submitted: submitted)
        focus(r)
        #expect(r.systemKeyboard.traits?.returnKey == .send)
        tap(.return, r)
        #expect(submitted.value == "sent")
    }

    @Test func layoutsFollowTheLanguage() {
        #expect(KeyboardLanguage(languageIdentifier: "de-CH").letterRows[0].joined() == "qwertzuiopü")
        #expect(KeyboardLanguage(languageIdentifier: "en").letterRows[0].joined() == "qwertyuiop")
        #expect(KeyboardLanguage(languageIdentifier: "fr-CH") == .swissFrench)
        // The measured key frames: Q at 7, 28.33 wide (32 on a 10-key row); space 186.33 wide.
        let keys = KeyboardLanguage.swissGerman.keys(page: .letters)
        #expect(abs(keys[0].frame.minX - 7) < 0.01 && abs(keys[0].frame.width - 28.33) < 0.01)
        #expect(keys.first { $0.kind == .space }?.frame.width == 186.33)
        let us = KeyboardLanguage.usEnglish.keys(page: .letters)
        #expect(abs(us[0].frame.minX - 7) < 0.01 && abs(us[0].frame.width - 32) < 0.01)
    }

    @Test func theViewersOwnKeysHoldTheDrawnOnes() {
        let box = KeyboardTextBox("x")
        let r = runtime(box)
        focus(r)
        tap(.page(.numbers), r)
        r.softwareKeyboardHardwareKeyDown("ü")
        #expect(r.systemKeyboard.page == .letters)
        #expect(r.systemKeyboard.hardwareKey?.kind == letter("ü"))
        r.softwareKeyboardHardwareKeysUp()
        #expect(r.systemKeyboard.hardwareKey == nil)
        r.softwareKeyboardHardwareKeyDown("7")
        #expect(r.systemKeyboard.page == .numbers && r.systemKeyboard.hardwareKey?.kind == letter("7"))
    }

    @Test func nothingWithoutTheHostsAskOrOffTheIPhoneLook() {
        let box = KeyboardTextBox("")
        let r = runtime(box)
        r.drawsSoftwareKeyboard = false
        focus(r)
        #expect(!r.systemKeyboard.isVisible && r.keyboardInset == 0)
    }

    @Test func swissFrenchsAccentKeyFollowsTheLetterBeforeIt() {
        let box = KeyboardTextBox("x")
        let r = runtime(box, language: "fr-CH")
        focus(r)
        #expect(!r.systemKeyboard.keys.contains { $0.kind == letter("é") })
        #expect(r.systemKeyboard.accentKeyMark == "\u{2019}")
        tap(letter("e"), r)
        #expect(r.systemKeyboard.accentKeyMark == "\u{B4}")
        tap(.accent, r)
        tap(letter("a"), r)
        tap(.accent, r)
        tap(letter("l"), r)
        tap(.accent, r)
        #expect(box.value == "xéàl\u{2019}")
        // Q at 7 and the accent key ending row 2 at the tenth place, 32 wide.
        let accent = r.systemKeyboard.keys.first { $0.kind == .accent }!
        #expect(abs(accent.frame.minX - (7 + 9 * 38.67)) < 0.01 && abs(accent.frame.width - 32) < 0.01)
    }

    @Test func sentenceStarts() {
        #expect(SystemKeyboard.isSentenceStart(""))
        #expect(SystemKeyboard.isSentenceStart("Hi. "))
        #expect(SystemKeyboard.isSentenceStart("Hi!  "))
        #expect(!SystemKeyboard.isSentenceStart("Hi."))
        #expect(!SystemKeyboard.isSentenceStart("Hi "))
        #expect(SystemKeyboard.isSentenceStart("Hi\n"))
    }
}

private final class KeyboardTextBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}
#endif
