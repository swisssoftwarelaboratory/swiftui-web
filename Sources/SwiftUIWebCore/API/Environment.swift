import Observation

/// A key for accessing values in the environment.
public protocol EnvironmentKey {
    /// The associated type representing the type of the environment key's value.
    associatedtype Value

    /// The default value for the environment key.
    static var defaultValue: Self.Value { get }
}

/// A collection of environment values propagated through a view hierarchy.
public struct EnvironmentValues: CustomStringConvertible {
    /// Stored values by key type. Absent keys resolve to `K.defaultValue`.
    package var values: [ObjectIdentifier: Any] = [:]

    /// Identity of this set of values: two `EnvironmentValues` with the same generation are
    /// copies of one another with no mutation in between, so nodes can skip re-evaluation.
    package private(set) var generation: UInt64 = 0

    /// Creates an environment values instance.
    public init() {}

    package mutating func didMutate() {
        generation = _EnvironmentGeneration.next()
    }

    /// Accesses the environment value associated with a custom key.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            if let stored = values[ObjectIdentifier(key)] {
                return stored as! K.Value
            }
            return K.defaultValue
        }
        set {
            // Writing the value already there is no change: the generation stays, so the views
            // under a node that derives its content's environment on every update (a scroll view
            // clearing the lazy axis, a stack giving its context) keep their memoised sizes
            // (new-website#216). Values that cannot be compared count as changed.
            if !_valuesDiffer(self[key], newValue) { return }
            values[ObjectIdentifier(key)] = newValue
            didMutate()
        }
    }

    public var description: String {
        "EnvironmentValues(\(values.count) keys)"
    }

    /// Reads an observable object of the given type from the environment, or `nil` if none was
    /// stored with `View.environment(_:)`.
    public subscript<T: AnyObject & Observable>(objectType: T.Type) -> T? {
        get { values[ObjectIdentifier(objectType)] as? T }
        set {
            if (values[ObjectIdentifier(objectType)] as? T) === newValue, newValue != nil || values[ObjectIdentifier(objectType)] == nil { return }
            values[ObjectIdentifier(objectType)] = newValue
            didMutate()
        }
    }
}

package enum _EnvironmentGeneration {
    nonisolated(unsafe) private static var counter: UInt64 = 0

    /// Environment values are only mutated on the main actor (view bodies, modifiers).
    package static func next() -> UInt64 {
        counter += 1
        return counter
    }
}

/// A property wrapper that reads a value from a view's environment.
///
/// The runtime resolves the key path against the environment of the view that declares the
/// property (Phase 1 steps 2–3). Before installation it reads the default `EnvironmentValues`.
@propertyWrapper
@frozen
public struct Environment<Value>: DynamicProperty {
    @usableFromInline
    package enum Content {
        case keyPath(KeyPath<EnvironmentValues, Value>)
        case lookup((EnvironmentValues) -> Value)
        case value(Value)
    }

    @usableFromInline
    package var content: Content

    /// Creates an environment property to read the specified key path.
    @inlinable
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        content = .keyPath(keyPath)
    }

    /// The current value of the environment property.
    @inlinable
    public var wrappedValue: Value {
        switch content {
        case .value(let value):
            return value
        case .keyPath(let keyPath):
            return EnvironmentValues()[keyPath: keyPath]
        case .lookup(let lookup):
            return lookup(EnvironmentValues())
        }
    }

    /// Resolves the property against `values`. Called by the runtime when a view's body is about
    /// to be evaluated.
    package mutating func resolve(in values: EnvironmentValues) {
        switch content {
        case .keyPath(let keyPath):
            content = .value(values[keyPath: keyPath])
        case .lookup(let lookup):
            content = .value(lookup(values))
        case .value:
            break
        }
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        resolve(in: node.environment)
    }
}

/// Sendable when its value is, as SwiftUI's (swift-dependencies keeps one in its `Sendable`
/// `@Dependency`); the key path or lookup it holds is only run on the main actor.
extension Environment: @unchecked Sendable where Value: Sendable {}

extension Environment where Value: AnyObject & Observable {
    /// Creates an environment property to read an observable object from the environment.
    /// Reading it when no object of that type was stored is a programmer error, as in SwiftUI.
    public init(_ objectType: Value.Type) {
        content = .lookup { values in
            guard let object = values[objectType] else {
                fatalError("No Observable object of type \(objectType) found. A View.environment(_:) for \(objectType) may be missing as an ancestor of this view.")
            }
            return object
        }
    }
}

extension Environment {
    /// Creates an environment property to read an observable object from the environment,
    /// returning `nil` if no corresponding object has been set.
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T? {
        content = .lookup { $0[objectType] }
    }
}

/// Stores an observable object in the environment. Produced by `View.environment(_:)`.
public struct _EnvironmentObjectWritingModifier<T: AnyObject & Observable> {
    public var object: T?

