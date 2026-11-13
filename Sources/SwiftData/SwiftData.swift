// SwiftData for the web (decision 0021, pf-swiftdata), written against the Countries app's
// models and repositories. `@Model` (SwiftDataMacros) gives a class its identity, observation
// and a table of its persisted properties; this module is the store those tables drive:
//
// - `Schema`, `ModelConfiguration`, `ModelContainer` with its `mainContext`;
// - `ModelContext`: `insert` (an `@Attribute(.unique)` value already stored makes it an update
//   of that row, as SwiftData upserts), `delete`, `fetch(FetchDescriptor)` with an in-memory
//   `#Predicate` and sort descriptors, `transaction`, `save`, autosave at the end of a transaction;
// - relationships kept in both directions (`@Relationship(inverse:)`): setting one side sets
//   the other; a deleted model leaves its inverses;
// - persistence: every container that is not in-memory-only writes its models (attributes as
//   JSON, relationships as identifiers) to the host's store under its name and reads them back
//   when opened again — the browser host keeps it in localStorage; without a host the store is
//   the process's memory.
//
// Not SwiftData: no SQL (predicates run as Swift closures over the models in memory, which is
// what `#Predicate` expands to here), no lazy faulting, no migration plans (the schema version
// is recorded; a different version empties the store), no CloudKit, no undo manager.
// Apple's frameworks re-export Foundation: a file importing only this module names Data and URL.
@_exported import WebFoundation
@_exported import Observation
import SwiftUIWebCore
import WebCombine

// MARK: - The macros (SwiftDataMacros)

@attached(member, names: named(_storage), named(_entityName), named(_persistedProperties), named(_make), named(_$observationRegistrar), named(access), named(withMutation), named(init(_uninitialized:)))
@attached(memberAttribute)
@attached(extension, conformances: PersistentModel)
public macro Model() = #externalMacro(module: "SwiftDataMacros", type: "ModelMacro")

@attached(accessor)
@attached(peer, names: prefixed(_))
public macro _ModelProperty() = #externalMacro(module: "SwiftDataMacros", type: "ModelPropertyMacro")

@attached(peer)
public macro Attribute(_ options: Schema.Attribute.Option..., originalName: String? = nil, hashModifier: String? = nil) = #externalMacro(module: "SwiftDataMacros", type: "AttributeMacro")

@attached(peer)
public macro Relationship(_ options: Schema.Relationship.Option..., deleteRule: Schema.Relationship.DeleteRule = .nullify, minimumModelCount: Int? = 0, maximumModelCount: Int? = 0, originalName: String? = nil, inverse: AnyKeyPath? = nil, hashModifier: String? = nil) = #externalMacro(module: "SwiftDataMacros", type: "RelationshipMacro")

@attached(peer)
public macro Transient() = #externalMacro(module: "SwiftDataMacros", type: "TransientMacro")

@freestanding(expression)
public macro Predicate<T>(_ body: (T) -> Bool) -> WebFoundation.Predicate<T> = #externalMacro(module: "SwiftDataMacros", type: "PredicateMacro")

@attached(member, names: named(modelExecutor), named(modelContainer), named(init(modelContainer:)))
@attached(extension, conformances: ModelActor)
public macro ModelActor() = #externalMacro(module: "SwiftDataMacros", type: "ModelActorMacro")

// `@Query` is a macro, as Apple's: it writes the backing `Query<Element, [Element]>` with the
// element type spelled out from the declared array, which a wrapper application cannot infer.
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query() = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Value: Comparable, Element: PersistentModel>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value>, order: SortDescriptor<Element>.Order = .forward, transaction: Transaction? = nil) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Value: Comparable, Element: PersistentModel>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value?>, order: SortDescriptor<Element>.Order = .forward, transaction: Transaction? = nil) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Value: Comparable, Element: PersistentModel>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value>, order: SortDescriptor<Element>.Order = .forward, animation: Animation) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Element: PersistentModel>(filter: WebFoundation.Predicate<Element>? = nil, sort descriptors: [SortDescriptor<Element>] = [], transaction: Transaction? = nil) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Element: PersistentModel>(filter: WebFoundation.Predicate<Element>? = nil, sort descriptors: [SortDescriptor<Element>] = [], animation: Animation) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Element: PersistentModel>(_ descriptor: FetchDescriptor<Element>, transaction: Transaction? = nil) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")
@attached(accessor)
@attached(peer, names: prefixed(`_`))
public macro Query<Element: PersistentModel>(_ descriptor: FetchDescriptor<Element>, animation: Animation) = #externalMacro(module: "SwiftDataMacros", type: "QueryMacro")

// MARK: - Identity

/// The identity of a stored model: its type and a number unique within the store.
public struct PersistentIdentifier: Hashable, Sendable, Codable, CustomStringConvertible {
    public let entityName: String
    public let storeIdentifier: String?
    let number: Int
    /// Identity is the entity and the number: a row read back from the store is the model it was.
    public static func == (lhs: PersistentIdentifier, rhs: PersistentIdentifier) -> Bool { lhs.entityName == rhs.entityName && lhs.number == rhs.number }
    public func hash(into hasher: inout Hasher) { hasher.combine(entityName); hasher.combine(number) }
    init(entityName: String, number: Int, store: String?) {
        self.entityName = entityName
        self.number = number
        storeIdentifier = store
    }
    /// A model not yet inserted anywhere has a temporary identity.
    public var isTemporary: Bool { storeIdentifier == nil }
    public var description: String { "\(entityName)#\(number)\(storeIdentifier.map { "@" + $0 } ?? "")" }
}

// MARK: - The persisted value of a property

/// A property's value as the store keeps it: the scalar kinds Codable attributes map to, and
/// relationships as identifiers.
public enum _StoredValue: Equatable, Sendable {
    case null
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case data([UInt8])
    case date(Double)
    case array([_StoredValue])
    case dictionary([String: _StoredValue])
    case reference(PersistentIdentifier)
    case references([PersistentIdentifier])
}

/// A type an attribute can hold: how it becomes a stored value and back.
public protocol _PersistableValue {
    var _storedValue: _StoredValue { get }
    static func _fromStoredValue(_ value: _StoredValue) -> Self?
}

