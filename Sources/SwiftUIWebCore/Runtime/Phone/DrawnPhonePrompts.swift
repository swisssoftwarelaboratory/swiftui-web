#if !os(WASI)
import Foundation
#endif
import WebFoundation   // `_PhonePrompts`; never full Foundation on wasm: it links ICU (decisions 0006, 0017)
import WebGraphics

// The drawn iPhone's permission prompts (new-website#666): what iOS shows over an app when it
// asks for notifications, the camera, photos, Face ID, Health or alarms. The frameworks ask
// through `_PhonePrompts` (WebFoundation); the phone shows iOS 27's own alert (the one an
// app's `.alert` draws, new-website#649), Apple Health's access sheet on UIKit's sheet spring,
// or the Face ID badge, one at a time as iOS queues them. The answers are kept by the
// frameworks under `_PhonePrompts.keyPrefix`; a fresh install forgets them.

/// The prompts waiting their turn on the drawn iPhone.
@MainActor
package final class PhonePromptQueue {
    struct Waiting {
        let prompt: _PhonePrompts.Ask
        let answered: @MainActor (_PhonePrompts.Answer) -> Void
    }
    var waiting: [Waiting] = []
    var showing = false
    /// The Face ID badge on screen: how long it has shown, and what runs when it is gone.
    var faceID: (time: Double, done: @MainActor () -> Void)?
}

extension DrawnPhone {
    /// Puts the phone behind `_PhonePrompts` (once, when the first phone appears).
    static func installPrompts() {
        _PhonePrompts.phone = { _DrawnPhoneSystem.isPresent }
        _PhonePrompts.ask = { prompt, answered in
            guard let phone = DrawnPhone.current else { answered(.button(0)); return }
            phone.prompts.waiting.append(.init(prompt: prompt, answered: answered))
            phone.showNextPrompt()
        }
    }

    private func showNextPrompt() {
        guard !prompts.showing, !prompts.waiting.isEmpty else { return }
        let next = prompts.waiting.removeFirst()
        prompts.showing = true
        let finish: @MainActor (_PhonePrompts.Answer) -> Void = { [weak self] answer in
            next.answered(answer)
            self?.prompts.showing = false
            self?.showNextPrompt()
        }
        switch next.prompt {
        case let .alert(title, message, buttons):
            presentAlert(title: title, message: message, buttons: buttons, answered: finish)
        case let .health(share, read, shareExplanation, readExplanation):
            presentHealthSheet(share: share, read: read, shareExplanation: shareExplanation, readExplanation: readExplanation, answered: finish)
        case .faceID:
            showFaceID { finish(.done) }
        }
    }

    // MARK: The alert

    private func presentAlert(title: String, message: String, buttons: [String], answered: @escaping @MainActor (_PhonePrompts.Answer) -> Void) {
        let actions = _PromptButtons(titles: buttons) { index in answered(.button(index)) }
        let body = message.isEmpty ? AnyView(EmptyView()) : AnyView(Text(verbatim: message))
        let view = AnyView(_AlertContent(title: Text(verbatim: title), message: body, actions: AnyView(actions)))
        let node = runtime.present(kind: .alert, view: view, environment: runtime.rootEnvironment, anchor: runtime.root) {}
        // Only a button answers a system alert: Escape and presses beside it do nothing.
        node.options.interactiveDismissDisabled = true
    }

    // MARK: Apple Health's access sheet

    private func presentHealthSheet(share: [String], read: [String], shareExplanation: String, readExplanation: String,
                                    answered: @escaping @MainActor (_PhonePrompts.Answer) -> Void) {
        var node: PresentationNode?
        let sheet = _HealthAccessSheet(share: share, read: read, shareExplanation: shareExplanation, readExplanation: readExplanation) { allowed in
            if let node, node.isMounted { node.dismiss() }
            answered(.health(allowed: allowed))
        }
        node = runtime.present(kind: .sheet, view: AnyView(sheet), environment: runtime.rootEnvironment, anchor: runtime.root) {}
        // Only Don't Allow or Allow closes it, as on iOS: no swipe down.
        node?.options.interactiveDismissDisabled = true
    }

