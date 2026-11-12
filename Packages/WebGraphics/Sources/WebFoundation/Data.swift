// Foundation's `Data` on wasm (decision 0017, pf-web-foundation-gaps): a byte array with the
// surface the frameworks and ordinary apps use. A slice keeps its indices, as Foundation's
// does (`data[2..<4].startIndex` is 2; `Data(slice)` starts a fresh value at zero);
// `String.Encoding` lives in StringEncoding.swift.
#if os(WASI)
public struct Data: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible,
                    RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public typealias Index = Int
    public typealias Element = UInt8
    public typealias SubSequence = Data

    /// The bytes, as an array (a slice's own bytes, from its `startIndex`).
    public var bytes: [UInt8]
    /// The index of the first byte: zero, or where a slice began in its source.
    public private(set) var startIndex: Int = 0

    public init() { bytes = [] }
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    private init(bytes: [UInt8], startIndex: Int) {
        self.bytes = bytes
        self.startIndex = startIndex
    }
    public init<S: Sequence>(_ elements: S) where S.Element == UInt8 { bytes = Array(elements) }
    public init(repeating value: UInt8, count: Int) { bytes = Array(repeating: value, count: count) }
    public init(capacity: Int) { bytes = []; bytes.reserveCapacity(capacity) }
    /// `count` zero bytes.
    public init(count: Int) { bytes = Array(repeating: 0, count: count) }
    public init(bytes pointer: UnsafeRawPointer, count: Int) {
        self.bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
    public init(buffer: UnsafeBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(buffer: UnsafeMutableBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(_ buffer: UnsafeRawBufferPointer) { bytes = Array(buffer) }

    public var endIndex: Int { startIndex + bytes.count }
    /// The number of bytes. Setting it truncates or pads with zeros, as Foundation's does.
    public var count: Int {
        get { bytes.count }
        set {
            precondition(newValue >= 0, "count must not be negative")
            if newValue < bytes.count { bytes.removeLast(bytes.count - newValue) } else { bytes += Array(repeating: 0, count: newValue - bytes.count) }
        }
    }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> UInt8 {
        get { bytes[position - startIndex] }
        set { bytes[position - startIndex] = newValue }
    }
    /// A slice sharing this value's indices.
    public subscript(bounds: Range<Int>) -> Data {
        get { Data(bytes: Array(bytes[(bounds.lowerBound - startIndex)..<(bounds.upperBound - startIndex)]), startIndex: bounds.lowerBound) }
        set { bytes.replaceSubrange((bounds.lowerBound - startIndex)..<(bounds.upperBound - startIndex), with: newValue.bytes) }
    }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == UInt8 {
        bytes.replaceSubrange((subrange.lowerBound - startIndex)..<(subrange.upperBound - startIndex), with: newElements)
    }
    public mutating func append(_ other: Data) { bytes.append(contentsOf: other.bytes) }
    public mutating func append(_ byte: UInt8) { bytes.append(byte) }
    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == UInt8 { bytes.append(contentsOf: elements) }
    public mutating func append(_ pointer: UnsafePointer<UInt8>, count: Int) {
        bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
    }
    public mutating func reserveCapacity(_ minimumCapacity: Int) { bytes.reserveCapacity(minimumCapacity) }
    public mutating func resetBytes(in range: Range<Int>) {
        for i in range { bytes[i - startIndex] = 0 }
    }
    /// The bytes in `range` (this value's indices) as a fresh value indexed from zero.
    public func subdata(in range: Range<Int>) -> Data { Data(bytes[(range.lowerBound - startIndex)..<(range.upperBound - startIndex)]) }
    public static func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
    public mutating func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeMutableBytes(body)
    }
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
        for i in 0..<Swift.min(count, bytes.count) { pointer[i] = bytes[i] }
    }
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Int>) {
        for (offset, i) in range.enumerated() { pointer[offset] = bytes[i - startIndex] }
    }
    /// Foundation's `firstRange(of:)`: where `other` first occurs, in this value's indices.
    public func range(of other: Data, options: SearchOptions = [], in range: Range<Int>? = nil) -> Range<Int>? {
        let bounds = range ?? startIndex..<endIndex
        let needle = other.bytes
        guard !needle.isEmpty, bounds.count >= needle.count else { return nil }
        let indices = Array(bounds.lowerBound...(bounds.upperBound - needle.count))
        for start in options.contains(.backwards) ? indices.reversed() : indices {
            if bytes[(start - startIndex)..<(start - startIndex + needle.count)].elementsEqual(needle) { return start..<(start + needle.count) }
        }
        return nil
    }
    public struct SearchOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let backwards = SearchOptions(rawValue: 1)
        public static let anchored = SearchOptions(rawValue: 2)
    }

    // Foundation compares and hashes the bytes alone, whatever a slice's indices.
    public static func == (lhs: Data, rhs: Data) -> Bool { lhs.bytes == rhs.bytes }
    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
    @discardableResult
    public func copyBytes(to buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        let count = Swift.min(buffer.count, bytes.count)
        guard let base = buffer.baseAddress else { return 0 }
        copyBytes(to: base, count: count)
        return count
    }

    /// Options Foundation's base64 methods take; `lineLength64Characters` and
    /// `lineLength76Characters` wrap the output, the line-ending options are accepted.
    public struct Base64EncodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let lineLength64Characters = Base64EncodingOptions(rawValue: 1)
        public static let lineLength76Characters = Base64EncodingOptions(rawValue: 2)
        public static let endLineWithCarriageReturn = Base64EncodingOptions(rawValue: 16)
        public static let endLineWithLineFeed = Base64EncodingOptions(rawValue: 32)
    }
    public struct Base64DecodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let ignoreUnknownCharacters = Base64DecodingOptions(rawValue: 1)
    }

    public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
        let line = options.contains(.lineLength64Characters) ? 64 : options.contains(.lineLength76Characters) ? 76 : nil
        return _Base64.encode(bytes, lineLength: line)
    }
    public func base64EncodedData(options: Base64EncodingOptions = []) -> Data { Data(base64EncodedString(options: options).utf8) }
    public init?(base64Encoded string: String, options: Base64DecodingOptions = []) {
        guard let bytes = _Base64.decode(string.utf8, ignoreUnknown: options.contains(.ignoreUnknownCharacters)) else { return nil }
        self.bytes = bytes
    }
    public init?(base64Encoded data: Data, options: Base64DecodingOptions = []) {
        guard let bytes = _Base64.decode(data.bytes, ignoreUnknown: options.contains(.ignoreUnknownCharacters)) else { return nil }
        self.bytes = bytes
    }

    public var description: String { "\(bytes.count) bytes" }
    public var debugDescription: String { description }

    // Foundation encodes `Data` as an unkeyed container of bytes.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var bytes: [UInt8] = []
        if let count = container.count { bytes.reserveCapacity(count) }
        while !container.isAtEnd { bytes.append(try container.decode(UInt8.self)) }
        self.bytes = bytes
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: bytes)
    }
}