extension String: _PersistableValue {
    public var _storedValue: _StoredValue { .string(self) }
    public static func _fromStoredValue(_ value: _StoredValue) -> String? { if case .string(let s) = value { return s }; return nil }
}
extension Int: _PersistableValue {
    public var _storedValue: _StoredValue { .int(self) }
    public static func _fromStoredValue(_ value: _StoredValue) -> Int? {
        if case .int(let i) = value { return i }; if case .double(let d) = value { return Int(d) }; return nil
    }
}
extension Double: _PersistableValue {
    public var _storedValue: _StoredValue { .double(self) }
    public static func _fromStoredValue(_ value: _StoredValue) -> Double? {
        if case .double(let d) = value { return d }; if case .int(let i) = value { return Double(i) }; return nil
    }
}
extension Bool: _PersistableValue {
    public var _storedValue: _StoredValue { .bool(self) }
    public static func _fromStoredValue(_ value: _StoredValue) -> Bool? { if case .bool(let b) = value { return b }; return nil }
}
extension Data: _PersistableValue {
    public var _storedValue: _StoredValue { .data(Array(self)) }
    public static func _fromStoredValue(_ value: _StoredValue) -> Data? { if case .data(let bytes) = value { return Data(bytes) }; return nil }
}
extension Date: _PersistableValue {
    public var _storedValue: _StoredValue { .date(timeIntervalSince1970) }
    public static func _fromStoredValue(_ value: _StoredValue) -> Date? { if case .date(let t) = value { return Date(timeIntervalSince1970: t) }; return nil }
}
extension URL: _PersistableValue {
    public var _storedValue: _StoredValue { .string(absoluteString) }
    public static func _fromStoredValue(_ value: _StoredValue) -> URL? { if case .string(let s) = value { return URL(string: s) }; return nil }
}
extension Optional: _PersistableValue where Wrapped: _PersistableValue {
    public var _storedValue: _StoredValue { self?._storedValue ?? .null }
    public static func _fromStoredValue(_ value: _StoredValue) -> Wrapped?? {
        if case .null = value { return .some(nil) }
        return Wrapped._fromStoredValue(value).map { .some($0) }
    }
}
extension Array: _PersistableValue where Element: _PersistableValue {
    public var _storedValue: _StoredValue { .array(map(\._storedValue)) }
    public static func _fromStoredValue(_ value: _StoredValue) -> [Element]? {
        guard case .array(let items) = value else { return nil }
        var result: [Element] = []
        for item in items { guard let element = Element._fromStoredValue(item) else { return nil }; result.append(element) }
        return result
    }
}
extension Dictionary: _PersistableValue where Key == String, Value: _PersistableValue {
    public var _storedValue: _StoredValue { .dictionary(mapValues(\._storedValue)) }
    public static func _fromStoredValue(_ value: _StoredValue) -> [String: Value]? {
        guard case .dictionary(let items) = value else { return nil }
        var result: [String: Value] = [:]
        for (key, item) in items { guard let element = Value._fromStoredValue(item) else { return nil }; result[key] = element }
        return result
    }
}

// MARK: - The property table a @Model carries

/// One persisted property of a model type: how to read, write, encode and decode it, and
/// whether it is unique or a relationship with an inverse.
public struct _PersistedProperty: @unchecked Sendable {
    public enum Kind: Sendable { case attribute, toOne, toMany }
    public let name: String
    public let kind: Kind
    public let isUnique: Bool
    /// The related type's entity name (relationships).
    public let relatedEntity: String?
    /// The inverse property on the related type (relationships declared with `inverse:`).
    public let inverse: String?
    /// Reads the value as stored (relationships as identifiers, through the model's context).
    public let read: (any PersistentModel) -> _StoredValue
    /// Writes a stored value (relationships resolved through the model's context).
    public let write: (any PersistentModel, _StoredValue, ModelContext?) -> Void
    /// Reads a relationship's models (relationships only).
    public let related: ((any PersistentModel) -> [any PersistentModel])?
    /// Replaces a relationship's models without touching inverses (the context keeps those).
    public let setRelated: ((any PersistentModel, [any PersistentModel]) -> Void)?

    public init(name: String, kind: Kind, isUnique: Bool = false, relatedEntity: String? = nil, inverse: String? = nil,
                read: @escaping (any PersistentModel) -> _StoredValue,
                write: @escaping (any PersistentModel, _StoredValue, ModelContext?) -> Void,
                related: ((any PersistentModel) -> [any PersistentModel])? = nil,
                setRelated: ((any PersistentModel, [any PersistentModel]) -> Void)? = nil) {
        self.name = name; self.kind = kind; self.isUnique = isUnique; self.relatedEntity = relatedEntity; self.inverse = inverse
        self.read = read; self.write = write; self.related = related; self.setRelated = setRelated
    }
}

/// The property table's entry for a property whose kind its spelling does not tell (`@Model`
/// leaves it to these overloads): another model or an array of them is a relationship, a
/// value type we persist directly an attribute, and any other Codable value an attribute
/// kept as its JSON.
extension _PersistedProperty {
    public static func _inferred<M: PersistentModel, R: PersistentModel>(_ name: String, _ path: ReferenceWritableKeyPath<M, R?>, isUnique: Bool = false) -> _PersistedProperty {
        _PersistedProperty(name: name, kind: .toOne, relatedEntity: R._entityName,
                           read: { model in (model as! M)[keyPath: path].map { .reference($0.persistentModelID) } ?? .null },
                           write: { model, value, context in
                               if case .reference(let id) = value { (model as! M)[keyPath: path] = context?._resolve(id) as? R }
                               else { (model as! M)[keyPath: path] = nil }
                           },
                           related: { model in (model as! M)[keyPath: path].map { [$0 as any PersistentModel] } ?? [] },
                           setRelated: { model, related in (model as! M)[keyPath: path] = related.first as? R })
    }

    public static func _inferred<M: PersistentModel, R: PersistentModel>(_ name: String, _ path: ReferenceWritableKeyPath<M, [R]>, isUnique: Bool = false) -> _PersistedProperty {
        _toMany(name, R.self, get: { model in (model as! M)[keyPath: path] }, set: { model, related in (model as! M)[keyPath: path] = related })
    }

    public static func _inferred<M: PersistentModel, R: PersistentModel>(_ name: String, _ path: ReferenceWritableKeyPath<M, [R]?>, isUnique: Bool = false) -> _PersistedProperty {
        _toMany(name, R.self, get: { model in (model as! M)[keyPath: path] ?? [] }, set: { model, related in (model as! M)[keyPath: path] = related })
    }

    public static func _inferred<M: PersistentModel, V: _PersistableValue>(_ name: String, _ path: ReferenceWritableKeyPath<M, V>, isUnique: Bool = false) -> _PersistedProperty {
        _PersistedProperty(name: name, kind: .attribute, isUnique: isUnique,
                           read: { model in (model as! M)[keyPath: path]._storedValue },
                           write: { model, value, _ in if let decoded = V._fromStoredValue(value) { (model as! M)[keyPath: path] = decoded } })
    }

    @_disfavoredOverload
    public static func _inferred<M: PersistentModel, V: Codable>(_ name: String, _ path: ReferenceWritableKeyPath<M, V>, isUnique: Bool = false) -> _PersistedProperty {
        _PersistedProperty(name: name, kind: .attribute, isUnique: isUnique,
                           read: { model in
                               guard let data = try? JSONEncoder().encode((model as! M)[keyPath: path]) else { return .null }
                               return .data(Array(data))
                           },
                           write: { model, value, _ in
                               guard case .data(let bytes) = value, let decoded = try? JSONDecoder().decode(V.self, from: Data(bytes)) else { return }
                               (model as! M)[keyPath: path] = decoded
                           })
    }

