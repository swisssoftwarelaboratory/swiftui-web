// UILabel (Docs/elements/UIKit/UILabel.md): text laid out by the scene's text engine; the block
// is the font's line height per line plus its leading between lines, rounded up to the pixel
// (UIFont.labelHeight), centred vertically in the bounds as UIKit does. Attributed text draws
// its runs' fonts and colours; `adjustsFontSizeToFitWidth` scales the text to fit.
import WebFoundation   // NSCoder, for init?(coder:)

#if !os(WASI)
import Foundation
#endif

/// A view that displays one or more lines of informational text.
@preconcurrency @MainActor
open class UILabel: UIView {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open var text: String? {
        didSet {
            if text != oldValue {
                if !settingAttributedText { storedAttributedText = nil }
                textDidChange()
            }
        }
    }
    open var font: UIFont = .systemFont(ofSize: 17) { didSet { if font != oldValue { textDidChange() } } }

    /// Attributed text: its runs' fonts and colours draw as they are (`.font`,
    /// `.foregroundColor`; a paragraph style's alignment and line break mode apply); `text` and
    /// `font` follow the string and its first run.
    open var attributedText: NSAttributedString? {
        get { storedAttributedText }
        set {
            storedAttributedText = newValue
            settingAttributedText = true
            text = newValue?.string
            settingAttributedText = false
            if let first = newValue?.uniformAttributes {
                if let font = first[.font] as? UIFont { self.font = font }
                if let color = first[.foregroundColor] as? UIColor { textColor = color }
                if let paragraph = first[.paragraphStyle] as? NSParagraphStyle {
                    textAlignment = paragraph.alignment
                    lineBreakMode = paragraph.lineBreakMode
                }
            }
            textDidChange()
        }
    }
    private var storedAttributedText: NSAttributedString?
    private var settingAttributedText = false

    /// One run of the text with its font and colour (the label's for plain text).
    struct Run {
        var text: String
        var font: UIFont
        var color: UIColor?
    }

