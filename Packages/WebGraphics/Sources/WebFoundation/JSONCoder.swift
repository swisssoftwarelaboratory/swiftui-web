// The JSON coder behind `CodableRepresentation` (a payload encoded by one view and decoded by
// a drop destination in the same app), navigation paths and `UserDefaults` on wasm.
// Foundation's `JSONEncoder` would extract its scanner, writer, `Decimal` and string members
// into the wasm bundle, 300 KB the app never runs (decision 0006, the wasm size log); this
// coder speaks the JSON that `Codable` needs.
#if !os(WASI)
import Foundation
#endif

/// A JSON value with the boxes the encoder's containers write into.
indirect enum _JSONNode {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array(_JSONArrayBox)
    case object(_JSONObjectBox)
    case deferred(_JSONNodeBox)

    /// The node with every box resolved: what serialization and decoding read.
    var resolved: _JSONNode {
        switch self {
        case .array(let box): return .array(_JSONArrayBox(box.items.map(\.resolved)))
        case .object(let box): return .object(_JSONObjectBox(box.entries.map { ($0.key, $0.value.resolved) }))
        case .deferred(let box): return (box.node ?? .null).resolved
        default: return self
        }
    }
}

final class _JSONArrayBox {
    var items: [_JSONNode]
    init(_ items: [_JSONNode] = []) { self.items = items }
}

final class _JSONObjectBox {
    var entries: [(key: String, value: _JSONNode)]
    init(_ entries: [(key: String, value: _JSONNode)] = []) { self.entries = entries }
    subscript(key: String) -> _JSONNode? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
            } else if let newValue {
                entries.append((key, newValue))
            }
        }
    }
}

final class _JSONNodeBox {
    var node: _JSONNode?
}

// MARK: - Encoding

/// Encodes a `Codable` transfer item as JSON.
public struct _TransferJSONEncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encode(value, options: _JSONEncodingOptions(), format: _JSONFormat())
    }

    package func encode<T: Encodable>(_ value: T, options: _JSONEncodingOptions, format: _JSONFormat) throws -> Data {
        let node = try options.node(for: value, codingPath: [])
        var text = ""
        try _JSONWriter.write(node.resolved, into: &text, format: format)
        return Data(text.utf8)
    }
}

