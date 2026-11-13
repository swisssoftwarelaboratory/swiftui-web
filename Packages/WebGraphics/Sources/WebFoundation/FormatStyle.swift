// Foundation's number format styles and `NumberFormatter` on wasm (decision 0017): `.number`,
// `.percent` and `.currency(code:)` for integers and floating-point values, with precision and
// grouping, and the parse strategies `TextField(_:value:format:)` uses. `_NumberFormatting` is
// the platform-neutral core, held to Foundation's output on macOS by `WebFoundationTests`:
// grouping in threes, up to six fraction digits with trailing zeros dropped (half-even
// rounding), two for a currency, en_US symbols.

/// Formats and parses numbers the way Foundation's en_US styles do.
public struct _NumberFormatting: Hashable, Sendable {
    public enum Style: Hashable, Sendable { case decimal, percent, currency(String) }

    public var style: Style
    /// The fraction digits shown: at least `minimumFractionDigits`, at most `maximumFractionDigits`
    /// (nil: Foundation's six for a decimal or percent, the currency's two).
    public var minimumFractionDigits = 0
    public var maximumFractionDigits: Int?
    public var usesGrouping = true

    public init(style: Style = .decimal) { self.style = style }

    private var fractionRange: ClosedRange<Int> {
        switch style {
        case .currency(let code):
            let digits = Self.currencyDigits(code)
            return (maximumFractionDigits == nil ? digits : minimumFractionDigits)...(maximumFractionDigits ?? digits)
        default:
            return minimumFractionDigits...(maximumFractionDigits ?? 6)
        }
    }

    static func currencyDigits(_ code: String) -> Int { ["JPY", "KRW", "VND", "CLP", "ISK", "HUF"].contains(code.uppercased()) ? 0 : 2 }

    /// The symbol before the number for a currency, en_US style ("$", "€"; other codes are
    /// written out with a space).
    static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CNY": return "CN¥"
        case "INR": return "₹"
        case "KRW": return "₩"
        case "CAD": return "CA$"
        case "AUD": return "A$"
        case "MXN": return "MX$"
        case "BRL": return "R$"
        default: return code.uppercased() + "\u{00A0}"
        }
    }

    public func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value < 0 ? "-∞" : "∞") }
        // ICU rounds the shortest decimal representation (2.675 → "2.68"), not the binary value.
        var (digits, exponent) = Self.decimalDigits(abs(value))
        if case .percent = style { exponent += 2 }
        let range = fractionRange
        var integer: [UInt8] = exponent > 0 ? Array(digits.prefix(exponent)) : []
        while integer.count < max(0, exponent) { integer.append(0) }
        var fraction: [UInt8] = exponent < 0 ? Array(repeating: 0, count: -exponent) : []
        if exponent < digits.count { fraction += digits[max(0, exponent)...] }
        if fraction.count > range.upperBound {
            let next = fraction[range.upperBound]
            let restNonZero = fraction[(range.upperBound + 1)...].contains { $0 != 0 }
            fraction.removeSubrange(range.upperBound...)
            let lastKept = range.upperBound > 0 ? fraction[range.upperBound - 1] : (integer.last ?? 0)
            if next > 5 || (next == 5 && (restNonZero || lastKept % 2 == 1)) {
                Self.increment(&integer, &fraction)
            }
        }
        while fraction.count > range.lowerBound, fraction.last == 0 { fraction.removeLast() }
        while fraction.count < range.lowerBound { fraction.append(0) }
        while integer.count > 1, integer.first == 0 { integer.removeFirst() }
        var integerPart = integer.isEmpty ? "0" : integer.map { String($0) }.joined()
        if usesGrouping { integerPart = Self.grouped(integerPart) }
        let negative = value < 0 && (integer.contains { $0 != 0 } || fraction.contains { $0 != 0 })
        return assemble(integer: integerPart, fraction: fraction.map { String($0) }.joined(), negative: negative)
    }

    /// Adds one unit in the last fraction place, carrying into the whole part.
    private static func increment(_ integer: inout [UInt8], _ fraction: inout [UInt8]) {
        var index = fraction.count - 1
        while index >= 0 {
            if fraction[index] < 9 { fraction[index] += 1; return }
            fraction[index] = 0
            index -= 1
        }
        index = integer.count - 1
        while index >= 0 {
            if integer[index] < 9 { integer[index] += 1; return }
            integer[index] = 0
            index -= 1
        }
        integer.insert(1, at: 0)
    }

    /// The shortest decimal digits of a finite, non-negative value, as `0.d₁d₂… × 10^exponent`
    /// (from Swift's shortest round-trip description; no leading or trailing zeros).
    static func decimalDigits(_ value: Double) -> (digits: [UInt8], exponent: Int) {
        let description = "\(value)"
        var mantissa = Substring(description)
        var exponent10 = 0
        if let e = description.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = description[..<e]
            exponent10 = Int(description[description.index(after: e)...]) ?? 0
        }
        var digits: [UInt8] = []
        var pointPosition: Int?
        for character in mantissa {
            if character == "." { pointPosition = digits.count } else if let digit = character.wholeNumberValue { digits.append(UInt8(digit)) }
        }
        var exponent = (pointPosition ?? digits.count) + exponent10
        while let first = digits.first, first == 0 { digits.removeFirst(); exponent -= 1 }
        while let last = digits.last, last == 0 { digits.removeLast() }
        if digits.isEmpty { return ([], 0) }
        return (digits, exponent)
    }

    public func format<I: BinaryInteger>(_ value: I) -> String {
        let magnitude = value.magnitude
        var integerPart = String(magnitude)
        if usesGrouping { integerPart = Self.grouped(integerPart) }
        let range = fractionRange
        let fraction = String(repeating: "0", count: range.lowerBound)
        return assemble(integer: integerPart, fraction: fraction, negative: value < 0)
    }

    private func assemble(integer: String, fraction: String, negative: Bool) -> String {
        var body = integer
        if !fraction.isEmpty { body += "." + fraction }
        switch style {
        case .decimal: return (negative ? "-" : "") + body
        case .percent: return (negative ? "-" : "") + body + "%"
        case .currency(let code): return (negative ? "-" : "") + Self.currencySymbol(code) + body
        }
    }

    /// The number in `text`: grouping, a currency symbol, a percent sign and spaces are ignored;
    /// nil when nothing parses (Foundation's strategies reject `abc` and accept `12.7`).
    public func parse(_ text: String) -> Double? {
        var cleaned = ""
        var sawPercent = false
        for character in text {
            if character.isNumber || character == "." || character == "-" { cleaned.append(character) }
            else if character == "%" { sawPercent = true }
        }
        guard !cleaned.isEmpty, let value = Double(cleaned) else { return nil }
        if case .percent = style { return value / 100 }
        return sawPercent ? value / 100 : value
    }

    // MARK: Digits

    private static func grouped(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return result
    }
}

