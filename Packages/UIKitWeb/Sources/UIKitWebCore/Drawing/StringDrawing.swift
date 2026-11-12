// String, attributed string and image drawing inside `draw(_:)` (Docs/elements/UIKit/Drawing.md):
// `"text".draw(at:withAttributes:)`, `draw(in:withAttributes:)` and `size(withAttributes:)`,
// `NSAttributedString.draw(at:)` / `draw(in:)` / `size()`, `UIImage.draw(at:)` / `draw(in:)`,
// all recorded into the current graphics context through its transform, alpha and shadow.
// Measured on the iPhone SE simulator (uikit/draw/text).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The paragraph attributes string drawing reads: the alignment and the line break mode.
open class NSParagraphStyle: @unchecked Sendable {
    public internal(set) var alignment: NSTextAlignment = .natural
    public internal(set) var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public internal(set) var lineSpacing: CGFloat = 0
    /// Line height bounds (0: none), kept for the app; the labels lay lines out at their
    /// font's height.
    public internal(set) var minimumLineHeight: CGFloat = 0
    public internal(set) var maximumLineHeight: CGFloat = 0
    public internal(set) var lineHeightMultiple: CGFloat = 0
    public internal(set) var paragraphSpacing: CGFloat = 0
    /// How lines break around words (`.standard` by default, as on iOS); kept, the labels break
    /// at the last word that fits.
    public internal(set) var lineBreakStrategy: LineBreakStrategy = .standard
    public init() {}

    /// The strategies for breaking lines while laying out paragraphs.
    public struct LineBreakStrategy: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let pushOut = LineBreakStrategy(rawValue: 1 << 0)
        public static let hangulWordPriority = LineBreakStrategy(rawValue: 1 << 16)
        public static let standard = LineBreakStrategy(rawValue: 0xFFFF)
    }
    public static var `default`: NSParagraphStyle { NSParagraphStyle() }
    public func mutableCopy() -> Any {
        let copy = NSMutableParagraphStyle()
        copy.alignment = alignment
        copy.lineBreakMode = lineBreakMode
        copy.lineSpacing = lineSpacing
        copy.minimumLineHeight = minimumLineHeight
        copy.maximumLineHeight = maximumLineHeight
        copy.lineHeightMultiple = lineHeightMultiple
        copy.paragraphSpacing = paragraphSpacing
        copy.lineBreakStrategy = lineBreakStrategy
        return copy
    }
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {
    open override var alignment: NSTextAlignment { get { super.alignment } set { super.alignment = newValue } }
    open override var lineBreakMode: NSLineBreakMode { get { super.lineBreakMode } set { super.lineBreakMode = newValue } }
    open override var lineSpacing: CGFloat { get { super.lineSpacing } set { super.lineSpacing = newValue } }
    open override var minimumLineHeight: CGFloat { get { super.minimumLineHeight } set { super.minimumLineHeight = newValue } }
    open override var maximumLineHeight: CGFloat { get { super.maximumLineHeight } set { super.maximumLineHeight = newValue } }
    open override var lineHeightMultiple: CGFloat { get { super.lineHeightMultiple } set { super.lineHeightMultiple = newValue } }
    open override var paragraphSpacing: CGFloat { get { super.paragraphSpacing } set { super.paragraphSpacing = newValue } }
    open override var lineBreakStrategy: LineBreakStrategy { get { super.lineBreakStrategy } set { super.lineBreakStrategy = newValue } }
}

extension NSAttributedString {
    /// The attributes at the string's start (drawing uses one font and colour for the string).
    var uniformAttributes: [Key: Any] { length > 0 ? attributes(at: 0, effectiveRange: nil) : [:] }
}

extension NSAttributedString.Key {
    public static let font = NSAttributedString.Key("NSFont")
    public static let foregroundColor = NSAttributedString.Key("NSColor")
    public static let paragraphStyle = NSAttributedString.Key("NSParagraphStyle")
    public static let backgroundColor = NSAttributedString.Key("NSBackgroundColor")
    public static let underlineStyle = NSAttributedString.Key("NSUnderline")
    public static let strikethroughStyle = NSAttributedString.Key("NSStrikethrough")
    public static let underlineColor = NSAttributedString.Key("NSUnderlineColor")
    public static let strikethroughColor = NSAttributedString.Key("NSStrikethroughColor")
    public static let kern = NSAttributedString.Key("NSKern")
    public static let baselineOffset = NSAttributedString.Key("NSBaselineOffset")
    public static let link = NSAttributedString.Key("NSLink")
    public static let attachment = NSAttributedString.Key("NSAttachment")
}