    private static func _toMany<R: PersistentModel>(_ name: String, _ related: R.Type, get: @escaping (any PersistentModel) -> [R],
                                                    set: @escaping (any PersistentModel, [R]) -> Void) -> _PersistedProperty {
        _PersistedProperty(name: name, kind: .toMany, relatedEntity: R._entityName,
                           read: { model in .references(get(model).map { $0.persistentModelID }) },
                           write: { model, value, context in
                               guard case .references(let ids) = value else { return }
                               set(model, ids.compactMap { context?._resolve($0) as? R })
                           },
                           related: { model in get(model).map { $0 as any PersistentModel } },
                           setRelated: { model, related in set(model, related.compactMap { $0 as? R }) })
    }
}

// MARK: - PersistentModel

/// The interface that enables SwiftData to manage a Swift class as a stored model object.
/// `@Model` adds the conformance: the identity, the property table, the context link and
/// observation. Models and contexts are not isolated to an actor (as Apple's): they belong
/// to the actor that made them — the main actor for `mainContext` and `@Query`, a
/// `@ModelActor` for its own; on wasm there is one thread.
public protocol PersistentModel: AnyObject, Observable, Hashable, Identifiable, SendableMetatype {
    /// The entity's name (the class name).
    nonisolated static var _entityName: String { get }
    /// The persisted properties, declaration order.
    nonisolated static var _persistedProperties: [_PersistedProperty] { get }
    /// A model with its stored values (for reading a store back).
    static func _make(from values: [String: _StoredValue], in context: ModelContext) -> Self
    var persistentModelID: PersistentIdentifier { get }
    var modelContext: ModelContext? { get }
    /// The store's bookkeeping for this model.
    var _storage: _ModelStorage { get }
    var hasChanges: Bool { get }
    var isDeleted: Bool { get }
}

extension PersistentModel {
    public var id: PersistentIdentifier { persistentModelID }
    nonisolated public static func == (lhs: Self, rhs: Self) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    public var persistentModelID: PersistentIdentifier { _storage.identifier }
    public var modelContext: ModelContext? { _storage.context }
    public var hasChanges: Bool { _storage.hasChanges }
    public var isDeleted: Bool { _storage.isDeleted }
    nonisolated public static var _entityName: String { String(describing: Self.self) }
}

/// What the store keeps per model instance.
public final class _ModelStorage: @unchecked Sendable {
    public var identifier: PersistentIdentifier
    public weak var context: ModelContext?
    public var hasChanges = false
    public var isDeleted = false
    nonisolated(unsafe) private static var nextTemporary = 1
    public init(entityName: String) {
        identifier = PersistentIdentifier(entityName: entityName, number: Self.nextTemporary, store: nil)
        Self.nextTemporary += 1
    }
    /// Called by a `@Model`'s setters: the change reaches the context's autosave.
    public func didChange() {
        hasChanges = true
        context?.noteChange()
    }
}

// MARK: - Schema and configuration

/// An object that maps model classes to data in the model store.
public final class Schema: @unchecked Sendable {
    public enum Attribute {
        public struct Option: Hashable, Sendable {
            let name: String
            public static let unique = Option(name: "unique")
            public static let externalStorage = Option(name: "externalStorage")
            public static let transformable = Option(name: "transformable")
            public static let spotlight = Option(name: "spotlight")
            public static let ephemeral = Option(name: "ephemeral")
            public static let allowsCloudEncryption = Option(name: "allowsCloudEncryption")
            public static let preserveValueOnDeletion = Option(name: "preserveValueOnDeletion")
        }
    }
    public enum Relationship {
        public struct Option: Hashable, Sendable {
            let name: String
            public static let unique = Option(name: "unique")
        }
        public enum DeleteRule: Sendable { case noAction, nullify, cascade, deny }
    }
    public struct Version: Hashable, Sendable, CustomStringConvertible {
        public let major: Int, minor: Int, patch: Int
        public init(_ major: Int, _ minor: Int, _ patch: Int) { self.major = major; self.minor = minor; self.patch = patch }
        public var description: String { "\(major).\(minor).\(patch)" }
    }
    public let entities: [any PersistentModel.Type]
    public let version: Version
    public var entityNames: [String] { entities.map { $0._entityName } }
    public init(_ types: [any PersistentModel.Type], version: Version = Version(1, 0, 0)) {
        entities = types
        self.version = version
    }
    public convenience init(_ types: any PersistentModel.Type..., version: Version = Version(1, 0, 0)) { self.init(types, version: version) }
    public convenience init(versionedSchema: any VersionedSchema.Type) { self.init(versionedSchema.models, version: versionedSchema.versionIdentifier) }
    func entity(named name: String) -> (any PersistentModel.Type)? { entities.first { $0._entityName == name } }
}

/// A type that describes the entities of a specific version of a schema.
public protocol VersionedSchema {
    static var versionIdentifier: Schema.Version { get }
    static var models: [any PersistentModel.Type] { get }
}

/// A type that describes the configuration of an app's schema or specific group of models.
public struct ModelConfiguration: Hashable, Sendable {
    public let name: String
    public let isStoredInMemoryOnly: Bool
    public let allowsSave: Bool
    public let schema: Schema?
    public init(_ name: String? = nil, schema: Schema? = nil, isStoredInMemoryOnly: Bool = false, allowsSave: Bool = true) {
        self.name = name ?? "default"
        self.schema = schema
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.allowsSave = allowsSave
    }
    public init(isStoredInMemoryOnly: Bool) { self.init(nil, isStoredInMemoryOnly: isStoredInMemoryOnly) }
    /// The forms that name a CloudKit database or an app group: the browser store syncs with
    /// neither, so both are accepted and the store is the app's own.
    public init(_ name: String? = nil, schema: Schema? = nil, isStoredInMemoryOnly: Bool = false, allowsSave: Bool = true,
                groupContainer: GroupContainer = .automatic, cloudKitDatabase: CloudKitDatabase) {
        self.init(name, schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly, allowsSave: allowsSave)
    }

    /// The app group a store lives in.
    public struct GroupContainer: Sendable, Hashable {
        package let identifier: String?
        public static let automatic = GroupContainer(identifier: nil)
        public static let none = GroupContainer(identifier: nil)
        public static func identifier(_ groupName: String) -> GroupContainer { GroupContainer(identifier: groupName) }
    }

    /// The CloudKit database a store syncs with.
    public struct CloudKitDatabase: Sendable, Hashable {
        package let identifier: String?
        public static let automatic = CloudKitDatabase(identifier: nil)
        public static let none = CloudKitDatabase(identifier: nil)
        public static func `private`(_ containerIdentifier: String) -> CloudKitDatabase { CloudKitDatabase(identifier: containerIdentifier) }
    }
    public static func == (lhs: ModelConfiguration, rhs: ModelConfiguration) -> Bool { lhs.name == rhs.name && lhs.isStoredInMemoryOnly == rhs.isStoredInMemoryOnly }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

// MARK: - Container

/// An object that manages an app's schema and model storage configuration.
public final class ModelContainer: @unchecked Sendable {
    public let schema: Schema
    public let configurations: [ModelConfiguration]
    /// The context for the main actor (made on first use there).
    @MainActor public var mainContext: ModelContext {
        if let context = mainContextStorage { return context }
        let context = ModelContext(self)
        context.isMainActorContext = true
        mainContextStorage = context
        return context
    }
    nonisolated(unsafe) private var mainContextStorage: ModelContext?
    /// The store: rows by identifier, with their values, per entity.
    let store: _ModelStore

