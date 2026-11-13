// Sending a selector to an object with as many arguments as its method takes. Target-action,
// key commands, display links and selector notification observers all name methods that may take
// the sender (`newGame(_:)`) or nothing (`refresh`, `synchronize`). Darwin's message send ignores
// an extra argument; WebAssembly checks the signature of every indirect call, so on the
// Objective-C runtime build (decision 0023) sending a no-argument method one argument traps. The
// count comes from the selector's colons, as it does for any Objective-C method.
#if _runtime(_ObjC)
import ObjectiveC

extension NSObject {
    /// Sends `selector` with `argument` if the method takes one (and nil as a second if it takes
    /// two, `action:forEvent:`), or with none if it takes none.
    @discardableResult
    public func _send(_ selector: Selector, passing argument: Any?) -> Unmanaged<AnyObject>? {
        switch NSStringFromSelector(selector).reduce(0, { $1 == ":" ? $0 + 1 : $0 }) {
        case 0: return perform(selector)
        case 1: return perform(selector, with: argument)
        default: return perform(selector, with: argument, with: nil)
        }
    }
}
#endif
