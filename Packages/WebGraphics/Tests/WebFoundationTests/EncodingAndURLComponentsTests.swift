// pf-web-foundation-gaps: the text encodings, Punycode hosts and URL component cores held
// to Foundation's on macOS.
import Testing
import Foundation
@testable import WebFoundation

/// Whether Foundation in this process rejects bytes above 0x7F as ASCII, as current systems do.
/// It reads them as Latin 1 for a program built with an SDK before macOS 15, and Swift 6.4.2's
/// `swiftpm-testing-helper`, the process the tests run in, is built with the macOS 14 SDK.
let foundationDecodesASCIIStrictly = String(data: Data([0x80]), encoding: .ascii) == nil

@Suite struct TextEncodingTests {
    static let samples = ["", "plain ASCII", "café ünïcödé", "日本語テキスト", "emoji 🙂👍🏽", "mixed: ß€“quotes”—dash", "\u{0}nul\u{1F}", "Zażółć gęślą jaźń"]
    static let pairs: [(_TextEncoding, String.Encoding)] = [
        (.utf8, .utf8), (.ascii, .ascii), (.isoLatin1, .isoLatin1), (.windows1252, .windowsCP1252), (.utf16, .utf16),
        (.utf16BigEndian, .utf16BigEndian), (.utf16LittleEndian, .utf16LittleEndian), (.utf32, .utf32),
        (.utf32BigEndian, .utf32BigEndian), (.utf32LittleEndian, .utf32LittleEndian),
    ]

    @Test(arguments: pairs) func encodingMatchesFoundation(_ pair: (_TextEncoding, String.Encoding)) {
        for text in Self.samples {
            let ours = _TextEncoding.encode(text, as: pair.0)
            let theirs = text.data(using: pair.1).map { Array($0) }
            #expect(ours == theirs, "\(pair.1) encode \(text)")
            // Lossy conversion writes a question mark per UTF-16 unit; Foundation's ASCII form also
            // transliterates Latin letters (not carried), so ASCII is compared on the other strings.
            // Linux's corelibs Foundation writes 0xFF instead (its own difference from Darwin).
            if foundationIsCurrent, pair.1 != .ascii || text.unicodeScalars.allSatisfy({ $0.value < 0xC0 || $0.value > 0x24F }) {
                let lossy = _TextEncoding.encode(text, as: pair.0, lossy: true)
                let theirLossy = text.data(using: pair.1, allowLossyConversion: true).map { Array($0) }
                #expect(lossy == theirLossy, "\(pair.1) lossy \(text)")
            }
            if let bytes = theirs {
                #expect(_TextEncoding.decode(bytes, as: pair.0) == String(data: Data(bytes), encoding: pair.1), "\(pair.1) decode \(text)")
            }
        }
    }

    @Test func decodingRejectsWhatFoundationRejects() {
        let bad: [[UInt8]] = [[0xC3], [0xFF, 0xFE, 0x00], [0x80], [0xED, 0xA0, 0x80], [0xD8, 0x00]]
        for bytes in bad {
            #expect(_TextEncoding.decode(bytes, as: .utf8) == String(data: Data(bytes), encoding: .utf8), "utf8 \(bytes)")
            if foundationDecodesASCIIStrictly {
                #expect(_TextEncoding.decode(bytes, as: .ascii) == String(data: Data(bytes), encoding: .ascii), "ascii \(bytes)")
            }
        }
        // A byte-order mark picks the order; without one UTF-16 reads big-endian.
        #expect(_TextEncoding.decode([0xFE, 0xFF, 0x00, 0x41], as: .utf16) == String(data: Data([0xFE, 0xFF, 0x00, 0x41]), encoding: .utf16))
        #expect(_TextEncoding.decode([0xFF, 0xFE, 0x41, 0x00], as: .utf16) == String(data: Data([0xFF, 0xFE, 0x41, 0x00]), encoding: .utf16))
        #expect(_TextEncoding.decode([0x00, 0x41], as: .utf16) == String(data: Data([0x00, 0x41]), encoding: .utf16))
        #expect(_TextEncoding.decode([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41], as: .utf32) == String(data: Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x41]), encoding: .utf32))
        #expect(_TextEncoding.decode([0x80, 0x9F, 0x81], as: .windows1252) == String(data: Data([0x80, 0x9F, 0x81]), encoding: .windowsCP1252))
    }
}

@Suite struct PunycodeTests {
    static let hosts = ["bücher.example", "例え.テスト", "Bücher.Example", "münchen.de", "ñandú.com.ar", "xn--already.encoded", "plain.example",
                        "mañana.ünïcödé.example", "ليهمابتكلموشعربي؟.example", "ᏣᎳᎩ.example", "a.bü-c.d", "-.ü"]

    @Test func hostsEncodeAsFoundationPunycodes() {
        for host in Self.hosts {
            let theirs = URL(string: "https://\(host)/")?.host
            #expect(_Punycode.encodedHost(host) == theirs, Comment(rawValue: host))
            #expect(_URLParts.parse("https://\(host)/path")?.host == theirs, "parse \(host)")
        }
        // Round trips and the Unicode form `URLComponents.host` shows.
        for host in Self.hosts where !host.hasPrefix("xn--") && !host.hasPrefix("-") {
            let encoded = _Punycode.encodedHost(host)!
            #expect(_Punycode.decodedHost(encoded) == URLComponents(string: "https://\(encoded)/")?.host, "decode \(host)")
        }
        #expect(_Punycode.decode("not-valid-\u{1F600}") == nil && _Punycode.decode("!!!") == nil)
    }
}