    public init(for schema: Schema, configurations: [ModelConfiguration]) throws {
        self.schema = schema
        self.configurations = configurations.isEmpty ? [ModelConfiguration(schema: schema)] : configurations
        store = try _ModelStore(name: self.configurations[0].name, schema: schema, inMemory: self.configurations[0].isStoredInMemoryOnly)
    }
    public convenience init(for schema: Schema, configurations: ModelConfiguration...) throws { try self.init(for: schema, configurations: configurations) }
    public convenience init(for types: any PersistentModel.Type..., configurations: ModelConfiguration...) throws {
        try self.init(for: Schema(types), configurations: configurations)
    }

    @MainActor public func deleteAllData() {
        mainContext.deleteAll()
        try? store.eraseAll()
    }
}

// MARK: - Fetching

/// A type that describes the criteria, sort order, and any additional configuration to use
/// when performing a fetch.
public struct FetchDescriptor<T: PersistentModel> {
    public var predicate: WebFoundation.Predicate<T>?
    public var sortBy: [SortDescriptor<T>]
    public var fetchLimit: Int?
    public var fetchOffset: Int?
    public var includePendingChanges = true
    public init(predicate: WebFoundation.Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []) {
        self.predicate = predicate
        self.sortBy = sortBy
    }
}

// `Predicate` itself is WebFoundation's. This module names it `WebFoundation.Predicate`, because
// on macOS and Linux other modules import Foundation directly and the bare name is ambiguous.

/// A description of how to order models by one of their properties.
public struct SortDescriptor<Compared>: @unchecked Sendable {
    public enum Order: Sendable { case forward, reverse }
    public let order: Order
    /// The key path the descriptor sorts by.
    public let keyPath: PartialKeyPath<Compared>?
    /// Whether the first value comes before the second, the order applied.
    let ordersBefore: (Compared, Compared) -> Bool
    public init<Value: Comparable>(_ keyPath: KeyPath<Compared, Value>, order: Order = .forward) {
        self.order = order
        self.keyPath = keyPath
        ordersBefore = { a, b in order == .forward ? a[keyPath: keyPath] < b[keyPath: keyPath] : a[keyPath: keyPath] > b[keyPath: keyPath] }
    }
    public init<Value: Comparable>(_ keyPath: KeyPath<Compared, Value?>, order: Order = .forward) {
        self.order = order
        self.keyPath = keyPath
        ordersBefore = { a, b in
            switch (a[keyPath: keyPath], b[keyPath: keyPath]) {
            case (nil, nil): return false
            case (nil, _): return order == .forward
            case (_, nil): return order == .reverse
            case (let x?, let y?): return order == .forward ? x < y : x > y
            }
        }
    }
    public init(_ keyPath: KeyPath<Compared, String>, comparator: Any? = nil, order: Order = .forward) {
        self.order = order
        self.keyPath = keyPath
        ordersBefore = { a, b in order == .forward ? a[keyPath: keyPath] < b[keyPath: keyPath] : a[keyPath: keyPath] > b[keyPath: keyPath] }
    }

    /// How two values order under the descriptor, its order applied (Foundation's
    /// `SortComparator.compare`).
    public func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
        ordersBefore(lhs, rhs) ? .orderedAscending : ordersBefore(rhs, lhs) ? .orderedDescending : .orderedSame
    }
}

// MARK: - Context

/// An object that enables you to fetch, insert, and delete models, and save any changes to disk.
public final class ModelContext: @unchecked Sendable {
    public let container: ModelContainer
    public var autosaveEnabled = true
    /// Models the context holds, by identifier, in insertion order.
    private var models: [PersistentIdentifier: any PersistentModel] = [:]
    private var order: [PersistentIdentifier] = []
    private var pending = false
    private var inTransaction = 0
    private(set) var changeCount = 0
    /// The store generation this context last synced to (`_ModelStore.sync`).
    var syncedGeneration = 0
    /// Told after every save or deletion (`@Query` refetches).
    /// Told after every save, with whether the saving context is the main actor's (a save in
    /// `mainContext` happens on the main actor by its contract; any other context's does not).
    var observers: [(id: Int, run: @Sendable (_ onMainActor: Bool) -> Void)] = []
    private var nextObserver = 1
    /// The container's `mainContext`: used from the main actor only.
    var isMainActorContext = false

    public init(_ container: ModelContainer) {
        self.container = container
        container.store.attach(self)
        container.store.load(into: self)
    }

    /// The store saved (this context or another of the same store): `@Query` refetches.
    func storeDidSave(by saver: ModelContext) { for observer in observers { observer.run(saver.isMainActorContext) } }

    public var hasChanges: Bool { pending }
    public var insertedModelsArray: [any PersistentModel] { order.compactMap { models[$0] }.filter { $0._storage.identifier.isTemporary } }
    public var changedModelsArray: [any PersistentModel] { order.compactMap { models[$0] }.filter { $0.hasChanges } }
    public var deletedModelsArray: [any PersistentModel] { [] }

    func noteChange() {
        pending = true
        changeCount += 1
        if autosaveEnabled, inTransaction == 0 { try? save() }
    }

    /// Registers the model with the context. A model whose `@Attribute(.unique)` value is
    /// already stored replaces that model's values (SwiftData's upsert) and is not a second row.
    public func insert<T: PersistentModel>(_ model: T) {
        if let existing = existingModel(matching: model) {
            upsert(model, into: existing)
            return
        }
        register(model)
        // Relationships set before the insert: their inverses now.
        for property in T._persistedProperties where property.kind != .attribute {
            if let related = property.related?(model) { link(model, property, related) }
        }
        model._storage.didChange()
    }

    /// The registered model of `model`'s type with the same `@Attribute(.unique)` value, if any.
    private func existingModel(matching model: any PersistentModel) -> (any PersistentModel)? {
        let modelType = type(of: model)
        guard model._storage.context !== self, let unique = modelType._persistedProperties.first(where: { $0.isUnique }) else { return nil }
        let value = unique.read(model)
        return models.values.first { type(of: $0) == modelType && $0 !== model && unique.read($0) == value }
    }

    /// `existing` takes `model`'s attributes and relationships (the unique attribute is the
    /// same by construction); `model` itself stays outside the context.
    private func upsert(_ model: any PersistentModel, into existing: any PersistentModel) {
        let properties = type(of: model)._persistedProperties
        for property in properties where property.kind == .attribute && !property.isUnique {
            property.write(existing, property.read(model), self)
        }
        for property in properties where property.kind != .attribute {
            // The app may construct a new graph each time (Countries builds a fresh Currency per
            // store); a relationship set on the replaced instance is applied only when it names
            // something, so an empty default does not clear what the stored model already has.
            if let related = property.related?(model), !related.isEmpty, let set = property.setRelated {
                let resolved = related.map { resolveUnique($0) }
                set(existing, resolved)
                link(existing, property, resolved)
            }
        }
        existing._storage.didChange()
    }

    /// A related model that duplicates a registered one by its unique attribute stands for that
    /// one: its values go to the registered model (upsert) and the relationship points there.
    private func resolveUnique(_ related: any PersistentModel) -> any PersistentModel {
        guard let existing = existingModel(matching: related) else { return related }
        upsert(related, into: existing)
        return existing
    }