/// What a `JSONEncoder`'s strategies ask of the encoding (the transfer coders use the defaults:
/// `Codable`'s own dates and data, keys as written).
package struct _JSONEncodingOptions {
    package enum DateStrategy {
        case deferred, secondsSince1970, millisecondsSince1970, iso8601
        case formatted(DateFormatter)
        case custom((Date, any Encoder) throws -> Void)
    }
    package enum DataStrategy { case deferred, base64, custom((Data, any Encoder) throws -> Void) }
    package enum KeyStrategy { case useDefault, snakeCase, custom(([any CodingKey]) -> any CodingKey) }

    package var dateStrategy: DateStrategy = .deferred
    package var dataStrategy: DataStrategy = .deferred
    package var keyStrategy: KeyStrategy = .useDefault
    /// The strings written for +∞, -∞ and NaN (`convertToString`); nil throws for them.
    package var nonConformingFloats: (positiveInfinity: String, negativeInfinity: String, nan: String)?
    /// A `URL` as its absolute string, as `JSONEncoder` writes one (its own `Codable` is keyed).
    package var urlsAsStrings = false
    package var userInfo: [CodingUserInfoKey: Any] = [:]
    package init() {}

    /// The node for a value: a date, data or URL as the strategies write it, else what the
    /// value encodes.
    func node<T: Encodable>(for value: T, codingPath: [any CodingKey]) throws -> _JSONNode {
        if T.self == Date.self, let date = value as? Date {
            switch dateStrategy {
            case .deferred: break
            case .secondsSince1970: return try number(date.timeIntervalSince1970, codingPath: codingPath)
            case .millisecondsSince1970: return try number(date.timeIntervalSince1970 * 1000, codingPath: codingPath)
            case .iso8601: return .string(_formatISO8601(date))
            case .formatted(let formatter): return .string(formatter.string(from: date))
            case .custom(let encode): return try custom(codingPath) { try encode(date, $0) }
            }
        } else if T.self == Data.self, let data = value as? Data {
            switch dataStrategy {
            case .deferred: break
            case .base64: return .string(data.base64EncodedString())
            case .custom(let encode): return try custom(codingPath) { try encode(data, $0) }
            }
        } else if urlsAsStrings, T.self == URL.self, let url = value as? URL {
            return .string(url.absoluteString)
        }
        let nested = _JSONEncoding(codingPath: codingPath, options: self)
        try value.encode(to: nested)
        return nested.box.node ?? .null
    }

    /// What a custom strategy's closure encodes: an empty object when it encodes nothing, as
    /// Foundation's does.
    private func custom(_ codingPath: [any CodingKey], _ body: (any Encoder) throws -> Void) throws -> _JSONNode {
        let encoder = _JSONEncoding(codingPath: codingPath, options: self)
        try body(encoder)
        return encoder.box.node ?? .object(_JSONObjectBox())
    }

    func number(_ value: Double, codingPath: [any CodingKey]) throws -> _JSONNode {
        if !value.isFinite, let strings = nonConformingFloats {
            return .string(value.isNaN ? strings.nan : value > 0 ? strings.positiveInfinity : strings.negativeInfinity)
        }
        return try _JSONWriter.number(value, codingPath: codingPath)
    }

    /// A `Float` written as its own shortest digits (`0.1`, not the `0.10000000149011612` of
    /// its `Double`), as Foundation writes one.
    func number(_ value: Float, codingPath: [any CodingKey]) throws -> _JSONNode {
        guard value.isFinite, value != value.rounded() else { return try number(Double(value), codingPath: codingPath) }
        return .number(Double(value.description) ?? Double(value))
    }

    /// The name a key is written under.
    func name(_ key: any CodingKey, codingPath: [any CodingKey]) -> String {
        switch keyStrategy {
        case .useDefault: return key.stringValue
        case .snakeCase: return Self.snakeCase(key.stringValue)
        case .custom(let convert): return convert(codingPath + [key]).stringValue
        }
    }

    /// A key as Foundation's `convertToSnakeCase` writes it: words split before each capital
    /// and around each run of capitals, lowercased and joined by underscores
    /// (`myURLProperty` → `my_url_property`).
    static func snakeCase(_ key: String) -> String {
        let characters = Array(key)
        guard !characters.isEmpty else { return key }
        let end = characters.count
        func first(from start: Int, _ test: (Character) -> Bool) -> Int? { (start..<end).first { test(characters[$0]) } }
        var words: [Range<Int>] = []
        var wordStart = 0
        var searchStart = 1
        while let upper = first(from: searchStart, \.isUppercase) {
            words.append(wordStart..<upper)
            guard let lower = first(from: upper, \.isLowercase) else { wordStart = upper; break }
            if lower == upper + 1 {
                wordStart = upper
            } else {
                // A run of capitals is a word of its own, up to the capital before the lowercase.
                words.append(upper..<(lower - 1))
                wordStart = lower - 1
            }
            searchStart = lower + 1
        }
        words.append(wordStart..<end)
        return words.map { String(characters[$0]).lowercased() }.joined(separator: "_")
    }
}

final class _JSONEncoding: Encoder {
    let codingPath: [CodingKey]
    let options: _JSONEncodingOptions
    let box: _JSONNodeBox
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(codingPath: [CodingKey], options: _JSONEncodingOptions, box: _JSONNodeBox = _JSONNodeBox()) {
        self.codingPath = codingPath
        self.options = options
        self.box = box
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let object: _JSONObjectBox
        if case .object(let existing)? = box.node { object = existing } else { object = _JSONObjectBox(); box.node = .object(object) }
        return KeyedEncodingContainer(_JSONKeyedEncoding<Key>(object: object, codingPath: codingPath, options: options))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let array: _JSONArrayBox
        if case .array(let existing)? = box.node { array = existing } else { array = _JSONArrayBox(); box.node = .array(array) }
        return _JSONUnkeyedEncoding(array: array, codingPath: codingPath, options: options)
    }

    func singleValueContainer() -> SingleValueEncodingContainer { _JSONSingleValueEncoding(box: box, codingPath: codingPath, options: options) }
}

/// A key on an encoder's path (`Int` keys for unkeyed containers, `super` for super encoders).
struct _JSONKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) { self.stringValue = "Index \(intValue)"; self.intValue = intValue }
    static let superKey = _JSONKey(stringValue: "super")
}

