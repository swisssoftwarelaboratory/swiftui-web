// The `@Entry` macro: on a stored property declared in an extension of `EnvironmentValues`,
// `FocusedValues`, `Transaction` or `ContainerValues`, it adds the key type the container needs and turns the
// property into accessors over the container's subscript (Docs/elements/Environment.md).
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct EntryMacro: AccessorMacro, PeerMacro {
    /// The key protocol for the extended container, from the lexical context.
    private static func container(in context: some MacroExpansionContext) -> (name: String, key: String, optional: Bool)? {
        for lexical in context.lexicalContext {
            guard let extensionDecl = lexical.as(ExtensionDeclSyntax.self) else { continue }
            let name = extensionDecl.extendedType.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
            switch name {
            case "EnvironmentValues": return (name, "EnvironmentKey", false)
            case "FocusedValues": return (name, "FocusedValueKey", true)
            case "Transaction": return (name, "TransactionKey", false)
            case "ContainerValues": return (name, "ContainerValueKey", false)
            default: return nil
            }
        }
        return nil
    }

    private static func property(of declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> (name: String, type: String, initializer: String?)? {
        guard let variable = declaration.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            context.diagnose(Diagnostic(node: Syntax(declaration), message: EntryMessage("'@Entry' can only be applied to a 'var' with a name")))
            return nil
        }
        guard let type = binding.typeAnnotation?.type.trimmedDescription else {
            context.diagnose(Diagnostic(node: Syntax(declaration), message: EntryMessage("'@Entry' needs an explicit type")))
            return nil
        }
        return (name, type, binding.initializer?.value.trimmedDescription)
    }

    public static func expansion(of node: AttributeSyntax, providingAccessorsOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [AccessorDeclSyntax] {
        guard let property = try property(of: declaration, in: context) else { return [] }
        guard container(in: context) != nil else {
            context.diagnose(Diagnostic(node: Syntax(node), message: EntryMessage("'@Entry' can only be applied inside an extension of EnvironmentValues, FocusedValues, Transaction or ContainerValues")))
            return []
        }
        let key = "__Key_\(property.name)"
        return [
            "get { self[\(raw: key).self] }",
            "set { self[\(raw: key).self] = newValue }",
        ]
    }

    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let property = try property(of: declaration, in: context), let container = container(in: context) else { return [] }
        let key = "__Key_\(property.name)"
        if container.optional {
            // Focused values are optional and have no default.
            return ["private struct \(raw: key): \(raw: container.key) { typealias Value = \(raw: unwrapped(property.type)) }"]
        }
        guard let initializer = property.initializer else {
            // An optional entry without one defaults to nil, as Apple's macro does
            // (`@Entry var navigation: Navigation?`).
            if property.type.hasSuffix("?") || property.type.hasPrefix("Optional<") {
                return ["private struct \(raw: key): \(raw: container.key) { static var defaultValue: \(raw: property.type) { nil } }"]
            }
            context.diagnose(Diagnostic(node: Syntax(declaration), message: EntryMessage("'@Entry' needs a default value")))
            return []
        }
        // Computed, as Apple's expansion is: the initializer runs on each read, and a
        // non-Sendable value (a main-actor closure) needs no concurrency-safe static.
        return ["private struct \(raw: key): \(raw: container.key) { static var defaultValue: \(raw: property.type) { \(raw: initializer) } }"]
    }

    /// `T?` or `Optional<T>` → `T` (focused values are declared optional).
    private static func unwrapped(_ type: String) -> String {
        if type.hasSuffix("?") { return String(type.dropLast()) }
        if type.hasPrefix("Optional<"), type.hasSuffix(">") { return String(type.dropFirst("Optional<".count).dropLast()) }
        return type
    }
}

struct EntryMessage: DiagnosticMessage {
    let message: String
    init(_ message: String) { self.message = message }
    var diagnosticID: MessageID { MessageID(domain: "SwiftUIWebMacros", id: "entry") }
    var severity: DiagnosticSeverity { .error }
}