#if os(WASI)
import FoundationEssentials

/// A type that converts a given data type into a representation in another type, such as a string.
public protocol FormatStyle: Hashable, Sendable {
    associatedtype FormatInput
    associatedtype FormatOutput
    func format(_ value: FormatInput) -> FormatOutput
    func locale(_ locale: Locale) -> Self
}

extension FormatStyle {
    public func locale(_ locale: Locale) -> Self { self }
}

/// A type that parses an input into an output, the inverse of a format style.
public protocol ParseStrategy: Hashable, Sendable {
    associatedtype ParseInput
    associatedtype ParseOutput
    func parse(_ value: ParseInput) throws -> ParseOutput
}

/// A format style that can parse the strings it produces.
public protocol ParseableFormatStyle: FormatStyle {
    associatedtype Strategy: ParseStrategy where Strategy.ParseInput == FormatOutput, Strategy.ParseOutput == FormatInput
    var parseStrategy: Strategy { get }
}

/// The error a parse strategy throws for text it cannot read.
public struct FormatParseError: Error, Sendable {
    public let text: String
}

/// Configuration for the number format styles.
public enum NumberFormatStyleConfiguration {
    /// The number of fraction digits a style shows.
    public struct Precision: Hashable, Sendable {
        package var minimum: Int
        package var maximum: Int?

        public static func fractionLength(_ length: Int) -> Precision { Precision(minimum: length, maximum: length) }
        public static func fractionLength<R: RangeExpression>(_ limits: R) -> Precision where R.Bound == Int {
            let range = limits.relative(to: 0..<100)
            return Precision(minimum: range.lowerBound, maximum: range.upperBound - 1)
        }
    }

    /// Whether thousands are grouped.
    public struct Grouping: Hashable, Sendable {
        package let groups: Bool
        public static let automatic = Grouping(groups: true)
        public static let never = Grouping(groups: false)
    }
}

extension _NumberFormatting {
    public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> _NumberFormatting {
        var copy = self
        copy.minimumFractionDigits = precision.minimum
        copy.maximumFractionDigits = precision.maximum
        return copy
    }

    public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> _NumberFormatting {
        var copy = self
        copy.usesGrouping = grouping.groups
        return copy
    }
}

