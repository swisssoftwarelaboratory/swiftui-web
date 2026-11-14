// The text field node: layout (a line, or wrapped lines for `axis: .vertical`), painting of
// bezel, text, placeholder, bullets, caret and selection, focus, and the text-change, submit
// and selection entry points the host calls from its input element.

@MainActor
package final class TextFieldNode: LeafNode<_TextFieldCore>, _Interactive {
    override package var layoutSpacing: ViewSpacing {
        if PlatformMetrics.controlsUsePlainSpacing { return ViewSpacing() }
        return .control(top: PlatformMetrics.textFieldSpacing, bottom: PlatformMetrics.textFieldSpacing,
                 belowText: PlatformMetrics.textFieldSpacing, aboveText: PlatformMetrics.textFieldSpacing)
    }

    private static var nextIdentifier = 3_000_000
    package let identifier: Int

    /// A value field's text while it is being edited (committed on submit or when focus leaves).
    private var editBuffer: String?
    /// The selected range in UTF-16 offsets (a caret when empty), while focused.
    package private(set) var selection: Range<Int>?
    /// The input method's marked text (UTF-16 offsets), underlined until it commits
    /// (pf-native-text; the browser's input shows its own composition).
    package private(set) var markedRange: Range<Int>?

    override package init(_ context: _NodeContext<_TextFieldCore>) {
        Self.nextIdentifier += 1
        identifier = Self.nextIdentifier
        super.init(context)
    }

    override package func update(view: _TextFieldCore, environment: EnvironmentValues, force: Bool) {
        // A value written from outside while a value field is not focused shows at once.
        if editBuffer != nil, runtime.focusedTextFieldIdentifier != identifier { editBuffer = nil }
        super.update(view: view, environment: environment, force: force)
    }

    /// The style's bezel; the automatic style is plain on iOS (ios/textfield/basic `plain`).
    private var bezel: _TextFieldBezel {
        if environment.platformProfile.isIOS, view.style is DefaultTextFieldStyle { return .plain }
        return view.style._bezel
    }
    private var resolvedFont: ResolvedFont {
        (environment.font ?? environment.platformProfile.defaultFont).resolve(in: environment)
    }
    private var metrics: SystemFontMetrics { environment.platformProfile.systemFontMetrics(for: resolvedFont) }
    private var isVertical: Bool { view.axis == .vertical }

    /// The text shown: the edit buffer of a value field being typed into, else the binding's;
    /// a field leaving through a removal transition keeps what it last showed, as its binding
    /// may name an element that is gone (a row of a `ForEach` over a binding, SimpleScores'
    /// Remove All).
    package var displayText: String {
        if let editBuffer { return editBuffer }
        if !isExiting { shownText = view.text.wrappedValue }
        return shownText
    }
    private var shownText = ""

    /// Insets between the frame and the text line: 6 pt sideways and 4 pt vertically for a bezel,
    /// none for the plain style.
    private var insets: EdgeInsets {
        bezel == .plain ? EdgeInsets() : EdgeInsets(top: PlatformMetrics.textFieldVerticalPadding, leading: PlatformMetrics.textFieldHorizontalPadding,
                                                    bottom: PlatformMetrics.textFieldVerticalPadding, trailing: PlatformMetrics.textFieldHorizontalPadding)
    }

    private func textWidth(_ string: String) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        return runtime.layoutText(string, font: resolvedFont, width: nil).size.width
    }

    /// The wrapped lines of a vertical field for `width` (the placeholder is one line).
    private func wrappedLayout(width: CGFloat) -> TextLayout? {
        let text = displayText
        guard isVertical, !text.isEmpty else { return nil }
        return runtime.layoutText([StyledRun(text, font: resolvedFont)],
                                  options: TextLayoutOptions(lineLimit: environment.lineLimit, minimumLines: 0), width: width)
    }

    /// The lines a vertical field shows: its wrapped text (at least one line, at least the
    /// reserved lines, at most the limit). A recorded layout is one line whose height carries
    /// the wrapped lines, so the count comes from the height.
    private func lineCount(width: CGFloat) -> Int {
        var count = 1
        if let layout = wrappedLayout(width: width) {
            let pitch = metrics.lineHeight
            let fromHeight = pitch > 0 ? Int((layout.size.height / pitch).rounded()) : 1
            count = max(layout.lines.count, fromHeight)
        }
        count = max(count, 1, environment.minimumLines)
        if let limit = environment.lineLimit { count = min(count, max(1, limit)) }
        return count
    }

    /// The frame's height: the bezel's, or the line plus the plain style's extra (iOS: 26 for a
    /// 24.5 pt body line, ios/textfield/basic; 25 while only the placeholder shows,
    /// ios/dark/controls `emptyField`). A vertical field stacks its lines at the line height.
    /// (`textfield/vertical`: 16 per line on macOS; `ios/textfield/vertical`: 26 per line, 52 for
    /// two plain lines and 60 in a bezel, the plain style's extra height being each line's).
    private func height(lineHeight: CGFloat, insets: EdgeInsets, lines: Int) -> CGFloat {
        let extra = displayText.isEmpty ? PlatformMetrics.textFieldPlainEmptyExtraHeight : PlatformMetrics.textFieldPlainExtraHeight
        let textHeight = linePitch * CGFloat(lines)
        guard bezel == .plain else {
            // Several lines: the lines at their pitch inside `textFieldMultilinePadding`
            // (ios/textfield/vertical `rounded`: 60 for two 26 pt lines).
            if lines > 1 { return textHeight + PlatformMetrics.textFieldMultilinePadding }
            return max(lineHeight + insets.top + insets.bottom, PlatformMetrics.textFieldHeight)
        }
        return lines > 1 ? textHeight : lineHeight + extra
    }

    /// The distance between a vertical field's lines: the line height plus the plain style's
    /// extra (0 on macOS, 5.5 on iOS).
    private var linePitch: CGFloat { metrics.lineHeight + PlatformMetrics.textFieldPlainExtraHeight }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let insets = insets
        let lineHeight = metrics.lineHeight
        // Flexible across the proposal; the ideal width fits the shown text (the placeholder
        // when empty) plus `textFieldIdealInset` each side (textfield/formatted: "Hello" at
        // 34.95, the unrounded width plus 4; our widths are rounded to the half point).
        let shownText = displayText.isEmpty ? view.placeholder : displayText
        let ideal = textWidth(shownText) + insets.leading + insets.trailing + 2 * PlatformMetrics.textFieldIdealInset
        if view.fitsText {
            let shown = displayText.isEmpty ? view.placeholder : displayText
            let width = textWidth(shown) + insets.leading + insets.trailing
            return CGSize(width: width, height: height(lineHeight: lineHeight, insets: insets, lines: lineCount(width: width - insets.leading - insets.trailing)))
        }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ideal
        let lines = isVertical ? lineCount(width: max(0, width - insets.leading - insets.trailing)) : 1
        return CGSize(width: width, height: height(lineHeight: lineHeight, insets: insets, lines: lines))
    }

    /// Where the text line sits below the centred position (iOS: 0.75 down in a bezel, at the
    /// top of the plain style's frame).
    private var textOffset: CGFloat { bezel == .plain ? PlatformMetrics.textFieldPlainTextOffset : PlatformMetrics.textFieldTextOffset }

    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let lines = isVertical ? lineCount(width: max(0, size.width - insets.leading - insets.trailing)) : 1
        let top = (size.height - metrics.lineHeight * CGFloat(lines)) / 2 + textOffset
        let first = top + metrics.baseline
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: first,
            VerticalAlignment.lastTextBaseline.key: first + metrics.lineHeight * CGFloat(lines - 1),
        ])
    }

    /// The text's rectangle within the frame: one line, or the lines of a vertical field.
    package var textRect: CGRect {
        let insets = insets
        let lineHeight = metrics.lineHeight
        let width = max(0, frame.width - insets.leading - insets.trailing)
        let lines = isVertical ? lineCount(width: width) : 1
        let height = lineHeight * CGFloat(lines)
        return CGRect(x: insets.leading, y: (frame.height - height) / 2 + textOffset, width: width, height: height)
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        let bounds = absoluteBounds(context)
        let enabled = environment.isEnabled
        if bezel != .plain && PlatformMetrics.textFieldBorderInside {
            // iOS: a 0.5 pt border inside the frame (ios/textfield/basic).
            let border = PlatformMetrics.textFieldBorderWidth, radius = PlatformMetrics.textFieldCornerRadius
            list.append(.fillRRect(bounds, cornerRadius: radius, environment._ink(PlatformMetrics.textFieldBorderAlpha)))
            list.append(.fillRRect(bounds.insetBy(dx: border, dy: border), cornerRadius: radius - border,
                                   environment._controlBackground.multiplyingAlpha(by: enabled || environment._isDark ? 1 : PlatformMetrics.textFieldDisabledFillAlpha)))
        } else if bezel != .plain {
            let outer = bounds.insetBy(dx: -PlatformMetrics.textFieldBorderWidth, dy: -PlatformMetrics.textFieldBorderWidth)
            // Dark: a mid-grey ring at the same alpha over the opaque control background (dark/controls).
            list.append(.fillRRect(outer, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.textFieldBorderWidth,
                                   environment._isDark ? RGBA(r: 128, g: 128, b: 128, a: PlatformMetrics.textFieldBorderAlpha) : environment._ink(PlatformMetrics.textFieldBorderAlpha)))
            list.append(.fillRRect(bounds, cornerRadius: PlatformMetrics.textFieldCornerRadius,
                                   environment._controlBackground.multiplyingAlpha(by: enabled || environment._isDark ? 1 : PlatformMetrics.textFieldDisabledFillAlpha)))
            if runtime.focusedTextFieldIdentifier == identifier {
                let ring = bounds.insetBy(dx: -PlatformMetrics.focusRingWidth / 2, dy: -PlatformMetrics.focusRingWidth / 2)
                list.append(.strokePath(Path(roundedRect: ring, cornerRadius: PlatformMetrics.textFieldCornerRadius + PlatformMetrics.focusRingWidth / 2, style: .circular),
                                        style: StrokeStyle(lineWidth: PlatformMetrics.focusRingWidth),
                                        Color.accentColor.opacity(PlatformMetrics.focusRingOpacity).resolve(in: environment)))
            }
        }
        let text = displayText
        let rect = context.absoluteRect(textRect)
        let font = resolvedFont
        let lineHeight = metrics.lineHeight
        let baseline = CGPoint(x: rect.minX, y: rect.minY + metrics.baseline)
        let focused = runtime.focusedTextFieldIdentifier == identifier && enabled
        if focused { paintSelection(into: &list, rect: rect, text: text) }
        if text.isEmpty {
            if !view.placeholder.isEmpty {
                list.append(.drawText(view.placeholder, DisplayFont(font), origin: baseline, (environment._isDark ? PlatformMetrics.textFieldPlaceholderDark : PlatformMetrics.textFieldPlaceholder) ?? Color.secondary.resolve(in: environment)))
            }
        } else if view.isSecure {
            let color = (environment.foregroundColor ?? .primary).resolve(in: environment)
            let radius = PlatformMetrics.secureBulletDiameter / 2
            var x = rect.minX + PlatformMetrics.secureBulletInset + radius
            let y = baseline.y - PlatformMetrics.secureBulletBaselineOffset
            for _ in text {
                guard x + radius <= rect.maxX + 0.5 else { break }
                list.append(.fillPath(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), color))
                x += PlatformMetrics.secureBulletPitch
            }
        } else {
            var color = (environment.foregroundColor ?? .primary).resolve(in: environment)
            if !enabled { color = color.multiplyingAlpha(by: PlatformMetrics.disabledLabelOpacity) }
            list.withSavedState { list in
                list.append(.clipRect(rect))
                if let layout = wrappedLayout(width: rect.width) {
                    var y = baseline.y
                    for line in layout.lines {
                        for fragment in line.fragments where !fragment.text.isEmpty {
                            list.append(.drawText(fragment.text, DisplayFont(font), origin: CGPoint(x: rect.minX + fragment.x, y: y), color))
                        }
                        y += lineHeight
                    }
                } else {
                    list.append(.drawText(text, DisplayFont(font), origin: baseline, color))
                }
            }
        }
        if focused { paintCaret(into: &list, rect: rect, text: text); paintMarkedText(into: &list, rect: rect, text: text) }
    }

    // MARK: Caret and selection

    /// The line index and x offset (from the text rect's leading edge) of a UTF-16 offset.
    private func position(of offset: Int, in text: String, width: CGFloat) -> (line: Int, x: CGFloat) {
        let utf16 = text.utf16
        let clamped = min(max(0, offset), utf16.count)
        if view.isSecure {
            return (0, clamped == 0 ? 0 : PlatformMetrics.secureBulletInset + PlatformMetrics.secureBulletPitch * CGFloat(clamped))
        }
        if let layout = wrappedLayout(width: width) {
            let index = utf16.index(utf16.startIndex, offsetBy: clamped)
            for (number, line) in layout.lines.enumerated() {
                let last = number == layout.lines.count - 1
                if index < line.range.upperBound || last {
                    let start = line.range.lowerBound
                    let prefix = index >= start ? String(text[start..<max(start, index)]) : ""
                    return (number, (line.fragments.first?.x ?? 0) + textWidth(prefix))
                }
            }
            return (0, 0)
        }
        let index = utf16.index(utf16.startIndex, offsetBy: clamped)
        return (0, textWidth(String(text[..<index])))
    }

    private var caretColor: RGBA {
        PlatformMetrics.textCaretUsesAccent ? Color.accentColor.resolve(in: environment) : (environment.foregroundColor ?? .primary).resolve(in: environment)
    }

    private func paintSelection(into list: inout DisplayList, rect: CGRect, text: String) {
        guard let selection, !selection.isEmpty, !text.isEmpty else { return }
        let lineHeight = metrics.lineHeight
        let start = position(of: selection.lowerBound, in: text, width: rect.width)
        let end = position(of: selection.upperBound, in: text, width: rect.width)
        let color = PlatformMetrics.textSelectionColor
        for line in start.line...end.line {
            let from = line == start.line ? start.x : 0
            let to = line == end.line ? end.x : rect.width
            guard to > from else { continue }
            list.append(.fillRect(CGRect(x: rect.minX + from, y: rect.minY + lineHeight * CGFloat(line), width: to - from, height: lineHeight), color))
        }
    }

    /// The input method's marked text: a 1 pt underline in the text colour under the marked
    /// run (AppKit underlines the composition; the segments' thick and thin lines are not kept).
    private func paintMarkedText(into list: inout DisplayList, rect: CGRect, text: String) {
        guard let markedRange, !markedRange.isEmpty, !text.isEmpty else { return }
        let lineHeight = metrics.lineHeight
        let start = position(of: markedRange.lowerBound, in: text, width: rect.width)
        let end = position(of: markedRange.upperBound, in: text, width: rect.width)
        for line in start.line...end.line {
            let from = line == start.line ? start.x : 0
            let to = line == end.line ? end.x : rect.width
            guard to > from else { continue }
            list.append(.fillRect(CGRect(x: rect.minX + from, y: rect.minY + lineHeight * CGFloat(line + 1) - 1.5, width: to - from, height: 1), caretColor))
        }
    }

    /// The insertion point: a `textCaretWidth` bar the line's height, in the text colour
    /// (macOS) or the accent (iOS); unverified against the platforms (the goldens never focus).
    private func paintCaret(into list: inout DisplayList, rect: CGRect, text: String) {
        guard let selection, selection.isEmpty else { return }
        let lineHeight = metrics.lineHeight
        let caret = position(of: selection.lowerBound, in: text, width: rect.width)
        let width = PlatformMetrics.textCaretWidth
        list.append(.fillRect(CGRect(x: rect.minX + caret.x - width / 2, y: rect.minY + lineHeight * CGFloat(caret.line), width: width, height: lineHeight), caretColor))
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressEnded(inside: Bool) {
        guard inside, environment.isEnabled else { return }
        runtime.focusTextField(identifier)
    }

    package var semantics: SemanticsNode {
        let absolute = frameInRoot
        let rect = textRect.offsetBy(dx: absolute.minX, dy: absolute.minY)
        var info = TextInputInfo(text: displayText, placeholder: view.placeholder, isSecure: view.isSecure,
                                 textRect: rect, font: DisplayFont(resolvedFont), isEnabled: environment.isEnabled)
        if isVertical {
            info.isMultiline = true
            info.lineHeight = metrics.lineHeight
            info.firstBaseline = metrics.baseline
        }
        info.paintsCaret = true
        info.inputMode = environment._keyboardType.inputMode
        info.inputType = view.isSecure ? "password" : environment._keyboardType.inputType
        info.autocomplete = environment._textContentType?.rawValue
        info.autocapitalize = environment._textInputAutocapitalization?.kind.token
        info.enterKeyHint = environment._submitLabel.key.enterKeyHint
        info.autocorrect = !environment.autocorrectionDisabled
        return SemanticsNode(role: .textField, label: view.placeholder, frame: absolute, identifier: identifier, textInput: info)
    }

    /// The host's input changed: push the text into the binding, or hold it until the value
    /// field commits. The caret follows the end of the text until the host says otherwise.
    package func setText(_ text: String) {
        selection = text.utf16.count..<text.utf16.count
        if view.commitsOnSubmit {
            guard editBuffer != text else { return }
            editBuffer = text
            runtime.requestLayout()
            return
        }
        guard view.text.wrappedValue != text else { return }
        view.text.wrappedValue = text
    }

    /// The host's selection changed (UTF-16 offsets).
    package func setSelection(start: Int, end: Int) {
        let range = min(start, end)..<max(start, end)
        guard selection != range else { return }
        selection = range
        runtime.requestRedraw()
    }

    package func setMarkedRange(_ range: Range<Int>?) {
        guard markedRange != range else { return }
        markedRange = range
        runtime.requestRedraw()
    }

    private func commitEdit() {
        guard let buffer = editBuffer else { return }
        editBuffer = nil
        if view.text.wrappedValue != buffer { view.text.wrappedValue = buffer }
        runtime.requestLayout()
    }

    package func submit() {
        commitEdit()
        view.onCommit?()
        environment.submitAction?.run()
    }

    package func focusChanged(_ focused: Bool) {
        if focused {
            if selection == nil { selection = displayText.utf16.count..<displayText.utf16.count }
        } else {
            commitEdit()
            selection = nil
        }
        view.onEditingChanged?(focused)
        runtime.setNeedsDisplay()
    }
}

