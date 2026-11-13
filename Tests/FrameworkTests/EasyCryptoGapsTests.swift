// What EasyCrypto asks of NumberFormatter: an abbreviation suffix ("12.5K"), padded integer
// digits, a decimal point that always shows, whole-number-only reading, and a subclass that
// reads its own input through `getObjectValue`. The cases run against Foundation on macOS and
// Linux too, which holds WebFoundation's answers to it.
import Testing
import WebFoundation
import WebFoundationFormats

@Suite struct EasyCryptoGapsTests {
    @Test func suffixesFollowTheSign() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.positiveSuffix = "K"
        formatter.negativeSuffix = "K"
        formatter.allowsFloats = true
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        #expect(formatter.string(from: NSNumber(value: 12.5)) == "12.5K")
        #expect(formatter.string(from: NSNumber(value: -3)) == "-3K")
        #expect(formatter.string(from: NSNumber(value: 0.25)) == "0.25K")
    }

    @Test func integerDigitsPadAndTheSeparatorCanStay() {
        let padded = NumberFormatter()
        padded.locale = Locale(identifier: "en_US")
        padded.minimumIntegerDigits = 3
        #expect(padded.string(from: NSNumber(value: 7)) == "007")
        let dotted = NumberFormatter()
        dotted.locale = Locale(identifier: "en_US")
        dotted.alwaysShowsDecimalSeparator = true
        #expect(dotted.string(from: NSNumber(value: 12)) == "12.")
        dotted.numberStyle = .currency
        dotted.minimumFractionDigits = 2
        dotted.maximumFractionDigits = 2
        #expect(dotted.string(from: NSNumber(value: 1234.5)) == "$1,234.50")
    }

    @Test func wholeNumbersOnlyWhenFloatsAreOff() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.allowsFloats = false
        #expect(formatter.number(from: "2") != nil)
        #if os(Linux)
        // swift-corelibs-foundation truncates "1.5" to 1 here, where Apple's Foundation (the
        // one iOS apps are written against, and the one WebFoundation follows) refuses it.
        // On Linux the case can only hold that the fraction is never kept.
        #expect(formatter.number(from: "1.5")?.doubleValue != 1.5)
        #else
        #expect(formatter.number(from: "1.5") == nil)
        #endif
        #expect(NumberFormatter().number(from: "abc") == nil)
    }

    #if _runtime(_ObjC)
    /// EasyCrypto's DecimalFormatter form: digits read as cents.
    final class CentsFormatter: NumberFormatter, @unchecked Sendable {
        override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
                                     range rangep: UnsafeMutablePointer<NSRange>?) throws {
            let digits = string.filter(\.isNumber)
            obj?.pointee = NSNumber(value: (Double(digits) ?? 0) / 100)
        }
    }

    @Test func aSubclassReadsItsOwnForm() {
        #expect(CentsFormatter().number(from: "$12.34").map { "\($0)" } == "12.34")
    }
    #endif
}