/// A structure that converts between integer values and their textual representations.
public struct IntegerFormatStyle<Value: BinaryInteger>: ParseableFormatStyle {
    public var core = _NumberFormatting()
    public init() {}
    public init(locale: Locale) {}
    public func format(_ value: Value) -> String { core.format(value) }
    public var parseStrategy: IntegerParseStrategy<Self> { IntegerParseStrategy(core: core) }
    public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
    public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }

    /// The integer as a percentage (7 → "7%").
    public struct Percent: ParseableFormatStyle {
        public var core = _NumberFormatting(style: .percent)
        public init() {}
        public func format(_ value: Value) -> String { core.format(value) }
        public var parseStrategy: IntegerParseStrategy<Self> { IntegerParseStrategy(core: core) }
        public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
        public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
    }

    /// The integer as an amount of a currency (1234 → "$1,234.00").
    public struct Currency: ParseableFormatStyle {
        public var core: _NumberFormatting
        public init(code: String) { core = _NumberFormatting(style: .currency(code)) }
        public func format(_ value: Value) -> String { core.format(value) }
        public var parseStrategy: IntegerParseStrategy<Self> { IntegerParseStrategy(core: core) }
        public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
        public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
    }
}

/// A structure that converts between floating-point values and their textual representations.
public struct FloatingPointFormatStyle<Value: BinaryFloatingPoint>: ParseableFormatStyle {
    public var core = _NumberFormatting()
    public init() {}
    public init(locale: Locale) {}
    public func format(_ value: Value) -> String { core.format(Double(value)) }
    public var parseStrategy: FloatingPointParseStrategy<Self> { FloatingPointParseStrategy(core: core) }
    public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
    public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }

    /// The value as a percentage (0.25 → "25%").
    public struct Percent: ParseableFormatStyle {
        public var core = _NumberFormatting(style: .percent)
        public init() {}
        public func format(_ value: Value) -> String { core.format(Double(value)) }
        public var parseStrategy: FloatingPointParseStrategy<Self> { FloatingPointParseStrategy(core: core) }
        public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
        public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
    }

    /// The value as an amount of a currency (12.5 → "$12.50").
    public struct Currency: ParseableFormatStyle {
        public var core: _NumberFormatting
        public init(code: String) { core = _NumberFormatting(style: .currency(code)) }
        public func format(_ value: Value) -> String { core.format(Double(value)) }
        public var parseStrategy: FloatingPointParseStrategy<Self> { FloatingPointParseStrategy(core: core) }
        public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
        public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
    }
}

/// Parses the text of an integer format style (a fraction is truncated, as Foundation does).
public struct IntegerParseStrategy<Format: FormatStyle>: ParseStrategy where Format.FormatInput: BinaryInteger {
    package let core: _NumberFormatting
    public func parse(_ value: String) throws -> Format.FormatInput {
        guard let number = core.parse(value), let result = Format.FormatInput(exactly: number.rounded(.towardZero)) else { throw FormatParseError(text: value) }
        return result
    }
}

/// Parses the text of a floating-point format style.
public struct FloatingPointParseStrategy<Format: FormatStyle>: ParseStrategy where Format.FormatInput: BinaryFloatingPoint {
    package let core: _NumberFormatting
    public func parse(_ value: String) throws -> Format.FormatInput {
        guard let number = core.parse(value) else { throw FormatParseError(text: value) }
        return Format.FormatInput(number)
    }
}

