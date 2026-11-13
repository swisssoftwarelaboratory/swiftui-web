// TextEditor node (Docs/elements/TextEditor.md): fills its proposal, paints a white background
// and the text in black 5 pt in, the first line's cap height at the top edge and lines at the
// text view's pitch (font size × 0.955, rounded) plus the line spacing; focus hands editing to
// the host's multi-line input.

@MainActor
private var nextEditorIdentifier = 9_500_000

@MainActor
package final class TextEditorNode: LeafNode<_TextEditorHost>, _Interactive, _TextInputNode, _Scrollable {
    private let identifier: Int
    /// How far the content is scrolled (long text in a short frame; the host's textarea
    /// reports its own scrolling while focused).
    package private(set) var contentOffset = CGPoint.zero
    /// The host's last selection (UTF-16 offsets), so a binding change is pushed only when it differs.
    private var hostSelection: (start: Int, end: Int)?

    override package init(_ context: _NodeContext<_TextEditorHost>) {
        nextEditorIdentifier += 1
        identifier = nextEditorIdentifier
        super.init(context)
    }

    private var resolvedFont: ResolvedFont {
        (environment.font ?? environment.platformProfile.defaultFont).resolve(in: environment)
    }

    /// The distance between baselines: the text view's line height for the font, plus the
    /// environment's line spacing.
    package var linePitch: CGFloat {
        (resolvedFont.size * PlatformMetrics.textEditorLineFactor).rounded() + environment.lineSpacing
    }

    /// The first baseline below the top edge: the cap height, plus a top gap that grows with
    /// the font size (two measurements: 13 pt and 22 pt).
    package var firstBaseline: CGFloat {
        let font = resolvedFont
        let cap = environment.platformProfile.systemFontMetrics(for: font).capHeight
        return cap + max(0, font.size - PlatformMetrics.textEditorBaseSize) * PlatformMetrics.textEditorTopGrowth
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.textEditorIdealSize.width,
               height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? PlatformMetrics.textEditorIdealSize.height)
    }

    /// The text area: 5 pt in from the sides, under the find bar when one is up.
    package var textRect: CGRect {
        CGRect(x: PlatformMetrics.textEditorInset, y: view.topInset, width: max(0, frame.width - 2 * PlatformMetrics.textEditorInset), height: max(0, frame.height - view.topInset))
    }

    private var layout: TextLayout? {
        guard !view.value.isEmpty else { return nil }
        return runtime.layoutText([StyledRun(view.value, font: resolvedFont)], options: TextLayoutOptions(lineSpacing: environment.lineSpacing),
                                         width: textRect.width)
    }

    /// The height of the laid-out lines at the editor's pitch.
    package var contentHeight: CGFloat {
        guard let layout else { return 0 }
        return firstBaseline + CGFloat(max(0, layout.lines.count - 1)) * linePitch + (linePitch - firstBaseline) + PlatformMetrics.textEditorInset
    }

    private func clampOffset() {
        let maxY = max(0, contentHeight - textRect.height)
        if contentOffset.y > maxY || contentOffset.y < 0 { contentOffset.y = min(max(0, contentOffset.y), maxY) }
    }

    /// The host's textarea scrolled: the painted text follows.
    package func setScrollOffset(_ y: CGFloat) {
        guard contentOffset.y != y else { return }
        contentOffset.y = y
        clampOffset()
        runtime.requestRedraw()
    }

    // MARK: _Scrollable (the wheel over an unfocused editor scrolls its content)

    package func scroll(by delta: CGSize) -> CGSize {
        let maxY = max(0, contentHeight - textRect.height)
        let target = min(max(0, contentOffset.y + delta.height), maxY)
        let consumed = target - contentOffset.y
        guard consumed != 0 else { return delta }
        contentOffset.y = target
        runtime.requestRedraw()
        return CGSize(width: delta.width, height: delta.height - consumed)
    }
    package func showIndicators() {}
    package func beginMomentum(velocity: CGSize) {}
    package var isDecelerating: Bool { false }
    package func pull(by distance: CGFloat) -> Bool { false }
    package func endPull() {}
    package func stopMomentum() {}
    package func advance(elapsed: Double) -> Bool { false }
    package var canMoveContentOnly: Bool { true }
    package func moveContent() {}
    package func beginTracking() {}
    package func endTracking(velocity: CGSize) {}
    package var dismissesKeyboardOnScroll: Bool { false }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        if view.paintsBackground {
            list.append(.fillRect(bounds, RGBA(red: 1, green: 1, blue: 1, alpha: 1)))
        }
        guard let layout else { return }
        let rect = context.absoluteRect(textRect)
        let color = environment.foregroundColor?.resolve(in: environment) ?? PlatformMetrics.textEditorTextColor
        let font = DisplayFont(resolvedFont)
        let pitch = linePitch
        clampOffset()
        var baseline = rect.minY + firstBaseline - contentOffset.y
        let metrics = environment.platformProfile.systemFontMetrics(for: resolvedFont)
        let text = view.value
        list.withSavedState { list in
            list.append(.clipRect(context.absoluteRect(CGRect(x: 0, y: view.topInset, width: frame.width, height: max(0, frame.height - view.topInset)))))
            for (number, line) in layout.lines.enumerated() {
                // The find navigator's matches on this line: yellow, the current one stronger.
                for (index, match) in view.highlights.enumerated() {
                    let start = max(match.lowerBound, line.range.lowerBound), end = min(match.upperBound, line.range.upperBound)
                    guard start < end, line.range.upperBound <= text.endIndex else { continue }
                    let x0 = prefixWidth(text[line.range.lowerBound..<start]), x1 = prefixWidth(text[line.range.lowerBound..<end])
                    let current = index == view.currentMatch
                    list.append(.fillRRect(CGRect(x: rect.minX + x0 - 1, y: baseline - metrics.baseline, width: x1 - x0 + 2, height: metrics.lineHeight),
                                           cornerRadius: 3, RGBA(red: 1, green: current ? 0.78 : 0.95, blue: current ? 0 : 0.4, alpha: current ? 1 : 0.7)))
                }
                for fragment in line.fragments where !fragment.text.isEmpty {
                    list.append(.drawText(fragment.text, font, origin: CGPoint(x: rect.minX + fragment.x, y: baseline), color))
                }
                baseline += pitch
                _ = number
            }
        }
    }

    private func prefixWidth(_ prefix: Substring) -> CGFloat {
        guard !prefix.isEmpty else { return 0 }
        func width(_ text: String) -> CGFloat { runtime.textEngine.layout(text, font: resolvedFont, width: nil).size.width }
        return prefix.last == " " ? width(String(prefix) + "|") - width("|") : width(String(prefix))
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.focusTextField(identifier)
    }

    package var semantics: SemanticsNode {
        let absolute = frameInRoot
        var info = TextInputInfo(text: view.value, placeholder: "", isSecure: false, textRect: textRect.offsetBy(dx: absolute.minX, dy: absolute.minY),
                                 font: DisplayFont(resolvedFont), isEnabled: environment.isEnabled)
        info.isMultiline = true
        info.lineHeight = linePitch
        info.firstBaseline = firstBaseline
        info.submitsOnReturn = false
        info.scrollOffset = contentOffset.y
        // A selection binding's value reaches the host's element when it differs from the host's own.
        if let selection = view.selection?.wrappedValue?.range {
            let utf16 = view.value.utf16
            let start = utf16.distance(from: utf16.startIndex, to: min(selection.lowerBound, view.value.endIndex))
            let end = utf16.distance(from: utf16.startIndex, to: min(selection.upperBound, view.value.endIndex))
            if hostSelection == nil || hostSelection!.start != start || hostSelection!.end != end { info.selection = TextRange(start: start, end: end) }
        }
        return SemanticsNode(role: .textField, label: "", frame: absolute, identifier: identifier, textInput: info)
    }

    package func setText(_ text: String) {
        guard view.text.wrappedValue != text else { return }
        view.text.wrappedValue = text
    }

    /// The host's selection changed (UTF-16 offsets): the binding follows.
    package func setSelection(start: Int, end: Int) {
        hostSelection = (start, end)
        guard let binding = view.selection else { return }
        let utf16 = view.value.utf16
        let lower = utf16.index(utf16.startIndex, offsetBy: min(max(0, start), utf16.count))
        let upper = utf16.index(utf16.startIndex, offsetBy: min(max(start, end), utf16.count))
        let selection = TextSelection(range: lower..<upper)
        if binding.wrappedValue != selection { binding.wrappedValue = selection }
    }

    /// Return inserts a newline in an editor.
    package func submit() {
        setText(view.text.wrappedValue + "\n")
    }
}
