import Observation
import WebCombine
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
/// A part of an app's user interface with a life cycle managed by the system.
@MainActor @preconcurrency
public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }

    /// Hidden hook: the scene's root views, for hosts that mount them.
    @MainActor static func _windows(of scene: Self) -> [_WindowDescriptor]
}

extension Scene {
    public static func _windows(of scene: Self) -> [_WindowDescriptor] {
        Body._windows(of: scene.body)
    }

    @MainActor public static func _rootViews(of scene: Self) -> [AnyView] {
        _windows(of: scene).map { $0.make(nil) }
    }
}

/// `Never` as a scene reuses its `View` body; the default `_rootViews` is unreachable.
extension Never: Scene {}

/// A result builder for composing a collection of scenes into a single composite scene.
@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Scene>(_ content: repeat each Content) -> _TupleScene<(repeat each Content)> {
        _TupleScene(value: (repeat each content), roots: { value in
            var roots: [_WindowDescriptor] = []
            for scene in repeat each value { roots += _sceneWindows(scene) }
            return roots
        })
    }
    public static func buildExpression<Content: Scene>(_ content: Content) -> Content { content }
}

/// Two or more scenes in a `SceneBuilder` block.
public struct _TupleScene<T> {
    public var value: T
    package let roots: @MainActor (T) -> [_WindowDescriptor]
}

extension _TupleScene: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("_TupleScene has no body") }
    public static func _windows(of scene: _TupleScene<T>) -> [_WindowDescriptor] { scene.roots(scene.value) }
}

@MainActor
private func _sceneWindows<S: Scene>(_ scene: S) -> [_WindowDescriptor] { S._windows(of: scene) }

/// A scene that presents a group of identically structured windows.
/// A window scene the app declares: what to show, under which id, for which value type.
public struct _WindowDescriptor {
    public enum Kind: Equatable, Sendable { case windowGroup, window, settings, menuBarExtra }
    package var kind: Kind
    package var id: String?
    package var title: String?
    package var valueType: Any.Type?
    package var defaultSize: CGSize?
    /// `defaultPosition`: where the window opens in the host (centred when nil).
    package var defaultPosition: UnitPoint?
    /// `windowResizability(.contentSize)`: the window keeps its content's size (no resize grip).
    package var resizable = true
    /// `windowStyle(.hiddenTitleBar)` / `.plain`: no title bar (the traffic lights stay).
    package var hidesTitleBar = false
    /// `commands` on the scene: the app's menus (`Commands`).
    package var commands: [_CommandMenuData] = []
    /// A `DocumentGroup`'s document operations (the runtime's New, Open and Save).
    package var documentType: _DocumentTypeBox?
    /// Builds the root for a window; a window group over a value gets the box its binding writes
    /// to. A scene modifier that wraps the roots (`environment`, `environmentObject`) replaces it.
    package var make: @MainActor (_WindowValueBox?) -> AnyView

    package init(kind: Kind, id: String?, title: String?, valueType: Any.Type? = nil, make: @escaping @MainActor (_WindowValueBox?) -> AnyView) {
        self.kind = kind
        self.id = id
        self.title = title
        self.valueType = valueType
        self.make = make
    }
}

/// The value a window group window shows, shared with its content's binding.
@MainActor
public final class _WindowValueBox {
    public var value: Any?
    package var onChange: (() -> Void)?
    package init(_ value: Any?) { self.value = value }
}

public struct WindowGroup<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: nil, title: nil) { _ in AnyView(view) }
    }

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: nil, title: title) { _ in AnyView(view) }
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: id, title: nil) { _ in AnyView(view) }
    }

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .windowGroup, id: id, title: title) { _ in AnyView(view) }
    }

    /// A group whose windows show a value; `openWindow(value:)` opens one per distinct value.
    public init<D: Hashable & Codable>(for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: nil, title: nil, type: type, content: content)
    }

    public init<D: Hashable & Codable>(id: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: id, title: nil, type: type, content: content)
    }

    public init<D: Hashable & Codable>(_ title: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: nil, title: title, type: type, content: content)
    }

    public init<D: Hashable & Codable>(_ title: String, id: String, for type: D.Type, @ViewBuilder content: @escaping @MainActor (Binding<D?>) -> Content) {
        descriptor = Self.valued(id: id, title: title, type: type, content: content)
    }

    private static func valued<D: Hashable & Codable>(id: String?, title: String?, type: D.Type,
                                                       content: @escaping @MainActor (Binding<D?>) -> Content) -> _WindowDescriptor {
        nonisolated(unsafe) let content = content   // runs on the main actor; Swift 5 mode (decision 0027)
        return _WindowDescriptor(kind: .windowGroup, id: id, title: title, valueType: type) { box in
            let box = box ?? _WindowValueBox(nil)
            let binding = Binding<D?>(get: { box.value as? D }, set: { box.value = $0; box.onChange?() })
            return AnyView(content(binding))
        }
    }
}