    // MARK: The Face ID badge

    /// The badge's timeline in seconds: in, the face, the tick, out.
    static let faceIDIn: Double = 0.2
    static let faceIDTick: Double = 0.75
    static let faceIDOut: Double = 1.15
    static let faceIDGone: Double = 1.4

    private func showFaceID(done: @escaping @MainActor () -> Void) {
        prompts.faceID = (0, done)
        changed()
    }

    /// Moves the badge on; returns whether it is still on screen.
    func advanceFaceID(elapsed: Double) -> Bool {
        guard let badge = prompts.faceID else { return false }
        let time = badge.time + elapsed
        if time >= Self.faceIDGone {
            prompts.faceID = nil
            runtime.requestRepaint()
            badge.done()
            return false
        }
        prompts.faceID = (time, badge.done)
        runtime.requestRepaint()
        return true
    }

    /// The badge: a rounded glass square in the middle of the screen with the face drawn in
    /// lines, which turns into a tick once the face is recognised. Our own drawing, never
    /// Apple's symbol.
    func paintFaceID(into list: inout DisplayList) {
        guard let time = prompts.faceID?.time else { return }
        let fadeIn = min(1, time / Self.faceIDIn)
        let fadeOut = time > Self.faceIDOut ? max(0, 1 - (time - Self.faceIDOut) / (Self.faceIDGone - Self.faceIDOut)) : 1
        let opacity = min(fadeIn, fadeOut)
        guard opacity > 0 else { return }
        let scale = CGFloat(0.9 + 0.1 * fadeIn)
        let side: CGFloat = 156 * scale
        let rect = CGRect(x: CGFloat(width) / 2 - side / 2, y: CGFloat(height) / 2 - side / 2, width: side, height: side)
        let dark = runtime.rootEnvironment.colorScheme == .dark
        let path = Path(roundedRect: rect, cornerRadius: 34 * scale)
        list.append(.beginGroup(opacity: opacity))
        list.append(.backdropBlur(path, bounds: rect, radius: 30, saturation: 1.6))
        list.append(.fillPath(path, dark ? RGBA(red: 0.17, green: 0.17, blue: 0.18, alpha: 0.82) : RGBA(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.82)))
        let ink = dark ? RGBA(red: 1, green: 1, blue: 1, alpha: 0.9) : RGBA(red: 0.12, green: 0.12, blue: 0.13, alpha: 0.9)
        let glyph = CGRect(x: rect.midX - 32 * scale, y: rect.minY + 30 * scale, width: 64 * scale, height: 64 * scale)
        let style = StrokeStyle(lineWidth: 3.4 * scale, lineCap: .round, lineJoin: .round)
        if time < Self.faceIDTick {
            list.append(.strokePath(Self.faceGlyph(in: glyph), style: style, ink))
        } else {
            var tick = Path()
            tick.move(to: CGPoint(x: glyph.minX + glyph.width * 0.2, y: glyph.minY + glyph.height * 0.52))
            tick.addLine(to: CGPoint(x: glyph.minX + glyph.width * 0.42, y: glyph.minY + glyph.height * 0.74))
            tick.addLine(to: CGPoint(x: glyph.minX + glyph.width * 0.82, y: glyph.minY + glyph.height * 0.28))
            list.append(.strokePath(tick, style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round, lineJoin: .round), ink))
        }
        let font = Font.system(size: 17 * scale, weight: .semibold).resolve(profile: runtime.rootEnvironment.platformProfile)
        let text = "Face ID"
        let layout = runtime.layoutText(text, font: font, width: nil)
        let textWidth = layout.lines.first?.inkWidth ?? layout.size.width
        list.append(.drawText(text, DisplayFont(font), origin: CGPoint(x: rect.midX - textWidth / 2, y: rect.maxY - 26 * scale), ink))
        list.append(.endGroup)
    }

    /// Four corner brackets, two eyes, a nose and a smile, in a 64 pt square.
    static func faceGlyph(in rect: CGRect) -> Path {
        let s = rect.width / 64
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        // Corners: a line in, a quarter round, a line on.
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (p(4, 18), p(4, 4), p(18, 4)), (p(46, 4), p(60, 4), p(60, 18)),
            (p(60, 46), p(60, 60), p(46, 60)), (p(18, 60), p(4, 60), p(4, 46)),
        ]
        for (start, corner, end) in corners {
            path.move(to: start)
            path.addArc(tangent1End: corner, tangent2End: end, radius: 9 * s)
            path.addLine(to: end)
        }
        path.move(to: p(22, 23)); path.addLine(to: p(22, 28))
        path.move(to: p(42, 23)); path.addLine(to: p(42, 28))
        path.move(to: p(32, 23)); path.addLine(to: p(32, 36)); path.addLine(to: p(29, 36))
        path.move(to: p(23, 43)); path.addQuadCurve(to: p(41, 43), control: p(32, 50))
        return path
    }
}