struct _JSONKeyedEncoding<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let object: _JSONObjectBox
    let codingPath: [CodingKey]
    let options: _JSONEncodingOptions

    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }
    private func set(_ node: _JSONNode, _ key: Key) { object[options.name(key, codingPath: codingPath)] = node }
    mutating func encodeNil(forKey key: Key) throws { set(.null, key) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { set(.bool(value), key) }
    mutating func encode(_ value: String, forKey key: Key) throws { set(.string(value), key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { set(try options.number(value, codingPath: path(key)), key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { set(try options.number(value, codingPath: path(key)), key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { set(.integer(value), key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { set(try _JSONWriter.unsigned(UInt64(value), codingPath: path(key)), key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { set(.integer(Int64(value)), key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { set(try _JSONWriter.unsigned(value, codingPath: path(key)), key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { set(try options.node(for: value, codingPath: path(key)), key) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let name = options.name(key, codingPath: codingPath)
        let nested: _JSONObjectBox
        if case .object(let existing)? = object[name] { nested = existing } else { nested = _JSONObjectBox(); object[name] = .object(nested) }
        return KeyedEncodingContainer(_JSONKeyedEncoding<NestedKey>(object: nested, codingPath: path(key), options: options))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let name = options.name(key, codingPath: codingPath)
        let nested: _JSONArrayBox
        if case .array(let existing)? = object[name] { nested = existing } else { nested = _JSONArrayBox(); object[name] = .array(nested) }
        return _JSONUnkeyedEncoding(array: nested, codingPath: path(key), options: options)
    }

    mutating func superEncoder() -> Encoder { superEncoder(named: _JSONKey.superKey.stringValue, path: codingPath + [_JSONKey.superKey]) }
    mutating func superEncoder(forKey key: Key) -> Encoder { superEncoder(named: options.name(key, codingPath: codingPath), path: path(key)) }

    private func superEncoder(named name: String, path: [CodingKey]) -> Encoder {
        let box = _JSONNodeBox()
        object[name] = .deferred(box)
        return _JSONEncoding(codingPath: path, options: options, box: box)
    }
}

struct _JSONUnkeyedEncoding: UnkeyedEncodingContainer {
    let array: _JSONArrayBox
    let codingPath: [CodingKey]
    let options: _JSONEncodingOptions
    var count: Int { array.items.count }

    private var nextPath: [CodingKey] { codingPath + [_JSONKey(intValue: array.items.count)] }
    mutating func encodeNil() throws { array.items.append(.null) }
    mutating func encode(_ value: Bool) throws { array.items.append(.bool(value)) }
    mutating func encode(_ value: String) throws { array.items.append(.string(value)) }
    mutating func encode(_ value: Double) throws { array.items.append(try options.number(value, codingPath: nextPath)) }
    mutating func encode(_ value: Float) throws { array.items.append(try options.number(value, codingPath: nextPath)) }
    mutating func encode(_ value: Int) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int8) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int16) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int32) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int64) throws { array.items.append(.integer(value)) }
    mutating func encode(_ value: UInt) throws { array.items.append(try _JSONWriter.unsigned(UInt64(value), codingPath: nextPath)) }
    mutating func encode(_ value: UInt8) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt16) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt32) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt64) throws { array.items.append(try _JSONWriter.unsigned(value, codingPath: nextPath)) }
    mutating func encode<T: Encodable>(_ value: T) throws { array.items.append(try options.node(for: value, codingPath: nextPath)) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let nested = _JSONObjectBox()
        let path = nextPath
        array.items.append(.object(nested))
        return KeyedEncodingContainer(_JSONKeyedEncoding<NestedKey>(object: nested, codingPath: path, options: options))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let nested = _JSONArrayBox()
        let path = nextPath
        array.items.append(.array(nested))
        return _JSONUnkeyedEncoding(array: nested, codingPath: path, options: options)
    }

    mutating func superEncoder() -> Encoder {
        let box = _JSONNodeBox()
        let path = nextPath
        array.items.append(.deferred(box))
        return _JSONEncoding(codingPath: path, options: options, box: box)
    }
}

struct _JSONSingleValueEncoding: SingleValueEncodingContainer {
    let box: _JSONNodeBox
    let codingPath: [CodingKey]
    let options: _JSONEncodingOptions

    mutating func encodeNil() throws { box.node = .null }
    mutating func encode(_ value: Bool) throws { box.node = .bool(value) }
    mutating func encode(_ value: String) throws { box.node = .string(value) }
    mutating func encode(_ value: Double) throws { box.node = try options.number(value, codingPath: codingPath) }
    mutating func encode(_ value: Float) throws { box.node = try options.number(value, codingPath: codingPath) }
    mutating func encode(_ value: Int) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int8) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int16) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int32) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int64) throws { box.node = .integer(value) }
    mutating func encode(_ value: UInt) throws { box.node = try _JSONWriter.unsigned(UInt64(value), codingPath: codingPath) }
    mutating func encode(_ value: UInt8) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt16) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt32) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt64) throws { box.node = try _JSONWriter.unsigned(value, codingPath: codingPath) }
    mutating func encode<T: Encodable>(_ value: T) throws { box.node = try options.node(for: value, codingPath: codingPath) }
}

