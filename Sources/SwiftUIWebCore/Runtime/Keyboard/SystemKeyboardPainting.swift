#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
// How the drawn keyboard looks (new-website#619): colours sampled from the iOS 27 simulator's
// screenshots (`prototype-619-keyboard/ref/`), every key the same colour, no shadow; our own
// drawn icons only, never SF Symbols; text in the viewer's system font.

extension SystemKeyboard {
    struct Palette {
        var panel, key, keyDown, ink, tag, divider, bubble, accentOn: RGBA
        var blue = RGBA(r: 0, g: 122, b: 255, a: 1)
        var blueDown = RGBA(r: 51, g: 149, b: 255, a: 1)

        static let light = Palette(panel: RGBA(r: 226, g: 227, b: 232, a: 1), key: RGBA(r: 255, g: 255, b: 255, a: 1),
                                   keyDown: RGBA(r: 223, g: 223, b: 223, a: 1), ink: RGBA(r: 0, g: 0, b: 0, a: 1),
                                   tag: RGBA(r: 142, g: 142, b: 147, a: 1), divider: RGBA(r: 201, g: 202, b: 206, a: 1),
                                   bubble: RGBA(r: 255, g: 255, b: 255, a: 1), accentOn: RGBA(r: 0, g: 122, b: 255, a: 1))
        static let dark = Palette(panel: RGBA(r: 32, g: 32, b: 32, a: 1), key: RGBA(r: 68, g: 68, b: 68, a: 1),
                                  keyDown: RGBA(r: 103, g: 103, b: 103, a: 1), ink: RGBA(r: 255, g: 255, b: 255, a: 1),
                                  tag: RGBA(r: 142, g: 142, b: 147, a: 1), divider: RGBA(r: 58, g: 58, b: 60, a: 1),
                                  bubble: RGBA(r: 80, g: 80, b: 80, a: 1), accentOn: RGBA(r: 0, g: 122, b: 255, a: 1))
    }

    private var palette: Palette { runtime.rootEnvironment._isDark ? .dark : .light }

    private func font(_ size: CGFloat, weight: FontWeight = .regular) -> ResolvedFont {
        ResolvedFont(family: "system", size: size, weight: weight, italic: false, textStyle: nil, profile: "iOS")
    }

    /// Draws `text` centred on `center`: capitals and figures on their cap height, lower case on
    /// its x-height, as the keys set them.
    private func drawCentered(_ text: String, font: ResolvedFont, center: CGPoint, color: RGBA, context: PaintContext, into list: inout DisplayList) {
        let width = runtime.textEngine.layout(text, font: font, width: nil).size.width
        let lower = text.count == 1 && text.lowercased() == text && text.uppercased() != text
        let rise = font.size * (lower ? 0.26 : 0.355)
        let origin = context.absolutePoint(CGPoint(x: center.x - width / 2, y: center.y + rise))
        list.append(.drawText(text, DisplayFont(font), origin: origin, color))
    }

    /// Paints the keyboard (and over it, the held key's bubble or the accent row).
    package func paint(into list: inout DisplayList, context: PaintContext) {
        guard isVisible else { return }
        let p = palette
        let origin = frame.origin
        let ctx = PaintContext(origin: CGPoint(x: context.origin.x + origin.x, y: context.origin.y + context.round(origin.y)), scale: context.scale)
        let width = frame.width
        // The panel runs past the screen's bottom so a spring's overshoot never shows a gap.
        let panel = CGRect(x: 0, y: 0, width: width, height: height + 60)
        list.append(.fillPath(Path(roundedRect: ctx.absoluteRect(panel), cornerRadii: RectangleCornerRadii(topLeading: KeyboardMetrics.cornerRadius, topTrailing: KeyboardMetrics.cornerRadius), style: .continuous), p.panel))
        paintSuggestions(p, context: ctx, into: &list)
        let held = finger?.accents == nil ? (finger?.key ?? hardwareKey) : finger?.key
        let keys = self.keys
        for key in keys { paintKey(key, held: key == held, palette: p, context: ctx, into: &list) }
        if !showsEmoji {
            // The globe and the microphone under the keys.
            let y = KeyboardMetrics.iconRowCenterY
            Self.globe(list: &list, center: ctx.absolutePoint(CGPoint(x: KeyboardMetrics.globeCenterX * width / KeyboardMetrics.width, y: y)), scale: 1, color: p.ink)
            Self.mic(list: &list, center: ctx.absolutePoint(CGPoint(x: KeyboardMetrics.micCenterX * width / KeyboardMetrics.width, y: y)), color: p.ink)
        }
        if let press = finger, let accents = press.accents {
            paintAccents(accents, frame: press.accentFrame, pick: press.pick, palette: p, context: ctx, into: &list)
        } else if let key = held, case .character(let character) = key.kind {
            let label = finger == nil && hardwareKey != nil && !hardwareLabel.isEmpty ? hardwareLabel : label(for: character)
            paintBubble(label, over: key.frame, palette: p, context: ctx, into: &list)
        }
    }