/// An attachment in an attributed string: an image (or file contents) and the bounds it
/// takes in the line. Attributed text holds it under `.attachment` at U+FFFC; text views show
/// the attachment character's run as text (attachments are not laid out inline yet).
open class NSTextAttachment: @unchecked Sendable {
    /// The character an attachment stands on.
    public static let character: Int = 0xFFFC
    open var image: UIImage?
    open var contents: Data?
    open var fileType: String?
    open var bounds: CGRect = .zero
    public init(data contentData: Data?, ofType uti: String?) {
        contents = contentData
        fileType = uti
    }
    public convenience init() { self.init(data: nil, ofType: nil) }
    public convenience init(image: UIImage) {
        self.init(data: nil, ofType: nil)
        self.image = image
    }
}

extension NSAttributedString {
    /// A one-character string holding `attachment`.
    public convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }
}

/// The underline and strikethrough styles (`NSUnderlineStyle.single.rawValue` as the
/// attribute's value); every non-zero style draws one line here. Foundation keeps the type in
/// UIKit and AppKit, so the module declares it everywhere.
public struct NSUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 1)
    public static let thick = NSUnderlineStyle(rawValue: 2)
    public static let double = NSUnderlineStyle(rawValue: 9)
    public static let patternDot = NSUnderlineStyle(rawValue: 0x100)
    public static let patternDash = NSUnderlineStyle(rawValue: 0x200)
    public static let byWord = NSUnderlineStyle(rawValue: 0x8000)
}

/// What string drawing resolves from an attribute dictionary: UIKit's defaults are Helvetica 12
/// (spelled as the 12 pt system font here) in black, natural alignment. An attributed string
/// draws every range in its own font and colour, underlined or struck through where asked
/// (`.underlineStyle` / `.strikethroughStyle` other than 0, in `.underlineColor` /
/// `.strikethroughColor` or the text's colour); the paragraph style is read at the start.
struct StringDrawingStyle {
    struct Run {
        var text: String
        var font: UIFont
        var color: UIColor
        var underline: UIColor?
        var strikethrough: UIColor?
    }

    var font: UIFont = .systemFont(ofSize: 12)
    var color: UIColor = .black
    var alignment: NSTextAlignment = .natural
    var lineBreakMode: NSLineBreakMode = .byWordWrapping
    /// The ranges of an attributed string; empty for a plain string (one run in `font`).
    var runs: [Run] = []

    init(_ attributes: [NSAttributedString.Key: Any]?) {
        guard let attributes else { return }
        if let font = attributes[.font] as? UIFont { self.font = font }
        if let color = attributes[.foregroundColor] as? UIColor { self.color = color }
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            alignment = paragraph.alignment
            lineBreakMode = paragraph.lineBreakMode
        }
    }

    @MainActor init(_ attributed: NSAttributedString) {
        self.init(attributed.uniformAttributes)
        let utf16 = Array(attributed.string.utf16)
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attributes, range, _ in
            let piece = String(decoding: utf16[range.location..<min(utf16.count, range.location + range.length)], as: UTF16.self)
            let color = attributes[.foregroundColor] as? UIColor ?? .black
            func line(_ style: NSAttributedString.Key, _ colorKey: NSAttributedString.Key) -> UIColor? {
                let value = attributes[style]
                let on = (value as? Int).map { $0 != 0 } ?? (value as? NSUnderlineStyle).map { !$0.isEmpty } ?? false
                return on ? (attributes[colorKey] as? UIColor ?? color) : nil
            }
            runs.append(Run(text: piece, font: attributes[.font] as? UIFont ?? .systemFont(ofSize: 12), color: color,
                            underline: line(.underlineStyle, .underlineColor), strikethrough: line(.strikethroughStyle, .strikethroughColor)))
        }
    }

    /// The runs to lay out: the attributed ranges, or the whole string in one.
    func styledRuns(for string: String) -> [Run] {
        runs.isEmpty ? [Run(text: string, font: font, color: color, underline: nil, strikethrough: nil)] : runs
    }
}

#if os(WASI)
/// `(text as NSString).draw(...)`: the same drawing and measuring as the string's.
extension NSString {
    @preconcurrency @MainActor public func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        string.draw(at: point, withAttributes: attributes)
    }
    @preconcurrency @MainActor public func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        string.draw(in: rect, withAttributes: attributes)
    }
    @preconcurrency @MainActor public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize {
        string.size(withAttributes: attributes)
    }
    @preconcurrency @MainActor public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext? = nil) -> CGRect {
        string.boundingRect(with: size, options: options, attributes: attributes, context: context)
    }
}
#endif

