// Foundation's person name and its formatter (decision 0017), which FoundationEssentials does
// not carry: Sign in with Apple hands an app the person's name as one (new-website#707), and
// apps format it with `PersonNameComponentsFormatter` or `formatted()`. Names are put together
// as Western ones are (given, middle, family); the phonetic form is kept, not used.
#if os(WASI)
/// The parts of a person's name.
public struct PersonNameComponents: Hashable, Sendable, Codable, CustomStringConvertible {
    public var namePrefix: String?
    public var givenName: String?
    public var middleName: String?
    public var familyName: String?
    public var nameSuffix: String?
    public var nickname: String?
    public var phoneticRepresentation: PersonNameComponents? {
        get { phonetic?.value }
        set { phonetic = newValue.map(Box.init) }
    }

    /// Holds the phonetic form, a value of this same type.
    private final class Box: Hashable, @unchecked Sendable, Codable {
        let value: PersonNameComponents
        init(_ value: PersonNameComponents) { self.value = value }
        static func == (a: Box, b: Box) -> Bool { a.value == b.value }
        func hash(into hasher: inout Hasher) { hasher.combine(value) }
        init(from decoder: any Decoder) throws { value = try PersonNameComponents(from: decoder) }
        func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
    }
    private var phonetic: Box?

    public init() {}

    public init(namePrefix: String? = nil, givenName: String? = nil, middleName: String? = nil, familyName: String? = nil,
                nameSuffix: String? = nil, nickname: String? = nil, phoneticRepresentation: PersonNameComponents? = nil) {
        self.namePrefix = namePrefix
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nameSuffix = nameSuffix
        self.nickname = nickname
        self.phoneticRepresentation = phoneticRepresentation
    }

    public var description: String { PersonNameComponentsFormatter.localizedString(from: self, style: .default) }

    /// The name in the default style.
    public func formatted() -> String { PersonNameComponentsFormatter.localizedString(from: self, style: .default) }

    /// The name in `style`'s length.
    public func formatted(_ style: FormatStyle) -> String { style.format(self) }

    /// How long a formatted name is.
    public struct FormatStyle: Hashable, Sendable {
        public enum Style: Hashable, Sendable { case short, medium, long, abbreviated }
        public var style: Style
        public init(style: Style = .medium) { self.style = style }
        public func format(_ value: PersonNameComponents) -> String {
            let mapped: PersonNameComponentsFormatter.Style = switch style {
            case .short: .short
            case .medium: .medium
            case .long: .long
            case .abbreviated: .abbreviated
            }
            return PersonNameComponentsFormatter.localizedString(from: value, style: mapped)
        }
    }
}

extension PersonNameComponents.FormatStyle {
    public static func name(style: Style) -> Self { Self(style: style) }
}

/// Formats a person's name.
open class PersonNameComponentsFormatter: @unchecked Sendable {
    public enum Style: Int, Sendable {
        case `default` = 0, short, medium, long, abbreviated
    }
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let phonetic = Options(rawValue: 2)
    }

    open var style: Style = .default
    open var isPhonetic = false

    public init() {}

    open func string(from components: PersonNameComponents) -> String {
        Self.localizedString(from: isPhonetic ? (components.phoneticRepresentation ?? components) : components, style: style)
    }

    open func personNameComponents(from string: String) -> PersonNameComponents? {
        let words = string.split(separator: " ").map(String.init)
        guard let first = words.first else { return nil }
        var components = PersonNameComponents(givenName: first)
        if words.count > 1 { components.familyName = words.dropFirst().joined(separator: " ") }
        return components
    }

    open class func localizedString(from components: PersonNameComponents, style: Style, options: Options = []) -> String {
        let name = options.contains(.phonetic) ? (components.phoneticRepresentation ?? components) : components
        func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
        switch style {
        case .short: return name.nickname ?? name.givenName ?? name.familyName ?? ""
        case .abbreviated:
            return [name.givenName, name.familyName].compactMap { $0?.first.map(String.init) }.joined()
        case .long: return join([name.namePrefix, name.givenName, name.middleName, name.familyName, name.nameSuffix])
        case .default, .medium: return join([name.givenName, name.familyName])
        }
    }
}
#endif