extension WindowGroup: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("WindowGroup has no body") }
    public static func _windows(of scene: WindowGroup<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A single window, opened by id.
public struct Window<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .window, id: id, title: title) { _ in AnyView(view) }
    }
}

extension Window: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("Window has no body") }
    public static func _windows(of scene: Window<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// The settings window, opened by `openSettings`.
public struct Settings<Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .settings, id: "com.apple.SwiftUI.Settings", title: "Settings") { _ in AnyView(view) }
    }
}

extension Settings: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("Settings has no body") }
    public static func _windows(of scene: Settings<Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A menu bar item; recorded but not shown (browsers have no menu bar).
public struct MenuBarExtra<Label: View, Content: View> {
    package let descriptor: _WindowDescriptor

    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        let view = content()
        descriptor = _WindowDescriptor(kind: .menuBarExtra, id: nil, title: nil) { _ in AnyView(view) }
    }
}

extension MenuBarExtra where Label == Text {
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }

    public init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

extension MenuBarExtra: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("MenuBarExtra has no body") }
    public static func _windows(of scene: MenuBarExtra<Label, Content>) -> [_WindowDescriptor] { [scene.descriptor] }
}

/// A scene with a modifier applied (default size; the others are accepted and ignored).
public struct _ModifiedScene<Base: Scene> {
    package let base: Base
    package let transform: (inout _WindowDescriptor) -> Void
}

extension _ModifiedScene: Scene {
    public typealias Body = Never
    public var body: Never { fatalError("_ModifiedScene has no body") }
    public static func _windows(of scene: _ModifiedScene<Base>) -> [_WindowDescriptor] {
        Base._windows(of: scene.base).map { var d = $0; scene.transform(&d); return d }
    }
}

public enum WindowResizability: Sendable { case automatic, contentSize, contentMinSize }
public struct MenuBarExtraStyle: Sendable {
    public static var automatic: MenuBarExtraStyle { MenuBarExtraStyle() }
    public static var menu: MenuBarExtraStyle { MenuBarExtraStyle() }
    public static var window: MenuBarExtraStyle { MenuBarExtraStyle() }
}
public struct WindowStyle: Sendable {
    package let hidesTitleBar: Bool
    package init(hidesTitleBar: Bool = false) { self.hidesTitleBar = hidesTitleBar }
    public static var automatic: WindowStyle { WindowStyle() }
    public static var hiddenTitleBar: WindowStyle { WindowStyle(hidesTitleBar: true) }
    public static var titleBar: WindowStyle { WindowStyle() }
    public static var plain: WindowStyle { WindowStyle(hidesTitleBar: true) }
}