    private func register(_ model: any PersistentModel) {
        if model._storage.identifier.isTemporary {
            model._storage.identifier = container.store.nextIdentifier(for: type(of: model)._entityName)
        }
        model._storage.context = self
        model._storage.isDeleted = false
        if models[model._storage.identifier] == nil { order.append(model._storage.identifier) }
        models[model._storage.identifier] = model
        // Related models not yet in the context come along (SwiftData inserts a graph); one that
        // duplicates a registered model by its unique attribute is that model.
        for property in type(of: model)._persistedProperties where property.kind != .attribute {
            guard let related = property.related?(model), !related.isEmpty else { continue }
            let resolved = related.map { resolveUnique($0) }
            if zip(resolved, related).contains(where: { $0 !== $1 }) { property.setRelated?(model, resolved) }
            for other in resolved where other._storage.context !== self { register(other) }
        }
    }

    /// The property on the related entity that is the inverse of `property`: the one `property`
    /// names, or the one that names `property` (SwiftData reads `inverse:` from either side).
    func inverse(of property: _PersistedProperty, on owner: any PersistentModel.Type) -> (type: any PersistentModel.Type, property: _PersistedProperty)? {
        guard let relatedEntity = property.relatedEntity, let relatedType = container.schema.entity(named: relatedEntity) else { return nil }
        let candidates = relatedType._persistedProperties.filter { $0.kind != .attribute }
        if let name = property.inverse, let named = candidates.first(where: { $0.name == name }) { return (relatedType, named) }
        if let back = candidates.first(where: { $0.inverse == property.name && $0.relatedEntity == owner._entityName }) { return (relatedType, back) }
        return nil
    }

    /// Sets the inverse side of `property` on each of `related` (and removes `model` from the
    /// inverses of models no longer related).
    func link(_ model: any PersistentModel, _ property: _PersistedProperty, _ related: [any PersistentModel]) {
        guard let (relatedType, inverse) = inverse(of: property, on: type(of: model)), let setInverse = inverse.setRelated else { return }
        for other in related {
            var current = inverse.related?(other) ?? []
            if !current.contains(where: { $0 === model }) {
                if inverse.kind == .toOne { current = [model] } else { current.append(model) }
                setInverse(other, current)
                other._storage.didChange()
            }
        }
        // Models of the related entity that still list `model` but are no longer related: unlinked.
        for other in models.values where type(of: other) == relatedType && !related.contains(where: { $0 === other }) {
            let current = inverse.related?(other) ?? []
            if current.contains(where: { $0 === model }) {
                setInverse(other, current.filter { $0 !== model })
                other._storage.didChange()
            }
        }
    }

    /// Removes the model from the context and from every inverse that listed it; the row goes
    /// at the next save.
    public func delete<T: PersistentModel>(_ model: T) {
        guard models[model._storage.identifier] != nil else { return }
        for property in T._persistedProperties where property.kind != .attribute { link(model, property, []) }
        models[model._storage.identifier] = nil
        order.removeAll { $0 == model._storage.identifier }
        model._storage.isDeleted = true
        model._storage.context = nil
        container.store.remove(model._storage.identifier)
        noteChange()
    }

    public func delete<T: PersistentModel>(model: T.Type, where predicate: WebFoundation.Predicate<T>? = nil) throws {
        for model in try fetch(FetchDescriptor<T>(predicate: predicate)) { delete(model) }
    }

    func deleteAll() {
        for model in models.values { model._storage.isDeleted = true; model._storage.context = nil }
        models.removeAll(); order.removeAll()
        noteChange()
    }

    /// The models of `T` the predicate accepts, sorted; every model in the context counts
    /// (there is no separate persistent state to be out of date against).
    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        container.store.sync(into: self)
        var result: [T] = []
        for identifier in order {
            guard let model = models[identifier] as? T else { continue }
            if let predicate = descriptor.predicate, try !predicate.evaluate(model) { continue }
            result.append(model)
        }
        if !descriptor.sortBy.isEmpty {
            result.sort { a, b in
                for descriptor in descriptor.sortBy {
                    if descriptor.ordersBefore(a, b) { return true }
                    if descriptor.ordersBefore(b, a) { return false }
                }
                return false
            }
        }
        if let offset = descriptor.fetchOffset { result = Array(result.dropFirst(offset)) }
        if let limit = descriptor.fetchLimit { result = Array(result.prefix(limit)) }
        return result
    }

    public func fetchCount<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> Int { try fetch(descriptor).count }

    /// The model with this identifier, read from the store if this context has not met it yet
    /// (a dragged identifier, an identifier kept across launches).
    public func model(for identifier: PersistentIdentifier) -> any PersistentModel {
        if models[identifier] == nil { container.store.sync(into: self) }
        guard let model = models[identifier] else { fatalError("ModelContext: no model with identifier \(identifier)") }
        return model
    }
    public func registeredModel<T: PersistentModel>(for identifier: PersistentIdentifier) -> T? { models[identifier] as? T }
    func registeredModelAny(for identifier: PersistentIdentifier) -> (any PersistentModel)? { models[identifier] }

    /// Runs `block` as one change: autosave waits until it returns, then saves once.
    public func transaction(block: () throws -> Void) throws {
        inTransaction += 1
        do { try block() } catch { inTransaction -= 1; throw error }
        inTransaction -= 1
        if inTransaction == 0 { try save() }
    }

    /// Writes every model's values to the store (the host keeps them for the next open).
    public func save() throws {
        for identifier in order {
            guard let model = models[identifier] else { continue }
            container.store.put(model)
        }
        try container.store.flush()   // a refused write leaves the changes pending
        pending = false
        for identifier in order { models[identifier]?._storage.hasChanges = false }
        container.store.didSave(by: self)
    }

    public func rollback() { pending = false }
    public func processPendingChanges() {}

    /// Tells `run` after every save (for `@Query`); the returned closure stops it.
    func observe(_ run: @escaping @Sendable (_ onMainActor: Bool) -> Void) -> @Sendable () -> Void {
        let id = nextObserver
        nextObserver += 1
        observers.append((id, run))
        return { [weak self] in self?.observers.removeAll { $0.id == id } }
    }

    /// Every model the context holds (the store writes them; tests read them).
    public var _allModels: [any PersistentModel] { order.compactMap { models[$0] } }

    /// A `@Model` setter on a relationship: the inverse side follows.
    public func _relationshipDidChange(_ model: any PersistentModel, _ name: String) {
        guard let property = type(of: model)._persistedProperties.first(where: { $0.name == name }), property.kind != .attribute,
              let related = property.related?(model) else { return }
        // A model given a relationship to one in this context joins it (and its relationships
        // set before then link as at any insert).
        if model._storage.context !== self { insert(model); return }
        // A model assigned to a relationship joins the context (SwiftData inserts the graph).
        let resolved = related.map { resolveUnique($0) }
        if zip(resolved, related).contains(where: { $0 !== $1 }) { property.setRelated?(model, resolved) }
        for other in resolved where other._storage.context !== self { insert(other) }
        link(model, property, resolved)
    }
}