/// How the writer lays the text out: `JSONEncoder.OutputFormatting` and
/// `JSONSerialization.WritingOptions`.
package struct _JSONFormat {
    /// Two-space indents, a line per value and `"key" : value`.
    package var prettyPrinted = false
    /// Object keys in Foundation's order: case-insensitive, digit runs by their value.
    package var sortedKeys = false
    /// `/` written as `\/`, as Foundation's coders do unless asked not to.
    package var escapesSlashes = false
    package init() {}
}

enum _JSONWriter {
    static func number(_ value: Double, codingPath: [CodingKey]) throws -> _JSONNode {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "JSON has no representation for \(value)"))
        }
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 { return .integer(Int64(value)) }
        return .number(value)
    }

    static func unsigned(_ value: UInt64, codingPath: [CodingKey]) throws -> _JSONNode {
        guard let signed = Int64(exactly: value) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "\(value) exceeds the JSON integer range"))
        }
        return .integer(signed)
    }

    static func write(_ node: _JSONNode, into text: inout String, format: _JSONFormat = _JSONFormat(), depth: Int = 0) throws {
        func newline(_ level: Int) {
            guard format.prettyPrinted else { return }
            text += "\n"
            text += String(repeating: " ", count: level * 2)
        }
        switch node {
        case .null: text += "null"
        case .bool(let value): text += value ? "true" : "false"
        case .integer(let value): text += String(value)
        case .number(let value): text += String(value)
        case .string(let value): writeString(value, into: &text, escapingSlashes: format.escapesSlashes)
        case .array(let box):
            guard !box.items.isEmpty else { text += "[]"; return }
            text += "["
            for (index, item) in box.items.enumerated() {
                if index > 0 { text += "," }
                newline(depth + 1)
                try write(item, into: &text, format: format, depth: depth + 1)
            }
            newline(depth)
            text += "]"
        case .object(let box):
            guard !box.entries.isEmpty else { text += "{}"; return }
            let entries = format.sortedKeys ? box.entries.sorted { precedes($0.key, $1.key) } : box.entries
            text += "{"
            for (index, entry) in entries.enumerated() {
                if index > 0 { text += "," }
                newline(depth + 1)
                writeString(entry.key, into: &text, escapingSlashes: format.escapesSlashes)
                text += format.prettyPrinted ? " : " : ":"
                try write(entry.value, into: &text, format: format, depth: depth + 1)
            }
            newline(depth)
            text += "}"
        case .deferred(let box): try write(box.node ?? .null, into: &text, format: format, depth: depth)
        }
    }

    /// Whether key `a` sorts before `b` as Foundation's `sortedKeys` orders them: compared
    /// without case, a run of digits by its value (`item2` before `item10`), ties by their scalars.
    static func precedes(_ a: String, _ b: String) -> Bool {
        let x = Array(a.lowercased().unicodeScalars), y = Array(b.lowercased().unicodeScalars)
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar.value >= 48 && scalar.value <= 57 }
        var i = 0, j = 0
        while i < x.count, j < y.count {
            if isDigit(x[i]), isDigit(y[j]) {
                var p = i, q = j
                while p < x.count, isDigit(x[p]) { p += 1 }
                while q < y.count, isDigit(y[q]) { q += 1 }
                let left = x[i..<p].drop { $0 == "0" }, right = y[j..<q].drop { $0 == "0" }
                if left.count != right.count { return left.count < right.count }
                for (l, r) in zip(left, right) where l != r { return l.value < r.value }
                i = p
                j = q
                continue
            }
            if x[i] != y[j] { return x[i].value < y[j].value }
            i += 1
            j += 1
        }
        if x.count - i != y.count - j { return x.count - i < y.count - j }
        return a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars)
    }

    static func writeString(_ value: String, into text: inout String, escapingSlashes: Bool = false) {
        text += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "/" where escapingSlashes: text += "\\/"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case "\u{00}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}

/// A date as `JSONEncoder.DateEncodingStrategy.iso8601` writes it: UTC to the whole second,
/// `2023-11-14T22:13:20Z`.
func _formatISO8601(_ date: Date) -> String {
    // Days and the second of the day in Double first: a 32-bit Int (wasm32) holds seconds only from 1901 to 2038.
    let seconds = date.timeIntervalSince1970.rounded(.down)
    let days = _Gregorian.day(ofSeconds: seconds)
    let time = Int(seconds - Double(days) * 86400)
    // A civil date from days since 1970-01-01 (Howard Hinnant's, proleptic Gregorian).
    let z = days + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
    return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(time / 3600, 2)):\(pad(time / 60 % 60, 2)):\(pad(time % 60, 2))Z"
}