/// A system alert's buttons, left to right, each answering with its index.
private struct _PromptButtons: View {
    let titles: [String]
    let pressed: @MainActor (Int) -> Void

    var body: some View {
        ForEach(0..<titles.count, id: \.self) { index in
            Button(titles[index]) { pressed(index) }
        }
    }
}

/// Apple Health's access sheet as iOS draws it: Don't Allow and Allow in the bar, a plain grey
/// square where Apple's Health icon would be (never Apple's icon), Turn On All, one switch per
/// type the app writes and per type it reads, sorted by name, and the app's explanations.
/// Allow stays off until a switch is on.
private struct _HealthAccessSheet: View {
    let share: [String]
    let read: [String]
    let shareExplanation: String
    let readExplanation: String
    let answered: @MainActor (Set<String>?) -> Void
    @State private var on: Set<String> = []

    private var german: Bool { _PhonePrompts.german }
    private var everything: Set<String> { Set(share.map { "share:" + $0 } + read.map { "read:" + $0 }) }

    var body: some View {
        NavigationStack {
            List {
                // The icon, title and line above the switches, on the sheet's ground, no card.
                Section {
                } header: {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(white: 0.84))
                            .frame(width: 64, height: 64)
                        Text(german ? "Health-Zugriff" : "Health Access")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text(verbatim: german
                             ? "\(_PhonePrompts.quotedName) m\u{00F6}chte auf deine Health-Daten zugreifen und sie aktualisieren."
                             : "\(_PhonePrompts.quotedName) would like to access and update your Health data.")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textCase(nil)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                Section {
                    Button(on == everything ? (german ? "Alle deaktivieren" : "Turn Off All") : (german ? "Alle aktivieren" : "Turn On All")) {
                        on = on == everything ? [] : everything
                    }
                }
                if !share.isEmpty {
                    Section {
                        ForEach(share.sorted(), id: \.self) { name in Toggle(name, isOn: binding("share:" + name)) }
                    } header: {
                        Text(verbatim: german ? "\(_PhonePrompts.quotedName) erlauben, Folgendes zu schreiben:" : "Allow \(_PhonePrompts.quotedName) to Write")
                    } footer: {
                        if !shareExplanation.isEmpty { Text(verbatim: (german ? "Erklärung der App: " : "App Explanation: ") + shareExplanation).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if !read.isEmpty {
                    Section {
                        ForEach(read.sorted(), id: \.self) { name in Toggle(name, isOn: binding("read:" + name)) }
                    } header: {
                        Text(verbatim: german ? "\(_PhonePrompts.quotedName) erlauben, Folgendes zu lesen:" : "Allow \(_PhonePrompts.quotedName) to Read")
                    } footer: {
                        if !readExplanation.isEmpty { Text(verbatim: (german ? "Erklärung der App: " : "App Explanation: ") + readExplanation).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
            .navigationTitle(german ? "Health-Zugriff" : "Health Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(_PhonePrompts.dontAllow) { answered(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(_PhonePrompts.allow) { answered(on) }
                        .disabled(on.isEmpty)
                }
            }
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(get: { on.contains(key) }, set: { if $0 { on.insert(key) } else { on.remove(key) } })
    }
}