extension Scene {
    /// The size a window opens at (its content is laid out in it).
    public func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        _ModifiedScene(base: self) { $0.defaultSize = CGSize(width: width, height: height) }
    }
    public func defaultSize(_ size: CGSize) -> some Scene { defaultSize(width: size.width, height: size.height) }
    /// `.contentSize` keeps an in-host window at its content's size (no resize grip); the
    /// others let its corner drag.
    public func windowResizability(_ resizability: WindowResizability) -> some Scene {
        _ModifiedScene(base: self) { $0.resizable = resizability != .contentSize }
    }
    /// `.hiddenTitleBar` and `.plain` open the in-host window without its 28 pt title bar.
    public func windowStyle(_ style: WindowStyle) -> some Scene { _ModifiedScene(base: self) { $0.hidesTitleBar = style.hidesTitleBar } }
    public func menuBarExtraStyle(_ style: MenuBarExtraStyle) -> some Scene { _ModifiedScene(base: self) { _ in } }
    /// Where the in-host window opens (a unit point of the host; centred by default).
    public func defaultPosition(_ position: UnitPoint) -> some Scene { _ModifiedScene(base: self) { $0.defaultPosition = position } }
    /// The app's menu commands (`CommandMenu`, `CommandGroup`): their keyboard shortcuts work in
    /// every host, the native host builds its menu bar from them.
    public func commands<C: Commands>(@CommandsBuilder content: () -> C) -> some Scene {
        let menus = content()._commandMenus
        return _ModifiedScene(base: self) { $0.commands += menus }
    }

    // MARK: Environment on a scene (sw-scene-environment, decision 0021)

    /// Wraps every window's root in `transform`: how the scene modifiers that set the
    /// environment reach the views.
    package func _wrappingRoots(_ transform: @escaping @MainActor (AnyView) -> AnyView) -> some Scene {
        _ModifiedScene(base: self) { descriptor in
            let make = descriptor.make
            descriptor.make = { box in transform(make(box)) }
        }
    }

    /// Places an observable object in the environment of every window's root.
    public func environment<T: AnyObject & Observable>(_ object: T?) -> some Scene {
        nonisolated(unsafe) let object = object
        return _wrappingRoots { AnyView($0.environment(object)) }
    }

    /// Sets the environment value of the specified key path for every window's root.
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some Scene {
        nonisolated(unsafe) let value = value
        nonisolated(unsafe) let keyPath = keyPath
        return _wrappingRoots { AnyView($0.environment(keyPath, value)) }
    }

    /// Supplies an observable object to every window's root view hierarchy.
    public func environmentObject<T: WebCombine.ObservableObject>(_ object: T) -> some Scene {
        nonisolated(unsafe) let object = object
        return _wrappingRoots { AnyView($0.environmentObject(object)) }
    }

    /// Sets the default storage of `AppStorage` in every window.
    public func defaultAppStorage(_ store: UserDefaults) -> some Scene { environment(\.defaultAppStorage, store) }

    /// Adds an action to perform when the given value changes. A scene's value that changes is
    /// its phase (an app's `@Environment(\.scenePhase)`): the action runs as the page's phase
    /// changes, with the old and new phases. Other values are read once, as scenes are.
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping () -> Void) -> some Scene {
        _onScenePhase(V.self) { _, _ in action() }
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false, _ action: @escaping (V, V) -> Void) -> some Scene {
        _onScenePhase(V.self) { action($0 as! V, $1 as! V) }
    }
    @available(*, deprecated, message: "Use `onChange` with a two or zero parameter action closure instead.")
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some Scene {
        _onScenePhase(V.self) { action($1 as! V) }
    }
    private func _onScenePhase<V>(_: V.Type, _ action: @escaping (ScenePhase, ScenePhase) -> Void) -> Self {
        if V.self == ScenePhase.self { _addScenePhaseAction(action) }
        return self
    }

    /// Specifies the external events this scene handles (accepted: one window takes them all).
    public func handlesExternalEvents(matching conditions: Set<String>) -> some Scene { self }
}

@MainActor @preconcurrency
public protocol App {
    associatedtype Body: Scene
    @SceneBuilder @MainActor @preconcurrency var body: Self.Body { get }

    init()

    /// Initializes and runs the app. The thin `SwiftUI` module provides the platform launcher.
    static func main()
}

/// The one instance of each app type, with its dynamic properties installed (decision 0021):
/// a `@StateObject` model declared on the `App` lives for the process, as SwiftUI keeps one
/// `App` value. The properties install into a node of their own; when one changes, the host
/// reads the app's body again and updates the main window's root in place (`_appRemount`;
/// the other windows keep their descriptors from launch).
@MainActor private var appInstances: [ObjectIdentifier: (app: Any, storage: AnyObject?)] = [:]
@MainActor private let appPropertyRuntime = Runtime()
@MainActor private let appPropertyNode = _AppPropertyNode(parent: nil, runtime: appPropertyRuntime, environment: EnvironmentValues())