extension StringProtocol {
    /// Draws the string with its top-left corner at `point`, unwrapped (line breaks only at newlines).
    @preconcurrency @MainActor public func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        UIGraphicsGetCurrentContext()?.drawString(String(self), style: StringDrawingStyle(attributes), at: point, width: nil, height: nil)
    }

    /// Draws the string wrapped in `rect`, the lines that fit its height only.
    @preconcurrency @MainActor public func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        UIGraphicsGetCurrentContext()?.drawString(String(self), style: StringDrawingStyle(attributes), at: rect.origin, width: rect.width, height: rect.height)
    }

    /// The string's unwrapped size in the attributes' font.
    @preconcurrency @MainActor public func size(withAttributes attributes: [NSAttributedString.Key: Any]? = nil) -> CGSize {
        UIGraphicsRecordingContext.measure(String(self), style: StringDrawingStyle(attributes), width: nil)
    }

    /// The string's bounding rectangle wrapped to `size.width` (the height ignored).
    @preconcurrency @MainActor public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], attributes: [NSAttributedString.Key: Any]? = nil, context: NSStringDrawingContext? = nil) -> CGRect {
        let width = size.width > 0 && size.width.isFinite ? size.width : nil
        return CGRect(origin: .zero, size: UIGraphicsRecordingContext.measure(String(self), style: StringDrawingStyle(attributes), width: width))
    }
}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 2)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 8)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 32)
}

public final class NSStringDrawingContext {
    public init() {}
}

extension NSAttributedString {
    @preconcurrency @MainActor public func draw(at point: CGPoint) {
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(self), at: point, width: nil, height: nil)
    }
    @preconcurrency @MainActor public func draw(in rect: CGRect) {
        UIGraphicsGetCurrentContext()?.drawString(string, style: StringDrawingStyle(self), at: rect.origin, width: rect.width, height: rect.height)
    }
    @preconcurrency @MainActor public func size() -> CGSize {
        UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(self), width: nil)
    }
    @preconcurrency @MainActor public func boundingRect(with size: CGSize, options: NSStringDrawingOptions = [], context: NSStringDrawingContext? = nil) -> CGRect {
        let width = size.width > 0 && size.width.isFinite ? size.width : nil
        return CGRect(origin: .zero, size: UIGraphicsRecordingContext.measure(string, style: StringDrawingStyle(self), width: width))
    }
}

extension UIImage {
    /// Draws the image at its own size with its top-left corner at `point`.
    @preconcurrency @MainActor public func draw(at point: CGPoint) { draw(in: CGRect(origin: point, size: size)) }
    @preconcurrency @MainActor public func draw(at point: CGPoint, blendMode: CGBlendMode, alpha: CGFloat) { draw(in: CGRect(origin: point, size: size), blendMode: blendMode, alpha: alpha) }
    /// Draws the image scaled into `rect`.
    @preconcurrency @MainActor public func draw(in rect: CGRect) { UIGraphicsGetCurrentContext()?.drawImage(self, in: rect, alpha: 1) }
    /// Draws the image scaled into `rect`, composited with `blendMode` at `alpha`.
    @preconcurrency @MainActor public func draw(in rect: CGRect, blendMode: CGBlendMode, alpha: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.withBlendMode(blendMode) { context.drawImage(self, in: rect, alpha: alpha) }
    }
}

extension UIGraphicsRecordingContext {
    /// The string's laid-out size: the engine's width (unbounded, or wrapped to `width`) and
    /// the tallest font's line pitch per line.
    @preconcurrency @MainActor static func measure(_ string: String, style: StringDrawingStyle, width: CGFloat?) -> CGSize {
        guard !string.isEmpty else { return .zero }
        let runs = style.styledRuns(for: string)
        let layout = UIKitScene.shared.textEngine.layout(runs.map { StyledRun($0.text, font: $0.font.resolved) }, options: TextLayoutOptions(), width: width)
        let lines = max(1, layout.lines.count)
        let font = runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? style.font
        let pitch = font.lineHeight + font.leading
        return CGSize(width: layout.size.width, height: pitch * CGFloat(lines) - font.leading)
    }