    public init(object: T?) {
        self.object = object
    }
}

extension _EnvironmentObjectWritingModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        values[T.self] = object
    }

    @MainActor
    public static func _makeNode<Content: View>(
        _ context: _NodeContext<ModifiedContent<Content, Self>>
    ) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

extension View {
    /// Places an observable object in the view's environment.
    nonisolated public func environment<T: AnyObject & Observable>(_ object: T?) -> some View {
        modifier(_EnvironmentObjectWritingModifier(object: object))
    }
}

/// Modifiers that change the environment for their content. The runtime applies them when it
/// builds the environment of the modified subtree.
@MainActor
package protocol _EnvironmentModifier {
    func modifyEnvironment(_ values: inout EnvironmentValues)
}

/// Writes a single value into the environment. Produced by `View.environment(_:_:)`.
public struct _EnvironmentKeyWritingModifier<Value> {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var value: Value

    @inlinable
    public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, value: Value) {
        self.keyPath = keyPath
        self.value = value
    }

}

/// Equal when it writes an equal value to the same key: a body evaluated again with the same
/// `.font(…)` or `.environment(\.x, value)` hands its content the same environment generation,
/// so the views under it keep their memoised sizes (new-website#216: every keystroke in a
/// search re-measured each row under its `.font` and `.textCase`).
extension _EnvironmentKeyWritingModifier: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyPath == rhs.keyPath && lhs.value == rhs.value
    }
}

extension _EnvironmentKeyWritingModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        values[keyPath: keyPath] = value
    }
}

/// A change to the environment that compares equal when it was made from equal values (`key`,
/// with the name of the modifier that made it): the fork's own modifiers that set several values
/// at once (`scrollIndicators`, `contentMargins`, `disabled`…) use it instead of a closure, so a
/// body evaluated again with the same arguments keeps its content's environment generation and
/// the content keeps its memoised sizes (new-website#216).
public struct _KeyedEnvironmentTransform<Key: Hashable> {
    package var name: String
    package var key: Key
    package var transform: (inout EnvironmentValues) -> Void

    package init(_ name: String, key: Key, transform: @escaping (inout EnvironmentValues) -> Void) {
        self.name = name
        self.key = key
        self.transform = transform
    }
}

extension _KeyedEnvironmentTransform: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name && lhs.key == rhs.key }
}

extension _KeyedEnvironmentTransform: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        transform(&values)
    }

    @MainActor
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        EnvironmentModifierNode(context)
    }
}

/// A key under which equal values compare equal: a `Hashable` value itself, a plain-data value by
/// its type and bytes (a style struct without stored properties), anything else a key equal to
/// nothing (compared as changed, as before).
package func _equalityKey<T>(_ value: T) -> AnyHashable {
    if let hashable = value as? any Hashable { return AnyHashable(hashable) }
    if _isPOD(T.self) {
        return AnyHashable([AnyHashable(ObjectIdentifier(T.self)), AnyHashable(withUnsafeBytes(of: value) { Array($0) })])
    }
    _unequalKeys &+= 1
    return AnyHashable(_UnequalKey(serial: _unequalKeys))
}

/// A key equal to no other made before it.
package struct _UnequalKey: Hashable { let serial: UInt64 }
nonisolated(unsafe) private var _unequalKeys: UInt64 = 0

extension View {
    /// Changes the environment through `transform`, equal to another such change made by the same
    /// modifier from an equal `key` (see `_KeyedEnvironmentTransform`).
    nonisolated package func _transformEnvironment<Key: Hashable>(_ name: String, key: Key, _ transform: @escaping (inout EnvironmentValues) -> Void) -> some View {
        modifier(_KeyedEnvironmentTransform(name, key: key, transform: transform))
    }
}

/// Transforms a single environment value in place. Produced by `View.transformEnvironment(_:transform:)`.
public struct _EnvironmentKeyTransformModifier<Value> {
    public var keyPath: WritableKeyPath<EnvironmentValues, Value>
    public var transform: (inout Value) -> Void

    @inlinable
    public init(keyPath: WritableKeyPath<EnvironmentValues, Value>, transform: @escaping (inout Value) -> Void) {
        self.keyPath = keyPath
        self.transform = transform
    }

}

extension _EnvironmentKeyTransformModifier: ViewModifier, _EnvironmentModifier {
    public typealias Body = Never

    package func modifyEnvironment(_ values: inout EnvironmentValues) {
        transform(&values[keyPath: keyPath])
    }
}

extension View {
    /// Sets the environment value of the specified key path to the given value.
    @inlinable
    nonisolated public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some View {
        modifier(_EnvironmentKeyWritingModifier(keyPath: keyPath, value: value))
    }

    /// Transforms the environment value of the specified key path with the given function.
    @inlinable
    nonisolated public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some View {
        modifier(_EnvironmentKeyTransformModifier(keyPath: keyPath, transform: transform))
    }
}
