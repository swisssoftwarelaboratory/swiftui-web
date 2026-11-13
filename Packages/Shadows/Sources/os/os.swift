// Apple's `os` module for wasm (Docs/coverage.md: 9 apps import `os`, 6 `OSLog`, 3 name
// `Logger`): the unified logging API over the page's console. `Logger`'s messages are string
// interpolations with the privacy, format and alignment options Apple's take; every value is
// written out, whatever its privacy, because the console a page logs to is the developer's own
// (Apple's redact private values only in logs read off the device). `os_log` takes the older
// format strings, with the arguments put in place of `%@`, `%d` and the like.
// `OSAllocatedUnfairLock` guards state with a closure as Apple's does; the wasm target runs one
// thread, so it orders nothing and needs no lock of its own.
#if os(WASI)

/// Where the compiler puts log strings it optimises (Swift 6.4 asks every module named `os` for
/// it, decision 0026). This module's messages are plain interpolations the compiler leaves alone,
/// so nothing lands there; the name is a wasm data segment's.
let osLogStringSectionName = ".rodata.oslogstring"

// MARK: Levels and logs

/// The level of a log message.
public struct OSLogType: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public init(_ rawValue: UInt8) { self.rawValue = rawValue }

    public static let `default` = OSLogType(rawValue: 0x00)
    public static let info = OSLogType(rawValue: 0x01)
    public static let debug = OSLogType(rawValue: 0x02)
    public static let error = OSLogType(rawValue: 0x10)
    public static let fault = OSLogType(rawValue: 0x11)

    var label: String {
        switch self {
        case .info: return "info"
        case .debug: return "debug"
        case .error: return "error"
        case .fault: return "fault"
        default: return "default"
        }
    }
}

/// A log object: the subsystem and category messages are filed under.
public final class OSLog: @unchecked Sendable {
    /// A category name, as the signpost categories Apple names.
    public struct Category: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let pointsOfInterest = Category(rawValue: "PointsOfInterest")
        public static let dynamicTracing = Category(rawValue: "DynamicTracing")
        public static let dynamicStackTracing = Category(rawValue: "DynamicStackTracing")
    }

    public let subsystem: String
    public let category: String
    let enabled: Bool

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        enabled = true
    }

    public convenience init(subsystem: String, category: Category) {
        self.init(subsystem: subsystem, category: category.rawValue)
    }

    private init(disabled: Void) {
        subsystem = ""
        category = ""
        enabled = false
    }

    /// The shared log with no subsystem.
    public static let `default` = OSLog(subsystem: "", category: "")
    /// A log that drops every message.
    public static let disabled = OSLog(disabled: ())

    public var signpostsEnabled: Bool { false }

    /// Whether messages of the given level are written: all of them, unless the log is disabled.
    public func isEnabled(type: OSLogType) -> Bool { enabled }

    func write(_ text: String, type: OSLogType) {
        guard enabled else { return }
        let prefix = category.isEmpty ? "" : "[\(category)] "
        let level = type == .default || type == .info ? "" : "\(type.label): "
        print(prefix + level + text)
    }
}

// MARK: Logger

/// An object for writing interpolated string messages to the unified logging system.
public struct Logger: @unchecked Sendable {
    let osLog: OSLog

    /// A logger with no subsystem or category.
    public init() { osLog = .default }
    public init(subsystem: String, category: String) { osLog = OSLog(subsystem: subsystem, category: category) }
    public init(_ logObj: OSLog) { osLog = logObj }

    public func log(_ message: OSLogMessage) { osLog.write(message.text, type: .default) }
    public func log(level: OSLogType, _ message: OSLogMessage) { osLog.write(message.text, type: level) }

    public func trace(_ message: OSLogMessage) { osLog.write(message.text, type: .debug) }
    public func debug(_ message: OSLogMessage) { osLog.write(message.text, type: .debug) }
    public func info(_ message: OSLogMessage) { osLog.write(message.text, type: .info) }
    public func notice(_ message: OSLogMessage) { osLog.write(message.text, type: .default) }
    public func warning(_ message: OSLogMessage) { osLog.write(message.text, type: .error) }
    public func error(_ message: OSLogMessage) { osLog.write(message.text, type: .error) }
    public func critical(_ message: OSLogMessage) { osLog.write(message.text, type: .fault) }
    public func fault(_ message: OSLogMessage) { osLog.write(message.text, type: .fault) }
}

/// The older function, with a format string whose `%` specifiers the arguments fill in order.
public func os_log(_ message: StaticString, dso: UnsafeRawPointer? = nil, log: OSLog = .default, type: OSLogType = .default, _ args: CVarArg...) {
    log.write(_osLogFormat("\(message)", args), type: type)
}