// MARK: - Decoding

/// Decodes a `Codable` transfer item from JSON.
/// `2023-11-14T22:13:20Z`, with an optional fraction and a `±hh:mm` or `Z` zone — the form
/// `JSONDecoder.DateDecodingStrategy.iso8601` reads (the `.iso8601` format style is wasm-only).
func _parseISO8601(_ text: String) -> Date? {
    let scalars = Array(text.utf8)
    func digits(_ range: Range<Int>) -> Int? {
        guard range.upperBound <= scalars.count else { return nil }
        var value = 0
        for byte in scalars[range] { guard byte >= 48 && byte <= 57 else { return nil }; value = value * 10 + Int(byte - 48) }
        return value
    }
    guard scalars.count >= 19, let year = digits(0..<4), let month = digits(5..<7), let day = digits(8..<10),
          let hour = digits(11..<13), let minute = digits(14..<16), let second = digits(17..<19) else { return nil }
    var index = 19
    var fraction = 0.0
    if index < scalars.count, scalars[index] == UInt8(ascii: ".") {
        index += 1
        var scale = 0.1
        while index < scalars.count, scalars[index] >= 48, scalars[index] <= 57 { fraction += Double(scalars[index] - 48) * scale; scale /= 10; index += 1 }
    }
    var offset = 0
    if index < scalars.count {
        let sign = scalars[index]
        if sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-"), let h = digits(index + 1..<index + 3), let m = digits(index + 4..<index + 6) {
            offset = (h * 3600 + m * 60) * (sign == UInt8(ascii: "-") ? -1 : 1)
        } else if sign != UInt8(ascii: "Z") { return nil }
    }
    // Days since 1970-01-01 (a proleptic Gregorian civil-from-days, Howard Hinnant's).
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146097 + doe - 719468
    return Date(timeIntervalSince1970: Double(days * 86400 + hour * 3600 + minute * 60 + second - offset) + fraction)
}

/// What a `JSONDecoder`'s strategies ask of the decoding (the transfer coders use the defaults:
/// `Codable`'s own dates and data, keys as written).
package struct _JSONDecodingOptions {
    package enum DateStrategy {
        case deferred, secondsSince1970, millisecondsSince1970, iso8601
        case formatted(DateFormatter)
        case custom((any Decoder) throws -> Date)
    }
    package enum DataStrategy { case deferred, base64, custom((any Decoder) throws -> Data) }

    package var dateStrategy: DateStrategy = .deferred
    package var dataStrategy: DataStrategy = .deferred
    package var convertsFromSnakeCase = false
    /// A custom key strategy: the key an object's key stands for, given the path to it.
    package var keyConverter: (([any CodingKey]) -> any CodingKey)?
    /// The strings read as +∞, -∞ and NaN (`convertFromString`).
    package var nonConformingFloats: (positiveInfinity: String, negativeInfinity: String, nan: String)?
    package var userInfo: [CodingUserInfoKey: Any] = [:]
    package init() {}

    func nonConforming(_ text: String) -> Double? {
        guard let strings = nonConformingFloats else { return nil }
        switch text {
        case strings.positiveInfinity: return .infinity
        case strings.negativeInfinity: return -.infinity
        case strings.nan: return .nan
        default: return nil
        }
    }
}

