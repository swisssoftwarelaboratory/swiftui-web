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
        case let .appleID(ask):
            presentAppleIDSheet(ask, answered: finish)
        case let .photoLibrary(title, message, buttons):
            presentPhotoLibraryAlert(title: title, message: message, buttons: buttons, answered: finish)
        case let .selectPhotos(selected):
            presentSelectPhotos(selected: selected, answered: finish)
        }
    }

    // MARK: The photo library's ask (new-website#708)

    /// iOS 27's full-access alert: the app's text, then a strip of the phone's newest photos,
    /// their count and Apple's line on what photos carry, then the three buttons stacked.
    private func presentPhotoLibraryAlert(title: String, message: String, buttons: [String],
                                          answered: @escaping @MainActor (_PhonePrompts.Answer) -> Void) {
        let actions = _PromptButtons(titles: buttons) { index in answered(.button(index)) }
        let body = AnyView(_PhotoAccessPreview(message: message))
        let view = AnyView(_AlertContent(title: Text(verbatim: title), message: body, actions: AnyView(actions)))
        let node = runtime.present(kind: .alert, view: view, environment: runtime.rootEnvironment, anchor: runtime.root) {}
        node.options.interactiveDismissDisabled = true
    }

    /// Select Photos' sheet: the photos picker's sheet with any number marked; its check button
    /// or X (or a pull down) closes it, and what is marked then is the answer.
    private func presentSelectPhotos(selected: [String], answered: @escaping @MainActor (_PhonePrompts.Answer) -> Void) {
        var node: PresentationNode?
        var done = false
        let finish: @MainActor ([String]) -> Void = { ids in
            guard !done else { return }
            done = true
            if let node, node.isMounted { node.dismiss() }
            answered(.photos(ids))
        }
        let sheet = _PhotosPickerSheet(limit: nil, preselected: selected, pick: { finish($0) }, cancel: { finish(selected) })
        node = runtime.present(kind: .sheet, view: AnyView(sheet), environment: runtime.rootEnvironment, anchor: runtime.root) {
            finish(selected)
        }
    }

    // MARK: Sign in with Apple's sheet (new-website#707)

    /// iOS's sheet over the dimmed app, floating at its content's height; Continue runs Face ID
    /// over it, then the sheet goes and the app gets its answer. Only its buttons close it.
    private func presentAppleIDSheet(_ ask: _PhonePrompts.AppleIDAsk, answered: @escaping @MainActor (_PhonePrompts.Answer) -> Void) {
        var node: PresentationNode?
        let close: @MainActor () -> Void = { if let node, node.isMounted { node.dismiss() } }
        let hasIcon = runtime.assetCatalog.image(named: appIconName) != nil
        let sheet = _AppleIDSheet(ask: ask, iconName: hasIcon ? appIconName : nil) { [weak self] choice in
            guard let choice else { close(); answered(.cancelled); return }
            guard let self else { return }
            self.showFaceID {
                close()
                answered(.appleID(name: choice.name, hideEmail: choice.hideEmail))
            }
        }
        node = runtime.present(kind: .sheet, view: AnyView(sheet), environment: runtime.rootEnvironment, anchor: runtime.root) {}
        node?.options.fitsContent = true
        node?.options.interactiveDismissDisabled = true
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

/// What the photo library's alert shows under its title: the app's text in the alert's grey,
/// then, measured from iOS 27 (320 pt alert): 16 below, the four newest photos edge to edge
/// across the buttons' width, 66 pt tall with rounded ends; the count in bold and Apple's line,
/// in the primary colour, 8 further out than the text.
private struct _PhotoAccessPreview: View {
    let message: String
    @ObservedObject private var library = _PhotoLibrary.shared

    init(message: String) { self.message = message }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.isEmpty { Text(verbatim: message).fixedSize(horizontal: false, vertical: true) }
            if !library.photos.isEmpty {
                HStack(spacing: 1) {
                    ForEach(Array(library.photos.prefix(4))) { photo in
                        Color(white: 0.85)
                            .overlay {
                                Image(source: .url(photo.url, pixelSize: CGSize(width: photo.pixelWidth, height: photo.pixelHeight), scale: 1), label: nil)
                                    .resizable().scaledToFill()
                            }
                            .clipped()
                    }
                }
                .frame(height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, -15.5)
                .padding(.top, 16)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: _PhotoAccess.countLine(library.photos.count))
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: _PhotoAccess.metadataLine)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, -7.5)
            .padding(.top, 13)
            .padding(.bottom, 28)
        }
        .task { await library.load() }
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

/// Sign in with Apple's sheet as iOS 27 draws it (measured from iOS 26's, new-website#707): the
/// title and a round close button, the app's icon beside a line naming the Apple Account, then
/// for a first sign-in the name and the email choice in two rounded groups, and Continue. Words
/// and our own drawings only, never Apple's logo.
private struct _AppleIDSheet: View {
    struct Choice { let name: String; let hideEmail: Bool }

    let ask: _PhonePrompts.AppleIDAsk
    /// The app's icon set in its catalog; a grey square without one.
    let iconName: String?
    /// Continue's choice, or nil for the close button.
    let answered: @MainActor (Choice?) -> Void