    private func label(for character: String) -> String {
        page == .letters && !showsEmoji && capitals ? character.uppercased() : character
    }

    private func paintSuggestions(_ p: Palette, context: PaintContext, into list: inout DisplayList) {
        let width = frame.width
        guard !showsEmoji else { return }
        for i in 1...2 {
            let x = width * CGFloat(i) / 3
            list.append(.fillRect(context.absoluteRect(CGRect(x: x - 0.5, y: 13, width: 1, height: 26)), p.divider.multiplyingAlpha(by: runtime.rootEnvironment._isDark ? 1 : 0.9)))
        }
        let word = currentWord
        if !word.isEmpty {
            let quoted = language == .swissFrench ? "\u{AB}\u{202F}\(word)\u{202F}\u{BB}" : language == .swissGerman ? "\u{201E}\(word)\u{201C}" : "\u{201C}\(word)\u{201D}"
            drawCentered(quoted, font: font(17), center: CGPoint(x: width / 6, y: 26), color: p.ink, context: context, into: &list)
        }
    }

    private func paintKey(_ key: KeyboardKey, held: Bool, palette p: Palette, context: PaintContext, into list: inout DisplayList) {
        let rect = context.absoluteRect(key.frame)
        let center = CGPoint(x: key.frame.midX, y: key.frame.midY)
        let returnKey = traits?.returnKey ?? .default
        let blue = key.kind == .return && returnKey != .default && returnKey != .continue
        let fill = blue ? (held ? p.blueDown : p.blue) : (held ? p.keyDown : p.key)
        if showsEmoji, case .character = key.kind {
            // Emoji sit on the panel, no key under them.
            if held { list.append(.fillRRect(rect, cornerRadius: KeyboardMetrics.keyCornerRadius, p.keyDown)) }
        } else {
            list.append(.fillRRect(rect, cornerRadius: KeyboardMetrics.keyCornerRadius, fill))
        }
        let at = context.absolutePoint(center)
        switch key.kind {
        case .character(let character):
            drawCentered(label(for: character), font: font(showsEmoji ? 28 : 25), center: center, color: p.ink, context: context, into: &list)
        case .shift:
            Self.shift(list: &list, center: at, state: shift, color: p.ink)
        case .delete:
            Self.delete(list: &list, center: at, color: p.ink)
        case .page(let page):
            let text = showsEmoji ? "ABC" : page == .letters ? "ABC" : page == .numbers ? "123" : "#+="
            drawCentered(text, font: font(18), center: center, color: p.ink, context: context, into: &list)
        case .emoji:
            Self.emojiFace(list: &list, center: at, color: p.ink)
        case .accent:
            drawCentered(accentKeyMark, font: font(25), center: CGPoint(x: center.x, y: center.y + 4), color: p.ink, context: context, into: &list)
        case .space:
            let tag = font(11, weight: .medium)
            let tagWidth = runtime.textEngine.layout(language.tag, font: tag, width: nil).size.width
            list.append(.drawText(language.tag, DisplayFont(tag), origin: context.absolutePoint(CGPoint(x: key.frame.maxX - 8 - tagWidth, y: key.frame.maxY - 5)), p.tag))
        case .return:
            Self.returnGlyph(returnKey, list: &list, center: at, color: blue ? RGBA(r: 255, g: 255, b: 255, a: 1) : p.ink)
        }
    }

    private func paintBubble(_ label: String, over key: CGRect, palette p: Palette, context: PaintContext, into list: inout DisplayList) {
        let size = CGSize(width: max(KeyboardMetrics.bubbleSize.width, key.width + 22), height: KeyboardMetrics.bubbleSize.height)
        let x = min(frame.width - size.width - 2, max(2, key.midX - size.width / 2))
        let rect = CGRect(x: x, y: key.minY - KeyboardMetrics.bubbleGap - size.height, width: size.width, height: size.height)
        let absolute = context.absoluteRect(rect)
        list.append(.beginShadow(RGBA(r: 0, g: 0, b: 0, a: 0.2), radius: 6, offset: CGSize(width: 0, height: 1)))
        list.append(.fillRRect(absolute, cornerRadius: KeyboardMetrics.bubbleCornerRadius, p.bubble))
        list.append(.endGroup)
        drawCentered(label, font: font(showsEmoji ? 40 : 44), center: CGPoint(x: rect.midX, y: rect.midY), color: p.ink, context: context, into: &list)
    }

