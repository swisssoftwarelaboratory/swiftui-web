// Shared between the Apple harness and SwiftUIWeb: every (string, font, width) that text
// fixtures use. GoldenGen measures each with real SwiftUI and writes Fixtures/Goldens/text-metrics.json;
// the headless text engine replays those numbers so Tier A layout stays exact.
import SwiftUI

/// A font spelled in a toolchain-neutral way. `key` must match `ResolvedFont.key` in SwiftUIWebCore.
public enum FixtureFont: Hashable, Sendable {
    /// "body", "title", … with optional overrides; `category` is a Dynamic Type size ("XS", "S", "M",
    /// "L", "XL", "XXL", "XXXL", "AXM", "AXL", "AXXL", "AXXXL", "AXXXXL": UIKit's short names) the
    /// text is measured at, nil for the environment's (sw-dynamic-type).
    case style(String, weight: String? = nil, design: String? = nil, italic: Bool = false, category: String? = nil)
    case system(size: CGFloat, weight: String, design: String, italic: Bool = false)          // weight "regular"…"black", design "default"…
    case custom(String, size: CGFloat, weight: String = "regular", italic: Bool = false)      // a bundled font by PostScript name (Fixtures/Fonts)

    public static let weights: [String: (Font.Weight, Int)] = [
        "ultraLight": (.ultraLight, 100), "thin": (.thin, 200), "light": (.light, 300), "regular": (.regular, 400),
        "medium": (.medium, 500), "semibold": (.semibold, 600), "bold": (.bold, 700), "heavy": (.heavy, 800), "black": (.black, 900),
    ]

    public static let styles: [String: Font.TextStyle] = [
        "largeTitle": .largeTitle, "title": .title, "title2": .title2, "title3": .title3, "headline": .headline,
        "subheadline": .subheadline, "body": .body, "callout": .callout, "footnote": .footnote, "caption": .caption, "caption2": .caption2,
    ]

    static func design(_ name: String?) -> Font.Design? {
        switch name {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        case nil, "default": return nil
        default: fatalError("unknown design \(name!)")
        }
    }

    /// The Dynamic Type sizes by UIKit's short category names.
    public static let categories: [String: DynamicTypeSize] = [
        "XS": .xSmall, "S": .small, "M": .medium, "L": .large, "XL": .xLarge, "XXL": .xxLarge, "XXXL": .xxxLarge,
        "AXM": .accessibility1, "AXL": .accessibility2, "AXXL": .accessibility3, "AXXXL": .accessibility4, "AXXXXL": .accessibility5,
    ]

    /// The Dynamic Type size a style font is measured at, nil for the environment's.
    public var dynamicTypeSize: DynamicTypeSize? {
        if case .style(_, _, _, _, let category?) = self { return Self.categories[category]! }
        return nil
    }

    public var key: String {
        switch self {
        case .style(let name, let weight, let design, let italic, let category):
            var key = "style:\(name)"
            if let category { key += ":\(category)" }
            if let weight { key += ":w\(Self.weights[weight]!.1)" }
            if let design, design != "default" { key += ":\(design)" }
            return key + (italic ? ":italic" : "")
        case .system(let size, let weight, let design, let italic):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "system:\(sizeText):\(Self.weights[weight]!.1):\(design)" + (italic ? ":italic" : "")
        case .custom(let name, let size, let weight, let italic):
            let sizeText = size == size.rounded() ? "\(Int(size))" : "\(size)"
            return "custom:\(name):\(sizeText):\(Self.weights[weight]!.1)" + (italic ? ":italic" : "")
        }
    }

    public var font: Font {
        switch self {
        case .style(let name, let weight, let design, let italic, _):
            let font = Font.system(Self.styles[name]!, design: Self.design(design), weight: weight.map { Self.weights[$0]!.0 })
            return italic ? font.italic() : font
        case .system(let size, let weight, let design, let italic):
            let font = Font.system(size: size, weight: Self.weights[weight]!.0, design: Self.design(design) ?? .default)
            return italic ? font.italic() : font
        case .custom(let name, let size, let weight, let italic):
            var font = Font.custom(name, size: size)
            if weight != "regular" { font = font.weight(Self.weights[weight]!.0) }
            return italic ? font.italic() : font
        }
    }
}

/// Layout options a text is measured with (`lineLimit`, `truncationMode`, `lineSpacing`).
/// Spelled into the key exactly like `TextLayoutOptions` in SwiftUIWebCore (`TextMetricsKey`).
public struct TextMetricOptions: Hashable, Sendable {
    public var lineLimit: Int? = nil
    /// Reserved lines: `lineLimit(n, reservesSpace: true)` when equal to `lineLimit`, otherwise
    /// the lower bound of a range limit.
    public var minimumLines = 0
    public var lineSpacing: CGFloat = 0
    public var truncation = "tail"      // "head" | "middle" | "tail"
    /// `kerning` / `tracking` in points (0 = none).
    public var kerning: CGFloat = 0
    public var tracking: CGFloat = 0
    /// `textScale(.secondary)`.
    public var secondaryScale = false
    /// `minimumScaleFactor` (1 = none) and `allowsTightening`.
    public var minimumScaleFactor: CGFloat = 1
    public var allowsTightening = false

    public init(lineLimit: Int? = nil, minimumLines: Int = 0, lineSpacing: CGFloat = 0, truncation: String = "tail", kerning: CGFloat = 0, tracking: CGFloat = 0,
                secondaryScale: Bool = false, minimumScaleFactor: CGFloat = 1, allowsTightening: Bool = false) {
        self.secondaryScale = secondaryScale
        self.minimumScaleFactor = minimumScaleFactor
        self.allowsTightening = allowsTightening
        self.lineLimit = lineLimit
        self.minimumLines = minimumLines
        self.lineSpacing = lineSpacing
        self.truncation = truncation
        self.kerning = kerning
        self.tracking = tracking
    }

    public static let `default` = TextMetricOptions()

    /// The suffix appended to the width slot of a key.
    public var keySuffix: String {
        var suffix = ""
        if let lineLimit { suffix += ";l\(lineLimit)" }
        if minimumLines > 0 { suffix += ";r\(minimumLines)" }
        if lineSpacing != 0 { suffix += ";s\(lineSpacing)" }
        if truncation != "tail" { suffix += ";t\(truncation)" }
        if kerning != 0 { suffix += ";k\(kerning)" }
        if tracking != 0 { suffix += ";tr\(tracking)" }
        if secondaryScale { suffix += ";sc2" }
        if minimumScaleFactor < 1 { suffix += ";m\(minimumScaleFactor)" }
        if allowsTightening { suffix += ";tt" }
        return suffix
    }
}

public struct TextMetricRequest: Hashable, Sendable {
    /// One part of a concatenated text: a string in a font.
    public struct Run: Hashable, Sendable {
        public let string: String
        public let font: FixtureFont
        public init(_ string: String, _ font: FixtureFont) {
            self.string = string
            self.font = font
        }
    }

    public let runs: [Run]
    public let width: CGFloat?
    public let options: TextMetricOptions

    public init(_ string: String, _ font: FixtureFont, width: CGFloat? = nil, options: TextMetricOptions = .default) {
        self.runs = [Run(string, font)]
        self.width = width
        self.options = options
    }

    /// A mixed-font text (`Text("a").font(f1) + Text("b").font(f2)`).
    public init(runs: [Run], width: CGFloat? = nil, options: TextMetricOptions = .default) {
        self.runs = runs
        self.width = width
        self.options = options
    }

    public var string: String { runs.map(\.string).joined() }
    /// The fonts the request uses (one per run, in order).
    public var fonts: [FixtureFont] { runs.map(\.font) }