    @State private var name = _PhonePrompts.AppleAccount.fullName
    @State private var hideEmail = true
    @State private var pressed = false
    @Environment(\.colorScheme) private var colorScheme

    private typealias Account = _PhonePrompts.AppleAccount
    private var german: Bool { _PhonePrompts.german }
    private var groupFill: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.5) }
    private var quotedEmail: String { german ? "\u{201E}\(Account.email)\u{201C}" : "\u{201C}\(Account.email)\u{201D}" }

    private var line: String {
        let app = _PhonePrompts.appName
        if ask.returning {
            return german ? "M\u{00F6}chtest du dich mit deinem Apple Account \(quotedEmail) bei \(app) anmelden?"
                : "Do you want to sign in to \(app) with your Apple Account \(quotedEmail)?"
        }
        return german ? "Erstelle einen Account f\u{00FC}r \(app) mit deinem Apple Account \(quotedEmail)."
            : "Create an account for \(app) using your Apple Account \(quotedEmail)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(german ? "Mit Apple anmelden" : "Sign in with Apple")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .padding(.leading, 3)
                Spacer(minLength: 8)
                Button { if !pressed { answered(nil) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(groupFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(german ? "Schlie\u{00DF}en" : "Close"))
            }
            .padding(.top, 15)
            HStack(alignment: .top, spacing: 10) {
                icon
                Text(verbatim: line)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 5)
            .padding(.top, 19)
            if !ask.returning, ask.asksName {
                nameGroup.padding(.top, 18)
            }
            if !ask.returning, ask.asksEmail {
                emailGroup.padding(.top, ask.asksName ? 10 : 18)
            }
            HStack {
                Spacer()
                Button { continuePressed() } label: {
                    Text(german ? "Fortfahren" : "Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 24)
                        .frame(height: 42)
                        .background(Capsule().fill(Color(red: 0.0, green: 0.53, blue: 1.0)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 16)
    }

    private func continuePressed() {
        guard !pressed else { return }
        pressed = true
        let asked = !ask.returning && ask.asksName
        answered(Choice(name: asked ? name : "", hideEmail: !ask.returning && ask.asksEmail && hideEmail))
    }

    @ViewBuilder private var icon: some View {
        if let iconName {
            Image(decorative: iconName)
                .resizable()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.84))
                .frame(width: 52, height: 52)
        }
    }

    /// A dark rounded square with a white drawing (our own, not Apple's symbols).
    private func glyph<S: Shape>(_ shape: S, flap: Bool = false) -> some View {
        ZStack {
            shape.fill(Color.white)
            if flap { _EnvelopeFlap().stroke(Color(white: 0.17), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)) }
        }
            .frame(width: 18, height: 18)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.17)))
    }

    private var nameGroup: some View {
        HStack(spacing: 16) {
            glyph(_PersonGlyph())
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Name")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.primary)
                TextField(german ? "Vor- und Nachname" : "First and Last Name", text: $name)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.secondary)
            }
            if !name.isEmpty {
                Button { name = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, 9)
        .frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(groupFill))
    }

    private var emailGroup: some View {
        HStack(alignment: .top, spacing: 16) {
            glyph(_EnvelopeGlyph(), flap: true).padding(.top, 13)
            VStack(alignment: .leading, spacing: 0) {
                emailRow(german ? "E-Mail-Adresse teilen" : "Share My Email", detail: Account.email, chosen: !hideEmail) { hideEmail = false }
                Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)
                emailRow(german ? "E-Mail-Adresse verbergen" : "Hide My Email",
                         detail: (german ? "Weiterleiten an:" : "Forward To:") + "\n" + Account.relayEmail, chosen: hideEmail) { hideEmail = true }
            }
        }
        .padding(.leading, 17)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(groupFill))
    }

    private func emailRow(_ title: String, detail: String, chosen: Bool, choose: @escaping @MainActor () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.primary)
                    // One line each, like iOS: a long address shrinks rather than breaking.
                    ForEach(detail.split(separator: "\n").map(String.init), id: \.self) { part in
                        Text(verbatim: part)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                Spacer(minLength: 0)
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.2).frame(width: 20, height: 20)
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A head and shoulders, filled, in a square.
private struct _PersonGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        var path = Path(ellipseIn: CGRect(x: rect.minX + 5.5 * s, y: rect.minY + 1 * s, width: 7 * s, height: 7 * s))
        path.addPath(Path(roundedRect: CGRect(x: rect.minX + 2 * s, y: rect.minY + 10 * s, width: 14 * s, height: 7 * s), cornerRadius: 3.5 * s))
        return path
    }
}

/// A closed envelope's body.
private struct _EnvelopeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        return Path(roundedRect: CGRect(x: rect.minX, y: rect.minY + 3 * s, width: 18 * s, height: 12.5 * s), cornerRadius: 1.8 * s)
    }
}

/// The envelope's flap, drawn over its body.
private struct _EnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 18
        var flap = Path()
        flap.move(to: CGPoint(x: rect.minX + 0.8 * s, y: rect.minY + 4 * s))
        flap.addLine(to: CGPoint(x: rect.minX + 9 * s, y: rect.minY + 10.4 * s))
        flap.addLine(to: CGPoint(x: rect.minX + 17.2 * s, y: rect.minY + 4 * s))
        return flap
    }
}