/// The older function with the type first, as packages write it (`os_log(.fault, dso:, log:,
/// "%@", message)`); disfavoured, so a bare literal still reads as the interpolated message.
@_disfavoredOverload
public func os_log(_ type: OSLogType, dso: UnsafeRawPointer? = nil, log: OSLog = .default, _ message: StaticString, _ args: CVarArg...) {
    log.write(_osLogFormat("\(message)", args), type: type)
}

/// The older function, with an interpolated message.
public func os_log(_ type: OSLogType, dso: UnsafeRawPointer? = nil, log: OSLog = .default, _ message: OSLogMessage) {
    log.write(message.text, type: type)
}

/// The format string with each `%…` specifier (`%@`, `%d`, `%{public}s`, `%.2f`) replaced by
/// the next argument's description; `%%` is a percent sign.
func _osLogFormat(_ format: String, _ args: [CVarArg]) -> String {
    var out = ""
    var remaining = args[...]
    var index = format.startIndex
    while index < format.endIndex {
        let character = format[index]
        index = format.index(after: index)
        guard character == "%", index < format.endIndex else { out.append(character); continue }
        if format[index] == "%" { out.append("%"); index = format.index(after: index); continue }
        // Skip the privacy braces, flags, width, precision and length, up to the conversion letter.
        while index < format.endIndex {
            let c = format[index]
            index = format.index(after: index)
            if c == "{" { while index < format.endIndex, format[index] != "}" { index = format.index(after: index) }; continue }
            if c.isLetter && !"hlqLjzt".contains(c) || c == "@" { break }
        }
        if let next = remaining.popFirst() { out += String(describing: next) }
    }
    return out
}

// MARK: Messages

/// A log message: a string interpolation whose values carry privacy and format options.
public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    let text: String
    public init(stringLiteral value: String) { text = value }
    public init(stringInterpolation: OSLogInterpolation) { text = stringInterpolation.text }
}

/// The interpolation of a log message.
public struct OSLogInterpolation: StringInterpolationProtocol {
    var text = ""
    public init(literalCapacity: Int, interpolationCount: Int) { text.reserveCapacity(literalCapacity) }
    public mutating func appendLiteral(_ literal: String) { text += literal }

    public mutating func appendInterpolation(_ argumentString: @autoclosure @escaping () -> String, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(argumentString())
    }

    public mutating func appendInterpolation<T>(_ value: @autoclosure @escaping () -> T, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(String(describing: value()))
    }

    public mutating func appendInterpolation(_ boolean: @autoclosure @escaping () -> Bool, format: OSLogBoolFormat = .truth, privacy: OSLogPrivacy = .auto) {
        let value = boolean()
        text += format == .answer ? (value ? "YES" : "NO") : (value ? "true" : "false")
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Int64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt8, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt16, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt32, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> UInt64, format: OSLogIntegerFormatting = .decimal, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }

    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Double, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(number()))
    }
    public mutating func appendInterpolation(_ number: @autoclosure @escaping () -> Float, format: OSLogFloatFormatting = .fixed, align: OSLogStringAlignment = .none, privacy: OSLogPrivacy = .auto) {
        text += align.apply(format.apply(Double(number())))
    }
}

// MARK: Options

/// Whether a logged value is shown or redacted (all are shown here; see the file's comment).
public struct OSLogPrivacy: Equatable, Sendable {
    /// How a redacted value is masked.
    public struct Mask: Equatable, Sendable {
        let kind: Int
        public static let hash = Mask(kind: 1)
        public static let none = Mask(kind: 0)
    }

    let kind: Int
    let mask: Mask

    public static let `public` = OSLogPrivacy(kind: 0, mask: .none)
    public static let `private` = OSLogPrivacy(kind: 1, mask: .none)
    public static let sensitive = OSLogPrivacy(kind: 2, mask: .none)
    public static let auto = OSLogPrivacy(kind: 3, mask: .none)
    public static func `private`(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 1, mask: mask) }
    public static func sensitive(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 2, mask: mask) }
    public static func auto(mask: Mask) -> OSLogPrivacy { OSLogPrivacy(kind: 3, mask: mask) }
}

/// How a Boolean is written.
public enum OSLogBoolFormat: Sendable {
    /// `true` or `false`.
    case truth
    /// `YES` or `NO`.
    case answer
}

/// Padding a value to a column width.
public struct OSLogStringAlignment: Sendable {
    let columns: Int
    let right: Bool

    public static let none = OSLogStringAlignment(columns: 0, right: false)
    public static func right(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment(columns: columns(), right: true) }
    public static func left(columns: @autoclosure @escaping () -> Int) -> OSLogStringAlignment { OSLogStringAlignment(columns: columns(), right: false) }

    func apply(_ text: String) -> String {
        let padding = String(repeating: " ", count: max(0, columns - text.count))
        return right ? padding + text : text + padding
    }
}