extension PersistentModel {
    /// A `@Model` setter: a relationship's change reaches this model's context, or, for a model
    /// not inserted yet, the context of a model it now relates to (SwiftData inserts the graph
    /// from either end: `task.project = project` saves the task with the project).
    public func _relationshipDidChange(_ name: String) {
        if let context = modelContext { context._relationshipDidChange(self, name); return }
        guard let property = Self._persistedProperties.first(where: { $0.name == name }), property.kind != .attribute,
              let context = property.related?(self).lazy.compactMap({ $0.modelContext }).first else { return }
        context._relationshipDidChange(self, name)
    }
}

// MARK: - The store

/// The rows, as stored values, and their persistence through the host.
public final class _ModelStore: @unchecked Sendable {
    public enum Host {
        /// Loads and saves one store's JSON by name (the browser host: localStorage).
        nonisolated(unsafe) public static var store: (load: (String) throws -> String?, save: (String, String?) throws -> Void)?
    }

    let name: String
    let schema: Schema
    let inMemory: Bool
    private var rows: [PersistentIdentifier: [String: _StoredValue]] = [:]
    /// The contexts over this store (weakly): a save in one reaches the others' observers,
    /// and a fetch in one adopts rows another saved.
    private var contexts: [_WeakContext] = []
    final class _WeakContext { weak var context: ModelContext?; init(_ context: ModelContext) { self.context = context } }
    func attach(_ context: ModelContext) { contexts.append(_WeakContext(context)); contexts.removeAll { $0.context == nil } }
    func didSave(by saver: ModelContext) { for entry in contexts { entry.context?.storeDidSave(by: saver) } }

    /// Rows another context saved that `context` does not hold yet: made and adopted, their
    /// relationships resolved (what one context's `@Query` sees after a model actor's save).
    func sync(into context: ModelContext) {
        guard context.syncedGeneration != generation else { return }
        context.syncedGeneration = generation
        let ordered = rows.keys.sorted { ($0.entityName, $0.number) < ($1.entityName, $1.number) }
        var made: [PersistentIdentifier] = []
        // Rows deleted elsewhere: gone from this context too, unless it changed the model itself.
        for model in context._allModels where rows[model._storage.identifier] == nil && !model._storage.hasChanges {
            context._forget(model)
        }
        for identifier in ordered {
            guard let type = schema.entity(named: identifier.entityName), let values = rows[identifier] else { continue }
            if let registered = context.registeredModelAny(for: identifier) {
                // Registered already: its attributes follow the row unless this context has
                // unsaved changes to it (a fetch refreshes what the context has not touched).
                guard !registered._storage.hasChanges else { continue }
                for property in type._persistedProperties where property.kind == .attribute {
                    if let value = values[property.name], property.read(registered) != value { property.write(registered, value, context) }
                }
                made.append(identifier)
                continue
            }
            let model = type._make(from: values, in: context)
            model._storage.identifier = identifier
            context._adopt(model)
            made.append(identifier)
        }
        for identifier in made {
            guard let model = context.registeredModelAny(for: identifier), let values = rows[identifier] else { continue }
            for property in type(of: model)._persistedProperties where property.kind != .attribute {
                if let value = values[property.name], property.read(model) != value { property.write(model, value, context) }
            }
            model._storage.hasChanges = false
        }
    }
    /// Counts the store's writes; a context whose last sync saw this generation is current.
    private(set) var generation = 0
    private var counters: [String: Int] = [:]
    init(name: String, schema: Schema, inMemory: Bool) throws {
        self.name = name
        self.schema = schema
        self.inMemory = inMemory
        // An in-memory store is this container's alone (SwiftData's): nothing read, nothing kept.
        guard !inMemory else { return }
        // A persistent store needs the host's storage; without it the container does not open
        // (an in-memory stand-in would be reported as persistence that is not there).
        guard let host = Host.store else { throw SwiftDataError.storageUnavailable(name, reason: "no host storage is bound") }
        let json: String?
        do { json = try host.load(name) } catch { throw SwiftDataError.storageUnavailable(name, reason: "\(error)") }
        guard let json else { return }   // the first open: empty
        guard let stored = _StoreCodec.decode(json, store: name) else { throw SwiftDataError.corruptStore(name) }
        // Another schema version wrote the store: no migration here, and its bytes stay as they
        // are — the container fails to open rather than saving over them.
        guard stored.version == schema.version.description else {
            throw SwiftDataError.incompatibleSchema(name, stored: stored.version, expected: schema.version.description)
        }
        rows = stored.rows
        counters = stored.counters
    }

    func nextIdentifier(for entity: String) -> PersistentIdentifier {
        let number = (counters[entity] ?? 0) + 1
        counters[entity] = number
        return PersistentIdentifier(entityName: entity, number: number, store: name)
    }

    func put(_ model: any PersistentModel) {
        var values: [String: _StoredValue] = [:]
        for property in type(of: model)._persistedProperties { values[property.name] = property.read(model) }
        if rows[model._storage.identifier] != values { rows[model._storage.identifier] = values; generation += 1 }
    }

    func remove(_ identifier: PersistentIdentifier) {
        if rows.removeValue(forKey: identifier) != nil { generation += 1 }
    }

    func eraseAll() throws {
        rows.removeAll(); counters.removeAll()
        generation += 1
        try flush()
    }

    /// Writes the rows through the host; a refused write (no storage left, a browser that
    /// blocks it) is the save's error.
    func flush() throws {
        guard !inMemory, let host = Host.store else { return }
        do { try host.save(name, _StoreCodec.encode(rows: rows, counters: counters, version: schema.version.description)) }
        catch { throw SwiftDataError.saveFailed(name, reason: "\(error)") }
    }

    /// Rebuilds the models in `context`: attributes first, then relationships by identifier.
    func load(into context: ModelContext) {
        guard !rows.isEmpty else { return }
        var made: [PersistentIdentifier: any PersistentModel] = [:]
        let ordered = rows.keys.sorted { ($0.entityName, $0.number) < ($1.entityName, $1.number) }
        for identifier in ordered {
            guard let type = schema.entity(named: identifier.entityName), let values = rows[identifier] else { continue }
            let model = type._make(from: values, in: context)
            model._storage.identifier = identifier
            made[identifier] = model
            context._adopt(model)   // registered first, so relationships below resolve by identifier
        }
        for identifier in ordered {
            guard let model = made[identifier], let values = rows[identifier] else { continue }
            for property in type(of: model)._persistedProperties where property.kind != .attribute {
                if let value = values[property.name] { property.write(model, value, context) }
            }
            model._storage.hasChanges = false
        }
    }
}

extension ModelContext {
    /// A model read back from the store: registered as it is, with its stored identity.
    func _adopt(_ model: any PersistentModel) {
        model._storage.context = self
        if models[model._storage.identifier] == nil { order.append(model._storage.identifier) }
        models[model._storage.identifier] = model
        model._storage.hasChanges = false
    }
    /// A row another context deleted: the model leaves this context without a store write.
    func _forget(_ model: any PersistentModel) {
        models[model._storage.identifier] = nil
        order.removeAll { $0 == model._storage.identifier }
        model._storage.isDeleted = true
        model._storage.context = nil
    }
    /// A relationship written from stored identifiers resolves through the context.
    public func _resolve(_ identifier: PersistentIdentifier) -> (any PersistentModel)? { models[identifier] }
}

