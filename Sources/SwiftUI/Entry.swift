/// Creates an environment, focused or transaction value from a property declared in an extension
/// of `EnvironmentValues`, `FocusedValues` or `Transaction`: the macro adds the key type the
/// container needs (named after the property) and accessors over the container's subscript.
/// Environment and transaction entries need a default value unless optional (nil); focused ones are optional.
@attached(accessor)
@attached(peer, names: prefixed(__Key_))
public macro Entry() = #externalMacro(module: "SwiftUIWebMacros", type: "EntryMacro")