public struct _TransferJSONDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decode(type, from: data, options: _JSONDecodingOptions())
    }

    package func decode<T: Decodable>(_ type: T.Type, from data: Data, options: _JSONDecodingOptions) throws -> T {
        var parser = _JSONParser(bytes: Array(data))
        var node = try parser.parseDocument()
        if let convert = options.keyConverter {
            node = Self.convertingKeys(node, path: []) { convert($0).stringValue }
        } else if options.convertsFromSnakeCase {
            node = Self.convertingKeysFromSnakeCase(node)
        }
        if let special = try _JSONDecoding.special(type, from: node, codingPath: [], options: options) { return special }
        return try T(from: _JSONDecoding(node: node, codingPath: [], options: options))
    }

    /// Every object key as Foundation's `convertFromSnakeCase` reads it: the underscores
    /// between words dropped and the word after each capitalised (`created_at_i` → `createdAtI`),
    /// leading and trailing underscores kept.
    static func convertingKeysFromSnakeCase(_ node: _JSONNode) -> _JSONNode {
        switch node {
        case .array(let box): return .array(_JSONArrayBox(box.items.map(convertingKeysFromSnakeCase)))
        case .object(let box): return .object(_JSONObjectBox(box.entries.map { (snakeToCamel($0.key), convertingKeysFromSnakeCase($0.value)) }))
        default: return node
        }
    }

    /// Every object key as a custom key strategy names it, given the path to the key.
    static func convertingKeys(_ node: _JSONNode, path: [any CodingKey], _ convert: ([any CodingKey]) -> String) -> _JSONNode {
        switch node {
        case .array(let box):
            return .array(_JSONArrayBox(box.items.enumerated().map { convertingKeys($1, path: path + [_JSONKey(intValue: $0)], convert) }))
        case .object(let box):
            return .object(_JSONObjectBox(box.entries.map { entry in
                let name = convert(path + [_JSONKey(stringValue: entry.key)])
                return (name, convertingKeys(entry.value, path: path + [_JSONKey(stringValue: name)], convert))
            }))
        default: return node
        }
    }

    static func snakeToCamel(_ key: String) -> String {
        guard key.contains("_") else { return key }
        let leading = key.prefix { $0 == "_" }
        let trailing = key.reversed().prefix { $0 == "_" }
        let core = key.dropFirst(leading.count).dropLast(trailing.count)
        guard !core.isEmpty else { return key }
        let words = core.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = words.first else { return key }
        let joined = first.lowercased() + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined()
        return String(leading) + joined + String(trailing)
    }
}

struct _JSONParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> _JSONNode {
        let node = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw error("Unexpected text after the JSON value") }
        return node
    }

    private func error(_ message: String) -> DecodingError {
        .dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "\(message) at byte \(index)"))
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 { index += 1 }
    }

    private mutating func consume(_ literal: String) throws {
        for byte in literal.utf8 {
            guard index < bytes.count, bytes[index] == byte else { throw error("Malformed literal") }
            index += 1
        }
    }

    private mutating func parseValue() throws -> _JSONNode {
        skipWhitespace()
        guard index < bytes.count else { throw error("Unexpected end of JSON") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try consume("true"); return .bool(true)
        case UInt8(ascii: "f"): try consume("false"); return .bool(false)
        case UInt8(ascii: "n"): try consume("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func parseObject() throws -> _JSONNode {
        index += 1
        let object = _JSONObjectBox()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("Expected an object key") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("Expected ':'") }
            index += 1
            object.entries.append((key, try parseValue()))
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated object") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
            throw error("Expected ',' or '}'")
        }
    }

    private mutating func parseArray() throws -> _JSONNode {
        index += 1
        let array = _JSONArrayBox()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(array) }
        while true {
            array.items.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated array") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(array) }
            throw error("Expected ',' or ']'")
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var scalars = String.UnicodeScalarView()
        var utf8Run: [UInt8] = []
        func flushRun() {
            if !utf8Run.isEmpty { scalars.append(contentsOf: String(decoding: utf8Run, as: UTF8.self).unicodeScalars); utf8Run.removeAll() }
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                flushRun()
                return String(scalars)
            case UInt8(ascii: "\\"):
                flushRun()
                guard index < bytes.count else { throw error("Unterminated escape") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try parseHex4()
                    if code >= 0xD800, code < 0xDC00 {
                        try consume("\\u")
                        let low = try parseHex4()
                        guard low >= 0xDC00, low < 0xE000 else { throw error("Invalid surrogate pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw error("Invalid unicode escape") }
                    scalars.append(scalar)
                default: throw error("Unknown escape")
                }
            default:
                utf8Run.append(byte)
            }
        }
        throw error("Unterminated string")
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("Short unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A")) + 10
            default: throw error("Invalid hex digit")
            }
            value = value * 16 + digit
        }
        return value
    }

    private mutating func parseNumber() throws -> _JSONNode {
        let start = index
        var isInteger = true
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") { isInteger = false }
            else if !(byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))) { break }
            index += 1
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if isInteger, let value = Int64(text) { return .integer(value) }
        guard let value = Double(text) else { throw error("Malformed number '\(text)'") }
        return .number(value)
    }
}

final class _JSONDecoding: Decoder {
    let node: _JSONNode
    let codingPath: [CodingKey]
    let options: _JSONDecodingOptions
    var userInfo: [CodingUserInfoKey: Any] { options.userInfo }

    init(node: _JSONNode, codingPath: [CodingKey], options: _JSONDecodingOptions = _JSONDecodingOptions()) {
        self.node = node
        self.codingPath = codingPath
        self.options = options
    }

