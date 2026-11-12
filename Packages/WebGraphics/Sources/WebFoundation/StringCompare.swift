// The NSString comparisons and normalizations on wasm, where FoundationEssentials keeps them
// internal: `compare(_:options:range:locale:)`, the case-insensitive and localized forms,
// `replacingCharacters(in:with:)`, `components(separatedBy:)` with a character set, and the
// canonical normalization forms (`precomposedStringWithCanonicalMapping`, NFC, and
// `decomposedStringWithCanonicalMapping`, NFD) through the standard library's own tables.
// Case folding is Unicode's full folding ("ß" matches "SS"), as Foundation's. The localized
// forms order as the root collation does for the scripts apps sort: letters before their
// accented forms, and lowercase before uppercase only when nothing else differs ("a" < "A" <
// "b"); there is no per-language tailoring.
#if os(WASI)
@_spi(_Unicode) import Swift
import FoundationEssentials

public enum _StringCompare {
    /// Foundation's `compare(_:options:)`: literal or canonical, with case and diacritic
    /// folding and numeric runs as the options ask.
    public static func compare(_ lhs: String, _ rhs: String, options: String.CompareOptions = []) -> ComparisonResult {
        let left = keys(lhs, options: options)
        let right = keys(rhs, options: options)
        return order(left, right, numeric: options.contains(.numeric))
    }

    /// The root collation's order: letters first (case and accents folded), then accents,
    /// then case, lowercase first.
    public static func localizedCompare(_ lhs: String, _ rhs: String, options: String.CompareOptions = []) -> ComparisonResult {
        let numeric = options.contains(.numeric)
        let primary = order(keys(lhs, options: [.caseInsensitive, .diacriticInsensitive]),
                            keys(rhs, options: [.caseInsensitive, .diacriticInsensitive]), numeric: numeric)
        if primary != .orderedSame || options.contains(.diacriticInsensitive) && options.contains(.caseInsensitive) { return primary }
        if !options.contains(.diacriticInsensitive) {
            let secondary = order(keys(lhs, options: .caseInsensitive), keys(rhs, options: .caseInsensitive), numeric: numeric)
            if secondary != .orderedSame { return secondary }
        }
        if options.contains(.caseInsensitive) { return .orderedSame }
        // Lowercase sorts first: compare with the cases swapped.
        return order(keys(swappedCase(lhs), options: []), keys(swappedCase(rhs), options: []), numeric: numeric)
    }

    /// The scalars a comparison runs over.
    static func keys(_ string: String, options: String.CompareOptions) -> [Unicode.Scalar] {
        var scalars: [Unicode.Scalar] = []
        let decomposes = options.contains(.diacriticInsensitive)
        if options.contains(.literal) && !decomposes {
            scalars = Array(string.unicodeScalars)
        } else if decomposes {
            for scalar in string._nfd where scalar.properties.generalCategory != .nonspacingMark { scalars.append(scalar) }
        } else {
            scalars = Array(string._nfc)
        }
        guard options.contains(.caseInsensitive) else { return scalars }
        var folded: [Unicode.Scalar] = []
        for scalar in scalars { folded += scalar.properties._caseFolded.unicodeScalars }
        // A folded scalar can compose with its neighbours again.
        return decomposes ? folded : Array(String(String.UnicodeScalarView(folded))._nfc)
    }