    /// The text's runs: the attributed string's, else one in the label's font.
    var runs: [Run] {
        guard let attributed = storedAttributedText, attributed.length > 0 else {
            return text.map { [Run(text: $0, font: font, color: nil)] } ?? []
        }
        var result: [Run] = []
        let utf16 = Array(attributed.string.utf16)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
            let piece = String(decoding: utf16[range.location..<min(utf16.count, range.location + range.length)], as: UTF16.self)
            result.append(Run(text: piece, font: attributes[.font] as? UIFont ?? font, color: attributes[.foregroundColor] as? UIColor))
        }
        return result
    }

    /// The font whose line box is tallest among the runs (the label's height follows it).
    var tallestFont: UIFont { runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? font }

    /// The scale the text was last drawn at (`adjustsFontSizeToFitWidth`): 1 when it fits.
    public private(set) var fittedScale: CGFloat = 1
    open var textColor: UIColor = .label { didSet { setNeedsDisplay() } }
    open var textAlignment: NSTextAlignment = .natural { didSet { setNeedsDisplay() } }
    open var lineBreakMode: NSLineBreakMode = .byTruncatingTail { didSet { textDidChange() } }
    /// How lines break around words; kept (lines break at the last word that fits).
    open var lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = .standard
    /// 0 lays out as many lines as the text needs.
    open var numberOfLines = 1 { didSet { textDidChange() } }
    open var adjustsFontSizeToFitWidth = false
    open var minimumScaleFactor: CGFloat = 0
    open var allowsDefaultTighteningForTruncation = false
    open var isEnabled = true { didSet { setNeedsDisplay() } }
    open var isHighlighted = false
    open var highlightedTextColor: UIColor?
    open var shadowColor: UIColor?
    open var shadowOffset = CGSize(width: 0, height: -1)
    /// A text-style font follows the content size category of the label's traits (the scene's
    /// `preferredContentSizeCategory`, a trait override above the label).
    open var adjustsFontForContentSizeCategory = false { didSet { if adjustsFontForContentSizeCategory { followContentSizeCategory() } } }

    private func followContentSizeCategory() {
        guard adjustsFontForContentSizeCategory, let style = font.textStyle else { return }
        let scaled = UIFont.preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        if scaled != font { font = scaled }
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { followContentSizeCategory() }
    }
    open var showsExpansionTextWhenTruncated = false
    /// The width the intrinsic height wraps at (0: one line).
    open var preferredMaxLayoutWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        backgroundColor = nil
        // A label keeps UIView's priorities: hugging 250 and compression resistance 750 on both
        // axes (uikit/autolayout/hugging measured them; UIKit's 251 is folklore).
    }

    private func textDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    override open var accessibilityLabel: String? {
        get { super.accessibilityLabel ?? text }
        set { super.accessibilityLabel = newValue }
    }

    // MARK: Layout

    /// The text engine's layout of the text within `width` (nil: unbounded).
    func layout(width: CGFloat?) -> TextLayout? { layout(width: width, fitting: false) }

    /// The layout of the runs within `width`; `fitting` shrinks the fonts to fit the width
    /// (`adjustsFontSizeToFitWidth`: UIKit scales the text continuously down to
    /// `minimumScaleFactor` so one line fits exactly, uikit/label/fitting: 17 pt text 159 wide in
    /// a 120 pt label draws at 12.83 pt) and lets letters tighten before truncation when allowed.
    func layout(width: CGFloat?, fitting: Bool) -> TextLayout? {
        let runs = runs
        guard !runs.isEmpty, runs.contains(where: { !$0.text.isEmpty }) else { return nil }
        let engine = UIKitScene.shared.textEngine
        let limit = numberOfLines > 0 ? numberOfLines : nil
        let truncation: TextTruncationMode
        switch lineBreakMode {
        case .byTruncatingHead: truncation = .head
        case .byTruncatingMiddle: truncation = .middle
        default: truncation = .tail
        }
        let wrap = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var scale: CGFloat = 1
        var tightens = false
        if fitting, let wrap, numberOfLines == 1, adjustsFontSizeToFitWidth || allowsDefaultTighteningForTruncation {
            let unscaled = engine.layout(runs.map { StyledRun($0.text, font: $0.font.resolved) }, options: TextLayoutOptions(lineLimit: 1, truncationMode: .tail), width: nil)
            if unscaled.size.width > wrap {
                if adjustsFontSizeToFitWidth, minimumScaleFactor > 0, minimumScaleFactor < 1 {
                    scale = max(minimumScaleFactor, wrap / unscaled.size.width)
                } else if allowsDefaultTighteningForTruncation {
                    // UIKit tightens only when that makes the line fit (a 72nd of the size per
                    // character at most); "Tightened before truncating" at 213 in 200 truncates plain.
                    let characters = CGFloat(runs.reduce(0) { $0 + $1.text.count })
                    tightens = unscaled.size.width - characters * font.pointSize / 72 <= wrap
                }
            }
        }
        let options = TextLayoutOptions(lineLimit: limit, truncationMode: truncation, allowsTightening: tightens)
        if fitting { fittedScale = scale }
        let styled = runs.map { StyledRun($0.text, font: (scale == 1 ? $0.font : $0.font.withSize($0.font.pointSize * scale)).resolved) }
        // Scaled to fit exactly, the line needs no width (nothing to truncate; a width a hair
        // under the scaled text's rounded measure would truncate it); at the floor it does.
        let exact = scale < 1 && scale > minimumScaleFactor
        return engine.layout(styled, options: options, width: exact ? nil : wrap)
    }

    /// The text's size: the layout's width (rounded up to the pixel) and the font's height for
    /// the lines, as UILabel reports it. The recorded engine answers a wrapped request as one
    /// line of the recorded height, so a single-line answer's line count comes from that height
    /// in the font's pitch.
    func textSize(fitting width: CGFloat?) -> CGSize {
        let scale = UIScreen.main.scale
        let font = tallestFont
        guard let layout = layout(width: width) else { return CGSize(width: 0, height: font.labelHeight(lines: 1, scale: scale)) }
        let pitch = font.lineHeight + font.leading
        let lines = layout.lines.count > 1 ? layout.lines.count : max(1, Int((layout.size.height / pitch).rounded()))
        return CGSize(width: layout.size.width.roundedUp(to: scale), height: font.labelHeight(lines: lines, scale: scale))
    }

    /// Whether the label has text to size: an empty label fits and measures 0 × 0
    /// (uikit/autolayout/hugging), its text rect keeps the line height.
    private var hasText: Bool { runs.contains { !$0.text.isEmpty } }

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        guard hasText else { return .zero }
        let width: CGFloat? = size.width > 0 && size.width < CGFloat.greatestFiniteMagnitude ? size.width : nil
        // A one-line label reports its whole width; a wrapping one fits the proposal.
        if numberOfLines == 1 { return textSize(fitting: nil) }
        let fitted = textSize(fitting: width)
        return CGSize(width: width.map { min($0, fitted.width) } ?? fitted.width, height: fitted.height)
    }

    /// The width Auto Layout gave a wrapping label on its first pass (UIKit sets a multi-line
    /// label's preferred width from its solved width and solves again; Layout/LayoutEngine.swift).
    var layoutWrapWidth: CGFloat = 0

    /// The intrinsic size: unbounded, or wrapped to the preferred layout width; a label that
    /// wraps in a table cell reports a point more than its fit (uikit/table/selfsizing: two
    /// 15 pt lines fit in 36 and take 37 under constraints, three 54 and 55, two 13 pt lines
    /// 31.5 and 32.5), while a collection cell's takes its fit (uikit/collection/rest: three
    /// 15 pt lines in a 70 pt item, 54 and the 16 of margins).
    override open var intrinsicContentSize: CGSize {
        guard hasText else { return .zero }
        let width: CGFloat? = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : (numberOfLines != 1 && layoutWrapWidth > 0 ? layoutWrapWidth : nil)
        var size = textSize(fitting: width)
        if width != nil, size.height > font.labelHeight(lines: 1, scale: UIScreen.main.scale), isInTableCell { size.height += 1 }
        return size
    }

    private var isInTableCell: Bool {
        var view = superview
        while let current = view {
            if current is UITableViewCell { return true }
            if current is UICollectionViewCell { return false }
            view = current.superview
        }
        return true
    }

    /// The text's rectangle in `bounds`: one line measures unbounded (it truncates rather than
    /// wraps), the block is centred vertically on the point grid.
    open func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let size = textSize(fitting: numberOfLines == 1 ? nil : bounds.width)
        return CGRect(x: bounds.minX, y: bounds.minY + ((bounds.height - size.height) / 2).rounded(), width: min(size.width, bounds.width), height: size.height)
    }

    /// The baselines of the text block in `size`: the text rect's top (rounded, as
    /// `textRect(forBounds:)` places it) plus the ascender rounded to the pixel, per line
    /// (`uikit/autolayout/baseline`: 10.5, 12.5, 16, 19, 26.5 and 32.5 for the 11, 13, 17, 20,
    /// 28 and 34 pt system fonts' ascenders 10.47, 12.38, 16.19, 19.04, 26.66 and 32.37).
    override func textBaselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) {
        guard let layout = layout(width: numberOfLines == 1 ? nil : size.width), !layout.lines.isEmpty else { return (0, size.height) }
        let font = tallestFont
        let pitch = font.lineHeight + font.leading
        let lines = CGFloat(layout.lines.count)
        let top = textRect(forBounds: CGRect(origin: .zero, size: size), limitedToNumberOfLines: numberOfLines).minY
        let scale = UIScreen.main.scale
        let first = top + (font.ascender * scale).rounded() / scale
        return (first, first + pitch * (lines - 1))
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let layout = layout(width: bounds.width, fitting: true) else { return }
        let lines = layout.lines
        guard !lines.isEmpty else { return }
        let runs = runs
        let scale = fittedScale
        // The lines share the tallest run's pitch; mixed runs sit on one baseline (the tallest
        // font's ascender), as UIKit draws attributed text (uikit/label/fitting).
        let font = scale == 1 ? tallestFont : tallestFont.withSize(tallestFont.pointSize * scale)
        let pitch = font.lineHeight + font.leading
        let textHeight = font.lineHeight * CGFloat(lines.count) + font.leading * CGFloat(lines.count - 1)
        // The block is centred vertically; each line's baseline sits at the ascender.
        let top = (bounds.height - textHeight) / 2
        let labelColor = (isEnabled ? textColor : .tertiaryLabel).rgba(for: style)
        let alignment = textAlignment
        for (index, line) in lines.enumerated() {
            let baseline = context.origin.y + top + pitch * CGFloat(index) + font.ascender
            let inset: CGFloat
            switch alignment {
            case .center: inset = (bounds.width - line.inkWidth) / 2
            case .right: inset = bounds.width - line.inkWidth
            default: inset = 0
            }
            for fragment in line.fragments {
                let run = runs.indices.contains(fragment.run) ? runs[fragment.run] : Run(text: "", font: self.font, color: nil)
                let runFont = scale == 1 ? run.font : run.font.withSize(run.font.pointSize * scale)
                let color = isEnabled ? (run.color?.rgba(for: style) ?? labelColor) : labelColor
                list.append(.drawText(fragment.text, DisplayFont(runFont.resolved), origin: CGPoint(x: context.origin.x + inset + fragment.x, y: baseline), color))
            }
        }
    }
}

extension CGFloat {
    /// Rounded up to the pixel grid of `scale` pixels per point.
    func roundedUp(to scale: CGFloat) -> CGFloat { (self * scale).rounded(.up) / scale }
}

extension UIView {
    /// Labels in the subtree measure again after a font loads (`UIKitScene.fontsDidLoad`).
    func fontsDidLoadRecursively() {
        if let label = self as? UILabel {
            label.invalidateIntrinsicContentSize()
            label.setNeedsDisplay()
            label.superview?.setNeedsLayout()
        }
        for subview in subviews { subview.fontsDidLoadRecursively() }
    }
}