/// The store's JSON (`JSONEncoder` on the Codable shapes below): the version, the per-entity
/// counters, and a row per model with its stored values.
struct _StoreDocument: Codable {
    var version: String
    var counters: [String: Int]
    var rows: [_StoreRow]
}
struct _StoreRow: Codable {
    var entity: String
    var number: Int
    var values: [String: _StoredValue]
}

extension _StoredValue: Codable {
    private enum Keys: String, CodingKey { case t, v, e, n }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .null: try c.encode("null", forKey: .t)
        case .string(let s): try c.encode("s", forKey: .t); try c.encode(s, forKey: .v)
        case .int(let i): try c.encode("i", forKey: .t); try c.encode(i, forKey: .v)
        case .double(let d): try c.encode("d", forKey: .t); try c.encode(d, forKey: .v)
        case .bool(let b): try c.encode("b", forKey: .t); try c.encode(b, forKey: .v)
        case .data(let bytes): try c.encode("data", forKey: .t); try c.encode(Data(bytes).base64EncodedString(), forKey: .v)
        case .date(let t): try c.encode("date", forKey: .t); try c.encode(t, forKey: .v)
        case .array(let items): try c.encode("a", forKey: .t); try c.encode(items, forKey: .v)
        case .dictionary(let items): try c.encode("m", forKey: .t); try c.encode(items, forKey: .v)
        case .reference(let id): try c.encode("r", forKey: .t); try c.encode(id.entityName, forKey: .e); try c.encode(id.number, forKey: .n)
        case .references(let ids): try c.encode("rs", forKey: .t); try c.encode(ids.map { _StoredValue.reference($0) }, forKey: .v)
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .t) {
        case "s": self = .string(try c.decode(String.self, forKey: .v))
        case "i": self = .int(try c.decode(Int.self, forKey: .v))
        case "d": self = .double(try c.decode(Double.self, forKey: .v))
        case "b": self = .bool(try c.decode(Bool.self, forKey: .v))
        case "data": self = .data(Array(Data(base64Encoded: try c.decode(String.self, forKey: .v)) ?? Data()))
        case "date": self = .date(try c.decode(Double.self, forKey: .v))
        case "a": self = .array(try c.decode([_StoredValue].self, forKey: .v))
        case "m": self = .dictionary(try c.decode([String: _StoredValue].self, forKey: .v))
        case "r": self = .reference(PersistentIdentifier(entityName: try c.decode(String.self, forKey: .e), number: try c.decode(Int.self, forKey: .n), store: nil))
        case "rs":
            let items = try c.decode([_StoredValue].self, forKey: .v)
            self = .references(items.compactMap { if case .reference(let id) = $0 { return id }; return nil })
        default: self = .null
        }
    }
}

enum _StoreCodec {
    static func encode(rows: [PersistentIdentifier: [String: _StoredValue]], counters: [String: Int], version: String) -> String {
        let ordered = rows.sorted { ($0.key.entityName, $0.key.number) < ($1.key.entityName, $1.key.number) }
        let document = _StoreDocument(version: version, counters: counters, rows: ordered.map { _StoreRow(entity: $0.key.entityName, number: $0.key.number, values: $0.value) })
        guard let data = try? JSONEncoder().encode(document) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ text: String, store: String) -> (rows: [PersistentIdentifier: [String: _StoredValue]], counters: [String: Int], version: String)? {
        guard let document = try? JSONDecoder().decode(_StoreDocument.self, from: Data(text.utf8)) else { return nil }
        var rows: [PersistentIdentifier: [String: _StoredValue]] = [:]
        for row in document.rows { rows[PersistentIdentifier(entityName: row.entity, number: row.number, store: store)] = row.values }
        return (rows, document.counters, document.version)
    }
}

// MARK: - Model actors

/// An interface for providing mutually-exclusive access to the attributes of a conforming model.
public protocol ModelExecutor: AnyObject, Sendable {
    var modelContext: ModelContext { get }
}

/// A default implementation of a serial model executor.
public final class DefaultSerialModelExecutor: ModelExecutor, @unchecked Sendable {
    public let modelContext: ModelContext
    public init(modelContext: ModelContext) { self.modelContext = modelContext }
}

/// An interface for providing mutually-exclusive access to the attributes of a conforming
/// model actor (`@ModelActor` adds the members).
public protocol ModelActor: Actor {
    nonisolated var modelContainer: ModelContainer { get }
    nonisolated var modelExecutor: any ModelExecutor { get }
}

extension ModelActor {
    /// The actor's context (the executor's).
    public var modelContext: ModelContext { modelExecutor.modelContext }
}

// MARK: - Errors

public enum SwiftDataError: Error, CustomStringConvertible {
    case loadIssueModelContainer
    case missingModelContext
    case duplicateConfiguration
    /// A persistent configuration whose host storage is missing or refuses to be read (the
    /// browser without localStorage, a page denied storage).
    case storageUnavailable(String, reason: String)
    /// The host holds bytes under the store's name that are not a store document.
    case corruptStore(String)
    /// The store was written by another schema version; there is no migration, and the
    /// container does not open over it.
    case incompatibleSchema(String, stored: String, expected: String)
    /// The host refused the write; the context's changes are still pending.
    case saveFailed(String, reason: String)
    public var description: String {
        switch self {
        case .loadIssueModelContainer: return "SwiftData: the model container could not be loaded"
        case .missingModelContext: return "SwiftData: no model context"
        case .duplicateConfiguration: return "SwiftData: duplicate configuration"
        case .storageUnavailable(let name, let reason): return "SwiftData: no persistent storage for the store '\(name)': \(reason)"
        case .corruptStore(let name): return "SwiftData: the stored bytes of '\(name)' are not a store"
        case .incompatibleSchema(let name, let stored, let expected): return "SwiftData: the store '\(name)' was written by schema \(stored), this app expects \(expected)"
        case .saveFailed(let name, let reason): return "SwiftData: the store '\(name)' could not be written: \(reason)"
        }
    }
}

// MARK: - SwiftUI

extension EnvironmentValues {
    /// The context of the container set with `modelContainer(_:)`; without one, the main
    /// context of a default in-memory container (SwiftData's own behaviour is a fatal error).
    public var modelContext: ModelContext {
        get {
            if let context = self[_ModelContextKey.self] { return context }
            return _ModelContextKey.fallback
        }
        set { self[_ModelContextKey.self] = newValue }
    }
}