    static func swappedCase(_ string: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            let properties = scalar.properties
            let swapped = properties.isLowercase ? properties.uppercaseMapping : properties.isUppercase ? properties.lowercaseMapping : String(scalar)
            result.append(contentsOf: swapped.unicodeScalars)
        }
        return String(result)
    }

    /// Scalar by scalar, with runs of ASCII digits compared by value when `numeric`.
    static func order(_ left: [Unicode.Scalar], _ right: [Unicode.Scalar], numeric: Bool) -> ComparisonResult {
        var i = 0, j = 0
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }
        while i < left.count && j < right.count {
            if numeric && isDigit(left[i]) && isDigit(right[j]) {
                var iEnd = i, jEnd = j
                while iEnd < left.count && isDigit(left[iEnd]) { iEnd += 1 }
                while jEnd < right.count && isDigit(right[jEnd]) { jEnd += 1 }
                var a = left[i..<iEnd].drop { $0 == "0" }, b = right[j..<jEnd].drop { $0 == "0" }
                if a.isEmpty { a = left[(iEnd - 1)..<iEnd] }
                if b.isEmpty { b = right[(jEnd - 1)..<jEnd] }
                if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
                for (x, y) in zip(a, b) where x != y { return x.value < y.value ? .orderedAscending : .orderedDescending }
                i = iEnd
                j = jEnd
                continue
            }
            if left[i] != right[j] { return left[i].value < right[j].value ? .orderedAscending : .orderedDescending }
            i += 1
            j += 1
        }
        let leftDone = i >= left.count, rightDone = j >= right.count
        return leftDone && rightDone ? .orderedSame : leftDone ? .orderedAscending : .orderedDescending
    }

    /// Canonical composition (NFC).
    public static func precomposed(_ string: String) -> String { String(String.UnicodeScalarView(Array(string._nfc))) }
    /// Canonical decomposition (NFD).
    public static func decomposed(_ string: String) -> String { String(String.UnicodeScalarView(Array(string._nfd))) }
}

extension StringProtocol {
    /// The order of this string and `aString` (within `range` of this one) under `mask`'s
    /// options; with a `locale`, as `localizedCompare` orders.
    public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [], range: Range<String.Index>? = nil, locale: Locale? = nil) -> ComparisonResult {
        let subject = range.map { String(self[$0]) } ?? String(self)
        if locale != nil { return _StringCompare.localizedCompare(subject, String(aString), options: mask) }
        return _StringCompare.compare(subject, String(aString), options: mask)
    }
    public func caseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.compare(String(self), String(aString), options: .caseInsensitive)
    }
    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(aString))
    }
    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(aString), options: .caseInsensitive)
    }
    /// The Finder's order: localized, with numbers compared by value ("File 2" < "File 10").
    public func localizedStandardCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(string), options: .numeric)
    }

    /// The string with the characters in `range` replaced.
    public func replacingCharacters<T: StringProtocol, R: RangeExpression>(in range: R, with replacement: T) -> String where R.Bound == String.Index {
        let bounds = range.relative(to: self)
        return String(self[startIndex..<bounds.lowerBound]) + String(replacement) + String(self[bounds.upperBound...])
    }

    /// The pieces between the scalars in `separator` (empty ones included, as Foundation's).
    public func components(separatedBy separator: CharacterSet) -> [String] {
        var pieces: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in String(self).unicodeScalars {
            if separator.contains(scalar) {
                pieces.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        pieces.append(String(current))
        return pieces
    }

    /// Each word's first letter in uppercase and the rest in lowercase, in the root locale's
    /// case mapping (no per-language rules, such as Turkish dotted i).
    public var localizedCapitalized: String {
        var result = ""
        var startsWord = true
        for character in String(self) {
            result += startsWord ? character.uppercased() : character.lowercased()
            startsWord = !(character.isLetter || character.isNumber || character == "'" || character == "’")
        }
        return result
    }
    /// The string in uppercase, lowercase or capitalized for a locale: the root locale's case
    /// mapping, as the properties above (no per-language rules).
    public func uppercased(with locale: Locale?) -> String { String(self).uppercased() }
    public func lowercased(with locale: Locale?) -> String { String(self).lowercased() }
    public func capitalized(with locale: Locale?) -> String { localizedCapitalized }
    public var localizedLowercase: String { String(self).lowercased() }
    public var localizedUppercase: String { String(self).uppercased() }

    public var precomposedStringWithCanonicalMapping: String { _StringCompare.precomposed(String(self)) }
    public var decomposedStringWithCanonicalMapping: String { _StringCompare.decomposed(String(self)) }
}
#endif