/// How an integer is written.
public struct OSLogIntegerFormatting: Sendable {
    enum Radix: Sendable { case decimal, hex, octal }
    let radix: Radix
    let explicitPositiveSign: Bool
    let includePrefix: Bool
    let uppercase: Bool
    let minDigits: Int

    public static let decimal = OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)
    public static let hex = OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)
    public static let octal = OSLogIntegerFormatting(radix: .octal, explicitPositiveSign: false, includePrefix: false, uppercase: false, minDigits: 0)

    public static func decimal(explicitPositiveSign: Bool = false, minDigits: @autoclosure @escaping () -> Int = 0) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .decimal, explicitPositiveSign: explicitPositiveSign, includePrefix: false, uppercase: false, minDigits: minDigits())
    }
    public static func hex(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int = 0) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .hex, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits())
    }
    public static func octal(explicitPositiveSign: Bool = false, includePrefix: Bool = false, uppercase: Bool = false, minDigits: @autoclosure @escaping () -> Int = 0) -> OSLogIntegerFormatting {
        OSLogIntegerFormatting(radix: .octal, explicitPositiveSign: explicitPositiveSign, includePrefix: includePrefix, uppercase: uppercase, minDigits: minDigits())
    }

    func apply<T: BinaryInteger>(_ value: T) -> String {
        let base: Int = radix == .hex ? 16 : radix == .octal ? 8 : 10
        var digits = String(value.magnitude, radix: base, uppercase: uppercase)
        if digits.count < minDigits { digits = String(repeating: "0", count: minDigits - digits.count) + digits }
        if includePrefix { digits = (radix == .hex ? "0x" : radix == .octal ? "0" : "") + digits }
        let sign = value < 0 ? "-" : explicitPositiveSign ? "+" : ""
        return sign + digits
    }
}

/// How a floating-point number is written.
public struct OSLogFloatFormatting: Sendable {
    enum Style: Sendable { case fixed, hex, exponential, hybrid }
    let style: Style
    let precision: Int?
    let explicitPositiveSign: Bool

    public static let fixed = OSLogFloatFormatting(style: .fixed, precision: nil, explicitPositiveSign: false)
    public static let hex = OSLogFloatFormatting(style: .hex, precision: nil, explicitPositiveSign: false)
    public static let exponential = OSLogFloatFormatting(style: .exponential, precision: nil, explicitPositiveSign: false)
    public static let hybrid = OSLogFloatFormatting(style: .hybrid, precision: nil, explicitPositiveSign: false)

    public static func fixed(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(style: .fixed, precision: precision(), explicitPositiveSign: explicitPositiveSign)
    }
    public static func fixed(explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(style: .fixed, precision: nil, explicitPositiveSign: explicitPositiveSign)
    }
    public static func exponential(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(style: .exponential, precision: precision(), explicitPositiveSign: explicitPositiveSign)
    }
    public static func hybrid(precision: @autoclosure @escaping () -> Int, explicitPositiveSign: Bool = false, uppercase: Bool = false) -> OSLogFloatFormatting {
        OSLogFloatFormatting(style: .hybrid, precision: precision(), explicitPositiveSign: explicitPositiveSign)
    }

    /// Fixed notation rounds to the precision (six places when none is given, as `%f`); the
    /// other styles write the shortest exact form.
    func apply(_ value: Double) -> String {
        let sign = value >= 0 && explicitPositiveSign ? "+" : ""
        guard style == .fixed, value.isFinite else { return sign + "\(value)" }
        let places = max(0, min(precision ?? 6, 15))
        var factor = 1.0
        for _ in 0..<places { factor *= 10 }
        let scaled = (value.magnitude * factor).rounded()
        guard scaled < 9e18 else { return sign + "\(value)" }
        let whole = UInt64(scaled)
        let unit = UInt64(factor)
        var text = String(whole / unit)
        if places > 0 {
            let fraction = String(whole % unit)
            text += "." + String(repeating: "0", count: places - fraction.count) + fraction
        }
        return (value < 0 && scaled > 0 ? "-" : sign) + text
    }
}

// MARK: Locks

/// A lock around a value, used through closures.
public struct OSAllocatedUnfairLock<State>: @unchecked Sendable {
    final class Box { var state: State; init(_ state: State) { self.state = state } }
    let box: Box

    public init(initialState: State) { box = Box(initialState) }
    public init(uncheckedState initialState: State) { box = Box(initialState) }

    public func withLock<R>(_ body: @Sendable (inout State) throws -> R) rethrows -> R where R: Sendable {
        try body(&box.state)
    }

    public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
        try body(&box.state)
    }

    public func withLockIfAvailable<R>(_ body: @Sendable (inout State) throws -> R) rethrows -> R? where R: Sendable {
        try body(&box.state)
    }

    public func lock() {}
    public func unlock() {}
    public func lockIfAvailable() -> Bool { true }

    public enum Ownership: Hashable, Sendable { case owner, notOwner }
    public func precondition(_ condition: Ownership) {}
}

