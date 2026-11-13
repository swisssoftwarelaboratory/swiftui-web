// Associated objects on the stock wasm SDK (WebFoundation, AssociatedObjects.swift), as
// Kingfisher uses them: a value kept per object and key, gone with the object, removable.
#if os(WASI) && !_runtime(_ObjC)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmAssociatedObjectsTests {
    final class View {}
    final class Task {
        let name: String
        init(_ name: String) { self.name = name }
    }

    nonisolated(unsafe) static var taskKey: Void?
    nonisolated(unsafe) static var otherKey: Void?

    /// Kingfisher's helpers (Utility/Runtime.swift), called the way it calls them.
    func get<T>(_ object: Any, _ key: UnsafeRawPointer) -> T? {
        objc_getAssociatedObject(object, key) as? T
    }
    func setRetained<T>(_ object: Any, _ key: UnsafeRawPointer, _ value: T) {
        objc_setAssociatedObject(object, key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    @Test func aValueIsKeptPerObjectAndKey() {
        let view = View(), other = View()
        setRetained(view, &Self.taskKey, Task("avatar"))
        setRetained(view, &Self.otherKey, 3)
        #expect((get(view, &Self.taskKey) as Task?)?.name == "avatar")
        #expect(get(view, &Self.otherKey) == 3)
        #expect((get(other, &Self.taskKey) as Task?) == nil)

        setRetained(view, &Self.taskKey, Task("banner"))
        #expect((get(view, &Self.taskKey) as Task?)?.name == "banner")
        objc_setAssociatedObject(view, &Self.taskKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #expect((get(view, &Self.taskKey) as Task?) == nil)
        #expect(get(view, &Self.otherKey) == 3)

        objc_removeAssociatedObjects(view)
        #expect((get(view, &Self.otherKey) as Int?) == nil)
    }

    @Test func aRetainedValueLivesAsLongAsItsObject() {
        weak var task: Task?
        var view: View? = View()
        do {
            let made = Task("cover")
            task = made
            setRetained(view!, &Self.taskKey, made)
        }
        #expect(task != nil)   // the view holds it
        view = nil
        // The value goes with the table, which the next touch of the same identifier or a sweep
        // drops; a fresh object never sees it.
        let fresh = View()
        #expect((get(fresh, &Self.taskKey) as Task?) == nil)
        _ = view
    }

    @Test func anAssignedValueIsNotRetained() {
        let view = View()
        weak var task: Task?
        do {
            let made = Task("weak")
            task = made
            objc_setAssociatedObject(view, &Self.taskKey, made, .OBJC_ASSOCIATION_ASSIGN)
            #expect((get(view, &Self.taskKey) as Task?)?.name == "weak")
        }
        #expect(task == nil)
        #expect((get(view, &Self.taskKey) as Task?) == nil)
    }

    @Test func aValueTypeHasNoAssociatedValues() {
        setRetained(42, &Self.taskKey, Task("lost"))
        #expect((get(42, &Self.taskKey) as Task?) == nil)
    }
}
#endif
