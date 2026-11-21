#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
// The drawn iPhone's keyboard: which keys it has and where they sit (new-website#619, built in
// #648). Traced from the iOS 27 simulator on an iPhone 16 (393 × 852 pt): the keyboard is 328 pt
// tall from the screen's bottom (UIKit's end frame y 524), a 53 pt suggestions band on top,
// four rows of 42 pt keys at 53, 107, 161 and 215, the globe and the microphone under them. The layout follows the app's
// language: German gets Swiss German (QWERTZ with Ü Ö Ä), French Swiss French, anything else
// US English.

/// One of the keyboard's layouts.
package enum KeyboardLanguage: String, CaseIterable, Sendable {
    case swissGerman, usEnglish, swissFrench

    /// The layout for a language identifier ("de-CH", "fr", "en-US").
    package init(languageIdentifier: String) {
        let code = languageIdentifier.lowercased().prefix { $0.isLetter }
        switch code {
        case "de", "gsw": self = .swissGerman
        case "fr": self = .swissFrench
        default: self = .usEnglish
        }
    }

    /// The small tag at the space bar's bottom right.
    package var tag: String {
        switch self {
        case .swissGerman: return "DE"
        case .usEnglish: return "EN"
        case .swissFrench: return "FR"
        }
    }

    /// The three letter rows, lower case.
    package var letterRows: [[String]] {
        let rows: [String]
        switch self {
        case .swissGerman: rows = ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"]
        case .usEnglish: rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        case .swissFrench: rows = ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
        }
        return rows.map { $0.map(String.init) }
    }

    /// The 123 page's first two rows (the third is shared): € on the Swiss pages, $ in the US.
    package var numberRows: [[String]] {
        let currency = self == .usEnglish ? "$" : "€"
        return [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", currency, "&", "@", "\""]]
    }

    /// The #+= page's first two rows: the currencies the 123 page does not have.
    package var symbolRows: [[String]] {
        let currencies = self == .usEnglish ? ["€", "£", "¥"] : ["$", "£", "¥"]
        return [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">"] + currencies + ["•"]]
    }

    /// The accents a long press on a letter offers, the letter itself first.
    package func accents(for letter: String) -> [String]? {
        // Swiss French as the iOS 27 simulator shows them (left to right, the plain letter
        // first where the row opens to the right); the others' rows are traced the same way.
        let french: [String: String] = [
            "e": "eéèêëęėē", "a": "aàâæáäãåāª", "u": "uûùüúū", "i": "iîïìíįī", "o": "oöôœòóõøōº", "c": "cçćč",
        ]
        let table: [String: String] = [
            "a": "aàáâäæãåā", "e": "eéèêëēėę", "o": "oöôòóœøōõ", "u": "uüûùúū", "i": "iîïíīįì",
            "c": "cçćč", "n": "nñń", "s": "sßśš", "y": "yÿ", "z": "zžźż", "l": "lł",
        ]
        guard let accents = (self == .swissFrench ? french[letter] ?? table[letter] : table[letter]) else { return nil }
        return accents.map(String.init)
    }

}

/// The page of keys showing.
package enum KeyboardPage: Equatable, Sendable {
    case letters, numbers, symbols
}

/// What a key does.
package enum KeyboardKeyKind: Equatable, Sendable {
    /// Types its character (letters follow shift).
    case character(String)
    case shift
    case delete
    /// 123, #+= and ABC: brings that page up.
    case page(KeyboardPage)
    case emoji
    /// Swiss French's accent key: puts the mark that suits the letter before the caret on it
    /// (´ on e, ` on a, ^ on u, o, i), an apostrophe after a consonant.
    case accent
    case space
    case `return`
}

/// A key and its frame in the keyboard's own space (its top left at the keyboard's top left).
package struct KeyboardKey: Equatable, Sendable {
    package var kind: KeyboardKeyKind
    package var frame: CGRect
}

/// The measured geometry of the iPhone 16 keyboard, in points.
package enum KeyboardMetrics {
    /// From the keyboard's top to the screen's bottom.
    package static let height: CGFloat = 328
    package static let width: CGFloat = 393
    package static let cornerRadius: CGFloat = 34
    package static let suggestionsHeight: CGFloat = 53
    package static let rowTops: [CGFloat] = [53.33, 107.33, 161.33, 215.33]
    package static let keyHeight: CGFloat = 42
    package static let keyCornerRadius: CGFloat = 8.5
    /// The globe's and the microphone's centres, from the keyboard's top.
    package static let iconRowCenterY: CGFloat = 289
    package static let globeCenterX: CGFloat = 38
    package static let micCenterX: CGFloat = 356
    /// The held key's bubble: at least this size, its bottom this far above the key's top.
    package static let bubbleSize = CGSize(width: 52, height: 64)
    package static let bubbleGap: CGFloat = 4
    package static let bubbleCornerRadius: CGFloat = 13
    /// The accent row: one cell per accent.
    package static let accentCell = CGSize(width: 42, height: 46)
    package static let accentPadding: CGFloat = 5
}