/// A node whose text the host's input edits (text fields and editors).
@MainActor
package protocol _TextInputNode: AnyObject {
    func setText(_ text: String)
    func submit()
    /// The host's selection changed (UTF-16 offsets).
    func setSelection(start: Int, end: Int)
    /// The host's input method marked `range` (nil: nothing marked).
    func setMarkedRange(_ range: Range<Int>?)
    /// Keyboard focus arrived or left.
    func focusChanged(_ focused: Bool)
}

extension _TextInputNode {
    package func setSelection(start: Int, end: Int) {}
    package func setMarkedRange(_ range: Range<Int>?) {}
    package func focusChanged(_ focused: Bool) {}
}

extension TextFieldNode: _TextInputNode {}

extension Runtime {
    package func textInputNode(_ semanticsIdentifier: Int) -> (any _TextInputNode)? {
        interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _TextInputNode
    }

    /// Text typed into the field with this semantics identifier (from the host's input element).
    public func textField(_ semanticsIdentifier: Int, didChange text: String) {
        guard let node = textInputNode(semanticsIdentifier) else {
            platformTree(handling: semanticsIdentifier)?.textField(semanticsIdentifier, didChange: text)
            return
        }
        node.setText(text)
    }

    /// Return pressed in the field with this identifier (an editor inserts a newline).
    public func textFieldDidSubmit(_ semanticsIdentifier: Int) {
        guard let node = textInputNode(semanticsIdentifier) else {
            platformTree(handling: semanticsIdentifier)?.textFieldDidSubmit(semanticsIdentifier)
            return
        }
        node.submit()
    }

    /// The host's selection or caret moved in the field with this identifier (UTF-16 offsets).
    public func textField(_ semanticsIdentifier: Int, selectionStart start: Int, end: Int) {
        textInputNode(semanticsIdentifier)?.setSelection(start: start, end: end)
    }

    /// The host's input method is composing in the field (pf-native-text).
    public func textField(_ semanticsIdentifier: Int, markedRange range: Range<Int>?) {
        textInputNode(semanticsIdentifier)?.setMarkedRange(range)
    }

    /// The host's textarea scrolled: the editor's painted text follows.
    public func textField(_ semanticsIdentifier: Int, scrolledTo offset: CGFloat) {
        (textInputNode(semanticsIdentifier) as? TextEditorNode)?.setScrollOffset(offset)
    }

    /// The host's input gained or lost focus.
    public func textField(_ semanticsIdentifier: Int, focused: Bool) {
        if let tree = platformTree(handling: semanticsIdentifier) {
            tree.textField(semanticsIdentifier, focused: focused)
            return
        }
        if focused {
            focusTextField(semanticsIdentifier)
        } else if focusedTextFieldIdentifier == semanticsIdentifier {
            focusTextField(nil)
        }
    }
}