/// How a host re-reads the app's body after an app-level state change: its runtime (whose
/// scheduler coalesces the changes of one flush) and the re-mount.
@MainActor public var _appRemount: (runtime: Runtime, apply: @MainActor () -> Void)?

/// Told by a host once the app's root is mounted in its runtime, before the host runs: the
/// framework registers what the app may reach through UIKit (the scene's window, decision 0021).
@MainActor public var _appDidMount: (@MainActor (Runtime) -> Void)?

/// Observable objects the app puts in every window's environment without a modifier: an
/// `@UIApplicationDelegateAdaptor` delegate that is an `ObservableObject`, as SwiftUI injects
/// it (decision 0021). Read when the windows are described.
@MainActor public var _appEnvironmentObjects: [any WebCombine.ObservableObject] = []

/// How many times the app's body was read, and the scene `onChange(of: scenePhase)` actions of
/// the last read with the phase they last saw; one host lifecycle observer runs them. (Only an
/// app with such an action reaches the code that keeps them.)
@MainActor private var _appBodyReads = 0
@MainActor private var _scenePhaseActions: (read: Int, actions: [(ScenePhase, ScenePhase) -> Void]) = (0, [])
@MainActor private var _scenePhaseSeen: ScenePhase?
@MainActor private func _addScenePhaseAction(_ action: @escaping (ScenePhase, ScenePhase) -> Void) {
    if _scenePhaseActions.read != _appBodyReads { _scenePhaseActions = (_appBodyReads, []) }
    _scenePhaseActions.actions.append(action)
    guard _scenePhaseSeen == nil else { return }
    _scenePhaseSeen = .active
    Runtime._hostLifecycleObservers.append { visible, focused in
        let phase: ScenePhase = !visible ? .background : (focused ? .active : .inactive)
        guard let old = _scenePhaseSeen, old != phase else { return }
        _scenePhaseSeen = phase
        for action in _scenePhaseActions.actions { action(old, phase) }
    }
}

@MainActor final class _AppPropertyNode: ViewNode {
    private var pending = false
    override package func invalidate() {
        guard let (runtime, apply) = _appRemount, !pending else { return }
        pending = true
        runtime.scheduler.enqueue { [weak self] in
            self?.pending = false
            apply()
        }
    }
}

/// Root view of the first window of an app, for hosts.
extension App {
    /// The app's instance: made on the first use, its `@StateObject`, `@State` and
    /// `@Environment` properties installed once.
    @MainActor
    public static var _instance: Self {
        let key = ObjectIdentifier(Self.self)
        if let existing = appInstances[key]?.app as? Self { return existing }
        var app = Self()
        var storage: AnyObject?
        _DynamicPropertyFields<Self>.installAll(into: &app, node: appPropertyNode, slot: &storage)
        appInstances[key] = (app, storage)
        return app
    }

    /// Tests: forgets the instance so the next `_instance` makes a new one.
    @MainActor
    public static func _resetInstance() { appInstances[ObjectIdentifier(Self.self)] = nil }

    /// The app's window scenes, in declaration order; the app-level environment objects wrap
    /// every root.
    @MainActor
    public static func _windows() -> [_WindowDescriptor] {
        _appBodyReads += 1
        let windows = Body._windows(of: _instance.body)   // the instance first: its adaptor may register an object
        let objects = _appEnvironmentObjects
        guard !objects.isEmpty else { return windows }
        return windows.map { descriptor in
            var descriptor = descriptor
            let make = descriptor.make
            descriptor.make = { box in
                var view = make(box)
                for object in objects { view = AnyView(view._environmentObject(erased: object)) }
                return view
            }
            return descriptor
        }
    }

    /// The root of the main window: the first window group (or window). A document group's
    /// main window gets a value box of its own (`Runtime.mainWindowBox`: its document).
    @MainActor
    public static func _rootView() -> AnyView {
        let windows = _windows()
        let main = windows.first { $0.kind == .windowGroup || $0.kind == .window } ?? windows.first
        guard let main else { return AnyView(EmptyView()) }
        if main.documentType != nil {
            let box = _WindowValueBox(nil)
            Runtime.mainWindowBox = box
            return main.make(box)
        }
        return main.make(nil)
    }
}