struct _ModelContextKey: EnvironmentKey {
    static let defaultValue: ModelContext? = nil
    static var fallback: ModelContext {
        if let context = fallbackContext { return context }
        let container = try! ModelContainer(for: Schema([]), configurations: [ModelConfiguration("swiftui-fallback", isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        fallbackContext = context
        return context
    }
    nonisolated(unsafe) private static var fallbackContext: ModelContext?
}

extension View {
    /// Sets the model container and the main context in the environment of this view.
    nonisolated public func modelContainer(_ container: ModelContainer) -> some View {
        return environment(\.modelContext, MainActor.assumeIsolated { container.mainContext })
    }

    /// Sets the model container for the model types, made here (`isAutosaveEnabled`,
    /// `isUndoEnabled` accepted; `onSetup` told).
    nonisolated public func modelContainer(for modelTypes: [any PersistentModel.Type], inMemory: Bool = false, isAutosaveEnabled: Bool = true,
                                           isUndoEnabled: Bool = false, onSetup: @escaping (Result<ModelContainer, Error>) -> Void = { _ in }) -> some View {
        nonisolated(unsafe) let onSetup = onSetup
        let container: ModelContainer? = MainActor.assumeIsolated {
            do {
                let container = try ModelContainer(for: Schema(modelTypes), configurations: [ModelConfiguration(isStoredInMemoryOnly: inMemory)])
                container.mainContext.autosaveEnabled = isAutosaveEnabled
                onSetup(.success(container)); return container
            } catch { onSetup(.failure(error)); return nil }
        }
        return environment(\.modelContext, MainActor.assumeIsolated { container?.mainContext ?? _ModelContextKey.fallback })
    }
    nonisolated public func modelContainer(for modelType: any PersistentModel.Type, inMemory: Bool = false, isAutosaveEnabled: Bool = true,
                                           isUndoEnabled: Bool = false, onSetup: @escaping (Result<ModelContainer, Error>) -> Void = { _ in }) -> some View {
        modelContainer(for: [modelType], inMemory: inMemory, isAutosaveEnabled: isAutosaveEnabled, isUndoEnabled: isUndoEnabled, onSetup: onSetup)
    }
    /// Sets the model context in this view's environment.
    nonisolated public func modelContext(_ modelContext: ModelContext) -> some View {
        return environment(\.modelContext, modelContext)
    }
}

extension Scene {
    public func modelContainer(_ container: ModelContainer) -> some Scene {
        return _wrappingRoots { AnyView($0.modelContainer(container)) }
    }
    public func modelContainer(for modelTypes: [any PersistentModel.Type], inMemory: Bool = false, isAutosaveEnabled: Bool = true, isUndoEnabled: Bool = false) -> some Scene {
        return _wrappingRoots { AnyView($0.modelContainer(for: modelTypes, inMemory: inMemory, isAutosaveEnabled: isAutosaveEnabled, isUndoEnabled: isUndoEnabled)) }
    }
    public func modelContainer(for modelType: any PersistentModel.Type, inMemory: Bool = false, isAutosaveEnabled: Bool = true, isUndoEnabled: Bool = false) -> some Scene {
        modelContainer(for: [modelType], inMemory: inMemory, isAutosaveEnabled: isAutosaveEnabled, isUndoEnabled: isUndoEnabled)
    }
}

/// A property wrapper that fetches a set of models and keeps those models in sync with the
/// underlying data: the environment's context, fetched as each body is about to be evaluated
/// (`update()`), and the view re-read after every save (the box's `objectWillChange`). As on
/// Apple platforms, the results are those of the latest body: an action that inserts and then
/// reads the query still sees what the view shows until the view updates. The initializers live in the
/// struct with `Result == [Element]`, as Apple's: `@Query var items: [Item]` infers `Element`
/// from the one callable with no arguments.
@MainActor
public struct Query<Element: PersistentModel, Result>: DynamicProperty {
    @Environment(\.modelContext) private var context
    @StateObject private var box = _QueryBox<Element>()
    private let fetch: @MainActor (ModelContext) -> Result
    private var animation: Animation?

    /// The models of the latest update (a fetch now when there has been none, as for a read
    /// before the view is shown).
    public var wrappedValue: Result { box.results(fetch, in: context) }
    public var fetchError: Error? { nil }
    public var modelContext: ModelContext { context }
    /// Fetches for the body about to be evaluated, and watches the context so a save re-reads it.
    public mutating func update() { box.refresh(fetch, in: context) }

    private static func fetching(_ descriptor: FetchDescriptor<Element>) -> @MainActor (ModelContext) -> [Element] {
        { (try? $0.fetch(descriptor)) ?? [] }
    }

    public init<Value: Comparable>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value>, order: SortDescriptor<Element>.Order = .forward, animation: Animation) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])); self.animation = animation
    }
    public init<Value: Comparable>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value?>, order: SortDescriptor<Element>.Order = .forward, animation: Animation) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])); self.animation = animation
    }
    public init<Value: Comparable>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value>, order: SortDescriptor<Element>.Order = .forward, transaction: Transaction? = nil) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])); animation = transaction?.animation
    }
    public init<Value: Comparable>(filter: WebFoundation.Predicate<Element>? = nil, sort keyPath: KeyPath<Element, Value?>, order: SortDescriptor<Element>.Order = .forward, transaction: Transaction? = nil) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: [SortDescriptor(keyPath, order: order)])); animation = transaction?.animation
    }
    public init(filter: WebFoundation.Predicate<Element>? = nil, sort descriptors: [SortDescriptor<Element>] = [], animation: Animation) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: descriptors)); self.animation = animation
    }
    public init(filter: WebFoundation.Predicate<Element>? = nil, sort descriptors: [SortDescriptor<Element>] = [], transaction: Transaction? = nil) where Result == [Element] {
        fetch = Self.fetching(FetchDescriptor(predicate: filter, sortBy: descriptors)); animation = transaction?.animation
    }
    public init(_ descriptor: FetchDescriptor<Element>, transaction: Transaction? = nil) where Result == [Element] {
        fetch = Self.fetching(descriptor); animation = transaction?.animation
    }
    public init(_ descriptor: FetchDescriptor<Element>, animation: Animation) where Result == [Element] {
        fetch = Self.fetching(descriptor); self.animation = animation
    }
}

/// The state behind a `@Query`: the context's observer, dropped when the box goes, and the
/// results fetched for the latest body.
@MainActor
final class _QueryBox<Element: PersistentModel>: WebCombine.ObservableObject {
    private var stop: (@Sendable () -> Void)?
    private weak var watched: ModelContext?
    /// The query's `Result` as of the latest update.
    private var snapshot: Any?
    nonisolated init() {}

    func refresh<Result>(_ fetch: @MainActor (ModelContext) -> Result, in context: ModelContext) {
        watch(context)
        snapshot = fetch(context)
    }

    func results<Result>(_ fetch: @MainActor (ModelContext) -> Result, in context: ModelContext) -> Result {
        if let snapshot = snapshot as? Result { return snapshot }
        watch(context)
        let value = fetch(context)
        snapshot = value
        return value
    }

    func watch(_ context: ModelContext) {
        guard watched !== context else { return }
        stop?()
        watched = context
        // A save on the main actor (the app's own context) re-reads the view now; a model
        // actor's save reaches the main actor at its next turn.
        let end = context.observe { [weak self] onMainActor in
            if onMainActor { MainActor.assumeIsolated { self?.objectWillChange.send() } }
            else { Task { @MainActor in self?.objectWillChange.send() } }
        }
        stop = { end() }
    }
    deinit { stop?() }
}