// MARK: - Files in memory (sw-dragdrop-os, decision 0021)

/// wasm has no file system: a file that arrives from outside (a dropped file, an opened
/// document) lives in memory under a `memory:` URL, and the app's own files (`FileManager`'s
/// directories) under `file:` URLs, which `Data(contentsOf:)` reads and `write(to:)` writes,
/// so `FileRepresentation` imports and exports and an app's documents work as they do with
/// Foundation's file URLs. The `file:` ones outside `/tmp/` and the caches go to the host after
/// every write (`_hostStore`: the browser host keeps them in localStorage, base64 under
/// `swiftuiweb.files`), so a saved document is there after a reload.
public enum _MemoryFiles {
    nonisolated(unsafe) private static var files: [String: Data] = [:]
    nonisolated(unsafe) private static var directories: Set<String> = ["file:///", "file:///Documents/", "file:///Library/", "file:///tmp/"]
    nonisolated(unsafe) private static var counter = 0
    nonisolated(unsafe) private static var dates: [String: Date] = [:]
    nonisolated(unsafe) private static var creationDates: [String: Date] = [:]
    /// Where the durable files live between loads: the host installs one before the app runs.
    /// `list` names every kept path, `load` gives a file's bytes as base64, `save` with nil removes.
    nonisolated(unsafe) public static var _hostStore: (list: () -> [String], load: (String) -> String?, save: (String, String?) -> Void)?