    /// A date or data under a strategy other than its own `Codable`, or a URL written as a
    /// string (as `JSONEncoder` writes one); nil lets the type decode itself.
    static func special<T>(_ type: T.Type, from node: _JSONNode, codingPath: [CodingKey], options: _JSONDecodingOptions) throws -> T? {
        func corrupted(_ message: String) -> DecodingError {
            .dataCorrupted(DecodingError.Context(codingPath: codingPath, debugDescription: message))
        }
        if T.self == Date.self {
            let date: Date
            switch options.dateStrategy {
            case .deferred: return nil
            case .secondsSince1970: date = Date(timeIntervalSince1970: try primitive(Double.self, from: node, codingPath: codingPath, options: options))
            case .millisecondsSince1970: date = Date(timeIntervalSince1970: try primitive(Double.self, from: node, codingPath: codingPath, options: options) / 1000)
            case .iso8601:
                guard let parsed = _parseISO8601(try primitive(String.self, from: node, codingPath: codingPath)) else {
                    throw corrupted("Expected date string to be ISO8601-formatted.")
                }
                date = parsed
            case .formatted(let formatter):
                guard let parsed = formatter.date(from: try primitive(String.self, from: node, codingPath: codingPath)) else {
                    throw corrupted("Date string does not match format expected by formatter.")
                }
                date = parsed
            case .custom(let decode): date = try decode(_JSONDecoding(node: node, codingPath: codingPath, options: options))
            }
            return date as? T
        }
        if T.self == Data.self {
            switch options.dataStrategy {
            case .deferred: return nil
            case .base64:
                // An array of bytes still decodes as `Data`'s own: stores the Core Data and
                // SwiftData stand-ins wrote before the encoder applied its strategies.
                guard case .string(let text) = node else { return nil }
                guard let data = Data(base64Encoded: text) else {
                    throw corrupted("Encountered Data is not valid Base64.")
                }
                return data as? T
            case .custom(let decode): return try decode(_JSONDecoding(node: node, codingPath: codingPath, options: options)) as? T
            }
        }
        // A URL's own `Codable` is keyed, which still decodes below.
        if T.self == URL.self, case .string(let text) = node {
            guard let url = URL(string: text) else { throw corrupted("Invalid URL string.") }
            return url as? T
        }
        return nil
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = node else { throw _JSONDecoding.mismatch([String: Any].self, node, codingPath) }
        return KeyedDecodingContainer(_JSONKeyedDecoding<Key>(object: object, codingPath: codingPath, options: options))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = node else { throw _JSONDecoding.mismatch([Any].self, node, codingPath) }
        return _JSONUnkeyedDecoding(array: array, codingPath: codingPath, options: options)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer { _JSONSingleValueDecoding(node: node, codingPath: codingPath, options: options) }

    static func mismatch(_ type: Any.Type, _ node: _JSONNode, _ codingPath: [CodingKey]) -> DecodingError {
        if case .null = node {
            return .valueNotFound(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type) but found null"))
        }
        return .typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type)"))
    }

    /// The primitive a node holds as `T`, or a type mismatch.
    static func primitive<T>(_ type: T.Type, from node: _JSONNode, codingPath: [CodingKey], options: _JSONDecodingOptions? = nil) throws -> T {
        let value: Any?
        switch (type, node) {
        case (is Bool.Type, .bool(let bool)): value = bool
        case (is String.Type, .string(let string)): value = string
        case (is Double.Type, .integer(let whole)): value = Double(whole)
        case (is Double.Type, .number(let number)): value = number
        case (is Float.Type, .integer(let whole)): value = Float(whole)
        case (is Float.Type, .number(let number)): value = Float(number)
        case (is Double.Type, .string(let text)): value = options?.nonConforming(text)
        case (is Float.Type, .string(let text)): value = options?.nonConforming(text).map { Float($0) }
        case (_, .integer(let whole)): value = integer(type, whole)
        case (_, .number(let number)) where number == number.rounded() && abs(number) < 9.2e18: value = integer(type, Int64(number))
        default: value = nil
        }
        guard let value = value as? T else { throw mismatch(type, node, codingPath) }
        return value
    }

    private static func integer<T>(_ type: T.Type, _ value: Int64) -> Any? {
        switch type {
        case is Int.Type: return Int(exactly: value)
        case is Int8.Type: return Int8(exactly: value)
        case is Int16.Type: return Int16(exactly: value)
        case is Int32.Type: return Int32(exactly: value)
        case is Int64.Type: return value
        case is UInt.Type: return UInt(exactly: value)
        case is UInt8.Type: return UInt8(exactly: value)
        case is UInt16.Type: return UInt16(exactly: value)
        case is UInt32.Type: return UInt32(exactly: value)
        case is UInt64.Type: return UInt64(exactly: value)
        default: return nil
        }
    }
}