    /// Lays the string out (unbounded, or wrapped to `width`) and records its lines from `origin`,
    /// aligned within `width`, dropping the lines past `height`; each fragment in its run's font
    /// and colour, with the run's underline and strikethrough (uikit/draw/rest).
    @preconcurrency @MainActor func drawString(_ string: String, style: StringDrawingStyle, at origin: CGPoint, width: CGFloat?, height: CGFloat?) {
        guard !string.isEmpty else { return }
        let runs = style.styledRuns(for: string)
        let font = runs.map(\.font).max { $0.lineHeight < $1.lineHeight } ?? style.font
        let layout = UIKitScene.shared.textEngine.layout(runs.map { StyledRun($0.text, font: $0.font.resolved) }, options: TextLayoutOptions(), width: width)
        let pitch = font.lineHeight + font.leading
        let appearance = UITraitCollection.current.userInterfaceStyle
        let colors = runs.map { $0.color.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha)) }
        let fonts = runs.map { DisplayFont($0.font.resolved) }
        var commands: [DisplayCommand] = []
        var extent = CGRect(origin: origin, size: .zero)
        for (index, line) in layout.lines.enumerated() {
            let top = pitch * CGFloat(index)
            if let height, top + font.lineHeight > height + 0.5 { break }
            let inset: CGFloat
            switch style.alignment {
            case .center: inset = width.map { ($0 - line.inkWidth) / 2 } ?? 0
            case .right: inset = width.map { $0 - line.inkWidth } ?? 0
            default: inset = 0
            }
            let baseline = origin.y + top + font.ascender
            for fragment in line.fragments {
                let run = min(max(0, fragment.run), runs.count - 1)
                let x = origin.x + inset + fragment.x
                commands.append(.drawText(fragment.text, fonts[run], origin: CGPoint(x: x, y: baseline), colors[run]))
                extent = extent.union(CGRect(x: x, y: baseline - runs[run].font.ascender, width: fragment.width, height: runs[run].font.lineHeight))
                let decorations = SystemFontMetricsTables.textDecorationMetrics(for: runs[run].font.resolved)
                if let underline = runs[run].underline {
                    // UIKit's string drawing draws the underline at least a point thick, its top
                    // a whole number of points under the baseline (the table's centre less half
                    // the thickness, rounded: 2 pt at 15 and 17 pt), antialiased, not snapped.
                    let thickness = max(1, decorations.thickness)
                    let top = baseline + (decorations.underlineOffset - thickness / 2).rounded()
                    commands.append(.fillRect(CGRect(x: x, y: top, width: fragment.width, height: thickness), underline.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha))))
                }
                if let strikethrough = runs[run].strikethrough {
                    // The strikethrough centres on half the x-height above the baseline.
                    let top = baseline - decorations.xHeight / 2 - decorations.thickness / 2
                    commands.append(.fillRect(CGRect(x: x, y: top, width: fragment.width, height: decorations.thickness), strikethrough.rgba(for: appearance).multiplyingAlpha(by: Double(currentAlpha))))
                }
            }
        }
        record(commands, bounds: extent.insetBy(dx: -2, dy: -2))
    }


    /// Records the image scaled into `rect`: a symbol through the symbol painter, a catalog
    /// image as an image draw, an image context's recording replayed.
    @preconcurrency @MainActor func drawImage(_ image: UIImage, in rect: CGRect, alpha: CGFloat) {
        let style = UITraitCollection.current.userInterfaceStyle
        let tint: RGBA? = image.renderingMode == .alwaysTemplate || (image.renderingMode == .automatic && image.isSystemSymbol)
            ? (image.tint ?? UIColor.label).rgba(for: style) : image.tint?.rgba(for: style)
        var list = DisplayList()
        if let drawing = image.drawing {
            for command in drawing.commands(in: rect) { list.append(command) }
        } else if image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: rect, color: tint ?? UIColor.label.rgba(for: style), weight: image.symbolConfiguration?.weight?.css ?? 400, into: &list)
        } else {
            let catalog = UIKitScene.shared.assetCatalog
            guard let resource = catalog.image(named: image.name),
                  let variant = resource.variants.first(where: { $0.scale == scale }) ?? resource.variants.max(by: { $0.scale < $1.scale }) else { return }
            var draw = ImageDraw(file: variant.file, scale: variant.scale, pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: rect)
            draw.tint = tint
            list.append(.drawImage(draw))
        }
        let opacity = Double(currentAlpha * alpha)
        if opacity < 1 {
            record([.beginGroup(opacity: opacity)] + list.commands + [.endGroup], bounds: rect)
        } else {
            record(list.commands, bounds: rect)
        }
    }
}