    /// Adjacent runs in the same font, merged: colour boundaries do not affect measurement.
    public var mergedRuns: [Run] {
        var merged: [Run] = []
        for run in runs {
            if let last = merged.last, last.font == run.font {
                merged[merged.count - 1] = Run(last.string + run.string, run.font)
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// Key in text-metrics.json: `<font>|<width><options>|<string>`, with `rich:<key>=<count>,…`
    /// as the font of a mixed-font text (see `TextMetricsKey` in SwiftUIWebCore).
    public var key: String {
        let merged = mergedRuns
        let fontSlot = merged.count == 1 ? merged[0].font.key : "rich:" + merged.map { "\($0.font.key)=\($0.string.count)" }.joined(separator: ",")
        return "\(fontSlot)|\(width.map { "\($0)" } ?? "")\(options.keySuffix)|\(string)"
    }
}

public enum TextMetricsRequests {
    /// The font text gets when nothing sets one: on macOS the 13 pt system font (16 pt line), not
    /// `.body` (18.5 pt line) — see decision 0010.
    public static let defaultFont = FixtureFont.system(size: 13, weight: "regular", design: "default")
    static func defaultFont(weight: String) -> FixtureFont { .system(size: 13, weight: weight, design: "default") }

    public static let styleNames = ["largeTitle", "title", "title2", "title3", "headline", "subheadline", "body", "callout", "footnote", "caption", "caption2"]
    public static let sample = "The quick brown fox"
    public static let paragraph = "Layout must wrap this sentence onto several lines inside a narrow frame."
    /// Two paragraphs separated by a hard line break.
    public static let twoParagraphs = "First line.\nSecond paragraph wraps here as well."
    public static let newlineShort = "Left\nRight side"
    public static let longWord = "Supercalifragilistic"
    /// Parts of the mixed-font concatenations in text/concatenation.
    public static let richParagraphHead = "Layout must "
    public static let richParagraphTail = "wrap this sentence onto several lines inside a narrow frame."

    public static let all: [TextMetricRequest] = {
        var requests: [TextMetricRequest] = iOSRequests + formGroupedRequests + [
            TextMetricRequest("Hello", .style("body")),
            TextMetricRequest("One", .style("body")),
            TextMetricRequest("Two", .style("body")),
            TextMetricRequest("Three", .style("body")),
            TextMetricRequest("Big", .style("largeTitle")),
            TextMetricRequest("small", .style("body")),
            TextMetricRequest("Bold", .style("body", weight: "bold")),
            TextMetricRequest("Bold", .style("body", weight: "semibold")),
            TextMetricRequest("Bold", .style("body", weight: "heavy")),
            TextMetricRequest("Weight", .style("body", weight: "semibold")),
            TextMetricRequest("Env", .style("title")),
            TextMetricRequest("Count: 0", .style("title")),
            TextMetricRequest("Count: 0", .style("body")),
            TextMetricRequest(paragraph, .style("body"), width: 150),
            TextMetricRequest(paragraph, .style("body"), width: 260),
            TextMetricRequest(paragraph, .style("body"), width: 400),
            TextMetricRequest(paragraph, .style("body")),
            TextMetricRequest("Hg", .style("body")),
            TextMetricRequest("OK", .style("body")),
            TextMetricRequest("Increment", .style("body")),
            TextMetricRequest("Label", .style("body")),
            TextMetricRequest("−", .style("body")),
            TextMetricRequest("+", .style("body")),
            TextMetricRequest("Plain", .style("body")),
            TextMetricRequest("Bordered", .style("body")),
            TextMetricRequest("Borderless", .style("body")),
            TextMetricRequest("Prominent", .style("body")),
            TextMetricRequest("Padded", .style("body")),
            TextMetricRequest("Count: 0", .system(size: 13, weight: "regular", design: "default")),
            TextMetricRequest("Hg", .style("largeTitle")),
            TextMetricRequest("Hg", .style("caption2")),
        ]
        for style in styleNames { requests.append(TextMetricRequest(sample, .style(style))) }
        // Strings that fixtures show in the default font (layout, paint, button, ForEach, Section).
        for word in ["Hello", "One", "Two", "Three", "small", "Env", "Count: 0", "Hg", "OK", "Increment", "Label", "−", "+",
                     "Plain", "Bordered", "Borderless", "Prominent", "Padded",
                     "Row 0", "Row 1", "Row 2", "Apple", "Banana", "Cherry", "Alpha", "Beta", "Gamma", "Fruits",
                     "Vegetables", "Carrot", "Leek", "Header", "Footer", "Top", "Bottom", "A", "B"] {
            requests.append(TextMetricRequest(word, defaultFont))
        }
        requests.append(TextMetricRequest(paragraph, defaultFont))
        for width: CGFloat in [150, 260, 400] { requests.append(TextMetricRequest(paragraph, defaultFont, width: width)) }
        for weight in ["semibold", "bold", "heavy"] { requests.append(TextMetricRequest("Bold", defaultFont(weight: weight))) }
        requests.append(TextMetricRequest("Weight", defaultFont(weight: "semibold")))
        // Bold trait per text style (text/bold-trait): record the candidate weights.
        for style in styleNames {
            for weight in ["medium", "semibold", "bold", "heavy"] { requests.append(TextMetricRequest("Bold", .style(style, weight: weight))) }
        }
        requests.append(TextMetricRequest("Bold", .system(size: 20, weight: "bold", design: "default")))
        // Section headers, should they turn out to be styled outside List/Form.
        for word in ["Fruits", "Vegetables", "Header"] {
            requests.append(TextMetricRequest(word, .style("headline")))
        }
        // Bordered button labels use the 13 pt point-size font.
        for label in ["OK", "Increment", "Label", "−", "+", "Bordered", "Prominent", "Padded", "Go"] {
            requests.append(TextMetricRequest(label, .system(size: 13, weight: "regular", design: "default")))
        }
        for size: CGFloat in [10, 12, 20, 24, 32] { requests.append(TextMetricRequest(sample, .system(size: size, weight: "regular", design: "default"))) }
        for weight in ["light", "medium", "bold", "black"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: weight, design: "default"))) }
        for design in ["rounded", "serif", "monospaced"] { requests.append(TextMetricRequest(sample, .system(size: 20, weight: "regular", design: design))) }

        // Text completeness (Phase 2): wrapped paragraphs, line limit, truncation, spacing, concatenation.
        for width: CGFloat in [100, 120, 134, 200, 300] { requests.append(TextMetricRequest(paragraph, defaultFont, width: width)) }
        for limit in [1, 2, 3, 10] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: limit))) }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 260, options: .init(lineLimit: 1)))
        for mode in ["head", "middle"] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 1, truncation: mode))) }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 2, truncation: "middle")))
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 3, minimumLines: 1)))
        for spacing: CGFloat in [4, 10] { requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineSpacing: spacing))) }
        requests.append(TextMetricRequest(paragraph, .style("body"), width: 150, options: .init(lineSpacing: 4)))
        requests.append(TextMetricRequest(paragraph, .style("title"), width: 300))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 1)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 2, minimumLines: 2)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineLimit: 4, minimumLines: 2)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(minimumLines: 3)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(lineSpacing: 10)))
        requests.append(TextMetricRequest("Hello", defaultFont, options: .init(truncation: "head")))
        requests.append(TextMetricRequest(twoParagraphs, defaultFont))
        // text/markdown, text/attributed: the runs markdown and attributed strings produce.
        let bold = FixtureFont.system(size: 13, weight: "bold", design: "default")
        let italic = FixtureFont.system(size: 13, weight: "regular", design: "default", italic: true)
        let boldItalic = FixtureFont.system(size: 13, weight: "bold", design: "default", italic: true)
        let mono = FixtureFont.system(size: 13, weight: "regular", design: "monospaced")
        requests.append(TextMetricRequest(runs: [.init("Plain ", defaultFont), .init("bold", bold), .init(" and ", defaultFont), .init("italic", italic),
                                                 .init(" and ", defaultFont), .init("both", boldItalic), .init(" done", defaultFont)]))
        for (string, font) in [("bold", bold), ("italic", italic), ("both", boldItalic), ("code", mono), ("struck", defaultFont), ("a link", defaultFont),
                               ("**not** markdown", defaultFont), ("Escaped *stars*", defaultFont), ("Plain attributed", defaultFont),
                               (" Starred", defaultFont), ("Rate ", defaultFont), (" now", defaultFont), (" Next", defaultFont), (" Bold", bold)] {
            requests.append(TextMetricRequest(string, font))
        }
        requests.append(TextMetricRequest(runs: [.init("Call ", defaultFont), .init("now", bold), .init(" or visit today", defaultFont)]))
        requests.append(TextMetricRequest(runs: [.init("Mono ", .style("title3")), .init("code", .style("title3", design: "monospaced")), .init(" and plain", .style("title3"))]))
        requests.append(TextMetricRequest(runs: [.init("Hello ", defaultFont), .init("world", .style("title")), .init(" under up link", defaultFont)]))
        requests.append(TextMetricRequest(runs: [.init("Strong", bold), .init(" emphasized", italic), .init(" code", mono), .init(" struck", defaultFont)]))
        // text/custom-font: the bundled Abel face at 20 and 13 pt, bold and italic traits, a wrapped paragraph.
        let abel = FixtureFont.custom("Abel-Regular", size: 20)
        for string in [sample, "Custom", "Abel 20", "System"] { requests.append(TextMetricRequest(string, abel)) }
        requests.append(TextMetricRequest("Abel 13", .custom("Abel-Regular", size: 13)))
        requests.append(TextMetricRequest("System", defaultFont))
        for string in ["Item A", "Item B", "Pick", "Detail", "Presented"] { requests.append(TextMetricRequest(string, defaultFont)) }   // nav/item, nav/path-change
        for string in ["Home", "Alerts", "Off", "Home content", "Alerts content", "Off content"] { requests.append(TextMetricRequest(string, defaultFont)) }   // tabview/tab-api
        for string in ["Align", "Shared", "Mixed", "Size", "Fruit"] { requests.append(TextMetricRequest(string, .style("body"))) }   // picker/options labels
        for string in ["One", "Two", "Small", "Large", "Fresh", "—"] { requests.append(TextMetricRequest(string, defaultFont)) }     // picker/options options
        requests.append(TextMetricRequest("Bold", .custom("Abel-Regular", size: 20, weight: "bold")))
        requests.append(TextMetricRequest("Italic", .custom("Abel-Regular", size: 20, italic: true)))
        requests.append(TextMetricRequest(paragraph, abel, width: 150))
        requests.append(TextMetricRequest("Abel 40", .custom("Abel-Regular", size: 40)))
        // text/dates: the date and time styles at UTC (a narrow no-break space before the period).
        for string in ["May 28, 2026", "8:26\u{202F}PM"] { requests.append(TextMetricRequest(string, defaultFont)) }
        // text/fit: minimumScaleFactor and allowsTightening.
        for width: CGFloat in [120, 100, 80, 60, 40] { requests.append(TextMetricRequest(sample, defaultFont, width: width, options: .init(lineLimit: 1, minimumScaleFactor: 0.5))) }
        for width: CGFloat in [100, 80, 60] { requests.append(TextMetricRequest(sample, defaultFont, width: width, options: .init(lineLimit: 1, minimumScaleFactor: 0.8))) }
        requests.append(TextMetricRequest(sample, defaultFont, width: 80, options: .init(minimumScaleFactor: 0.5)))
        requests.append(TextMetricRequest(sample, defaultFont, width: 60, options: .init(lineLimit: 2, minimumScaleFactor: 0.5)))
        requests.append(TextMetricRequest(sample, .style("title"), width: 100, options: .init(lineLimit: 1, minimumScaleFactor: 0.5)))
        for width: CGFloat in [116, 112, 108, 100] {
            requests.append(TextMetricRequest(sample, defaultFont, width: width, options: .init(lineLimit: 1, allowsTightening: true)))
            requests.append(TextMetricRequest(sample, defaultFont, width: width, options: .init(lineLimit: 1)))   // the same without tightening
        }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 2)))
        requests.append(TextMetricRequest(sample, defaultFont, width: 100, options: .init(lineLimit: 1, minimumScaleFactor: 0.5, allowsTightening: true)))
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: .init(lineLimit: 2, allowsTightening: true)))
        // textfield/vertical (a 200 pt field: 188 inside the bezel, 200 plain) and textfield/formatted.
        requests.append(TextMetricRequest(fixtureFieldNote, defaultFont))
        for width: CGFloat in [188, 200] {
            requests.append(TextMetricRequest(fixtureFieldNote, defaultFont, width: width))
            requests.append(TextMetricRequest(fixtureFieldNote, defaultFont, width: width, options: .init(lineLimit: 2)))
            requests.append(TextMetricRequest(fixtureFieldNote, defaultFont, width: width, options: .init(lineLimit: 4)))
            requests.append(TextMetricRequest(fixtureFieldNote, defaultFont, width: width, options: .init(lineLimit: 4, minimumLines: 2)))
        }
        for string in ["Short", "Notes", "1,234", "1234", "3.14159", "3.142", "25%", "$12.50", "42", "Age", "Price", "Share", "Amount", "Count"] {
            requests.append(TextMetricRequest(string, defaultFont))
        }
        requests.append(TextMetricRequest(twoParagraphs, defaultFont, width: 220))
        requests.append(TextMetricRequest(newlineShort, defaultFont))
        requests.append(TextMetricRequest(longWord, defaultFont, width: 60))
        requests.append(TextMetricRequest(longWord, defaultFont))
        // Toggle and Label fixtures (default font and, should the controls style their labels, body).
        for word in ["Enabled", "Title", "On", "Off", "Placeholder", "Name", "Password", "A", "B"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
        }
        // Sidebar list rows use the body font.
        for word in ["Apple", "Banana", "Cherry"] { requests.append(TextMetricRequest(word, .style("body"))) }
        // List section headers and footers: candidate styles and weights.
        for word in ["Fruits", "Vegetables", "Footer"] {
            for style in ["headline", "subheadline", "footnote", "caption", "caption2", "body"] {
                for weight in ["regular", "medium", "semibold", "bold"] {
                    requests.append(TextMetricRequest(word, .style(style, weight: weight)))
                }
            }
            for size: CGFloat in [11, 12] {
                for weight in ["regular", "medium", "semibold", "bold"] {
                    requests.append(TextMetricRequest(word, .system(size: size, weight: weight, design: "default")))
                }
            }
        }
        // NavigationLink labels: default font, the 13 pt point-size font of bordered buttons, body.
        for word in ["Root", "Detail", "Value", "Wide", "Push", "Deeper", "Content", "Small", "Left", "Right", "Apple detail",
                     "Number 1", "Number 2", "Number 3", "Go"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
            requests.append(TextMetricRequest(word, .style("body")))
        }
        // Picker, Slider and Stepper labels and options: candidate fonts for control text.
        for word in ["Fruit", "Volume", "Min", "Max", "Count", "Row", "0", "1", "2", "25", "50", "75", "100"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        for word in ["Apple", "Banana", "Cherry", "Fruit", "Min", "Max"] {
            for style in ["callout", "footnote", "caption", "caption2", "subheadline"] {
                requests.append(TextMetricRequest(word, .style(style)))
                for weight in ["regular", "medium", "semibold"] { requests.append(TextMetricRequest(word, .style(style, weight: weight))) }
            }
            for size: CGFloat in [10, 11, 12, 13] {
                for weight in ["regular", "medium", "semibold"] { requests.append(TextMetricRequest(word, .system(size: size, weight: weight, design: "default"))) }
            }
        }
        // Form rows, headers and footers.
        for word in ["Name", "Enabled", "Fruit", "Volume", "Count", "Save", "Plain", "Hello", "Account", "Options", "Footer"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
            for style in ["headline", "subheadline", "footnote", "caption", "callout", "title3"] {
                requests.append(TextMetricRequest(word, .style(style)))
                for weight in ["medium", "semibold", "bold"] { requests.append(TextMetricRequest(word, .style(style, weight: weight))) }
            }
        }
        // Lifecycle fixtures.
        for word in ["A0 D0", "A1 D0", "A1 D1", "A2 D1", "A2 D2", "Child", "Waiting", "Done"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Above", "Below"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Sheet", "Popover", "Alert", "Done", "OK", "Sheet content", "Popover content", "Alert title", "Message"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        // presentation/mac-* (sw-mac-presentation-looks): the presenting buttons at the window's
        // width, the sheet's and popover's texts, the alert's 13 pt bold title and 11 pt message
        // at the alert's content width, its buttons.
        for word in ["Delete…", "Sheet", "Popover"] { for width: CGFloat? in [nil, 376, 400] { requests.append(TextMetricRequest(word, defaultFont, width: width)) } }
        for word in ["Sheet title", "Popover title"] { for width: CGFloat? in [nil, 360, 320] { requests.append(TextMetricRequest(word, .style("headline"), width: width)) } }
        for word in ["Some content under the title.", "A line of content.", "Done"] { for width: CGFloat? in [nil, 360, 320] { requests.append(TextMetricRequest(word, defaultFont, width: width)) } }
        for width: CGFloat? in [nil, 220, 228, 260] {
            requests.append(TextMetricRequest("Delete the item?", .system(size: 13, weight: "bold", design: "default"), width: width))
            requests.append(TextMetricRequest("This cannot be undone.", .system(size: 13, weight: "regular", design: "default"), width: width))
        }
        for word in ["Delete", "Cancel"] { for width: CGFloat? in [nil, 104, 110] { requests.append(TextMetricRequest(word, defaultFont, width: width)) } }
        for word in ["One", "Two", "Three", "Four", "Five", "Six", "A", "B", "D", "E", "Low", "High", "Last"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["BB", "CCC", "F", "G", "H", "Header"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Canvas", "Corner"] { requests.append(TextMetricRequest(word, defaultFont)); requests.append(TextMetricRequest(word, defaultFont, width: 100)) }
        for word in ["Count: 0", "Count: 1", "Count: 2", "Flag"] { requests.append(TextMetricRequest(word, defaultFont)); requests.append(TextMetricRequest(word, .style("body"))) }
        for word in ["Ticks: 0", "Ticks: 1", "Live", "Slow"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Email", "Focused: none", "Focused: name", "Focused: email", "Focus email"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        for word in ["Heading", "Plain", "Secret", "Card", "Detail", "Save"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .system(size: 13, weight: "regular", design: "default")))
        }
        requests.append(TextMetricRequest("Tilt", defaultFont))
        requests.append(TextMetricRequest("Sky", defaultFont))
        requests.append(TextMetricRequest("First", defaultFont))
        requests.append(TextMetricRequest("Second", defaultFont))
        requests.append(TextMetricRequest("One", defaultFont))
        requests.append(TextMetricRequest("Two", defaultFont))
        requests.append(TextMetricRequest("Three", defaultFont))
        requests.append(TextMetricRequest("A", defaultFont))
        requests.append(TextMetricRequest("B", defaultFont))
        requests.append(TextMetricRequest("No Mail", defaultFont))
        requests.append(TextMetricRequest("Try again later.", defaultFont))
        requests.append(TextMetricRequest("No Results", defaultFont))
        requests.append(TextMetricRequest("Search again.", defaultFont))
        requests.append(TextMetricRequest("Retry", defaultFont))
        requests.append(TextMetricRequest("Share", defaultFont))
        requests.append(TextMetricRequest("Send", defaultFont))
        requests.append(TextMetricRequest("Share…", defaultFont))
        requests.append(TextMetricRequest("No Mail", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("No Results", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("Try again later.", .style("body")))
        requests.append(TextMetricRequest("Search again.", .style("body")))
        requests.append(TextMetricRequest("Check the spelling or try a new search.", .style("body")))
        requests.append(TextMetricRequest("Check the spelling or try a new search.", defaultFont))
        requests.append(TextMetricRequest("Details", defaultFont))
        requests.append(TextMetricRequest("Alpha", defaultFont))
        requests.append(TextMetricRequest("Beta", defaultFont))
        requests.append(TextMetricRequest("Header", defaultFont))
        requests.append(TextMetricRequest("Hi", defaultFont))
        for word in ["Menu", "Select"] { requests.append(TextMetricRequest(word, defaultFont)) }
        // Gauge fixtures: 13 pt labels, the accessory styles' 17 pt semibold, 12 pt, 11 pt and 24 pt medium value labels.
        for word in ["Battery", "Level", "60%", "Range", "30", "Total", "Tinted", "Cap", "Hidden", "40", "Bare"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["40", "30", "0", "100"] {
            requests.append(TextMetricRequest(word, .system(size: 17, weight: "semibold", design: "default")))
            requests.append(TextMetricRequest(word, .system(size: 11, weight: "regular", design: "default")))
            requests.append(TextMetricRequest(word, .system(size: 24, weight: "medium", design: "default")))
            requests.append(TextMetricRequest(word, .system(size: 12, weight: "regular", design: "default")))
        }
        for word in ["A", "B", "C", "D"] { requests.append(TextMetricRequest(word, .system(size: 11, weight: "regular", design: "default"))) }
        // dark/chrome: the circular gauge's 11 pt label proposed the stack's width.
        requests.append(TextMetricRequest("Battery", .system(size: 11, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Battery", .system(size: 11, weight: "regular", design: "default"), width: 360))
        // DatePicker fixtures: body labels, the field's 13 pt components, the calendar's 13 pt bold
        // header, 10 pt bold weekdays and 11 pt days, the clock's 13 pt numerals and 13 pt medium period.
        for word in ["Date", "When", "Time", "Range", "Off", "Compact", "Field", "Stepper", "Both", "Clock", "Calendar", "Echo"] {
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, defaultFont))
        }
        for word in ["3", "15", "16", "2025", "2026", "1", "12", "31", "59", "09", "00", "/", ":", ",", " ", "PM", "AM", " PM", ", "] {
            requests.append(TextMetricRequest(word, defaultFont))
        }
        for word in ["Mar 2025", "Feb 2025", "Apr 2025", "Jan 2026", "Dec 2025"] { requests.append(TextMetricRequest(word, defaultFont(weight: "bold"))) }
        for word in ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] { requests.append(TextMetricRequest(word, .system(size: 10, weight: "bold", design: "default"))) }
        for day in 1...31 { requests.append(TextMetricRequest("\(day)", .system(size: 11, weight: "regular", design: "default"))) }
        for hour in 1...12 { requests.append(TextMetricRequest("\(hour)", defaultFont)) }
        for word in ["PM", "AM"] { requests.append(TextMetricRequest(word, defaultFont(weight: "medium"))) }
        // TextEditor fixtures: the paragraph wrapped in the editor's 270 pt, the title font, the echo texts.
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 270))
        requests.append(TextMetricRequest("Hello", .style("title")))
        requests.append(TextMetricRequest("Hello\nWorld", defaultFont))
        requests.append(TextMetricRequest("Hello\nWorld", defaultFont, width: 270))
        requests.append(TextMetricRequest("Left", defaultFont, width: 270))
        for word in ["Empty", "Filled"] { requests.append(TextMetricRequest(word, defaultFont)) }
        // texteditor/corners: the find bar's field prompt, Done button (its 17 pt frame), the
        // Replace checkbox, the editors' lines.
        requests.append(TextMetricRequest("Find", defaultFont))
        requests.append(TextMetricRequest("Done", defaultFont, width: 17.5))
        requests.append(TextMetricRequest("Done", defaultFont, width: 17.5, options: TextMetricOptions(lineLimit: 1)))
        for width: CGFloat? in [nil, 0, 279] { requests.append(TextMetricRequest("Replace", .style("body"), width: width)) }
        for text in ["Find me here", "One\nTwo\nThree\nFour", (1...20).map { "Line \($0)" }.joined(separator: "\n")] {
            requests.append(TextMetricRequest(text, defaultFont))
            requests.append(TextMetricRequest(text, defaultFont, width: 290))
        }
        // label/corners: a text icon and its title, a wrapping title, the grouped form's labels
        // and formatted values (body style).
        for word in ["Arrow", "→"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for width: CGFloat in [155.5, 148.5] { requests.append(TextMetricRequest("A title that wraps onto a second line here", defaultFont, width: width)) }
        requests.append(TextMetricRequest("A title that wraps onto a second line here", defaultFont))
        for word in ["Price", "Share", "Enabled", "Kind", "Plain", "12.5", "25%", "Value", "One", "Two"] {
            requests.append(TextMetricRequest(word, .style("body")))
            requests.append(TextMetricRequest(word, defaultFont))
        }
        // ContentUnavailableView on macOS 27 (unavailable/basic, unavailable/corners): the title
        // is the bold title3 style (a 23 line), the description title3 (22).
        for word in ["No Mail", "No Items", "Nothing Here", "No Results"] {
            requests.append(TextMetricRequest(word, .style("title3", weight: "bold")))
        }
        for word in ["Try again later.", "Add one.", "Search again.", "Check the spelling or try a new search."] {
            requests.append(TextMetricRequest(word, .style("title3")))
            requests.append(TextMetricRequest(word, .style("title3"), width: 320))
            requests.append(TextMetricRequest(word, .style("title3"), width: 328))
        }
        // Table fixtures: headers (11 pt, bold when sorted), cells.
        for word in ["Name", "Color", "Count", "Empty", "ID"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, defaultFont(weight: "bold")))
            requests.append(TextMetricRequest(word, .system(size: 11, weight: "regular", design: "default")))
            requests.append(TextMetricRequest(word, .system(size: 11, weight: "bold", design: "default")))
        }
        for word in ["Fruit", "Cherry", "1", "2", "3", "12"] { requests.append(TextMetricRequest(word, defaultFont)) }
        // ColorPicker fixtures: labels.
        for word in ["Accent", "Tint"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("body")))
        }
        for word in ["Red", "Yellow", "40"] { requests.append(TextMetricRequest(word, defaultFont)) }
        requests.append(TextMetricRequest("Details", .style("body")))
        requests.append(TextMetricRequest("Outer", .style("body")))
        requests.append(TextMetricRequest("Inner", .style("body")))
        requests.append(TextMetricRequest("Header", .style("headline")))
        requests.append(TextMetricRequest("Name", defaultFont))
        requests.append(TextMetricRequest("Corey", defaultFont))
        requests.append(TextMetricRequest("Count", defaultFont))
        requests.append(TextMetricRequest("3", defaultFont))
        requests.append(TextMetricRequest("Network", defaultFont))
        requests.append(TextMetricRequest("Hidden", defaultFont))
        requests.append(TextMetricRequest("Shown", defaultFont))
        requests.append(TextMetricRequest("Toggle", defaultFont))
        requests.append(TextMetricRequest("Narrow", defaultFont))
        requests.append(TextMetricRequest("Value", defaultFont))
        requests.append(TextMetricRequest("Email", defaultFont))
        requests.append(TextMetricRequest("Apple", defaultFont))
        requests.append(TextMetricRequest("Open site", defaultFont))
        requests.append(TextMetricRequest("Visit", defaultFont))
        requests.append(TextMetricRequest("the site", defaultFont))
        requests.append(TextMetricRequest("Disabled", defaultFont))
        requests.append(TextMetricRequest("Large", .style("title")))
        requests.append(TextMetricRequest("Name", .style("body")))
        requests.append(TextMetricRequest("Network", .style("body")))
        requests.append(TextMetricRequest("Narrow", .style("body")))
        requests.append(TextMetricRequest("Wide", .style("body")))
        requests.append(TextMetricRequest("Toggle", .style("body")))
        requests.append(TextMetricRequest("Hidden", .style("body")))
        requests.append(TextMetricRequest("Count", .style("body")))
        requests.append(TextMetricRequest("Email", .style("body")))
        requests.append(TextMetricRequest("Settings", defaultFont))
        requests.append(TextMetricRequest("Inside", defaultFont))
        requests.append(TextMetricRequest("Option", defaultFont))
        requests.append(TextMetricRequest("Plain content", defaultFont))
        requests.append(TextMetricRequest("Custom", defaultFont))
        requests.append(TextMetricRequest("Wide", defaultFont))
        requests.append(TextMetricRequest("Outer", defaultFont))
        requests.append(TextMetricRequest("Inner", defaultFont))
        requests.append(TextMetricRequest("Nested", defaultFont))
        requests.append(TextMetricRequest("Settings", .style("subheadline")))
        requests.append(TextMetricRequest("Wide", .style("subheadline")))
        requests.append(TextMetricRequest("Outer", .style("subheadline")))
        requests.append(TextMetricRequest("Inner", .style("subheadline")))
        requests.append(TextMetricRequest("Option", .style("body")))
        requests.append(TextMetricRequest("Custom", .style("subheadline")))
        requests.append(TextMetricRequest("Loading", defaultFont))
        requests.append(TextMetricRequest("Copying", defaultFont))
        requests.append(TextMetricRequest("30%", defaultFont))
        requests.append(TextMetricRequest("Ring", defaultFont))
        requests.append(TextMetricRequest("Working", defaultFont))
        requests.append(TextMetricRequest("Focus me", defaultFont))
        requests.append(TextMetricRequest("Save", defaultFont))
        requests.append(TextMetricRequest("Go", defaultFont))
        requests.append(TextMetricRequest("Cancel", defaultFont))
        requests.append(TextMetricRequest("Log: none", defaultFont))
        requests.append(TextMetricRequest("Selected: none", defaultFont))
        requests.append(TextMetricRequest("Star", defaultFont))
        requests.append(TextMetricRequest("Star label", defaultFont))
        requests.append(TextMetricRequest("Star button", defaultFont))
        requests.append(TextMetricRequest("Star", .style("title")))
        requests.append(TextMetricRequest("Star label", .style("title")))
        requests.append(TextMetricRequest("Gradient", .style("largeTitle")))
        requests.append(TextMetricRequest("Star label", .style("body")))
        requests.append(TextMetricRequest("Star", .system(size: 11, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 12, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 15, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 22, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 13, weight: "semibold", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 13, weight: "bold", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 10, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 17, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 26, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Star", .system(size: 40, weight: "regular", design: "default")))
        requests.append(TextMetricRequest("Options", defaultFont))
        requests.append(TextMetricRequest("Custom", defaultFont))
        requests.append(TextMetricRequest("Primary", defaultFont))
        requests.append(TextMetricRequest("Plain", defaultFont))
        requests.append(TextMetricRequest("Hidden", defaultFont))
        requests.append(TextMetricRequest("Right-click me", defaultFont))
        requests.append(TextMetricRequest("Last: none 0", defaultFont))
        requests.append(TextMetricRequest("Cut", defaultFont))
        requests.append(TextMetricRequest("Copy", defaultFont))
        requests.append(TextMetricRequest("More", defaultFont))
        requests.append(TextMetricRequest("Paste", defaultFont))
        requests.append(TextMetricRequest("Delete", defaultFont))
        requests.append(TextMetricRequest("Action", defaultFont))
        requests.append(TextMetricRequest("Hi", defaultFont))
        requests.append(TextMetricRequest("End", .style("largeTitle")))
        let bold13 = defaultFont(weight: "bold")
        requests.append(TextMetricRequest(runs: [.init("Hello, ", bold13), .init("World", defaultFont)]))
        requests.append(TextMetricRequest(runs: [.init("Big ", .style("largeTitle")), .init("small", defaultFont)]))
        requests.append(TextMetricRequest("Red Blue", defaultFont))
        requests.append(TextMetricRequest(runs: [.init("Title ", .style("title")), .init("italic", .style("title", italic: true))]))
        requests.append(TextMetricRequest(runs: [.init("Env ", .style("title")), .init("bold", .style("title", weight: "bold"))]))
        requests.append(TextMetricRequest(runs: [.init(richParagraphHead, bold13), .init(richParagraphTail, defaultFont)], width: 150))
        requests.append(TextMetricRequest(runs: [.init(richParagraphHead, bold13), .init(richParagraphTail, defaultFont)]))
        // Effects and text decorations (Phase 6).
        requests.append(TextMetricRequest("Shadow", .style("title")))
        requests.append(TextMetricRequest("Ghost", defaultFont))
        for word in ["Blurred", "Bright", "Gray", "Invert"] { requests.append(TextMetricRequest(word, .style("title"))) }
        requests.append(TextMetricRequest("Hue", defaultFont))
        requests.append(TextMetricRequest("Masked text", defaultFont))
        for word in ["Outside", "Inside", "No pointer", "Help me", "Link", "Text", "Entries: 0"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Taps: 0", "Content below the toolbar", "Cherry", "Date", "Elderberry"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Drag the box", "Long presses: 0", "Double taps: 0", "Idle", "Scale 1.00, 0°", "Rest"] { requests.append(TextMetricRequest(word, defaultFont)) }
        for word in ["Overview", "Archived: 0", "Level: 3", "Third", "Second", "Ticker", "Apple", "Banana"] { requests.append(TextMetricRequest(word, defaultFont)) }
        // Kerning and tracking (Phase 6): widths of the same words with letters spread or tightened.
        for word in ["Hello", "Kerned text", "Tracked text", "Tight"] {
            requests.append(TextMetricRequest(word, defaultFont))
            requests.append(TextMetricRequest(word, .style("title")))
            for value: CGFloat in [2, 5, -1] {
                requests.append(TextMetricRequest(word, defaultFont, options: TextMetricOptions(kerning: value)))
                requests.append(TextMetricRequest(word, defaultFont, options: TextMetricOptions(tracking: value)))
                requests.append(TextMetricRequest(word, .style("title"), options: TextMetricOptions(kerning: value)))
                requests.append(TextMetricRequest(word, .style("title"), options: TextMetricOptions(tracking: value)))
            }
        }
        requests.append(TextMetricRequest("Wrapped kerned words fill the line", defaultFont, width: 160, options: TextMetricOptions(kerning: 2)))
        requests.append(TextMetricRequest("Wrapped kerned words fill the line", defaultFont, width: 160))
        // Redaction: the fixture strings (layout is unchanged by redaction).
        for word in ["Plain text stays", "Redacted text", "Button", "Toggle", "Unredacted inside", "Secret", "Visible under privacy", "Hidden secret", "Balance:", "$1,234", "Invalidated"] {
            requests.append(TextMetricRequest(word, defaultFont))
        }
        requests.append(TextMetricRequest("Title", .style("title")))
        requests.append(TextMetricRequest("Two lines of redacted text that wrap around inside a narrow frame", defaultFont, width: 200))
        requests.append(TextMetricRequest("Two lines of redacted text that wrap around inside a narrow frame", defaultFont))
        for word in ["Failed", "Loading", "Below", "Starred"] { requests.append(TextMetricRequest(word, defaultFont)) }
        // Height pressure (Phase 6): the paragraph at the fixture widths with every line count.
        for width: CGFloat in [110, 150] {
            requests.append(TextMetricRequest(paragraph, defaultFont, width: width))
            for limit in 1...5 { requests.append(TextMetricRequest(paragraph, defaultFont, width: width, options: TextMetricOptions(lineLimit: limit))) }
        }
        let shortText = "Short second text that wraps twice here"
        requests.append(TextMetricRequest(shortText, defaultFont, width: 150))
        requests.append(TextMetricRequest(shortText, defaultFont, width: 150, options: TextMetricOptions(lineLimit: 1)))
        // textScale(.secondary): every style at both scales (textscale/styles, textscale/long), the paragraph wrapped (textscale/wrapped).
        let secondary = TextMetricOptions(secondaryScale: true)
        for name in ["largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption", "caption2"] {
            let font = FixtureFont.style(name)
            requests.append(TextMetricRequest("Hello", font))
            requests.append(TextMetricRequest("Hello", font, options: secondary))
            requests.append(TextMetricRequest(paragraph, font))
            requests.append(TextMetricRequest(paragraph, font, options: secondary))
        }
        for size: CGFloat in [13, 20, 40] {
            let font = FixtureFont.system(size: size, weight: "regular", design: "default")
            requests.append(TextMetricRequest("Hello", font))
            requests.append(TextMetricRequest("Hello", font, options: secondary))
            requests.append(TextMetricRequest(paragraph, font))
            requests.append(TextMetricRequest(paragraph, font, options: secondary))
        }
        requests.append(TextMetricRequest(paragraph, defaultFont, width: 150, options: secondary))
        for word in ["Selectable text", "Plain text", "Pulse", "Drag me"] { requests.append(TextMetricRequest(word, defaultFont)) }
        requests.append(TextMetricRequest("", defaultFont, width: 120))   // dragdrop/external: the empty label over the destination
        requests.append(TextMetricRequest("Mask", .system(size: 40, weight: "bold", design: "default")))
        for word in ["Underlined", "Colored", "Hello World", "Second", "Both", "Struck", "Red strike", "Mixed line", "Solid", "Dotted", "Dashed",
                     "Dash dot", "Dash dot dot", "Dash strike", "MIXED CASE", "mixed case", "mixed Case", "Base", "Up", "Down", "Raised"] {
            requests.append(TextMetricRequest(word, defaultFont))
        }
        for word in ["Title line", "Title strike", "Dotted title"] { requests.append(TextMetricRequest(word, .style("title"))) }
        for word in ["Caption small", "Caption strike"] { requests.append(TextMetricRequest(word, .style("caption"))) }
        for word in ["Bold Under", "Bold strike"] { requests.append(TextMetricRequest(word, defaultFont(weight: "bold"))) }
        requests.append(TextMetricRequest("Large strike", .style("largeTitle")))
        // The list looks (list/alternating, prominence, outline, tint, separators, background, pinning).
        for string in ["First", "Second", "Hidden", "Tinted", "Rows", "Increased", "Standard"] {
            for width: CGFloat in [288, 304] { requests.append(TextMetricRequest(string, .style("subheadline", weight: "semibold"), width: width)) }
        }
        for string in ["Wi-Fi", "Bluetooth", "Mobile"] {
            requests.append(TextMetricRequest(string, defaultFont))
            requests.append(TextMetricRequest(string, defaultFont, width: 266))
        }
        let numbered = (1...6).map({ "Item \($0)" }) + (1...6).map({ "Row \($0)" })
        for string in ["Water", "Fruits", "Vegetables", "Apple", "Banana", "Carrot", "Top", "Bottom", "Last"] + numbered {
            requests.append(TextMetricRequest(string, defaultFont))
            for width: CGFloat in [288, 279, 266] { requests.append(TextMetricRequest(string, defaultFont, width: width)) }
        }
        return requests
    }()
}

extension TextMetricsRequests {
    /// The strings the `ios/…` fixtures show (IOSFixtures.swift): the default font is `.body`
    /// there, and control labels come in the weights iOS styles use. Measured on every platform.
    /// form/grouped: section headers in the bold body font, footers and plain rows in the 13 pt
    /// font, the group box's subheadline label, the nested form's body label.
    static let formGroupedRequests: [TextMetricRequest] = {
        var requests: [TextMetricRequest] = []
        let system13 = FixtureFont.system(size: 13, weight: "regular", design: "default")
        for string in ["Account", "Levels"] {
            for weight in ["medium", "semibold", "bold"] {
                requests.append(TextMetricRequest(string, .style("body", weight: weight)))
                requests.append(TextMetricRequest(string, .style("body", weight: weight), width: 300))
            }
            requests.append(TextMetricRequest(string, .style("headline")))
            requests.append(TextMetricRequest(string, .style("headline"), width: 300))
        }
        for string in ["Your details.", "Plain row"] {
            requests.append(TextMetricRequest(string, system13))
            requests.append(TextMetricRequest(string, system13, width: 300))
        }
        // macOS 27 grouped form footers: the subheadline font (form/grouped).
        requests.append(TextMetricRequest("Your details.", .style("subheadline")))
        requests.append(TextMetricRequest("Your details.", .style("subheadline"), width: 300))
        requests.append(TextMetricRequest("Pear", system13))
        requests.append(TextMetricRequest("Boxed", system13))
        requests.append(TextMetricRequest("Boxed", system13, width: 290))
        requests.append(TextMetricRequest("Box", .style("subheadline")))
        requests.append(TextMetricRequest("Box", .style("subheadline"), width: 290))
        requests.append(TextMetricRequest("Count: 3", .style("body")))
        requests.append(TextMetricRequest("Nested", .style("body")))
        requests.append(TextMetricRequest("Nested", .style("body"), width: 279))
        // canvas/images: the symbol drawn by `resolveSymbol`.
        requests.append(TextMetricRequest("Sym", .style("body")))
        return requests
    }()

    /// The strings `ios/text/dynamic-type` shows, at the categories it sets (sw-dynamic-type).
    static let dynamicTypeRequests: [TextMetricRequest] = {
        var requests: [TextMetricRequest] = []
        for category in ["XS", "XXXL", "AXXXL"] {
            for (string, style) in [("Large Title", "largeTitle"), ("Title", "title"), ("Headline", "headline"), ("Body", "body"), ("Footnote", "footnote"), ("Caption 2", "caption2")] {
                requests.append(TextMetricRequest(string, .style(style, category: category)))
            }
            requests.append(TextMetricRequest("Bold", .style("body", weight: "semibold", category: category)))
            requests.append(TextMetricRequest(paragraph, .style("body", category: category), width: 300))
            // The fixture's stack is under height pressure at the large categories: the paragraph
            // keeps floor(room / pitch) lines (two in the goldens).
            for limit in [1, 2, 3] {
                requests.append(TextMetricRequest(paragraph, .style("body", category: category), width: 300, options: TextMetricOptions(lineLimit: limit)))
            }
        }
        // dynamicTypeSize(...xLarge) clamps the accessibility size to xLarge.
        requests.append(TextMetricRequest("Clamped", .style("body", category: "XL")))
        requests.append(TextMetricRequest("Clamped", .style("body", category: "XS")))
        // text/dynamic-type on macOS: the body style under the modifiers.
        requests.append(TextMetricRequest("Body", .style("body", category: "AXXXXL")))
        requests.append(TextMetricRequest("Body", .style("body", category: "XS")))
        return requests
    }()

    static let iOSRequests: [TextMetricRequest] = {
        var requests: [TextMetricRequest] = dynamicTypeRequests
        // ios/textfield/vertical: the note in a 300 pt field, plain and inside the bezel's padding.
        requests.append(TextMetricRequest(fixtureFieldNote, .style("body")))
        for width: CGFloat in [300, 285, 286, 288, 284, 290, 292, 298] {
            requests.append(TextMetricRequest(fixtureFieldNote, .style("body"), width: width))
        }
        let body = ["Hello", "One", "Two", "Hg", "Enabled", "OK", "Bordered", "Prominent", "Borderless", "Disabled", "Delete", "Short", "Notes",
                    "Home content", "Alerts content", "Search content", "Mail content", "More content",
                    "Quantity: 3", "Placeholder", "Password", "Name", "Fruit", "Apple", "Banana", "Cherry", "Size", "Small", "Medium", "Large",
                    "Wi-Fi", "Bluetooth", "Volume", "Save", "Bold", "Body", "secret", "••••••",
                    "Row 1", "Row 2", "Row 3", "Detail", "Selected"]   // ios/representable/hostingcells, hostingstate
        for string in body {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body", weight: "semibold")))
            requests.append(TextMetricRequest(string, .style("body", weight: "bold")))
        }
        for string in ["Apple", "Banana", "Cherry", "Small", "Medium", "Large"] {
            for weight in ["regular", "medium", "semibold"] {
                requests.append(TextMetricRequest(string, .system(size: 13, weight: weight, design: "default")))
                requests.append(TextMetricRequest(string, .style("footnote", weight: weight)))
                requests.append(TextMetricRequest(string, .style("subheadline", weight: weight)))
            }
        }
        for string in ["Ada", "Notifications", "Flavour", "Vanilla", "Chocolate", "Pushed", "Row", "Detail", "Value"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body", weight: "semibold")))
        }
        for string in ["Account", "Preferences", "Fruit"] {
            requests.append(TextMetricRequest(string, .style("body", weight: "medium")))
        }
        requests.append(TextMetricRequest("Settings", .style("headline")))
        // The navigation bar of a pushed screen (ios/nav/push*): its title and the back button's label.
        requests.append(TextMetricRequest("Detail", .style("headline")))
        requests.append(TextMetricRequest("Detail", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("Settings", .style("body")))
        requests.append(TextMetricRequest("Back", .style("body")))
        requests.append(TextMetricRequest("Bluetooth", .style("title")))    // ios/label/basic
        // The menu buttons (ios/menu/basic).
        for string in ["Off", "Options", "Plain", "Hidden", "Cut", "Copy"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body", weight: "semibold")))
        }
        for string in ["ACCOUNT", "PREFERENCES", "FRUIT", "Account", "Preferences", "Fruit"] {
            requests.append(TextMetricRequest(string, .style("footnote")))
            requests.append(TextMetricRequest(string, .style("subheadline")))
            requests.append(TextMetricRequest(string, .style("caption")))
            requests.append(TextMetricRequest(string, .style("body")))
        }
        for (string, style) in [("Large Title", "largeTitle"), ("Title", "title"), ("Title 2", "title2"), ("Title 3", "title3"), ("Headline", "headline"),
                                ("Subheadline", "subheadline"), ("Callout", "callout"), ("Footnote", "footnote"), ("Caption", "caption"), ("Caption 2", "caption2"),
                                ("Volume", "subheadline"), ("Settings", "largeTitle")] {
            requests.append(TextMetricRequest(string, .style(style)))
            requests.append(TextMetricRequest(string, .style(style, weight: "semibold")))
            requests.append(TextMetricRequest(string, .style(style, weight: "bold")))
        }
        // The presentations, tab bar, date pills and list selection (ios/sheet/, ios/alert/, ios/dialog/,
        // ios/tabs/, ios/datepicker/compact, ios/list/selection): every text at the widths the
        // fixtures propose (the phone's 375, the medium sheet's 363, the alert's 242 and its
        // buttons' 131.75, the dialog's 181 and its buttons' 211, the list row's 311).
        for string in ["Show sheet", "Delete…", "Options…", "Above", "Below", "Some content under the title.", "Done",
                       "Home content", "Search content", "Settings content"] {
            requests.append(TextMetricRequest(string, .style("body")))
            for width: CGFloat in [375, 363] { requests.append(TextMetricRequest(string, .style("body"), width: width)) }
        }
        // ios/sheet/nav: the bar pills (body; semibold for the confirmation action) and the row.
        for string in ["Show sheet", "Add"] { requests.append(TextMetricRequest(string, .style("body", weight: "semibold"))) }
        requests.append(TextMetricRequest("Dismiss", .style("body")))
        requests.append(TextMetricRequest("Daily Scrum", .style("body")))
        requests.append(TextMetricRequest("Daily Scrum", .style("body"), width: 311))
        requests.append(TextMetricRequest("Sheet title", .style("headline")))
        for width: CGFloat in [375, 363] { requests.append(TextMetricRequest("Sheet title", .style("headline"), width: width)) }
        for string in ["First", "Second", "Third"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body"), width: 311))
        }
        let seventeen = FixtureFont.system(size: 17, weight: "regular", design: "default")
        let seventeenBold = FixtureFont.system(size: 17, weight: "bold", design: "default")
        let seventeenSemibold = FixtureFont.system(size: 17, weight: "semibold", design: "default")
        requests.append(TextMetricRequest("Delete the item?", seventeenBold, width: 242))
        requests.append(TextMetricRequest("This cannot be undone.", .system(size: 15, weight: "regular", design: "default"), width: 242))
        for string in ["Delete", "Cancel"] {
            for font in [seventeen, seventeenSemibold] {
                requests.append(TextMetricRequest(string, font))
                requests.append(TextMetricRequest(string, font, width: 131.75))
                requests.append(TextMetricRequest(string, font, width: 211))
            }
        }
        // ios/alert/stacked, ios/sheet/fullscreen (sw-ios-presentation-rest).
        for string in ["Resolve…", "Show cover"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body"), width: 375))
        }
        requests.append(TextMetricRequest("The document has unsaved changes that will be lost", seventeenBold, width: 242))
        requests.append(TextMetricRequest("Choose what to do before closing.", .system(size: 15, weight: "regular", design: "default"), width: 242))
        for string in ["Save", "Discard"] {
            for font in [seventeen, seventeenSemibold] {
                requests.append(TextMetricRequest(string, font))
                for width: CGFloat in [85, 131.75, 211, 242, 270] { requests.append(TextMetricRequest(string, font, width: width)) }
            }
        }
        requests.append(TextMetricRequest("Item options", seventeenBold, width: 181))
        requests.append(TextMetricRequest("Choose what to do with the item.", seventeen, width: 181))
        // iOS 27: the alert's texts 257 wide (320 less the insets), the title's lines 5 apart.
        for string in ["Delete the item?", "The document has unsaved changes that will be lost"] {
            requests.append(TextMetricRequest(string, seventeenBold, width: 257, options: TextMetricOptions(lineSpacing: 5)))
        }
        for string in ["This cannot be undone.", "Choose what to do before closing."] {
            requests.append(TextMetricRequest(string, .system(size: 15, weight: "regular", design: "default"), width: 257))
        }
        // iOS 27: the dialog's texts within its 241 pt panel (177 wide), the message 15 pt.
        requests.append(TextMetricRequest("Item options", seventeenBold, width: 177))
        requests.append(TextMetricRequest("Choose what to do with the item.", .system(size: 15, weight: "regular", design: "default"), width: 177))
        for string in ["Copy", "Duplicate", "Delete", "Cancel"] { requests.append(TextMetricRequest(string, seventeen, width: 208)); requests.append(TextMetricRequest(string, seventeenSemibold, width: 208)) }
        for string in ["Delete", "Cancel", "Save", "Discard"] { requests.append(TextMetricRequest(string, seventeen, width: 132)); requests.append(TextMetricRequest(string, seventeenSemibold, width: 132)); requests.append(TextMetricRequest(string, seventeen, width: 288)); requests.append(TextMetricRequest(string, seventeenSemibold, width: 288)) }
        for string in ["Copy", "Duplicate"] {
            requests.append(TextMetricRequest(string, seventeen))
            requests.append(TextMetricRequest(string, seventeen, width: 211))
        }
        // ios/dialog/wide-button, trailing-button, tall-column (new-website#649): the screens' texts
        // and the dialogs' within the 241 pt panel.
        for string in ["Sign out", "Delete"] + (0..<10).map({ "Row \($0)" }) {
            requests.append(TextMetricRequest(string, .style("body")))
            for width: CGFloat in [311, 343, 375] { requests.append(TextMetricRequest(string, .style("body"), width: width)) }
        }
        requests.append(TextMetricRequest("Version 1.0 (1)", .style("footnote")))
        for width: CGFloat in [311, 343, 375] { requests.append(TextMetricRequest("Version 1.0 (1)", .style("footnote"), width: width)) }
        for string in ["Sign out?", "Delete it?"] { requests.append(TextMetricRequest(string, seventeenBold, width: 177)) }
        for string in ["Your plan and history stay saved. Sign in again any time.", "This can't be undone."] {
            requests.append(TextMetricRequest(string, .system(size: 15, weight: "regular", design: "default"), width: 177))
        }
        for string in ["Sign out", "Delete"] { requests.append(TextMetricRequest(string, seventeen, width: 208)); requests.append(TextMetricRequest(string, seventeenSemibold, width: 208)) }
        for string in ["Home", "Search", "Settings", "Alerts", "Mail", "More"] {   // ios/tabs/*
            requests.append(TextMetricRequest(string, .system(size: 10, weight: "medium", design: "default")))
        }
        for string in ["3", "New"] {   // ios/tabs/badges: the badge's text
            requests.append(TextMetricRequest(string, .system(size: 13, weight: "regular", design: "default")))
            requests.append(TextMetricRequest(string, .system(size: 13, weight: "medium", design: "default")))
        }
        for string in ["Mar 15, 2025", "11:09 AM"] { requests.append(TextMetricRequest(string, seventeen)) }
        requests.append(TextMetricRequest("UILabel in a sheet", seventeen))
        // The sizing corners (ios/representable/measure-axes, grid): the texts beside the boxes and the grid's cells.
        requests.append(TextMetricRequest("Tx", .style("body")))
        requests.append(TextMetricRequest("Tx", .style("body"), width: 156))
        for string in ["A", "B", "C", "Long cell"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body"), width: 1000))
        }
        requests.append(TextMetricRequest("C", .style("body"), width: 11.5))
        requests.append(TextMetricRequest("Long cell", .style("body"), width: 169.75))
        // ios/list/editing: the section headers (body medium on iOS) and the rows.
        for string in ["Editable", "Deletable", "Fixed"] { requests.append(TextMetricRequest(string, .style("body", weight: "medium"))) }
        for string in ["Date", "Detail"] { requests.append(TextMetricRequest(string, .style("body"))) }
        // ios/list/spacing: the section headers and the rows at their width.
        for string in ["First", "Second"] { requests.append(TextMetricRequest(string, .style("body", weight: "medium"))) }
        for string in ["Apple", "Banana", "Cherry", "Carrot"] { requests.append(TextMetricRequest(string, .style("body"), width: 256)) }
        // ios/datepicker/wheel: the 23 pt rows (the month names, days, years, minutes, periods).
        let wheelStrings = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December", "AM", "PM"]
            + (1...31).map { "\($0)" } + (2020...2030).map { "\($0)" } + (0...59).map { $0 < 10 ? "0\($0)" : "\($0)" }
        for string in wheelStrings { requests.append(TextMetricRequest(string, .system(size: 23, weight: "regular", design: "default"))) }
        // ios/button/looks: control sizes (mini and small labels are the subheadline) and roles.
        for string in ["Regular", "Extra", "Mini"] { requests.append(TextMetricRequest(string, .style("body"))) }
        for string in ["Mini", "Small"] { requests.append(TextMetricRequest(string, .style("subheadline"))) }
        // ios/search: the field's prompt and text, the suggestions, the scope segments and tokens.
        requests.append(TextMetricRequest("Fruit", .style("largeTitle", weight: "bold")))
        requests.append(TextMetricRequest("Fruit", .style("headline")))
        for string in ["Find fruit", "Elderberry", "ch", "an", "Search", "Cancel"] { requests.append(TextMetricRequest(string, .style("body"))) }
        for string in ["All", "Fresh", "Red"] {
            requests.append(TextMetricRequest(string, .style("body")))
            requests.append(TextMetricRequest(string, .style("body", weight: "medium")))
            for size: CGFloat in [13, 15, 16] {
                requests.append(TextMetricRequest(string, .system(size: size, weight: "regular", design: "default")))
                requests.append(TextMetricRequest(string, .system(size: size, weight: "medium", design: "default")))
            }
        }
        return requests
    }()
}