struct _JSONKeyedDecoding<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: _JSONObjectBox
    let codingPath: [CodingKey]
    var options = _JSONDecodingOptions()

    var allKeys: [Key] { object.entries.compactMap { Key(stringValue: $0.key) } }
    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    private func node(_ key: Key) throws -> _JSONNode {
        guard let node = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "No value for '\(key.stringValue)'"))
        }
        return node
    }
    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }
    private func primitive<T>(_ type: T.Type, _ key: Key) throws -> T { try _JSONDecoding.primitive(type, from: try node(key), codingPath: path(key), options: options) }

    func decodeNil(forKey key: Key) throws -> Bool { if case .null = try node(key) { return true } else { return false } }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try primitive(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try primitive(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try primitive(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try primitive(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try primitive(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try primitive(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try primitive(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try primitive(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try primitive(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try primitive(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try primitive(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try primitive(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try primitive(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try primitive(type, key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let child = try node(key)
        if let special = try _JSONDecoding.special(type, from: child, codingPath: path(key), options: options) { return special }
        return try T(from: _JSONDecoding(node: child, codingPath: path(key), options: options))
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try _JSONDecoding(node: try node(key), codingPath: path(key), options: options).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try _JSONDecoding(node: try node(key), codingPath: path(key), options: options).unkeyedContainer()
    }
    func superDecoder() throws -> Decoder {
        _JSONDecoding(node: object[_JSONKey.superKey.stringValue] ?? .null, codingPath: codingPath + [_JSONKey.superKey], options: options)
    }
    func superDecoder(forKey key: Key) throws -> Decoder { _JSONDecoding(node: try node(key), codingPath: path(key), options: options) }
}

struct _JSONUnkeyedDecoding: UnkeyedDecodingContainer {
    let array: _JSONArrayBox
    let codingPath: [CodingKey]
    var options = _JSONDecodingOptions()
    var currentIndex = 0

    var count: Int? { array.items.count }
    var isAtEnd: Bool { currentIndex >= array.items.count }

    private var path: [CodingKey] { codingPath + [_JSONKey(intValue: currentIndex)] }
    private mutating func next() throws -> _JSONNode {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: path, debugDescription: "Unkeyed container is at end"))
        }
        defer { currentIndex += 1 }
        return array.items[currentIndex]
    }
    private mutating func primitive<T>(_ type: T.Type) throws -> T {
        let path = path
        return try _JSONDecoding.primitive(type, from: try next(), codingPath: path, options: options)
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if case .null = array.items[currentIndex] { currentIndex += 1; return true }
        return false
    }
    mutating func decode(_ type: Bool.Type) throws -> Bool { try primitive(type) }
    mutating func decode(_ type: String.Type) throws -> String { try primitive(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try primitive(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try primitive(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try primitive(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try primitive(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try primitive(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try primitive(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try primitive(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try primitive(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try primitive(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try primitive(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try primitive(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try primitive(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let path = path
        let child = try next()
        if let special = try _JSONDecoding.special(type, from: child, codingPath: path, options: options) { return special }
        return try T(from: _JSONDecoding(node: child, codingPath: path, options: options))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let path = path
        return try _JSONDecoding(node: try next(), codingPath: path, options: options).container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let path = path
        return try _JSONDecoding(node: try next(), codingPath: path, options: options).unkeyedContainer()
    }
    mutating func superDecoder() throws -> Decoder {
        let path = path
        return _JSONDecoding(node: try next(), codingPath: path, options: options)
    }
}

struct _JSONSingleValueDecoding: SingleValueDecodingContainer {
    let node: _JSONNode
    let codingPath: [CodingKey]
    var options = _JSONDecodingOptions()

    private func primitive<T>(_ type: T.Type) throws -> T { try _JSONDecoding.primitive(type, from: node, codingPath: codingPath, options: options) }
    func decodeNil() -> Bool { if case .null = node { return true } else { return false } }
    func decode(_ type: Bool.Type) throws -> Bool { try primitive(type) }
    func decode(_ type: String.Type) throws -> String { try primitive(type) }
    func decode(_ type: Double.Type) throws -> Double { try primitive(type) }
    func decode(_ type: Float.Type) throws -> Float { try primitive(type) }
    func decode(_ type: Int.Type) throws -> Int { try primitive(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try primitive(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try primitive(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try primitive(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try primitive(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try primitive(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try primitive(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try primitive(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try primitive(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try primitive(type) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let special = try _JSONDecoding.special(type, from: node, codingPath: codingPath, options: options) { return special }
        return try T(from: _JSONDecoding(node: node, codingPath: codingPath, options: options))
    }
}