// `.number` hangs off the plain style, `.percent` and `.currency` off their own styles, as in
// Foundation: one declaration each, so `format: .percent` is unambiguous.
extension FormatStyle where Self == IntegerFormatStyle<Int> {
    public static var number: IntegerFormatStyle<Int> { IntegerFormatStyle() }
}
extension FormatStyle where Self == IntegerFormatStyle<Int>.Percent {
    public static var percent: IntegerFormatStyle<Int>.Percent { IntegerFormatStyle<Int>.Percent() }
}
extension FormatStyle where Self == IntegerFormatStyle<Int>.Currency {
    public static func currency(code: String) -> IntegerFormatStyle<Int>.Currency { IntegerFormatStyle<Int>.Currency(code: code) }
}
extension FormatStyle where Self == IntegerFormatStyle<Int64> {
    public static var number: IntegerFormatStyle<Int64> { IntegerFormatStyle() }
}
extension FormatStyle where Self == IntegerFormatStyle<UInt> {
    public static var number: IntegerFormatStyle<UInt> { IntegerFormatStyle() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    public static var number: FloatingPointFormatStyle<Double> { FloatingPointFormatStyle() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Percent {
    public static var percent: FloatingPointFormatStyle<Double>.Percent { FloatingPointFormatStyle<Double>.Percent() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    public static func currency(code: String) -> FloatingPointFormatStyle<Double>.Currency { FloatingPointFormatStyle<Double>.Currency(code: code) }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Float> {
    public static var number: FloatingPointFormatStyle<Float> { FloatingPointFormatStyle() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Float>.Percent {
    public static var percent: FloatingPointFormatStyle<Float>.Percent { FloatingPointFormatStyle<Float>.Percent() }
}
extension FormatStyle where Self == FloatingPointFormatStyle<Float>.Currency {
    public static func currency(code: String) -> FloatingPointFormatStyle<Float>.Currency { FloatingPointFormatStyle<Float>.Currency(code: code) }
}

extension BinaryInteger {
    /// The integer formatted by `style` (`1234.formatted(.number)`).
    public func formatted<F: FormatStyle>(_ style: F) -> F.FormatOutput where F.FormatInput == Self { style.format(self) }
    /// The integer formatted the default way ("1,234").
    public func formatted() -> String { IntegerFormatStyle<Self>().format(self) }
}

extension BinaryFloatingPoint {
    public func formatted<F: FormatStyle>(_ style: F) -> F.FormatOutput where F.FormatInput == Self { style.format(self) }
    /// The value formatted the default way ("3.14159", up to six fraction digits).
    public func formatted() -> String { FloatingPointFormatStyle<Self>().format(self) }
}

// MARK: - Formatter

/// Foundation's `Formatter` on wasm: string conversions of arbitrary values, overridable. An
/// `NSObject`, as Apple's is, so formatters hash and compare by identity (a struct holding one
/// stays `Hashable`, as SwiftDate's `DateInRegion` is).
open class Formatter: NSObject {
    public override init() { super.init() }
    /// The string for `obj`, nil when the formatter cannot represent it.
    open func string(for obj: Any?) -> String? { nil }
    /// The string shown while editing (the same by default).
    open func editingString(for obj: Any) -> String? { string(for: obj) }
    /// The value read from `string`, nil when it does not parse.
    open func value(from string: String) -> Any? { nil }
}

/// Foundation's `NumberFormatter` on wasm: the none, decimal, percent, currency and ordinal styles.
open class NumberFormatter: Formatter {
    public enum Style: Int, Sendable { case none = 0, decimal, currency, percent, scientific, spellOut, ordinal }

    open var numberStyle: Style = .none
    open var minimumFractionDigits = 0
    open var maximumFractionDigits = 0
    open var usesGroupingSeparator = false
    open var currencyCode = "USD"
    /// Whether a number with no fraction digits still shows its decimal point ("12.").
    open var alwaysShowsDecimalSeparator = false
    /// Whether `number(from:)` accepts a fraction; false reads only whole numbers.
    open var allowsFloats = true
    /// The fewest integer digits shown, padded with leading zeros ("007" for 3); 0 or 1 adds none.
    open var minimumIntegerDigits = 0
    /// Text after a number that is zero or more ("K" in "12K").
    open var positiveSuffix: String! = ""
    /// Text after a negative number.
    open var negativeSuffix: String! = ""
    /// The locale the formatter is for. Kept, not applied: numbers format as en_US
    /// (decision 0017).
    open lazy var locale: Locale = .current

    private var core: _NumberFormatting {
        var core: _NumberFormatting
        switch numberStyle {
        case .none, .scientific, .spellOut:
            core = _NumberFormatting(style: .decimal)
            core.usesGrouping = usesGroupingSeparator
            core.maximumFractionDigits = maximumFractionDigits
        case .decimal:
            core = _NumberFormatting(style: .decimal)
            core.maximumFractionDigits = max(maximumFractionDigits, 3)
        case .ordinal:
            core = _NumberFormatting(style: .decimal)
            core.maximumFractionDigits = 0
        case .percent:
            core = _NumberFormatting(style: .percent)
            core.maximumFractionDigits = maximumFractionDigits
        case .currency:
            core = _NumberFormatting(style: .currency(currencyCode))
            if maximumFractionDigits > 0 { core.maximumFractionDigits = maximumFractionDigits }
        }
        core.minimumFractionDigits = minimumFractionDigits
        return core
    }

    public override init() { super.init() }

    /// The string for a number of any integer or floating-point type.
    open override func string(for obj: Any?) -> String? {
        switch obj {
        case let value as Double: return format(value)
        case let value as Float: return format(Double(value))
        case let value as Int: return format(value)
        case let value as Int64: return format(value)
        case let value as UInt: return format(value)
        case let value as Int32: return format(value)
        case let value as NSNumber: return string(from: value)
        default: return nil
        }
    }

    @_disfavoredOverload
    public func string(from value: Double) -> String? { format(value) }

    /// The string for a number (Foundation's only `string(from:)`).
    public func string(from number: NSNumber) -> String? { format(number.doubleValue) }

    private func format(_ value: Double) -> String { decorate(styled(value), negative: value < 0) }

    private func format<I: BinaryInteger>(_ value: I) -> String { decorate(styled(value), negative: value < 0) }

    /// `text` with the integer digits padded, the decimal separator kept and the sign's suffix.
    private func decorate(_ text: String, negative: Bool) -> String {
        var out = text
        if minimumIntegerDigits > 1, let first = out.firstIndex(where: \.isNumber) {
            let integer = out[first...].prefix { $0.isNumber || $0 == "," }
            let digits = integer.filter(\.isNumber).count
            if digits < minimumIntegerDigits {
                out.insert(contentsOf: String(repeating: "0", count: minimumIntegerDigits - digits), at: first)
            }
        }
        if alwaysShowsDecimalSeparator, !out.contains("."), let last = out.lastIndex(where: \.isNumber) {
            out.insert(".", at: out.index(after: last))
        }
        return out + ((negative ? negativeSuffix : positiveSuffix) ?? "")
    }

    private func styled(_ value: Double) -> String {
        guard numberStyle == .ordinal else { return core.format(value) }
        let rounded = value.rounded(.toNearestOrEven)
        guard let whole = Int(exactly: rounded) else { return core.format(value) }
        return styled(whole)
    }

    private func styled<I: BinaryInteger>(_ value: I) -> String {
        guard numberStyle == .ordinal else { return core.format(value) }
        // English suffixes: 1st, 2nd, 3rd, then th, with 11th to 13th in every hundred.
        let lastTwo = Int(value.magnitude % 100)
        let suffix: String
        switch (lastTwo / 10 == 1 ? 0 : lastTwo % 10) {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return core.format(value) + suffix
    }

    /// The number in `string`, nil when it does not parse.
    public func number(from string: String) -> Double? {
        #if _runtime(_ObjC)
        // Through `getObjectValue`, as Foundation's, so a subclass's own reading applies.
        var object: AnyObject?
        try? getObjectValue(&object, for: string, range: nil)
        return (object as? NSNumber)?.doubleValue
        #else
        parse(string)
        #endif
    }

    open override func value(from string: String) -> Any? { parse(string) }

    private func parse(_ string: String) -> Double? {
        var text = string
        for suffix in [positiveSuffix ?? "", negativeSuffix ?? ""] where !suffix.isEmpty && text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        guard let value = core.parse(text) else { return nil }
        return allowsFloats || value.rounded(.towardZero) == value ? value : nil
    }

    #if _runtime(_ObjC)
    /// Reads the number in `string` into `obj` (an `NSNumber`); subclasses override it to read
    /// their own forms, as Foundation's does. Throws nothing here: a string that does not
    /// parse leaves `obj` nil.
    open func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
                             range rangep: UnsafeMutablePointer<NSRange>?) throws {
        obj?.pointee = parse(string).map { NSNumber(value: $0) }
    }
    #endif
}
#endif

// MARK: - ListFormatter (decision 0021)

#if os(WASI)
/// Foundation's `ListFormatter`: items joined as English prose ("a, b, and c", the serial
/// comma as Foundation's en_US; other locales are not carried).
open class ListFormatter: Formatter {
    public var locale: Locale = .current
    public var itemFormatter: Formatter?

    public override init() { super.init() }

    /// The items joined with the locale's conjunction.
    open class func localizedString(byJoining strings: [String]) -> String {
        ListFormatter().string(from: strings) ?? ""
    }

    open func string(from items: [Any]) -> String? {
        let strings = items.map { item -> String in
            if let formatter = itemFormatter, let text = formatter.string(for: item) { return text }
            return "\(item)"
        }
        switch strings.count {
        case 0: return ""
        case 1: return strings[0]
        case 2: return "\(strings[0]) and \(strings[1])"
        default: return strings.dropLast().joined(separator: ", ") + ", and " + strings[strings.count - 1]
        }
    }

    open override func string(for obj: Any?) -> String? {
        guard let items = obj as? [Any] else { return nil }
        return string(from: items)
    }
}
#endif