extension KeyboardLanguage {
    /// Every key of a page, laid out at `width` (the iPhone 16's 393 scales evenly to others).
    package func keys(page: KeyboardPage, width: CGFloat = KeyboardMetrics.width) -> [KeyboardKey] {
        let scale = width / KeyboardMetrics.width
        let rows = KeyboardMetrics.rowTops
        let h = KeyboardMetrics.keyHeight
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> CGRect { CGRect(x: x * scale, y: y, width: w * scale, height: h) }
        var keys: [KeyboardKey] = []
        /// A row of character keys (11-key keyboards 28.33 wide 35 apart, 10-key ones 32 wide
        /// 38.67 apart): a full row from 7, a shorter one centred (measured on the iOS 27
        /// simulator's screenshots, `prototype-619-keyboard/ref/`).
        func characterRow(_ characters: [String], y: CGFloat, pitch: CGFloat, full: Int) {
            let w = pitch - 6.67
            let total = CGFloat(characters.count) * pitch - 6.67
            var x = characters.count >= full ? 7 : (KeyboardMetrics.width - total) / 2
            for character in characters {
                keys.append(KeyboardKey(kind: .character(character), frame: rect(x, y, w)))
                x += pitch
            }
        }
        switch page {
        case .letters:
            let letters = letterRows
            let full = max(letters[0].count, letters[1].count)
            let pitch: CGFloat = full == 11 ? 35 : 38.67
            characterRow(letters[0], y: rows[0], pitch: pitch, full: full)
            characterRow(letters[1], y: rows[1], pitch: pitch, full: self == .swissFrench ? letters[1].count : full)
            if self == .swissFrench {
                // The accent key after L: its mark follows the letter before the caret.
                keys.append(KeyboardKey(kind: .accent, frame: rect(7 + 9 * pitch, rows[1], pitch - 6.67)))
            }
            keys.append(KeyboardKey(kind: .shift, frame: rect(7, rows[2], 43.33)))
            characterRow(letters[2], y: rows[2], pitch: pitch, full: full)
            keys.append(KeyboardKey(kind: .delete, frame: rect(342.67, rows[2], 43.67)))
        case .numbers, .symbols:
            let top = page == .numbers ? numberRows : symbolRows
            characterRow(top[0], y: rows[0], pitch: 38.67, full: 10)
            characterRow(top[1], y: rows[1], pitch: 38.67, full: 10)
            keys.append(KeyboardKey(kind: .page(page == .numbers ? .symbols : .numbers), frame: rect(7, rows[2], 43.33)))
            for (index, character) in [".", ",", "?", "!", "'"].enumerated() {
                keys.append(KeyboardKey(kind: .character(character), frame: rect(64.67 + CGFloat(index) * 54.08, rows[2], 47.33)))
            }
            keys.append(KeyboardKey(kind: .delete, frame: rect(342.67, rows[2], 43.67)))
        }
        keys.append(KeyboardKey(kind: .page(page == .letters ? .numbers : .letters), frame: rect(7, rows[3], 41.33)))
        keys.append(KeyboardKey(kind: .emoji, frame: rect(55, rows[3], 41.67)))
        keys.append(KeyboardKey(kind: .space, frame: rect(103.33, rows[3], 186.33)))
        keys.append(KeyboardKey(kind: .return, frame: rect(296.33, rows[3], 90)))
        return keys
    }

    /// The page a typed character is on, nil when no page has it (an emoji, a newline).
    package func page(of character: String) -> KeyboardPage? {
        let lower = character.lowercased()
        if letterRows.joined().contains(lower) { return .letters }
        let shared = [".", ",", "?", "!", "'"]
        if numberRows.joined().contains(character) || shared.contains(character) { return .numbers }
        if symbolRows.joined().contains(character) { return .symbols }
        return nil
    }
}

/// The key under a finger: the key containing the point, else the nearest one within reach (the
/// gaps between keys belong to their neighbours, as on an iPhone), nil in the suggestions band
/// or far from every key.
package func keyboardKey(at point: CGPoint, in keys: [KeyboardKey]) -> KeyboardKey? {
    guard point.y >= KeyboardMetrics.rowTops[0] - 8 else { return nil }
    var best: KeyboardKey?
    var bestDistance = CGFloat.infinity
    for key in keys {
        let f = key.frame
        let dx = point.x < f.minX ? f.minX - point.x : point.x > f.maxX ? point.x - f.maxX : 0
        let dy = point.y < f.minY ? f.minY - point.y : point.y > f.maxY ? point.y - f.maxY : 0
        let distance = dx + dy * 2
        if distance < bestDistance { bestDistance = distance; best = key }
    }
    return bestDistance < 20 ? best : nil
}

/// Swiss French's accent key (`KeyboardKeyKind.accent`): the mark it shows after `previous` and
/// what tapping it does. Measured in the iOS 27 simulator: ´ in an empty field or after e,
/// ` after a, ^ after u, o and i, ’ after a consonant.
package enum FrenchAccentKey {
    package static func mark(after previous: Character?) -> String {
        guard let previous else { return "\u{B4}" }
        switch previous.lowercased() {
        case "e": return "\u{B4}"
        case "a": return "`"
        case "u", "o", "i": return "^"
        default: return previous.isLetter ? "\u{2019}" : "\u{B4}"
        }
    }

    /// The letter with the mark on it (é, à, û), nil when the mark goes on nothing (it is typed).
    package static func combined(_ previous: Character, mark: String) -> String? {
        let table: [String: String] = [
            "\u{B4}": "aáeéiíoóuúAÁEÉIÍOÓUÚ", "`": "aàeèiìoòuùAÀEÈIÌOÒUÙ",
            "^": "aâeêiîoôuûAÂEÊIÎOÔUÛ", "\u{A8}": "aäeëiïoöuüyÿAÄEËIÏOÖUÜ",
        ]
        guard let pairs = table[mark].map(Array.init), let index = pairs.firstIndex(of: previous), index % 2 == 0 else { return nil }
        return String(pairs[index + 1])
    }
}