@Suite struct URLComponentsCoreTests {
    static let queries = ["x=1&y=a%20b&z&w=&v=1+2", "", "a=b=c&&d", "only", "%C3%BC=%C3%A4", "a=1&a=2", "=novalue", "sp%20ace=%26amp"]

    @Test func queryItemsSplitAsFoundationSplits() {
        for query in Self.queries {
            let components = URLComponents(string: "https://h/p?\(query)")!
            let ours = _URLParts.queryItems(query)
            let theirs = components.percentEncodedQueryItems ?? []
            #expect(ours.map(\.name) == theirs.map(\.name) && ours.map(\.value) == theirs.map(\.value), "split \(query)")
            let decoded = ours.map { (_URLParts.percentDecoded($0.name), $0.value.map(_URLParts.percentDecoded)) }
            let theirDecoded = (components.queryItems ?? []).map { ($0.name, $0.value) }
            #expect(decoded.map(\.0) == theirDecoded.map(\.0) && decoded.map(\.1) == theirDecoded.map(\.1), "decoded \(query)")
        }
        #expect(_URLParts.queryItems("").isEmpty && URLComponents(string: "https://h/p?")!.queryItems!.isEmpty)
    }

    @Test func queryItemsComposeAsFoundationComposes() {
        let items: [(String, String?)] = [("a b", "c&d"), ("e=f", "g+h"), ("ü", nil), ("empty", ""), ("q", "x?y/z#w"), ("per%cent", "100%"), ("colon:at@", "slash/")]
        var components = URLComponents(string: "https://h/p")!
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        #expect(_URLParts.query(items: items.map { (name: $0.0, value: $0.1) }) == components.percentEncodedQuery)
    }

    @Test func percentEncodingSetsMatchFoundation() {
        // Darwin's `urlPathAllowed` admits `;`; corelibs Foundation's does not: the Darwin sets are the reference.
        guard foundationIsCurrent else { return }
        let text = "aZ09-._~!$&'()*+,;=:@/?#[]%<> \"`{}|\\^ü日"
        let sets: [(_URLParts.Allowed, CharacterSet)] = [(.user, .urlUserAllowed), (.password, .urlPasswordAllowed), (.host, .urlHostAllowed), (.path, .urlPathAllowed), (.query, .urlQueryAllowed), (.fragment, .urlFragmentAllowed)]
        for (ours, theirs) in sets {
            #expect(_URLParts.percentEncoded(text, allowing: ours) == text.addingPercentEncoding(withAllowedCharacters: theirs), "\(theirs)")
        }
    }

    @Test func repairingAStringMatchesFoundation() {
        for text in ["not a url", "https://h/path;params?x=%zz", "https://h/a b?c=d e#f g", "%41%zz%", "https://h/\"quoted\"<>`{}|\\^"] {
            #expect(_URLParts.parse(_URLParts.repairedForParsing(text))?.string == URLComponents(string: text)?.string, Comment(rawValue: text))
        }
    }
}

/// The decoder's strategies (a `JSONDecoder` on wasm hands them to the transfer decoder;
/// the Ember app decodes Algolia's `created_at_i` with `convertFromSnakeCase`).
@Suite struct JSONDecodingStrategyTests {
    struct Hit: Decodable, Equatable {
        let objectId: String
        let createdAtI: Int
        let _private: Int?
        let whenSeconds: Date?
    }

    @Test func snakeCaseKeysBecomeCamelCase() throws {
        let json = #"{"object_id": "1", "created_at_i": 1700000000, "_private": 3, "when_seconds": 1700000000}"#
        var options = _JSONDecodingOptions()
        options.convertsFromSnakeCase = true
        options.dateStrategy = .secondsSince1970
        let hit = try _TransferJSONDecoder().decode(Hit.self, from: Data(json.utf8), options: options)
        #expect(hit.objectId == "1" && hit.createdAtI == 1_700_000_000 && hit._private == 3)
        #expect(hit.whenSeconds == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(_TransferJSONDecoder.snakeToCamel("created_at_i") == "createdAtI")
        #expect(_TransferJSONDecoder.snakeToCamel("__leading_x__") == "__leadingX__")
        #expect(_TransferJSONDecoder.snakeToCamel("plain") == "plain")
    }

    @Test func dateStrategiesReadNumbersAndISO8601() throws {
        struct Stamp: Decodable { let at: Date }
        var options = _JSONDecodingOptions()
        options.dateStrategy = .millisecondsSince1970
        #expect(try _TransferJSONDecoder().decode(Stamp.self, from: Data(#"{"at": 1700000000000}"#.utf8), options: options).at == Date(timeIntervalSince1970: 1_700_000_000))
        options.dateStrategy = .iso8601
        #expect(try _TransferJSONDecoder().decode(Stamp.self, from: Data(#"{"at": "2023-11-14T22:13:20Z"}"#.utf8), options: options).at == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