    private func paintAccents(_ accents: [String], frame box: CGRect, pick: Int?, palette p: Palette, context: PaintContext, into list: inout DisplayList) {
        list.append(.beginShadow(RGBA(r: 0, g: 0, b: 0, a: 0.2), radius: 6, offset: CGSize(width: 0, height: 1)))
        list.append(.fillRRect(context.absoluteRect(box), cornerRadius: KeyboardMetrics.bubbleCornerRadius, p.bubble))
        list.append(.endGroup)
        let cell = KeyboardMetrics.accentCell, pad = KeyboardMetrics.accentPadding
        for (index, accent) in accents.enumerated() {
            let rect = CGRect(x: box.minX + pad + CGFloat(index) * cell.width, y: box.minY + pad, width: cell.width, height: cell.height)
            let on = index == pick
            if on { list.append(.fillRRect(context.absoluteRect(rect), cornerRadius: 9, p.accentOn)) }
            drawCentered(accent, font: font(25), center: CGPoint(x: rect.midX, y: rect.midY), color: on ? RGBA(r: 255, g: 255, b: 255, a: 1) : p.ink, context: context, into: &list)
        }
    }

    // MARK: Icons (our own outlines, drawn around a centre in device pixels)

    private static func stroke(_ width: CGFloat = 1.7) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }

    private static func shiftArrow(at c: CGPoint) -> Path {
        Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - 9))
            p.addLine(to: CGPoint(x: c.x + 9.5, y: c.y + 1))
            p.addLine(to: CGPoint(x: c.x + 4.5, y: c.y + 1))
            p.addLine(to: CGPoint(x: c.x + 4.5, y: c.y + 7.5))
            p.addLine(to: CGPoint(x: c.x - 4.5, y: c.y + 7.5))
            p.addLine(to: CGPoint(x: c.x - 4.5, y: c.y + 1))
            p.addLine(to: CGPoint(x: c.x - 9.5, y: c.y + 1))
            p.closeSubpath()
        }
    }

    static func shift(list: inout DisplayList, center: CGPoint, state: Shift, color: RGBA) {
        let lockLift: CGFloat = state == .locked ? 2 : 0
        let arrow = shiftArrow(at: CGPoint(x: center.x, y: center.y - lockLift))
        if state == .off {
            list.append(.strokePath(arrow, style: stroke(1.6), color))
        } else {
            list.append(.fillPath(arrow, color))
            list.append(.strokePath(arrow, style: stroke(1.6), color))
        }
        if state == .locked {
            list.append(.fillRRect(CGRect(x: center.x - 4.5, y: center.y + 8.5, width: 9, height: 2), cornerRadius: 1, color))
        }
    }

    static func delete(list: inout DisplayList, center c: CGPoint, color: RGBA) {
        let body = Path { p in
            p.move(to: CGPoint(x: c.x - 12, y: c.y))
            p.addLine(to: CGPoint(x: c.x - 5.5, y: c.y - 8))
            p.addLine(to: CGPoint(x: c.x + 9.5, y: c.y - 8))
            p.addArc(tangent1End: CGPoint(x: c.x + 12, y: c.y - 8), tangent2End: CGPoint(x: c.x + 12, y: c.y), radius: 2.5)
            p.addArc(tangent1End: CGPoint(x: c.x + 12, y: c.y + 8), tangent2End: CGPoint(x: c.x, y: c.y + 8), radius: 2.5)
            p.addLine(to: CGPoint(x: c.x - 5.5, y: c.y + 8))
            p.closeSubpath()
        }
        list.append(.strokePath(body, style: stroke(1.6), color))
        let cross = Path { p in
            p.move(to: CGPoint(x: c.x - 1.5, y: c.y - 3.5)); p.addLine(to: CGPoint(x: c.x + 5.5, y: c.y + 3.5))
            p.move(to: CGPoint(x: c.x + 5.5, y: c.y - 3.5)); p.addLine(to: CGPoint(x: c.x - 1.5, y: c.y + 3.5))
        }
        list.append(.strokePath(cross, style: stroke(1.6), color))
    }

    static func emojiFace(list: inout DisplayList, center c: CGPoint, color: RGBA) {
        list.append(.strokePath(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)), style: stroke(1.6), color))
        list.append(.fillPath(Path(ellipseIn: CGRect(x: c.x - 5.3, y: c.y - 5.2, width: 3, height: 3.4)), color))
        list.append(.fillPath(Path(ellipseIn: CGRect(x: c.x + 2.3, y: c.y - 5.2, width: 3, height: 3.4)), color))
        let mouth = Path { p in
            p.move(to: CGPoint(x: c.x - 6, y: c.y + 1.5))
            p.addLine(to: CGPoint(x: c.x + 6, y: c.y + 1.5))
            p.addArc(center: CGPoint(x: c.x, y: c.y + 1.5), radius: 6, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
        }
        list.append(.fillPath(mouth, color))
    }

    static func globe(list: inout DisplayList, center c: CGPoint, scale: CGFloat, color: RGBA) {
        let r: CGFloat = 13
        let style = stroke(1.6)
        list.append(.strokePath(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), style: style, color))
        list.append(.strokePath(Path(ellipseIn: CGRect(x: c.x - 5.5, y: c.y - r, width: 11, height: 2 * r)), style: style, color))
        let lines = Path { p in
            p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
            p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
            p.move(to: CGPoint(x: c.x - 10.5, y: c.y - 6.5)); p.addLine(to: CGPoint(x: c.x + 10.5, y: c.y - 6.5))
            p.move(to: CGPoint(x: c.x - 10.5, y: c.y + 6.5)); p.addLine(to: CGPoint(x: c.x + 10.5, y: c.y + 6.5))
        }
        list.append(.strokePath(lines, style: style, color))
    }

    static func mic(list: inout DisplayList, center c: CGPoint, color: RGBA) {
        let style = stroke(1.6)
        list.append(.strokePath(Path(roundedRect: CGRect(x: c.x - 5, y: c.y - 15, width: 10, height: 18), cornerRadius: 5), style: style, color))
        let stand = Path { p in
            p.addArc(center: CGPoint(x: c.x, y: c.y - 2), radius: 9, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.move(to: CGPoint(x: c.x, y: c.y + 7)); p.addLine(to: CGPoint(x: c.x, y: c.y + 13))
            p.move(to: CGPoint(x: c.x - 5, y: c.y + 13)); p.addLine(to: CGPoint(x: c.x + 5, y: c.y + 13))
        }
        list.append(.strokePath(stand, style: style, color))
    }

    /// The return key's glyph for the field's `submitLabel`: the arrow up for Send, a magnifier
    /// for Search, a tick for Done, the bent return arrow otherwise.
    static func returnGlyph(_ kind: UIReturnKeyType, list: inout DisplayList, center c: CGPoint, color: RGBA) {
        let style = stroke(2)
        switch kind {
        case .send:
            let arrow = Path { p in
                p.move(to: CGPoint(x: c.x, y: c.y + 9)); p.addLine(to: CGPoint(x: c.x, y: c.y - 9))
                p.move(to: CGPoint(x: c.x - 7, y: c.y - 2)); p.addLine(to: CGPoint(x: c.x, y: c.y - 9)); p.addLine(to: CGPoint(x: c.x + 7, y: c.y - 2))
            }
            list.append(.strokePath(arrow, style: style, color))
        case .search, .google, .yahoo:
            list.append(.strokePath(Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 12.5, height: 12.5)), style: style, color))
            let handle = Path { p in p.move(to: CGPoint(x: c.x + 3, y: c.y + 3)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y + 8)) }
            list.append(.strokePath(handle, style: style, color))
        case .done:
            let tick = Path { p in
                p.move(to: CGPoint(x: c.x - 8, y: c.y)); p.addLine(to: CGPoint(x: c.x - 2.5, y: c.y + 6)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y - 6))
            }
            list.append(.strokePath(tick, style: style, color))
        case .go, .route, .join, .next, .continue, .emergencyCall:
            let arrow = Path { p in
                p.move(to: CGPoint(x: c.x - 9, y: c.y)); p.addLine(to: CGPoint(x: c.x + 9, y: c.y))
                p.move(to: CGPoint(x: c.x + 2, y: c.y - 7)); p.addLine(to: CGPoint(x: c.x + 9, y: c.y)); p.addLine(to: CGPoint(x: c.x + 2, y: c.y + 7))
            }
            list.append(.strokePath(arrow, style: style, color))
        case .default:
            let bent = Path { p in
                p.move(to: CGPoint(x: c.x + 8, y: c.y - 8)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y + 2)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y + 2))
                p.move(to: CGPoint(x: c.x - 3, y: c.y - 3)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y + 2)); p.addLine(to: CGPoint(x: c.x - 3, y: c.y + 7))
            }
            list.append(.strokePath(bent, style: stroke(1.7), color))
        }
    }
}

extension PaintContext {
    /// A point in this context's space, in absolute points (not pixel aligned).
    fileprivate func absolutePoint(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x, y: origin.y + point.y) }
}