extension OSAllocatedUnfairLock where State == Void {
    public init() { box = Box(()) }

    public func withLock<R>(_ body: @Sendable () throws -> R) rethrows -> R where R: Sendable { try body() }
    public func withLockUnchecked<R>(_ body: () throws -> R) rethrows -> R { try body() }
}

// MARK: Signposts

// Signposts mark intervals and events for Instruments, which a page has no counterpart of, so
// they are recorded nowhere (`OSLog.signpostsEnabled` is false). The calls and IDs are Apple's,
// so the code that times its work with them (Nuke's pipeline, the Composable Architecture's
// action log) runs unchanged.

/// The kind of a signpost: the start or end of an interval, or a single event.
public struct OSSignpostType: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let event = OSSignpostType(rawValue: 0x00)
    public static let begin = OSSignpostType(rawValue: 0x01)
    public static let end = OSSignpostType(rawValue: 0x02)
}

/// An identifier that ties a signpost interval's begin to its end.
public struct OSSignpostID: Hashable, Comparable, Sendable {
    public let rawValue: UInt64

    public init(_ value: UInt64) { rawValue = value }

    /// A new identifier, unique within this process.
    public init(log: OSLog) { rawValue = OSSignpostID.next() }

    /// The identifier for `object`, the same each time for the same object.
    public init(log: OSLog, object: AnyObject) { rawValue = UInt64(UInt(bitPattern: ObjectIdentifier(object).hashValue)) }

    /// The identifier for intervals that never overlap.
    public static let exclusive = OSSignpostID(0xEEEE_B0B5_B2B2_EEEE)
    public static let invalid = OSSignpostID(~0)
    public static let null = OSSignpostID(0)

    public static func < (lhs: OSSignpostID, rhs: OSSignpostID) -> Bool { lhs.rawValue < rhs.rawValue }

    private nonisolated(unsafe) static var counter: UInt64 = 1
    private static func next() -> UInt64 {
        counter += 1
        return counter
    }
}

/// Marks a point of interest or an interval's begin or end.
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer? = nil, log: OSLog, name: StaticString,
                        signpostID: OSSignpostID = .exclusive) {}

/// Marks a point of interest or an interval's begin or end, with a formatted message.
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer? = nil, log: OSLog, name: StaticString,
                        signpostID: OSSignpostID = .exclusive, _ format: StaticString, _ arguments: CVarArg...) {}

/// Marks a point of interest or an interval's begin or end, with an interpolated message.
public func os_signpost(_ type: OSSignpostType, dso: UnsafeRawPointer? = nil, log: OSLog, name: StaticString,
                        signpostID: OSSignpostID = .exclusive, _ message: OSLogMessage) {}

/// The state of an interval a signposter began, which ends it.
public struct OSSignpostIntervalState: Sendable {
    public let signpostID: OSSignpostID
}

/// The signpost API iOS 15 added: intervals and events on a log.
public struct OSSignposter: @unchecked Sendable {
    let log: OSLog

    public init() { log = .default }
    public init(subsystem: String, category: String) { log = OSLog(subsystem: subsystem, category: category) }
    public init(subsystem: String, category: OSLog.Category) { log = OSLog(subsystem: subsystem, category: category) }
    public init(logHandle: OSLog) { log = logHandle }
    public init(logger: Logger) { log = logger.osLog }

    /// A signposter that records nothing.
    public static let disabled = OSSignposter(logHandle: .disabled)

    /// Whether signposts are recorded (never, on a page).
    public var isEnabled: Bool { false }

    public func makeSignpostID() -> OSSignpostID { OSSignpostID(log: log) }
    public func makeSignpostID(from object: AnyObject) -> OSSignpostID { OSSignpostID(log: log, object: object) }

    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive) {}
    public func emitEvent(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) {}

    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        OSSignpostIntervalState(signpostID: id)
    }
    public func beginInterval(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage) -> OSSignpostIntervalState {
        OSSignpostIntervalState(signpostID: id)
    }
    public func beginAnimationInterval(_ name: StaticString, id: OSSignpostID = .exclusive) -> OSSignpostIntervalState {
        OSSignpostIntervalState(signpostID: id)
    }

    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {}
    public func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState, _ message: OSLogMessage) {}

    /// Runs `task` as one interval.
    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive,
                                        around task: () throws -> T) rethrows -> T {
        try task()
    }
    public func withIntervalSignpost<T>(_ name: StaticString, id: OSSignpostID = .exclusive, _ message: OSLogMessage,
                                        around task: () throws -> T) rethrows -> T {
        try task()
    }
}
#endif