    /// Stores `data` under a fresh `memory:` URL named `name`.
    public static func store(_ data: Data, name: String) -> URL {
        counter += 1
        let safe = String(name.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" ? $0 : "_" })
        let url = URL(string: "memory:/\(counter)/\(safe.isEmpty ? "file" : safe)")!
        files[url.absoluteString] = data
        return url
    }
    /// Reads one of the app's bundled files (`Bundle.url(forResource:)`: a URL relative to the
    /// page, under `Bundle._resourceBase`) from the host, at once, as iOS reads a bundle's files
    /// (the browser host fetches it synchronously); nil when the host has no such file.
    nonisolated(unsafe) public static var _hostResource: ((String) -> Data?)?

    public static func read(_ url: URL) -> Data? {
        let key = url.absoluteString
        if let data = files[key] { return data }
        if url.scheme == nil, key.hasPrefix(Bundle._resourceBase), let data = _hostResource?(key) {
            files[key] = data
            return data
        }
        guard isDurable(url), let text = _hostStore?.load(url.path), let data = Data(base64Encoded: text) else { return nil }
        files[key] = data
        return data
    }
    public static func write(_ data: Data, to url: URL) {
        files[url.absoluteString] = data
        dates[url.absoluteString] = Date()
        if creationDates[url.absoluteString] == nil { creationDates[url.absoluteString] = dates[url.absoluteString] }
        if url.isFileURL { createDirectory(url.deletingLastPathComponent()) }
        if isDurable(url) { _hostStore?.save(url.path, data.base64EncodedString()) }
    }
    public static func remove(_ url: URL) {
        files[url.absoluteString] = nil
        dates[url.absoluteString] = nil
        creationDates[url.absoluteString] = nil
        directories.remove(directoryKey(url))
        if isDurable(url) { _hostStore?.save(url.path, nil) }
    }
    public static func exists(_ url: URL) -> Bool {
        files[url.absoluteString] != nil || (isDurable(url) && _hostStore?.list().contains(url.path) == true)
    }
    public static func isDirectory(_ url: URL) -> Bool { directories.contains(directoryKey(url)) }
    /// When the file was last written here (a file kept by the host from an earlier load has none).
    public static func modificationDate(_ url: URL) -> Date? { dates[url.absoluteString] }
    /// When the file was first written here (or the date set with `setAttributes`).
    public static func creationDate(_ url: URL) -> Date? { creationDates[url.absoluteString] ?? dates[url.absoluteString] }
    /// Sets a file's dates (`FileManager.setAttributes`); nil leaves one as it is.
    public static func setDates(_ url: URL, creation: Date?, modification: Date?) {
        if let creation { creationDates[url.absoluteString] = creation }
        if let modification { dates[url.absoluteString] = modification }
    }
    public static func createDirectory(_ url: URL) {
        var path = url.path
        while path != "/" && !path.isEmpty {
            directories.insert("file://" + (path.hasSuffix("/") ? path : path + "/"))
            path = URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
    }
    /// The files and directories directly under `url`.
    public static func contents(of url: URL) -> [URL] {
        let prefix = directoryKey(url)
        var paths = Set(files.keys.filter { $0.hasPrefix(prefix) })
        if url.isFileURL, let kept = _hostStore?.list() {
            for path in kept where ("file://" + path).hasPrefix(prefix) { paths.insert("file://" + path) }
        }
        var children: Set<String> = []
        for path in paths {
            let rest = path.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") { children.insert(prefix + rest[..<slash] + "/") } else { children.insert(path) }
        }
        for directory in directories where directory.hasPrefix(prefix) && directory != prefix {
            let rest = directory.dropFirst(prefix.count).dropLast()
            if !rest.contains("/") { children.insert(directory) }
        }
        return children.sorted().compactMap { URL(string: $0) }
    }

    private static func directoryKey(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasSuffix("/") ? text : text + "/"
    }
    private static func isDurable(_ url: URL) -> Bool {
        url.isFileURL && !url.path.hasPrefix("/tmp/") && !url.path.hasPrefix("/Library/Caches/")
    }
}

extension Data {
    public struct _FileError: Error, CustomStringConvertible {
        public let url: URL
        public var description: String { "The file “\(url.lastPathComponent)” doesn’t exist." }
    }

    /// The bytes of an in-memory file (`memory:` and `file:` URLs); any other URL throws.
    public init(contentsOf url: URL) throws {
        guard let data = _MemoryFiles.read(url) else { throw _FileError(url: url) }
        self = data
    }

    /// Writes the bytes to an in-memory file (`memory:` and `file:` URLs); any other URL throws.
    public func write(to url: URL, options: WritingOptions = []) throws {
        guard url.scheme == "memory" || url.isFileURL else { throw _FileError(url: url) }
        _MemoryFiles.write(self, to: url)
    }

    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let atomic = WritingOptions(rawValue: 1)
        public static let withoutOverwriting = WritingOptions(rawValue: 2)
        /// File protection classes: accepted, as the host's store has no device lock to follow.
        public static let noFileProtection = WritingOptions(rawValue: 0x10000000)
        public static let completeFileProtection = WritingOptions(rawValue: 0x20000000)
        public static let completeFileProtectionUnlessOpen = WritingOptions(rawValue: 0x30000000)
        public static let completeFileProtectionUntilFirstUserAuthentication = WritingOptions(rawValue: 0x40000000)
        public static let completeFileProtectionWhenUserInactive = WritingOptions(rawValue: 0x50000000)
        public static let fileProtectionMask = WritingOptions(rawValue: 0xf0000000)
    }
}
#endif
